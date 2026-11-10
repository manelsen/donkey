## HTTP gateway — embedded HTTP/1.1 server for browser/UI clients.
##
## Runs on a dedicated OS thread (same pattern as WeChat/QQ webhook servers).
## Port: DONKEY_HTTP_PORT env var, default 8080.
##
## Endpoints:
##   GET /             → 200 OK, plain-text info
##   GET /api/status   → DaemonStatus JSON
##   GET /api/logs     → recent log entries JSON (?n=N, default 50)
##   GET /api/events    → SSE stream of log events (long-lived connection)
##   POST /api/chat     → receive inbound message from web UI (bidirectional SSE)
##
## CORS: Access-Control-Allow-Origin: * for local browser access.

import std/[json, net, os, strutils]
import locks
import std/posix
import ../core/pipeops
import ../core/types
import ../core/log
import ../ports/ipc
import ../core/agent_events
import ../domain/message
import ./metrics

const
  GatewayDefaultPort* = 8080
  SseHeartbeatIntervalMs = 5000   ## ms between SSE heartbeat/push cycles
  SseMaxPollCycles = 60           ## bounded to ~5 minutes at 5s intervals
  MaxConcurrentHttpConnections = 32
  ## SSE streams occupy a worker for their whole lifetime (up to ~5 minutes),
  ## so keep this well below GatewayWorkerCount: at least half of the workers
  ## must stay available for normal requests and 503 responses.
  MaxConcurrentSseConnections = 4

func resolveGatewayPort*(raw: string): int =
  ## Parses DONKEY_HTTP_PORT semantics.
  ## Empty or invalid values fall back to GatewayDefaultPort.
  ## Zero or negative values disable the HTTP gateway entirely.
  if raw.len == 0:
    return GatewayDefaultPort
  try:
    let parsed = parseInt(raw)
    if parsed <= 0: 0 else: parsed
  except ValueError:
    GatewayDefaultPort

func parseBearerToken(header: string): string =
  ## Extracts the token from an "Authorization: Bearer <token>" value.
  let value = header.strip()
  const prefix = "bearer "
  if value.len > prefix.len and value.toLowerAscii().startsWith(prefix):
    value[prefix.len .. ^1].strip()
  else:
    ""

func constantTimeEq(a, b: string): bool =
  if a.len != b.len:
    return false
  var diff = 0
  for i in 0 ..< a.len:
    diff = diff or (ord(a[i]) xor ord(b[i]))
  diff == 0

func isAuthorized*(authHeader, token: string): bool =
  ## Empty token keeps the historical local-only behavior; otherwise a
  ## matching Bearer token is required on every request.
  if token.len == 0:
    return true
  constantTimeEq(parseBearerToken(authHeader), token)

func gatewayBindIsAllowed*(bindAddr, token: string;
                           allowInsecure = false): bool =
  ## Loopback is always allowed. Non-loopback requires a token AND an explicit
  ## opt-in because this gateway speaks cleartext HTTP.
  let host = bindAddr.strip().toLowerAscii()
  if host in ["127.0.0.1", "localhost", "::1", "[::1]"]:
    return true
  allowInsecure and token.len > 0

func isLocalOrigin*(origin: string): bool =
  let value = origin.strip().toLowerAscii()
  if value.len == 0:
    return true
  for scheme in ["http://", "https://"]:
    if value.startsWith(scheme):
      let authority = value[scheme.len .. ^1]
      if '/' in authority:
        return false
      var host = authority
      if host.startsWith("["):
        let close = host.find(']')
        if close < 0:
          return false
        host = host[0 .. close]
      else:
        host = host.split(':')[0]
      return host in ["localhost", "127.0.0.1", "[::1]"]
  false

func chatRequestAllowed*(origin, contentType, token: string): bool =
  ## Blocks simple cross-origin form posts; with a token the bearer check is
  ## the primary control. Without a token only local origins and JSON bodies.
  if token.len > 0:
    return true
  if not isLocalOrigin(origin):
    return false
  contentType.toLowerAscii().strip.startsWith("application/json")

type
  GatewayRequest* = object
    meth*: string
    path*: string

# ── StatusProvider / LogProvider (same types as ipc_server) ───────────────────

type
  GatewayStatusFn* = proc(): DaemonStatus {.gcsafe.}
  GatewayLogFn*    = proc(n: int): seq[IpcLogEntry] {.gcsafe.}
  GatewayEventFn*  = proc(n: int): seq[AgentEvent] {.gcsafe.}

# ── Inbound handler ───────────────────────────────────────────────────────────

type
  GatewayInboundFn* = proc(msg: InboundMessage) {.gcsafe.}
    ## Callback to handle inbound messages from web UI POST /api/chat.
    ## Called on the gateway thread; must be thread-safe.

func parseGatewayRequest*(requestLine: string): GatewayRequest =
  ## Parses the first line of an HTTP request into method + path.
  ## Strips query strings. Returns empty strings for malformed input.
  let parts = requestLine.splitWhitespace()
  if parts.len < 2:
    return GatewayRequest()
  let meth = parts[0]
  var path = parts[1]
  let qmark = path.find('?')
  if qmark >= 0:
    path = path[0 ..< qmark]
  GatewayRequest(meth: meth, path: path)

func buildSseEvent*(event, data: string): string =
  ## Formats an SSE event string (double newline terminated).
  if event.len > 0:
    result = "event: " & event & "\n"
  result.add("data: " & data & "\n\n")

func buildStatusBody*(st: DaemonStatus): string =
  $st.toJson()

func buildLogsBody*(entries: seq[IpcLogEntry]): string =
  var arr = newJArray()
  for e in entries:
    arr.add(e.toJson())
  $arr

func buildAgentEventsBody*(events: seq[AgentEvent]): string =
  var arr = newJArray()
  for e in events:
    arr.add(e.toJson())
  $arr

func routeGatewayRequest*(req: GatewayRequest): string =
  case req.path
  of "/":              "index"
  of "/api/status":    "status"
  of "/api/logs":      "logs"
  of "/api/events":    "events"
  of "/api/chat":      "chat"
  else:                "notfound"

func routeChatMethod*(meth: string): string =
  case meth
  of "POST":  "chat"
  of "GET":   "chat_get"
  else:       "method_not_allowed"

# ── HTTP helpers ──────────────────────────────────────────────────────────────

const CorsHeaders = "Access-Control-Allow-Origin: *\r\n" &
                    "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" &
                    "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"

proc readHttpLine(s: Socket): string =
  var buf = ""
  var c: char
  while true:
    if s.recv(c.addr, 1) != 1: return buf
    if c == '\r':
      discard s.recv(c.addr, 1)
      break
    buf.add(c)
  buf

proc sendResponse(s: Socket; status, contentType, body: string; log: Logger) =
  let resp = "HTTP/1.1 " & status & "\r\n" &
             CorsHeaders &
             "Content-Type: " & contentType & "; charset=utf-8\r\n" &
             "Content-Length: " & $body.len & "\r\n" &
             "Connection: close\r\n\r\n" & body
  try: s.send(resp) except CatchableError:
    log.warn("http_gateway: sendResponse failed: " & getCurrentExceptionMsg())

proc sendJson(s: Socket; body: string; log: Logger) =
  s.sendResponse("200 OK", "application/json", body, log)

proc sendSseHeaders(s: Socket; log: Logger) =
  ## Sends SSE-specific response headers, keeps connection open.
  let headers = "HTTP/1.1 200 OK\r\n" &
                CorsHeaders &
                "Content-Type: text/event-stream\r\n" &
                "Cache-Control: no-cache\r\n" &
                "Connection: keep-alive\r\n\r\n"
  try: s.send(headers) except CatchableError:
    log.warn("http_gateway: sendSseHeaders failed: " & getCurrentExceptionMsg())

proc sendSseData(s: Socket; event, data: string): bool =
  ## Returns false if the connection is broken.
  try:
    s.send(buildSseEvent(event, data))
    true
  except CatchableError:
    false

# ── Query string parsing ──────────────────────────────────────────────────────

proc parseQueryInt(requestLine: string; key: string; default: int): int =
  let qmark = requestLine.find('?')
  if qmark < 0: return default
  let query = requestLine[qmark + 1 .. ^1]
  for pair in query.split('&'):
    let kv = pair.split('=', 1)
    if kv.len == 2 and kv[0] == key:
      try: return parseInt(kv[1])
      except ValueError: return default
  default

# ── Chat POST parsing ─────────────────────────────────────────────────────────

const
  CliDefaultUserId* = UserId("local:webui")
    ## Default user id for web UI messages.

proc parseChatPost*(body: string): Result[InboundMessage, string] =
  ## Parses a JSON body from POST /api/chat into an InboundMessage.
  ## Expected format: {"text": "message text", "userId": "optional-user-id"}
  if body.len == 0:
    return err("empty body")
  var jsonBody: JsonNode
  try:
    jsonBody = parseJson(body)
  except JsonParsingError as e:
    return err("invalid JSON: " & e.msg)
  if jsonBody.kind != JObject:
    return err("expected JSON object")
  let textNode = jsonBody.getOrDefault("text")
  if textNode.isNil or textNode.kind != JString or textNode.getStr().len == 0:
    return err("missing or empty 'text' field")
  let text = textNode.getStr()
  let userIdNode = jsonBody.getOrDefault("userId")
  var userId = CliDefaultUserId
  if not userIdNode.isNil and userIdNode.kind == JString:
    let uid = userIdNode.getStr()
    if uid.len > 0:
      userId = UserId(uid)
  ok(InboundMessage(
    userId:    userId,
    channelId: "webui",
    text:      text,
    mediaUrl:  "",
    channel:   ckCli,
  ))

# ── Connection handler ────────────────────────────────────────────────────────

proc tryAcquireSseConnection(): bool {.gcsafe.}
proc releaseSseConnection() {.gcsafe.}

proc handleGatewayConn(client: Socket;
                        statusFn: GatewayStatusFn;
                        logFn:    GatewayLogFn;
                        eventFn:  GatewayEventFn;
                        inboundFn: GatewayInboundFn;
                        authToken: string;
                        log:      Logger) {.gcsafe.} =
  try:
    let requestLine = client.readHttpLine()
    if requestLine.len == 0:
      client.close()
      return

    ## Drain headers
    var rawPath = if requestLine.splitWhitespace().len >= 2: requestLine.splitWhitespace()[1] else: "/"
    var contentLength = 0
    var authHeader = ""
    var contentType = ""
    var origin = ""
    while true:
      let h = client.readHttpLine()
      if h.len == 0: break
      let lc = h.toLowerAscii()
      if lc.startsWith("content-length:"):
        let val = lc[15..^1].strip()
        try: contentLength = parseInt(val) except ValueError: discard
      elif lc.startsWith("authorization:"):
        authHeader = h[14..^1].strip()
      elif lc.startsWith("content-type:"):
        contentType = h[13..^1].strip()
      elif lc.startsWith("origin:"):
        origin = h[7..^1].strip()

    let req = parseGatewayRequest(requestLine)
    if req.meth == "OPTIONS":
      client.sendResponse("204 No Content", "text/plain", "", log)
      client.close()
      return
    if not isAuthorized(authHeader, authToken):
      client.sendResponse("401 Unauthorized", "application/json",
                          "{\"error\":\"unauthorized\"}\n", log)
      client.close()
      return
    if authToken.len == 0 and origin.len > 0 and not isLocalOrigin(origin):
      client.sendResponse("403 Forbidden", "application/json",
                          "{\"error\":\"cross-origin access requires a token\"}\n", log)
      client.close()
      return
    let action = routeGatewayRequest(req)

    case action
    of "index":
      client.sendResponse("200 OK", "text/plain",
        "Donkey HTTP gateway\nEndpoints: /api/status /api/logs /api/events /api/chat\n", log)

    of "status":
      let st = statusFn()
      client.sendJson(buildStatusBody(st), log)

    of "logs":
      let n = parseQueryInt(rawPath, "n", 50)
      let entries = logFn(n)
      client.sendJson(buildLogsBody(entries), log)

    of "events":
      if not tryAcquireSseConnection():
        client.sendResponse("503 Service Unavailable", "text/plain",
                            "too many event streams\n", log)
        client.close()
        return
      try:
        client.sendSseHeaders(log)
        ## Push a heartbeat comment immediately to confirm stream started.
        try: client.send(": connected\n\n") except CatchableError: discard
        ## Poll loop: push log + agent event snapshots every SseHeartbeatIntervalMs.
        var lastLogCount   = 0
        var lastEventCount = 0
        for _ in 0 ..< SseMaxPollCycles:
          os.sleep(SseHeartbeatIntervalMs)
          let entries = logFn(100)
          if entries.len > lastLogCount or entries.len > 0:
            lastLogCount = entries.len
            if not client.sendSseData("logs", buildLogsBody(entries)):
              break
          if eventFn != nil:
            let evs = eventFn(100)
            if evs.len > lastEventCount or evs.len > 0:
              lastEventCount = evs.len
              if not client.sendSseData("agent", buildAgentEventsBody(evs)):
                break
          if entries.len == 0 and (eventFn == nil or eventFn(1).len == 0):
            ## Heartbeat comment to keep connection alive.
            try: client.send(": heartbeat\n\n") except CatchableError: break
      finally:
        releaseSseConnection()

    of "chat":
      let methAction = routeChatMethod(req.meth)
      case methAction
      of "chat":
        if not chatRequestAllowed(origin, contentType, authToken):
          client.sendResponse("403 Forbidden", "application/json",
                             "{\"error\":\"cross-origin chat requires a token\"}\n", log)
        elif inboundFn == nil:
          client.sendResponse("503 Service Unavailable", "application/json",
                             "{\"error\":\"inbound handler not configured\"}\n", log)
        else:
          var body = ""
          if contentLength > 0 and contentLength < 1024 * 1024:  # max 1MB
            var buf = newString(contentLength)
            let received = client.recv(buf.addr, contentLength)
            if received > 0:
              body = buf[0 ..< received]
          if body.len == 0:
            client.sendResponse("400 Bad Request", "application/json",
                               "{\"error\":\"empty body\"}\n", log)
          else:
            let msgResult = parseChatPost(body)
            if msgResult.isErr:
              client.sendResponse("400 Bad Request", "application/json",
                                 "{\"error\":\"" & msgResult.error & "\"}\n", log)
            else:
              inboundFn(msgResult.get())
              client.sendResponse("202 Accepted", "application/json",
                                 "{\"status\":\"accepted\"}\n", log)
      of "chat_get":
        client.sendResponse("200 OK", "application/json",
                           "{\"info\":\"POST to /api/chat to send messages\"}\n", log)
      else:
        client.sendResponse("405 Method Not Allowed", "text/plain", "", log)

    of "notfound":
      client.sendResponse("404 Not Found", "text/plain", "Not found\n", log)

    else:
      client.sendResponse("405 Method Not Allowed", "text/plain", "", log)

  except CatchableError:
    let errMsg = getCurrentExceptionMsg()
    log.warn("http_gateway: connection handler error: " & errMsg)
    recordWebhookFailure("http_gateway", errMsg)
  client.close()

# ── Gateway thread ────────────────────────────────────────────────────────────

type GatewayArgs = object
  port:      int
  bindAddr:  string
  authToken: string
  statusFn:  GatewayStatusFn
  logFn:     GatewayLogFn
  eventFn:   GatewayEventFn
  inboundFn: GatewayInboundFn
  log:       Logger

var gGatewayStatusFn: GatewayStatusFn
var gGatewayLogFn:    GatewayLogFn
var gGatewayEventFn:  GatewayEventFn
var gGatewayInboundFn: GatewayInboundFn
var gGatewayLog:      Logger
var gGatewayAuthToken: string

const GatewayWorkerCount = 8
const GatewayQueueDepth = 64

var
  gGatewayQueue {.global.}: Channel[SocketHandle]
  gGatewayWorkers {.global.}: array[GatewayWorkerCount, Thread[int]]
  gGatewayPoolStarted = false
  gGatewayPoolAttempted = false

proc applyClientTimeouts(sock: Socket; seconds: int = 10): Result[void, string] =
  ## Bounds header reads and sends from a connected client.
  var tv: Timeval
  tv.tv_sec = Time(seconds)
  tv.tv_usec = Suseconds(0)
  if setsockopt(sock.getFd, SOL_SOCKET, SO_RCVTIMEO, addr tv, SockLen(sizeof(tv))) != 0:
    return err("SO_RCVTIMEO failed")
  if setsockopt(sock.getFd, SOL_SOCKET, SO_SNDTIMEO, addr tv, SockLen(sizeof(tv))) != 0:
    return err("SO_SNDTIMEO failed")
  ok()

type HttpConnectionArgs = object
  client:    Socket
  statusFn:  GatewayStatusFn
  logFn:     GatewayLogFn
  eventFn:   GatewayEventFn
  inboundFn: GatewayInboundFn
  authToken: string
  log:       Logger

var gActiveHttpConnections = 0
var gActiveSseConnections = 0
var gHttpConnLock: Lock
initLock(gHttpConnLock)  # Module init runs before any gateway thread starts.

proc tryAcquireHttpConnection(): bool =
  acquire(gHttpConnLock)
  try:
    if gActiveHttpConnections >= MaxConcurrentHttpConnections:
      return false
    inc gActiveHttpConnections
    true
  finally:
    release(gHttpConnLock)

proc releaseHttpConnection() =
  acquire(gHttpConnLock)
  try:
    if gActiveHttpConnections > 0:
      dec gActiveHttpConnections
  finally:
    release(gHttpConnLock)

proc tryAcquireSseConnection(): bool =
  acquire(gHttpConnLock)
  try:
    if gActiveSseConnections >= MaxConcurrentSseConnections:
      return false
    inc gActiveSseConnections
    true
  finally:
    release(gHttpConnLock)

proc releaseSseConnection() =
  acquire(gHttpConnLock)
  try:
    if gActiveSseConnections > 0:
      dec gActiveSseConnections
  finally:
    release(gHttpConnLock)

proc gatewayWorker(id: int) {.thread.} =
  {.cast(gcsafe).}:
    while true:
      let fd = gGatewayQueue.recv()
      if fd == SocketHandle(-1):
        break
      var client: Socket
      try:
        client = newSocket(fd, buffered = true)
      except CatchableError as exc:
        gGatewayLog.warn("http_gateway: cannot wrap accepted socket: " & exc.msg)
        discard posix.close(fd)
        releaseHttpConnection()
        continue
      let timeoutResult = applyClientTimeouts(client)
      if timeoutResult.isErr:
        gGatewayLog.warn("http_gateway: " & timeoutResult.error)
        client.close()
        releaseHttpConnection()
        continue
      try:
        handleGatewayConn(client, gGatewayStatusFn, gGatewayLogFn, gGatewayEventFn,
                          gGatewayInboundFn, gGatewayAuthToken, gGatewayLog)
      finally:
        releaseHttpConnection()

proc gatewayThread(args: GatewayArgs) {.thread.} =
  {.cast(gcsafe).}:
    let host =
      if args.bindAddr.startsWith("[") and args.bindAddr.endsWith("]"):
        args.bindAddr[1 .. ^2]
      else:
        args.bindAddr
    let ipv6 = ':' in host
    var server: Socket
    try:
      server =
        if ipv6: newSocket(Domain.AF_INET6, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
        else: newSocket()
      server.setSockOpt(OptReuseAddr, true)
      server.bindAddr(Port(args.port), host)
      server.listen()
    except CatchableError as exc:
      args.log.error("http_gateway: bind " & host & ":" & $args.port & " failed — " & exc.msg)
      if server != nil:
        server.close()
      return
    while true:
      var client: Socket
      server.accept(client)
      let timeoutResult = applyClientTimeouts(client)
      if timeoutResult.isErr:
        args.log.warn("http_gateway: " & timeoutResult.error)
        client.close()
        continue
      if not tryAcquireHttpConnection():
        client.sendResponse("503 Service Unavailable", "text/plain",
                            "too many connections\n", args.log)
        client.close()
        continue
      if not gGatewayQueue.trySend(client.getFd):
        client.sendResponse("503 Service Unavailable", "text/plain",
                            "too many connections\n", args.log)
        client.close()
        releaseHttpConnection()
        continue
      # Ownership of the fd transfers to the worker; do not close here.

var gGatewayThread: Thread[GatewayArgs]

proc startGatewayPool(log: Logger): Result[void, string] =
  ## Opens the queue and starts every worker. Must be called with
  ## `gHttpConnLock` held so concurrent `startHttpGateway` calls cannot start
  ## duplicate workers. The pool is only marked started once the queue is
  ## open; a partial thread-start failure is reported but never retried into
  ## duplicates because the queue cannot be reopened.
  if gGatewayPoolStarted:
    return ok()
  if gGatewayPoolAttempted:
    return err("http_gateway: worker pool initialization already failed; not retrying")
  gGatewayPoolAttempted = true
  try:
    gGatewayQueue.open(GatewayQueueDepth)
  except CatchableError as exc:
    return err("http_gateway: cannot open worker queue — " & exc.msg)

  var started = 0
  var firstError = ""
  for i in 0 ..< GatewayWorkerCount:
    try:
      createThread(gGatewayWorkers[i], gatewayWorker, i)
      inc started
    except CatchableError as exc:
      if firstError.len == 0:
        firstError = exc.msg

  if started > 0:
    gGatewayPoolStarted = true
  if started < GatewayWorkerCount:
    let msg = "http_gateway: started " & $started & "/" & $GatewayWorkerCount &
              " workers — " & firstError
    log.error(msg)
    return err(msg)
  ok()

proc startHttpGateway*(port: int;
                       statusFn: GatewayStatusFn;
                       logFn:    GatewayLogFn;
                       eventFn:  GatewayEventFn = nil;
                       inboundFn: GatewayInboundFn = nil;
                       bindAddr = "127.0.0.1";
                       authToken = "";
                       log:       Logger = newLogger("http_gateway")
                      ): Result[void, string] =
  ## Starts the HTTP gateway on a dedicated OS thread.
  ## statusFn, logFn, and eventFn are called on each request; they must be gcsafe.
  ## inboundFn is called when POST /api/chat is received; may be nil.
  {.cast(gcsafe).}:
    gGatewayStatusFn  = statusFn
    gGatewayLogFn     = logFn
    gGatewayEventFn   = eventFn
    gGatewayInboundFn = inboundFn
    gGatewayLog       = log
    gGatewayAuthToken = authToken
    acquire(gHttpConnLock)
    let poolResult =
      try:
        startGatewayPool(log)
      finally:
        release(gHttpConnLock)
    if poolResult.isErr:
      # startGatewayPool already logged the detailed failure.
      return err(poolResult.error)
    let args = GatewayArgs(port: port, bindAddr: bindAddr, authToken: authToken,
                           statusFn: statusFn, logFn: logFn,
                           eventFn: eventFn, inboundFn: inboundFn, log: log)
    try:
      createThread(gGatewayThread, gatewayThread, args)
    except CatchableError as exc:
      let msg = "http_gateway: cannot start server thread — " & exc.msg
      log.error(msg)
      return err(msg)
    ok()
