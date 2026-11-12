## Slack Socket Mode — inbound events over WebSocket, without a public URL.
##
## The app-level token (`xapp-...`) opens the connection through
## `apps.connections.open`; the bot token remains responsible for outbound
## messages. Envelopes are acked after the payload is queued, and the Slack
## runtime drains the same module-level queue used by the webhook receiver.

import std/[atomics, json, locks, monotimes, net, os, strutils, times, uri]
when defined(posix):
  import std/posix
import ../../core/log
import ../../core/pipeops
import ../../ports/http
import ./slack
import ./ws_client

const
  SlackSocketReconnectMinMs = 1_000
  SlackSocketReconnectMaxMs = 30_000
  SlackSocketIdleTimeoutMs  = 120_000

type
  SlackSocketMode* = ref object
    appToken: string
    http:     HttpRuntimePort
    logger:   Logger
    stop:     Atomic[bool]
    stopped:  bool
    fdLock:   Lock
    activeFd: SocketHandle
    thread:   Thread[SlackSocketMode]

var
  gSlackSocketThread: Thread[SlackSocketMode]
  gSlackSocketClient: SlackSocketMode
  gSlackSocketStarted = false

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

proc openSocketUrl(client: SlackSocketMode): Result[string, string] =
  var resp: Result[HttpResponse, string]
  try:
    resp = client.http.post(
      SlackApiBase & "/apps.connections.open", "",
      @[("Authorization", "Bearer " & client.appToken),
        ("Content-Type", "application/x-www-form-urlencoded")])
  except CatchableError as e:
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

proc sleepOrStop(client: SlackSocketMode; ms: int): bool =
  var waited = 0
  while waited < ms and not client.stop.load():
    sleep(1000)
    waited += 1000
  not client.stop.load()

proc runSlackSocket(client: SlackSocketMode) {.thread.} =
  {.cast(gcsafe).}:
    var backoff = SlackSocketReconnectMinMs
    while not client.stop.load():
      let urlRes = client.openSocketUrl()
      if urlRes.isErr:
        client.logger.warn("slack socket: " & urlRes.error)
        if not client.sleepOrStop(backoff):
          break
        backoff = min(backoff * 2, SlackSocketReconnectMaxMs)
        continue

      let socketUrl = parseUri(urlRes.get())
      let port =
        if socketUrl.port.len > 0:
          try: Port(parseInt(socketUrl.port))
          except ValueError: Port(443)
        else:
          Port(443)
      let path =
        if socketUrl.path.len > 0: socketUrl.path else: "/"
      let fullPath =
        if socketUrl.query.len > 0: path & "?" & socketUrl.query else: path

      var ws: WsClient
      try:
        let onSocket = proc(sock: Socket) {.gcsafe.} =
          {.cast(gcsafe).}:
            acquire(client.fdLock)
            client.activeFd = sock.getFd
            release(client.fdLock)
        ws = wsConnect(socketUrl.hostname, port, fullPath,
                       timeoutMs = 10_000, onSocket = onSocket)
      except CatchableError as e:
        acquire(client.fdLock)
        client.activeFd = SocketHandle(-1)
        release(client.fdLock)
        client.logger.warn("slack socket: connect failed: " & e.msg)
        if not client.sleepOrStop(backoff):
          break
        backoff = min(backoff * 2, SlackSocketReconnectMaxMs)
        continue

      client.logger.info("slack socket: connected")
      backoff = SlackSocketReconnectMinMs
      var lastActivity = getMonoTime()
      var reopen = false
      while not client.stop.load() and not reopen:
        try:
          let frame = ws.recvFrame(1000)
          lastActivity = getMonoTime()
          case frame.opcode
          of WsOpcodeText:
            var envelope: JsonNode
            try:
              envelope = parseJson(frame.data)
            except CatchableError as e:
              client.logger.warn("slack socket: invalid envelope: " & e.msg)
              continue
            if envelope.getOrDefault("type").getStr("") == "hello":
              continue
            let id = envelopeId(envelope)
            let keepOpen = handleSlackSocketEnvelope(envelope)
            ## Ack after the payload is queued, so a crash before queueing
            ## leaves the event eligible for redelivery.
            if id.len > 0:
              ws.sendFrame($ %* {"envelope_id": id})
            if not keepOpen:
              reopen = true
          of WsOpcodePing:
            ws.sendFrame(frame.data, WsOpcodePong)
          of WsOpcodeClose:
            reopen = true
          else:
            discard
        except TimeoutError:
          if inMilliseconds(getMonoTime() - lastActivity) >=
             SlackSocketIdleTimeoutMs:
            client.logger.warn("slack socket: idle timeout; reconnecting")
            reopen = true
          else:
            continue
        except CatchableError as e:
          client.logger.warn("slack socket: " & e.msg)
          reopen = true

      acquire(client.fdLock)
      client.activeFd = SocketHandle(-1)
      release(client.fdLock)
      wsClose(ws)
      if not client.stop.load():
        if not client.sleepOrStop(1000):
          break

proc startSlackSocketMode*(appToken: string;
                           http: HttpRuntimePort;
                           logger: Logger): Result[void, string] {.gcsafe, raises: [].} =
  ## Starts the Socket Mode reader thread. Requires the app-level token; the
  ## bot token is validated by the gateway caller because it is only needed
  ## for outbound messages.
  if appToken.len == 0:
    return err("SLACK_APP_TOKEN is empty")
  if gSlackSocketStarted:
    return err("Slack Socket Mode is already started")

  let client = SlackSocketMode(appToken: appToken, http: http, logger: logger)
  client.stop.store(false)
  client.activeFd = SocketHandle(-1)
  initLock(client.fdLock)
  try:
    {.cast(gcsafe).}:
      createThread(gSlackSocketThread, runSlackSocket, client)
  except CatchableError as e:
    return err("cannot start Slack Socket Mode: " & e.msg)

  {.cast(gcsafe).}:
    gSlackSocketClient = client
    gSlackSocketStarted = true
  ok()

proc stopSlackSocketMode*() =
  ## Stops the reader thread. Safe to call when Socket Mode was never started.
  {.cast(gcsafe).}:
    if not gSlackSocketStarted:
      return
    let client = gSlackSocketClient
    client.stop.store(true)
    when defined(posix):
      ## Wake a blocked SSL_read so shutdown does not depend on frame timing.
      acquire(client.fdLock)
      if client.activeFd != SocketHandle(-1):
        discard posix.shutdown(posix.SocketHandle(client.activeFd),
                              posix.SHUT_RDWR)
      release(client.fdLock)
    joinThread(gSlackSocketThread)
    deinitLock(client.fdLock)
    gSlackSocketClient = nil
    gSlackSocketStarted = false
