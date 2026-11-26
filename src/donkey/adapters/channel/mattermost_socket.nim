## mattermost_socket — Mattermost's WebSocket, the inbound half (second
## round, front 1).
##
## The connection's lifecycle (thread, backoff, idle timeout, ping/pong,
## stop) is adapters/network/persistent_socket's; this module is the
## protocol: learn who the bot is (`users/me`), authenticate with its token,
## queue the posts it should answer, keep the link alive with the API's
## ping action. A refused token stops the thread: reconnecting cannot help.

import std/[net, options, strutils]   ## net: persistent_socket compares socket handles here
import ../../core/log
import ../../core/pipeops
import ../../ports/http
import ../network/persistent_socket
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
  ssKeep

proc mmFrame(cfg: MattermostSocketConfig; state: var MattermostSocketState; ws: WsClient;
             frame: WsFrame; log: Logger): SessionStep {.nimcall, gcsafe, raises: [CatchableError].} =
  if frame.opcode != WsOpcodeText:
    return ssKeep
  if authRefused(frame.data, ChallengeSeq):
    log.error("mattermost: the server refused the token; check MATTERMOST_TOKEN")
    return ssStop
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
    logger)
  ok()

proc stopMattermostSocket*() =
  ## Safe to call when it was never started.
  gMattermostSocket.stop()
