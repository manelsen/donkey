## Slack Socket Mode — inbound events over WebSocket, without a public URL.
##
## The app-level token (`xapp-...`) opens the connection through
## `apps.connections.open`; the bot token remains responsible for outbound
## messages. Envelopes are acked after the payload is queued, and the Slack
## runtime drains the same module-level queue used by the webhook receiver.
##
## The connection's lifecycle (thread, backoff, idle timeout, ping/pong,
## stop) is adapters/network/persistent_socket's; this module is the
## protocol: find the URL, read envelopes, ack them.

import std/[json, net, strutils, uri]
import ../../core/log
import ../../core/pipeops
import ../../ports/http
import ./slack
import ../network/persistent_socket

const
  SlackSocketReconnectMinMs = 1_000
  SlackSocketReconnectMaxMs = 30_000
  SlackSocketIdleTimeoutMs  = 120_000

type
  SlackHttpFactory* = proc(): HttpRuntimePort {.nimcall, gcsafe.}
    ## Builds the connection thread's HTTP port. Called on that thread, so the
    ## port's closures are never shared with the daemon loop.

  SlackSocketConfig = object
    ## Plain data, copied to the connection thread.
    appToken:    string
    httpFactory: SlackHttpFactory

  SlackSocketState = object
    ## Lives on the connection thread.
    http: HttpRuntimePort

var gSlackSocket: PersistentSocket[SlackSocketConfig, SlackSocketState]
  ## Pointers only: gcsafe to touch from the daemon.

func envelopeId(envelope: JsonNode): string =
  if envelope == nil or envelope.kind != JObject:
    return ""
  envelope.getOrDefault("envelope_id").getStr("")

proc handleSlackSocketEnvelope*(envelope: JsonNode): bool =
  ## Queues supported payloads into the Slack event queue. Returns false when
  ## the connection must be re-established (disconnect envelope).
  if envelope == nil or envelope.kind != JObject:
    return true

  case envelope.getOrDefault("type").getStr("")
  of "disconnect":
    return false
  of "events_api":
    let payload = envelope.getOrDefault("payload")
    if payload != nil and payload.kind == JObject:
      slack.pushEvent(payload)
  of "slash_commands":
    let payload = envelope.getOrDefault("payload")
    if payload != nil and payload.kind == JObject:
      var normalized = payload
      normalized["type"] = %"slash_command"
      slack.pushEvent(normalized)
  of "interactive":
    let payload = envelope.getOrDefault("payload")
    if payload != nil:
      if payload.kind == JObject:
        slack.pushEvent(payload)
      elif payload.kind == JString:
        try:
          slack.pushEvent(parseJson(payload.getStr))
        except CatchableError:
          discard
  else:
    discard
  true

proc openSocketUrl(http: HttpRuntimePort; appToken: string): Result[string, string]
                  {.gcsafe, raises: [].} =
  if http.postNoRedirect == nil:
    return err("apps.connections.open needs an HTTP port with postNoRedirect")
  var resp: Result[HttpResponse, string]
  try:
    resp = http.postNoRedirect(
      SlackApiBase & "/apps.connections.open", "",
      @[("Authorization", "Bearer " & appToken),
        ("Content-Type", "application/x-www-form-urlencoded")])
  except Exception as e:  ## effect boundary: callee raises are unannotated
    return err("apps.connections.open failed: " & e.msg)
  if resp.isErr:
    return err("apps.connections.open failed: " & resp.error)

  let r = resp.get()
  if r.status < 200 or r.status >= 300:
    return err("apps.connections.open HTTP " & $r.status)
  try:
    let payload = parseJson(r.body)
    if not payload.getOrDefault("ok").getBool(false):
      return err("apps.connections.open: " &
                 payload.getOrDefault("error").getStr("unknown error"))
    let url = payload.getOrDefault("url").getStr("")
    if not url.startsWith("wss://"):
      return err("apps.connections.open returned a non-wss URL")
    ok(url)
  except CatchableError as e:
    err("apps.connections.open response: " & e.msg)

proc slackLocate(cfg: SlackSocketConfig; state: var SlackSocketState;
                 log: Logger): Result[SocketTarget, string] {.nimcall, gcsafe, raises: [CatchableError].} =
  if state.http.postNoRedirect == nil:
    try:
      state.http = cfg.httpFactory()
    except Exception as e:  ## effect boundary: callee raises are unannotated
      return err("slack socket: cannot build its HTTP port: " & e.msg)
  let url = ? openSocketUrl(state.http, cfg.appToken)
  let socketUrl = parseUri(url)
  let port =
    if socketUrl.port.len > 0:
      try: Port(parseInt(socketUrl.port))
      except ValueError: Port(443)
    else:
      Port(443)
  let path = if socketUrl.path.len > 0: socketUrl.path else: "/"
  ok(SocketTarget(host: socketUrl.hostname, port: port, useTls: true,
                  path: if socketUrl.query.len > 0: path & "?" & socketUrl.query
                        else: path))

proc slackOpened(cfg: SlackSocketConfig; state: var SlackSocketState; ws: WsClient;
                 log: Logger): SessionStep {.nimcall, gcsafe, raises: [CatchableError].} =
  ssKeep

proc slackFrame(cfg: SlackSocketConfig; state: var SlackSocketState; ws: WsClient;
                frame: WsFrame; log: Logger): SessionStep {.nimcall, gcsafe, raises: [CatchableError].} =
  if frame.opcode != WsOpcodeText:
    return ssKeep
  var envelope: JsonNode
  try:
    envelope = parseJson(frame.data)
  except CatchableError as e:
    log.warn("slack socket: invalid envelope: " & e.msg)
    return ssKeep
  if envelope.getOrDefault("type").getStr("") == "hello":
    return ssKeep
  let id = envelopeId(envelope)
  let keepOpen = handleSlackSocketEnvelope(envelope)
  ## Ack after the payload is queued, so a crash before queueing leaves the
  ## event eligible for redelivery.
  if id.len > 0:
    ws.sendFrame($ %* {"envelope_id": id})
  if keepOpen: ssKeep else: ssReconnect

proc slackTick(cfg: SlackSocketConfig; state: var SlackSocketState; ws: WsClient;
               nowMs: int64; log: Logger): SessionStep {.nimcall, gcsafe, raises: [CatchableError].} =
  ssKeep

const SlackSocketProtocol = SocketProtocol[SlackSocketConfig, SlackSocketState](
  locate: slackLocate, opened: slackOpened, frame: slackFrame, tick: slackTick)

proc startSlackSocketMode*(appToken: string;
                           httpFactory: SlackHttpFactory;
                           logger: Logger): Result[void, string] {.gcsafe, raises: [].} =
  ## Starts Socket Mode. Requires the app-level token; the bot token is
  ## validated by the gateway caller because it is only needed for outbound
  ## messages.
  if appToken.len == 0:
    return err("SLACK_APP_TOKEN is empty")
  if httpFactory == nil:
    return err("Slack Socket Mode needs an HTTP port factory")
  if gSlackSocket.running:
    return err("Slack Socket Mode is already started")
  gSlackSocket = ? startPersistentSocket("slack socket", SlackSocketProtocol,
    SlackSocketConfig(appToken: appToken, httpFactory: httpFactory),
    SocketPolicy(reconnectMinMs: SlackSocketReconnectMinMs,
                 reconnectMaxMs: SlackSocketReconnectMaxMs,
                 idleTimeoutMs: SlackSocketIdleTimeoutMs,
                 recvTimeoutMs: 1_000),
    logger)
  ok()

proc stopSlackSocketMode*() =
  ## Stops Socket Mode. Safe to call when it was never started.
  gSlackSocket.stop()
