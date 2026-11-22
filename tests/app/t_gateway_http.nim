## End-to-end behaviour of the HTTP gateway over a real TCP socket.
##
## These tests talk HTTP to a running gateway and check what a client sees:
## status codes, auth, bodies, the agent turn and its stream. They do not
## depend on how the gateway is built (worker threads or the Chronos loop),
## so they hold the behaviour steady while the implementation changes. The
## client is a Chronos transport: it keeps the event loop running while it
## waits, which an in-loop server needs.

import std/[json, locks, nativesockets, net, os, strutils, times, unittest]
import chronos
import chronos/transports/stream
import donkey/app/chat_bridge
import donkey/adapters/http/gateway_server
import donkey/core/agent_events
import donkey/core/types
import donkey/domain/gateway/identity_pure
import donkey/domain/message
import donkey/ports/ipc

const
  Token = "secret-token"
  Model = "donkey/e2e"

var
  gLock: Lock
  gInbound: seq[string]       ## texts received by POST /api/chat
  gDispatched: seq[string]    ## users of /v1/chat/completions turns
  gBridge: ChatBridge
initLock(gLock)

proc clockMs(): int64 {.gcsafe, raises: [].} = int64(epochTime() * 1000)
proc nap(ms: int) {.gcsafe, raises: [].} = os.sleep(ms)

proc statusFn(): DaemonStatus {.gcsafe.} =
  DaemonStatus(uptimeSec: 7, sessionCount: 2)

proc logFn(n: int): seq[IpcLogEntry] {.gcsafe.} =
  @[IpcLogEntry(level: "info", subsys: "e2e", msg: "log line " & $n)]

proc eventFn(n: int): seq[AgentEvent] {.gcsafe.} =
  discard n
  @[]

proc inboundFn(msg: InboundMessage) {.gcsafe.} =
  {.cast(gcsafe).}:
    withLock gLock:
      gInbound.add msg.text

proc authorizeFn(userId: UserId): AuthVerdict {.gcsafe, raises: [].} =
  discard userId
  avAllowed

proc dispatchFn(msg: InboundMessage) {.gcsafe.} =
  ## Stands in for the daemon: the agent answers through the bridge, as the
  ## outbox drainer does for `api:` replies.
  {.cast(gcsafe).}:
    withLock gLock:
      gDispatched.add $msg.userId
    discard gBridge.deliver(OutboundMessage(
      userId: msg.userId, text: "pong", replyKind: rkFinalAnswer,
      bridgeToken: msg.bridgeToken), msg.bridgeToken)

type Reply = object
  status: int
  head: string
  body: string

proc freePort(): int =
  let s = newSocket()
  defer: s.close()
  s.bindAddr(Port(0), "127.0.0.1")
  int(s.getLocalAddr()[1])

var gPort: int

proc exchange(raw: string; readLimitMs = 5_000;
              stopAt = ""): Future[string] {.async.} =
  ## Sends `raw` and reads until the server closes, the limit passes, or
  ## `stopAt` shows up (for streams that stay open).
  let transport = await connect(initTAddress("127.0.0.1", gPort))
  defer: await transport.closeWait()
  discard await transport.write(raw)
  var received = ""
  let deadline = Moment.now() + chronos.milliseconds(readLimitMs)
  while Moment.now() < deadline:
    var buf = newSeq[byte](4096)
    let readFut = transport.readOnce(addr buf[0], buf.len)
    if not await readFut.withTimeout(deadline - Moment.now()):
      break
    let n = readFut.read()
    if n <= 0: break
    received.add cast[string](buf[0 ..< n])
    if stopAt.len > 0 and stopAt in received: break
  return received

proc request(meth, path: string; token = ""; body = "";
             headers: seq[string] = @[]; stopAt = ""): Reply =
  var raw = meth & " " & path & " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
  if token.len > 0: raw.add "Authorization: Bearer " & token & "\r\n"
  for h in headers: raw.add h & "\r\n"
  if body.len > 0 or meth == "POST":
    raw.add "Content-Type: application/json\r\nContent-Length: " & $body.len & "\r\n"
  raw.add "\r\n" & body
  let text =
    try: waitFor exchange(raw, stopAt = stopAt)
    except CatchableError: ""   ## not listening yet: status stays 0
  let split = text.find("\r\n\r\n")
  result.head = if split >= 0: text[0 ..< split] else: text
  result.body = if split >= 0: text[split + 4 .. ^1] else: ""
  let parts = result.head.splitWhitespace()
  if parts.len >= 2:
    try: result.status = parseInt(parts[1]) except ValueError: discard

proc chatBody(stream = false): string =
  $(%* {"model": Model, "user": "alice", "stream": stream,
        "messages": [%* {"role": "user", "content": "ping"}]})

proc runTests*() =
  suite "gateway over HTTP":
    gPort = freePort()
    gBridge = newChatBridge(clockMs, nap)
    let started = startHttpGateway(gPort, statusFn, logFn, eventFn, inboundFn,
                                   authToken = Token,
                                   agentDispatchFn = dispatchFn,
                                   authorizeFn = authorizeFn,
                                   chatBridge = gBridge,
                                   modelName = Model,
                                   agentTimeoutMs = 5_000)
    check started.isOk
    ## The listener comes up on its own; wait until it answers.
    for _ in 0 ..< 100:
      if request("GET", "/health").status == 200: break
      waitFor sleepAsync(chronos.milliseconds(20))

    test "public probes answer without a token":
      let health = request("GET", "/health")
      check health.status == 200
      check health.body.strip == "ok"
      let index = request("GET", "/")
      check index.status == 200
      check "Donkey HTTP gateway" in index.body

    test "api routes require the bearer token":
      check request("GET", "/api/status").status == 401
      check request("GET", "/api/status", token = "wrong").status == 401
      let ok = request("GET", "/api/status", token = Token)
      check ok.status == 200
      let st = parseJson(ok.body)
      check st["uptimeSec"].getInt == 7
      check st["sessionCount"].getInt == 2

    test "logs honour the n query parameter":
      let logs = request("GET", "/api/logs?n=3", token = Token)
      check logs.status == 200
      check "log line 3" in logs.body

    test "preflight on api routes is checked too":
      check request("OPTIONS", "/api/status").status == 401
      check request("OPTIONS", "/api/status", token = Token).status == 204

    test "unknown paths are 404 and the dashboard is HTML":
      check request("GET", "/nope", token = Token).status == 404
      let dash = request("GET", "/dashboard", token = Token)
      check dash.status == 200
      check "text/html" in dash.head.toLowerAscii

    test "POST /api/chat hands the message to the inbound hook":
      let reply = request("POST", "/api/chat", token = Token,
                          body = """{"text":"hello e2e"}""")
      check reply.status == 202
      withLock gLock:
        check "hello e2e" in gInbound

    test "an oversized body is refused before it is read":
      var raw = "POST /api/chat HTTP/1.1\r\nHost: x\r\nConnection: close\r\n" &
                "Authorization: Bearer " & Token & "\r\n" &
                "Content-Type: application/json\r\nContent-Length: 999999999\r\n\r\n"
      let text = waitFor exchange(raw)
      check text.startsWith("HTTP/1.1 413")

    test "too many headers are a 400":
      var headers: seq[string]
      for i in 0 ..< 200: headers.add "X-Filler-" & $i & ": y"
      check request("GET", "/health", headers = headers).status == 400

    test "the model list names the configured model":
      let models = request("GET", "/v1/models", token = Token)
      check models.status == 200
      check Model in models.body

    test "a chat completion runs one agent turn and returns its answer":
      var before: int
      withLock gLock: before = gDispatched.len
      let reply = request("POST", "/v1/chat/completions", token = Token,
                          body = chatBody())
      check reply.status == 200
      let j = parseJson(reply.body)
      check j["choices"][0]["message"]["content"].getStr == "pong"
      withLock gLock:
        check gDispatched.len == before + 1

    test "a streamed chat completion ends with [DONE]":
      var before: int
      withLock gLock: before = gDispatched.len
      let reply = request("POST", "/v1/chat/completions", token = Token,
                          body = chatBody(stream = true), stopAt = "[DONE]")
      check reply.status == 200
      check "text/event-stream" in reply.head.toLowerAscii
      check "pong" in reply.body
      check "[DONE]" in reply.body
      withLock gLock:
        check gDispatched.len == before + 1

    test "the event stream opens for an authorised client":
      let reply = request("GET", "/api/events", token = Token, stopAt = ": connected")
      check reply.status == 200
      check "text/event-stream" in reply.head.toLowerAscii
      check ": connected" in reply.body

    test "an open event stream does not hold up other requests":
      ## Long-lived connections must not block the rest: with one stream
      ## open (handshake read, connection still up), a probe still answers
      ## promptly, and the stream is still open afterwards.
      proc openStream(): Future[StreamTransport] {.async.} =
        let transport = await connect(initTAddress("127.0.0.1", gPort))
        discard await transport.write(
          "GET /api/events HTTP/1.1\r\nHost: x\r\nConnection: close\r\n" &
          "Authorization: Bearer " & Token & "\r\n\r\n")
        var seen = ""
        let deadline = Moment.now() + chronos.milliseconds(5_000)
        while ": connected" notin seen and Moment.now() < deadline:
          var buf = newSeq[byte](1024)
          let reading = transport.readOnce(addr buf[0], buf.len)
          if not await reading.withTimeout(deadline - Moment.now()):
            break
          let n = reading.read()
          if n <= 0: break
          seen.add cast[string](buf[0 ..< n])
        if ": connected" notin seen:
          await transport.closeWait()
          doAssert false, "the stream never confirmed within 5 s"
        return transport
      let stream = waitFor openStream()
      defer: waitFor stream.closeWait()
      let started = epochTime()
      let health = request("GET", "/health")
      check health.status == 200
      check epochTime() - started < 1.0
      check not stream.atEof()

when isMainModule:
  runTests()
