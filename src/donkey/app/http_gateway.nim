## HTTP gateway — embedded HTTP/1.1 server for browser/UI clients.
##
## Runs on a dedicated OS thread (same pattern as WeChat/QQ webhook servers).
## Port: DONKEY_HTTP_PORT env var, default 8080.
##
## Endpoints:
##   GET /             → 200 OK, plain-text info
##   GET /api/status   → DaemonStatus JSON
##   GET /api/logs     → recent log entries JSON (?n=N, default 50)
##   GET /api/events   → SSE stream of log events (long-lived connection)
##
## CORS: Access-Control-Allow-Origin: * for local browser access.

import std/[json, net, os, strutils]
import ../ports/ipc
import ../core/agent_events

const
  GatewayDefaultPort* = 8080
  SseHeartbeatIntervalMs = 5000   ## ms between SSE heartbeat/push cycles
  SseMaxPollCycles = 3600         ## ~5 hours at 5s intervals

type
  GatewayRequest* = object
    meth*: string
    path*: string

# ── StatusProvider / LogProvider (same types as ipc_server) ───────────────────

type
  GatewayStatusFn* = proc(): DaemonStatus {.gcsafe.}
  GatewayLogFn*    = proc(n: int): seq[IpcLogEntry] {.gcsafe.}
  GatewayEventFn*  = proc(n: int): seq[AgentEvent] {.gcsafe.}

# ── Pure functions ─────────────────────────────────────────────────────────────

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
  else:                "notfound"

# ── HTTP helpers ──────────────────────────────────────────────────────────────

const CorsHeaders = "Access-Control-Allow-Origin: *\r\n" &
                    "Access-Control-Allow-Methods: GET, OPTIONS\r\n" &
                    "Access-Control-Allow-Headers: Content-Type\r\n"

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

proc sendResponse(s: Socket; status, contentType, body: string) =
  let resp = "HTTP/1.1 " & status & "\r\n" &
             CorsHeaders &
             "Content-Type: " & contentType & "; charset=utf-8\r\n" &
             "Content-Length: " & $body.len & "\r\n" &
             "Connection: close\r\n\r\n" & body
  try: s.send(resp) except CatchableError: discard

proc sendJson(s: Socket; body: string) =
  s.sendResponse("200 OK", "application/json", body)

proc sendSseHeaders(s: Socket) =
  ## Sends SSE-specific response headers, keeps connection open.
  let headers = "HTTP/1.1 200 OK\r\n" &
                CorsHeaders &
                "Content-Type: text/event-stream\r\n" &
                "Cache-Control: no-cache\r\n" &
                "Connection: keep-alive\r\n\r\n"
  try: s.send(headers) except CatchableError: discard

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

# ── Connection handler ────────────────────────────────────────────────────────

proc handleGatewayConn(client: Socket;
                        statusFn: GatewayStatusFn;
                        logFn:    GatewayLogFn;
                        eventFn:  GatewayEventFn) =
  try:
    let requestLine = client.readHttpLine()
    if requestLine.len == 0:
      client.close()
      return

    ## Drain headers
    var rawPath = if requestLine.splitWhitespace().len >= 2: requestLine.splitWhitespace()[1] else: "/"
    while true:
      let h = client.readHttpLine()
      if h.len == 0: break

    let req = parseGatewayRequest(requestLine)
    let action = routeGatewayRequest(req)

    case action
    of "index":
      client.sendResponse("200 OK", "text/plain",
        "Donkey HTTP gateway\nEndpoints: /api/status /api/logs /api/events\n")

    of "status":
      let st = statusFn()
      client.sendJson(buildStatusBody(st))

    of "logs":
      let n = parseQueryInt(rawPath, "n", 50)
      let entries = logFn(n)
      client.sendJson(buildLogsBody(entries))

    of "events":
      client.sendSseHeaders()
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

    of "notfound":
      client.sendResponse("404 Not Found", "text/plain", "Not found\n")

    else:
      client.sendResponse("405 Method Not Allowed", "text/plain", "")

  except CatchableError:
    discard
  client.close()

# ── Gateway thread ────────────────────────────────────────────────────────────

type GatewayArgs = object
  port:     int
  statusFn: GatewayStatusFn
  logFn:    GatewayLogFn
  eventFn:  GatewayEventFn

var gGatewayStatusFn: GatewayStatusFn
var gGatewayLogFn:    GatewayLogFn
var gGatewayEventFn:  GatewayEventFn

proc gatewayThread(args: GatewayArgs) {.thread.} =
  {.cast(gcsafe).}:
    var server = newSocket()
    server.setSockOpt(OptReuseAddr, true)
    server.bindAddr(Port(args.port))
    server.listen()
    while true:
      var client: Socket
      server.accept(client)
      handleGatewayConn(client, args.statusFn, args.logFn, args.eventFn)

var gGatewayThread: Thread[GatewayArgs]

proc startHttpGateway*(port: int;
                       statusFn: GatewayStatusFn;
                       logFn:    GatewayLogFn;
                       eventFn:  GatewayEventFn = nil) =
  ## Starts the HTTP gateway on a dedicated OS thread.
  ## statusFn, logFn, and eventFn are called on each request; they must be gcsafe.
  gGatewayStatusFn = statusFn
  gGatewayLogFn    = logFn
  gGatewayEventFn  = eventFn
  let args = GatewayArgs(port: port, statusFn: statusFn, logFn: logFn, eventFn: eventFn)
  createThread(gGatewayThread, gatewayThread, args)
