## mattermost_socket — Mattermost's WebSocket, the inbound half (second
## round, front 1).
##
## The connection's lifecycle (thread, backoff, idle timeout, ping/pong,
## stop) is adapters/network/persistent_socket's; this module is the
## protocol: learn who the bot is (`users/me`), authenticate with its token,
## queue the posts it should answer, keep the link alive with the API's
## ping action. A refused token stops the thread: reconnecting cannot help.

import std/[algorithm, net, options, strutils]   ## net: persistent_socket compares socket handles here
import ../../core/log
import ../../core/pipeops
import ../../ports/http
import ../network/persistent_socket
import ../../infra/channel_process
import ../../infra/channel_worker
import ./mattermost

const
  MattermostReconnectMinMs = 1_000
  MattermostReconnectMaxMs = 60_000
  MattermostIdleTimeoutMs  = 90_000
  MattermostPingEveryMs    = 30_000
  ChallengeSeq = 1

type
  MattermostHttpFactory* = proc(): HttpRuntimePort {.nimcall, gcsafe.}
    ## Builds the connection thread's HTTP port, on that thread.

  MattermostSocketConfig = object
    ## Plain data, copied to the connection thread.
    serverUrl:   string
    token:       string
    httpFactory: MattermostHttpFactory

  MattermostSocketState = object
    ## Lives on the connection thread.
    http:       HttpRuntimePort
    httpBuilt:  bool
    me:         MattermostMe
    seq:        int
    lastPingMs: int64
    lastPostMs: int64   ## the newest post seen: where a catch-up starts

var gMattermostSocket: PersistentSocket[MattermostSocketConfig, MattermostSocketState]
  ## Pointers only: gcsafe to touch from the daemon.

func apiUrl(serverUrl, path: string): string =
  var base = serverUrl.strip
  while base.endsWith("/"): base.setLen(base.len - 1)
  base & path

proc whoAmI(cfg: MattermostSocketConfig; http: HttpRuntimePort): Result[MattermostMe, string]
           {.gcsafe, raises: [].} =
  if http.get == nil:
    return err("the HTTP port has no get (wiring error)")
  var resp: Result[HttpResponse, string]
  try:
    resp = http.get(apiUrl(cfg.serverUrl, "/api/v4/users/me"),
                    @[("Authorization", "Bearer " & cfg.token)])
  except Exception as e:  ## effect boundary: callee raises are unannotated
    return err("users/me failed: " & e.msg)
  let r = ? resp
  if r.status != 200:
    return err("users/me HTTP " & $r.status)
  parseMe(r.body)

const
  CatchUpWindowMs = 86_400_000'i64   ## never more than a day back
  CatchUpMaxPosts = 100

proc apiGet(http: HttpRuntimePort; url, token: string): string {.gcsafe, raises: [].} =
  ## The body of a 2xx answer, or "" (a catch-up is best effort).
  try:
    let r = http.get(url, @[("Authorization", "Bearer " & token)])
    if r.isOk and r.get.status in 200 .. 299: r.get.body else: ""
  except Exception:  ## effect boundary: callee raises are unannotated
    ""

func catchUpStart*(lastPostMs, nowMs: int64): tuple[since: int64, fetch: bool] =
  ## On the first connection there is nothing to catch up on: the time is
  ## marked, so a drop before any post still fetches what came after it.
  if lastPostMs <= 0: (nowMs, false) else: (lastPostMs, true)

proc catchUpPosts*(http: HttpRuntimePort; serverUrl, token: string; me: MattermostMe;
                   sinceMs, nowMs: int64): seq[MattermostPost] {.gcsafe, raises: [].} =
  ## The posts written in the bot's channels after `sinceMs` (at most a day
  ## back) that it should answer, oldest first, at most CatchUpMaxPosts.
  let since = max(sinceMs, nowMs - CatchUpWindowMs)
  for (team, _) in parseChannels(apiGet(http, apiUrl(serverUrl, "/api/v4/users/me/teams"), token)):
    for (channel, kind) in parseChannels(apiGet(http,
        apiUrl(serverUrl, "/api/v4/users/me/teams/" & team & "/channels"), token)):
      result.add postsSince(apiGet(http,
        apiUrl(serverUrl, "/api/v4/channels/" & channel & "/posts?since=" & $since), token),
        kind, me, since)
  result.sort(proc(a, b: MattermostPost): int = cmp(a.createdMs, b.createdMs))
  if result.len > CatchUpMaxPosts:
    result = result[result.len - CatchUpMaxPosts .. ^1]

proc mmLocate(cfg: MattermostSocketConfig; state: var MattermostSocketState;
              log: Logger): Result[SocketTarget, string] {.nimcall, gcsafe, raises: [CatchableError].} =
  if not state.httpBuilt:
    try:
      state.http = cfg.httpFactory()
    except Exception as e:  ## effect boundary: callee raises are unannotated
      return err("mattermost: cannot build its HTTP port: " & e.msg)
    state.httpBuilt = true
  if state.me.id.len == 0:
    state.me = whoAmI(cfg, state.http).valueOr:
      return err("mattermost: " & error)
    log.info("mattermost: connected as @" & state.me.username)
  socketTargetOf(? websocketUrl(cfg.serverUrl))

proc mmOpened(cfg: MattermostSocketConfig; state: var MattermostSocketState; ws: WsClient;
              log: Logger): SessionStep {.nimcall, gcsafe, raises: [CatchableError].} =
  state.seq = ChallengeSeq
  ws.sendFrame(authChallenge(cfg.token, ChallengeSeq))
  ## After a drop, what was written meanwhile (the socket does not replay it).
  let (since, fetch) = catchUpStart(state.lastPostMs, epochMs())
  state.lastPostMs = since
  if fetch:
    let missed = catchUpPosts(state.http, cfg.serverUrl, cfg.token, state.me,
                              since, epochMs())
    for p in missed:
      if not pushPost(p): break
      state.lastPostMs = max(state.lastPostMs, p.createdMs)
    if missed.len > 0:
      log.info("mattermost: caught up on " & $missed.len & " posts from while it was down")
  ssKeep

proc mmFrame(cfg: MattermostSocketConfig; state: var MattermostSocketState; ws: WsClient;
             frame: WsFrame; log: Logger): SessionStep {.nimcall, gcsafe, raises: [CatchableError].} =
  if frame.opcode != WsOpcodeText:
    return ssKeep
  if authRefused(frame.data, ChallengeSeq):
    log.error("mattermost: the server refused the token; check MATTERMOST_TOKEN")
    return ssStop
  let seenPost = parsePostedEvent(frame.data, state.me.id)
  if seenPost.isSome:
    state.lastPostMs = max(state.lastPostMs, seenPost.get.createdMs)
  let post = inboundPost(frame.data, state.me)
  if post.isSome and not pushPost(post.get):
    log.warn("mattermost: queue full, post " & post.get.id & " dropped")
  ssKeep

proc mmTick(cfg: MattermostSocketConfig; state: var MattermostSocketState; ws: WsClient;
            nowMs: int64; log: Logger): SessionStep {.nimcall, gcsafe, raises: [CatchableError].} =
  if nowMs - state.lastPingMs >= MattermostPingEveryMs:
    state.lastPingMs = nowMs
    inc state.seq
    ws.sendFrame(pingAction(state.seq))
  ssKeep

const MattermostSocketProtocol = SocketProtocol[MattermostSocketConfig, MattermostSocketState](
  locate: mmLocate, opened: mmOpened, frame: mmFrame, tick: mmTick)

proc startMattermostSocket*(serverUrl, token: string;
                            httpFactory: MattermostHttpFactory;
                            logger: Logger): Result[void, string] {.gcsafe, raises: [].} =
  discard ? websocketUrl(serverUrl)
  if token.strip.len == 0:
    return err("MATTERMOST_TOKEN is empty")
  if httpFactory == nil:
    return err("Mattermost needs an HTTP port factory")
  if gMattermostSocket.running:
    return err("the Mattermost socket is already started")
  gMattermostSocket = ? startPersistentSocket("mattermost socket", MattermostSocketProtocol,
    MattermostSocketConfig(serverUrl: serverUrl.strip, token: token.strip,
                           httpFactory: httpFactory),
    SocketPolicy(reconnectMinMs: MattermostReconnectMinMs,
                 reconnectMaxMs: MattermostReconnectMaxMs,
                 idleTimeoutMs: MattermostIdleTimeoutMs,
                 recvTimeoutMs: 1_000),
    logger, channel = some(ckMattermost))
  ok()

# ── The socket as its own process (E12.3) ─────────────────────────────────────

var gMattermostProcess: ChannelProcess

proc mattermostProcessSink*(payload: string) {.nimcall, gcsafe, raises: [].} =
  ## The daemon's side: a post from the child, into the inbound queue.
  let p = postFromWire(payload)
  if p.isOk: discard pushPost(p.get)

proc mattermostProcessSource*(): (bool, string) {.nimcall, gcsafe, raises: [].} =
  ## The daemon's side: nothing for the child; replies go out by REST, here.
  (false, "")

proc mattermostWorkerEvent*(): (bool, string) {.nimcall, gcsafe, raises: [].} =
  ## The child's side: a post the socket queued, for the daemon.
  let (has, p) = tryRecvPost()
  if has: (true, postToWire(p)) else: (false, "")

proc mattermostWorkerOut(line: string) {.nimcall, gcsafe, raises: [].} =
  discard   ## the daemon sends nothing over the wire

func mattermostWorkerSpec*(binary: string): ChannelProcessSpec =
  ChannelProcessSpec(name: "mattermost", channel: ckMattermost, command: binary,
                     args: @["channel-worker", "mattermost"])

proc startMattermostProcess*(binary: string; logger: Logger): Result[void, string] =
  ## The socket in a child (`donkey channel-worker mattermost`), restarted by
  ## the supervisor when it ends: a Defect there does not stop the daemon.
  gMattermostProcess = ? startChannelProcess(mattermostWorkerSpec(binary),
    mattermostProcessSink, mattermostProcessSource, logger)
  ok()

proc runMattermostWorker*(serverUrl, token: string; httpFactory: MattermostHttpFactory;
                          logger: Logger): int =
  ## The child: the socket as the daemon would run it, its posts carried
  ## over stdout until the daemon goes away.
  startMattermostSocket(serverUrl, token, httpFactory, logger).isOkOr:
    logger.error("mattermost: " & error)
    return 1
  result = runChannelWorker(ckMattermost, mattermostWorkerEvent, mattermostWorkerOut)
  gMattermostSocket.stop()

proc stopMattermostSocket*() =
  ## Stops the socket, or ends the child that runs it. Safe to call when it
  ## was never started.
  gMattermostProcess.stop()
  gMattermostSocket.stop()
