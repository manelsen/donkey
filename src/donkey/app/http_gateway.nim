## HTTP gateway — embedded HTTP/1.1 server for browser/UI clients.
##
## Runs on the Chronos event loop of the thread that starts it (the daemon's
## main loop): no worker threads, no shared state, no global callbacks. The
## providers below are captured by the connection handler, and every wait
## (request reads, agent turns, event streams) is an `await`, so one slow
## client never holds up the others.
## Port: DONKEY_HTTP_PORT env var, default 8080.
##
## Endpoints:
##   GET /             → 200 OK, plain-text info (public health probe)
##   GET /health       → 200 OK, plain-text "ok" (public health probe)
##   GET /api/status   → DaemonStatus JSON
##   GET /api/logs     → recent log entries JSON (?n=N, default 50)
##   GET /api/events    → SSE stream of log events (long-lived connection)
##   POST /api/chat     → receive inbound message from web UI (bidirectional SSE)
##
## CORS: Access-Control-Allow-Origin: * for local browser access.
##
## Auth: `GET /`, `/health` and `/dashboard` are public (liveness probes plus a
## data-free shell that asks for the Bearer token and keeps it in
## sessionStorage). Every `/api/*` route, including `/api/sessions` and
## `/api/providers`, requires `Authorization: Bearer <DONKEY_HTTP_TOKEN>` even on
## loopback and even for `OPTIONS`: there is no unauthenticated mode for the
## data routes, so a gateway started without a token answers `401` there and the
## shell is the only thing left open. The `/v1/*` agent routes keep their
## historical local-only behaviour for an empty token; the agent itself already
## refuses to run without one.
##
## The token authenticates the client against the instance, never a user: the
## `user` field of a request is caller-asserted, so any token holder may act as
## any `api:<name>`. Per-user authentication is an explicit PRD non-goal and is
## pinned by `tests/app/t_http_gateway.nim` so the limitation stays deliberate.

import std/[json, options, os, strutils, times]
import chronos
import chronos/transports/stream
import ../core/pipeops
import ../core/types
import ../core/log
import ../ports/ipc
import ../core/agent_events
import ../domain/message
import ../domain/agent_message
import ../domain/providers/openai_compat
import ../domain/gateway/auth_pure
import ../domain/gateway/routing_pure
import ../domain/gateway/dashboard_html
import ../domain/gateway/identity_pure
import ../domain/gateway/dashboard_pure
import ../domain/gateway/redact_pure
import ../domain/gateway/capacity_pure as capacity
import ../domain/gateway/chat_response
import ../ports/gateway_connection
import ./metrics
import ./chat_bridge
import ./agent_chat_runtime
import ./editor_registry
import ./editor_files
import ../domain/acp/editor_gateway_pure
import ../domain/acp/editor_pairing_pure

export auth_pure, routing_pure, dashboard_html

const
  SseHeartbeatIntervalMs = 5000   ## ms between SSE heartbeat/push cycles
  SseMaxPollCycles = 60           ## bounded to ~5 minutes at 5s intervals
  MaxConcurrentHttpConnections = 32
  GatewayMaxHeaderLines = 64
  GatewayMaxHeaderBytes = 64 * 1024
  GatewayRequestDeadlineSec = 15

# ── StatusProvider / LogProvider (same types as ipc_server) ───────────────────

type
  GatewayStatusFn* = proc(): DaemonStatus {.gcsafe, raises: [CatchableError].}
  GatewayLogFn*    = proc(n: int): seq[IpcLogEntry] {.gcsafe, raises: [CatchableError].}
  GatewayEventFn*  = proc(n: int): seq[AgentEvent] {.gcsafe, raises: [CatchableError].}
  GatewayAgentDispatchFn* = proc(msg: InboundMessage) {.gcsafe, raises: [CatchableError].}
    ## Starts one agent turn through the same ingress used by `/api/chat`.

  GatewayResponse* = object
    ## Status + body of a dashboard request, so the socket handler and the
    ## tests exercise the same code.
    status*: int
    contentType*: string
    body*: string

  GatewaySessionsFn* = proc(): seq[SessionDetail] {.gcsafe, raises: [CatchableError].}
    ## Returns every session; paging is applied by `buildSessionsJson`.

  GatewayProvidersFn* = proc(): string {.gcsafe, raises: [CatchableError].}
    ## Returns the provider-health JSON built by `buildProvidersJson`.

  GatewaySessionActionOutcome* = enum
    gsaoAccepted
    gsaoNotFound
    gsaoRevoked

  GatewaySessionActionFn* = proc(rawUserId: string; taskKind: TaskKind;
                                  payload: string): GatewaySessionActionOutcome
                                 {.gcsafe, raises: [CatchableError].}
    ## Performs the one management action. The raw id is the session key, not
    ## an `api:`-prefixed identity; the wiring owns lookup and revocation.

# ── Inbound handler ───────────────────────────────────────────────────────────

type
  GatewayInboundFn* = proc(msg: InboundMessage) {.gcsafe, raises: [CatchableError].}
    ## Callback to handle inbound messages from web UI POST /api/chat.
    ## Called on the event loop that runs the gateway.

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

func dashboardError*(status: int; message: string): GatewayResponse =
  ## Every dashboard error path leaves through `redactForClient`, so an echoed
  ## parser/provider message can never carry `Bearer`, `sk-`, `key=` or
  ## `token=` values to the browser.
  GatewayResponse(status: status, contentType: "application/json",
                  body: $(%*{"error": redactForClient(message)}))

proc handleSessionsRequest*(sessionsFn: GatewaySessionsFn;
                            rawLimit, rawOffset: int): GatewayResponse {.gcsafe.} =
  ## `GET /api/sessions`. The hook returns every row; paging/clamping is pure,
  ## so no query value can turn into a 500.
  if sessionsFn == nil:
    return dashboardError(503, "sessions hook not configured")
  GatewayResponse(status: 200, contentType: "application/json",
                  body: buildSessionsJson(sessionsFn(), rawLimit, rawOffset))

proc handleProvidersRequest*(providersFn: GatewayProvidersFn): GatewayResponse
                            {.gcsafe.} =
  ## `GET /api/providers`. The wiring builds the body with the pure provider
  ## builder, which derives health from availability, cooldowns and metrics.
  if providersFn == nil:
    return dashboardError(503, "providers hook not configured")
  GatewayResponse(status: 200, contentType: "application/json",
                  body: providersFn())

proc handleSessionActionRequest*(actionFn: GatewaySessionActionFn;
                                 rawUserId, body, authHeader,
                                 authToken: string): GatewayResponse {.gcsafe.} =
  ## `POST /api/sessions/{userId}/task`. The raw session key is never passed
  ## through `apiUserId`; auth is checked here as well as in the socket
  ## handler, and a missing hook fails closed. An empty token is a `401` here
  ## like in the socket handler: `/api/*` never runs unauthenticated.
  if authToken.len == 0:
    return dashboardError(401, "api routes require DONKEY_HTTP_TOKEN")
  if not isAuthorized(authHeader, authToken):
    return dashboardError(401, "unauthorized")
  if actionFn == nil:
    return dashboardError(503, "session action hook not configured")
  let parsed = parseSessionAction(body)
  if parsed.isErr:
    return dashboardError(400, parsed.error)
  case actionFn(rawUserId, tkNew, "")
  of gsaoAccepted:
    GatewayResponse(status: 202, contentType: "application/json",
                    body: "{\"status\":\"accepted\"}")
  of gsaoNotFound:
    dashboardError(404, "session not found")
  of gsaoRevoked:
    dashboardError(403, "access revoked")

proc agentNowSeconds(): int64 {.gcsafe, raises: [].} =
  epochTime().int64

proc agentClockMs(): int64 {.gcsafe, raises: [].} =
  int64(epochTime() * 1000)

proc agentNap(ms: int) {.gcsafe, raises: [].} =
  ## Only for a bridge built here when the caller passes none; the turns
  ## themselves wait with `sleepAsync`.
  os.sleep(ms)

# ── Admission ─────────────────────────────────────────────────────────────────
#
# Everything runs on one event loop, so the counters are plain integers: no
# lock and no thread can touch them concurrently. The limits are resource
# caps (open connections, streams, waiting turns), decided by the pure
# `capacity.admitLongLived` policy.

var gActiveHttpConnections = 0
var gActiveSseConnections = 0
var gActiveAgentTurns = 0
  ## Non-streaming `/v1/chat/completions` turns. Streaming chat is counted
  ## as an SSE connection instead, so one request is never counted twice.

proc tryAcquireHttpConnection(): bool {.gcsafe, raises: [].} =
  if gActiveHttpConnections >= MaxConcurrentHttpConnections:
    return false
  inc gActiveHttpConnections
  true

proc releaseHttpConnection() {.gcsafe, raises: [].} =
  if gActiveHttpConnections > 0:
    dec gActiveHttpConnections

proc resetLongLivedCountersForTest*() {.gcsafe, raises: [].} =
  ## Test/diagnostic hook: clears both long-lived counters.
  gActiveAgentTurns = 0
  gActiveSseConnections = 0

proc longLivedOccupancy*(): capacity.LongLivedSnapshot {.gcsafe, raises: [].} =
  ## Occupancy before the next request is decided. `longLivedWorkers` is the
  ## sum of both classes, never just the larger one.
  capacity.LongLivedSnapshot(
    pendingTurns:     gActiveAgentTurns,
    sseConnections:   gActiveSseConnections,
    longLivedWorkers: gActiveAgentTurns + gActiveSseConnections,
  )

proc tryReserveLongLived*(kind: capacity.LongLivedKind):
    capacity.CapacityVerdict {.gcsafe, raises: [].} =
  ## Runs `admitLongLived` against the live counters and increments the class
  ## counter only on `cvAdmit`. A refusal leaves the snapshot untouched, so an
  ## over-capacity request never consumes (or releases) someone else's slot.
  result = capacity.admitLongLived(kind, longLivedOccupancy())
  if result.admitted:
    case kind
    of capacity.llChatTurn: inc gActiveAgentTurns
    of capacity.llSseConnection: inc gActiveSseConnections

proc releaseLongLived*(kind: capacity.LongLivedKind) {.gcsafe, raises: [].} =
  case kind
  of capacity.llChatTurn:
    if gActiveAgentTurns > 0:
      dec gActiveAgentTurns
  of capacity.llSseConnection:
    if gActiveSseConnections > 0:
      dec gActiveSseConnections

proc tryAcquireSseConnection(): bool {.gcsafe, raises: [].} =
  tryReserveLongLived(capacity.llSseConnection).admitted

proc releaseSseConnection() {.gcsafe, raises: [].} =
  releaseLongLived(capacity.llSseConnection)

proc runAdmittedAgentTurn*(body: string;
                           bridge: ChatBridge;
                           dispatch: GatewayAgentDispatchFn;
                           authorize: AuthorizeFn;
                           tokenConfigured: bool;
                           now: AgentNowFn;
                           timeoutMs: int;
                           model: string;
                           nap: AgentNapFn = nil): Future[AgentChatReply]
                          {.async.} =
  ## Non-streaming `/v1/chat/completions`: reserve one long-lived slot before
  ## the turn can register or dispatch. A refusal never reaches the dispatch
  ## hook and keeps the streaming path's mapping: `429` with a
  ## `rate_limit_error` body for both capacity verdicts (`cvNoWorker` is a
  ## backlog condition that clears on its own, not a server fault). The code
  ## still distinguishes a full turn queue from a full shared pool.
  ##
  ## `finally` releases the reservation on every exit: 200, 502 from a
  ## dispatch/turn error, 504 on the deadline, or an escaping exception. The
  ## release happens before the response is written, so a client abort cannot
  ## strand the slot.
  let verdict = tryReserveLongLived(capacity.llChatTurn)
  if not verdict.admitted:
    var code = "no_worker"
    var message = "no long-lived worker available"
    case verdict
    of capacity.cvTooManyPendingTurns:
      code = "too_many_pending_turns"
      message = "too many pending chat turns"
    of capacity.cvNoWorker:
      discard
    of capacity.cvTooManySseConnections:
      code = "sse_capacity"
      message = "too many concurrent streams"
    of capacity.cvAdmit:
      discard  # unreachable: cvAdmit was handled above
    return AgentChatReply(
      status: 429,
      body: buildAgentError(message, "rate_limit_error", code),
    )
  try:
    return await runAgentChat(
      body            = body,
      bridge          = bridge,
      dispatch        = dispatch,
      authorize       = authorize,
      tokenConfigured = tokenConfigured,
      now             = now,
      timeoutMs       = timeoutMs,
      model           = model,
      nap             = nap,
    )
  finally:
    releaseLongLived(capacity.llChatTurn)

# ── HTTP over the connection port ─────────────────────────────────────────────

proc readHttpLine(conn: GatewayConnection; deadline: Moment):
    Future[Result[string, string]] {.async: (raises: []).} =
  ## One CRLF/LF line with a bounded length under the request deadline, which
  ## bounds the whole request (a slowloris client cannot stretch it).
  if Moment.now() >= deadline:
    return err("request deadline exceeded")
  let read = await conn.readLine(GatewayMaxRequestLine + 1, deadline)
  if read.isErr:
    return err(read.error)
  var line = read.get()
  if line.len > GatewayMaxRequestLine:
    return err("request line too long")
  if line.endsWith("\r"):
    line.setLen(line.len - 1)
  if line.len == 0 and conn.atEof():
    return err("connection closed")
  return ok(line)

proc sendRaw(conn: GatewayConnection; data: string): Future[bool]
    {.async: (raises: []).} =
  ## False when the client is gone; the callers stop writing then and log
  ## where it matters (the cause is the client, not the daemon).
  if data.len == 0:
    return true
  return (await conn.write(data)).isOk

proc sendResponse(conn: GatewayConnection; status, contentType, body: string;
                  log: Logger): Future[void] {.async: (raises: []).} =
  if not await conn.sendRaw(httpResponseText(status, contentType, body)):
    log.warn("http_gateway: sendResponse failed: client gone")

proc sendJson(conn: GatewayConnection; body: string; log: Logger): Future[void]
    {.async: (raises: []).} =
  await conn.sendResponse("200 OK", "application/json", body, log)

proc sendSseHeaders(conn: GatewayConnection; log: Logger): Future[bool]
    {.async: (raises: []).} =
  ## Returns false when the client is already gone.
  result = await conn.sendRaw(sseResponseHeaders())
  if not result:
    log.warn("http_gateway: sendSseHeaders failed: client gone")

proc sendSseData(conn: GatewayConnection; event, data: string): Future[bool]
    {.async: (raises: []).} =
  ## Returns false if the connection is broken.
  return await conn.sendRaw(buildSseEvent(event, data))

proc readRequestBody(conn: GatewayConnection; contentLength: int;
                     deadline: Moment): Future[string] {.async: (raises: []).} =
  ## Reads at most `contentLength` bytes before the request deadline. Returns
  ## whatever arrived; the caller validates emptiness.
  if contentLength <= 0:
    return ""
  var body = newStringOfCap(contentLength)
  while body.len < contentLength:
    let chunk = await conn.readSome(contentLength - body.len, deadline)
    ## End of stream, the deadline or a failed read: the body is what came,
    ## and `readRequestBodyStrict` refuses it when it is short.
    if chunk.isErr or chunk.get().len == 0:
      break
    body.add chunk.get()
  return body

proc readRequestBodyStrict(conn: GatewayConnection; contentLength: int;
                           deadline: Moment): Future[Result[string, string]]
                          {.async: (raises: []).} =
  ## Like `readRequestBody`, but refuses a short read: a JSON prefix is not the
  ## body the client declared, and acting on it would accept a truncated
  ## request.
  let body = await conn.readRequestBody(contentLength, deadline)
  if body.len != max(contentLength, 0):
    return err("request body incomplete")
  return ok(body)

# ── Connection handler ────────────────────────────────────────────────────────

type
  GatewayApprovalInputFn* = proc(userId: UserId; text: string): Option[string] {.gcsafe, raises: [].}
    ## The channels' approval handler (`tryHandleApprovalInput`).

  GatewayContext* = ref object
    ## Everything a connection needs; built once by `newGatewayContext`.
    statusFn:        GatewayStatusFn
    logFn:           GatewayLogFn
    eventFn:         GatewayEventFn
    inboundFn:       GatewayInboundFn
    agentDispatchFn: GatewayAgentDispatchFn
    sessionsFn:      GatewaySessionsFn
    providersFn:     GatewayProvidersFn
    sessionActionFn: GatewaySessionActionFn
    authorizeFn:     AuthorizeFn
    chatBridge:      ChatBridge
    modelName:       string
    agentTimeoutMs:  int
    authToken:       string
    editors:         EditorRegistry   ## nil = no editor routes (E10.2)
    approvalInput:   GatewayApprovalInputFn
    editorFiles:     EditorFileRequests  ## E10.5: answers to requests sent to the editor
      ## An approval's button pressed in the editor (E10.4); nil = refused.
    log:             Logger

proc handleGatewayConn(ctx: GatewayContext; client: GatewayConnection)
    {.async: (raises: []).} =
  let log = ctx.log
  try:
    let deadline = Moment.now() + chronos.seconds(GatewayRequestDeadlineSec)
    let requestLineResult = await client.readHttpLine(deadline)
    if requestLineResult.isErr:
      if requestLineResult.error != "connection closed":
        await client.sendResponse("400 Bad Request", "text/plain",
                                  requestLineResult.error & "\n", log)
      return
    let requestLine = requestLineResult.get
    if requestLine.len == 0:
      return

    ## Drain headers with bounded line count/bytes and a total deadline.
    let rawPath = if requestLine.splitWhitespace().len >= 2: requestLine.splitWhitespace()[1] else: "/"
    var contentLength = 0
    var authHeader = ""
    var contentType = ""
    var origin = ""
    var headerLines = 0
    var headerBytes = 0
    while true:
      if headerLines >= GatewayMaxHeaderLines:
        await client.sendResponse("400 Bad Request", "text/plain", "too many headers\n", log)
        return
      let headerResult = await client.readHttpLine(deadline)
      if headerResult.isErr:
        await client.sendResponse("400 Bad Request", "text/plain",
                                  headerResult.error & "\n", log)
        return
      inc headerLines
      headerBytes += headerResult.value.len
      if headerBytes > GatewayMaxHeaderBytes:
        await client.sendResponse("400 Bad Request", "text/plain", "headers too large\n", log)
        return
      let h = headerResult.value
      if h.len == 0: break
      let lc = h.toLowerAscii()
      if lc.startsWith("content-length:"):
        let val = lc[15..^1].strip()
        try:
          let parsed = parseBiggestInt(val)
          if parsed > MaxApiRequestBytes:
            await client.sendResponse("413 Payload Too Large", "application/json",
                                      "{\"error\":{\"message\":\"body too large\"," &
                                      "\"type\":\"invalid_request_error\"," &
                                      "\"code\":\"payload_too_large\"}}\n", log)
            return
          contentLength = parsed.int
        except ValueError:
          discard
      elif lc.startsWith("authorization:"):
        authHeader = h[14..^1].strip()
      elif lc.startsWith("content-type:"):
        contentType = h[13..^1].strip()
      elif lc.startsWith("origin:"):
        origin = h[7..^1].strip()

    let req = parseGatewayRequest(requestLine)
    var action = routeGatewayRequest(req)
    if req.meth == "OPTIONS":
      ## Preflights are answered before the body is read, but `/api/*` still
      ## needs the bearer check: `Access-Control-Allow-Origin: *` would
      ## otherwise let any page probe the data routes from loopback.
      if isApiRouteAction(action) and
         not isAuthorized(authHeader, ctx.authToken):
        await client.sendResponse("401 Unauthorized", "application/json",
                                  "{\"error\":\"unauthorized\"}\n", log)
        return
      await client.sendResponse("204 No Content", "text/plain", "", log)
      return
    var sessionTaskUser = ""
    if action == "notfound" and req.meth == "POST":
      let parsedTaskPath = parseSessionTaskPath(req.path)
      if parsedTaskPath.isOk:
        action = "session_task"
        sessionTaskUser = parsedTaskPath.get()
    case gatewayAuthVerdict(action, authHeader, ctx.authToken)
    of gavRejected:
      await client.sendResponse("401 Unauthorized", "application/json",
                                "{\"error\":\"unauthorized\"}\n", log)
      return
    of gavNoToken:
      await client.sendResponse("401 Unauthorized", "application/json",
                                "{\"error\":\"api routes require DONKEY_HTTP_TOKEN\"}\n", log)
      return
    of gavPublic, gavAllowed, gavEditor:
      discard
    if isEditorAction(action) and ctx.editors.isNil:
      action = "notfound"
    if not isPublicGatewayAction(action) and ctx.authToken.len == 0 and
       origin.len > 0 and not isLocalOrigin(origin):
      await client.sendResponse("403 Forbidden", "application/json",
                                "{\"error\":\"cross-origin access requires a token\"}\n", log)
      return

    case action
    of "index":
      await client.sendResponse("200 OK", "text/plain",
        "Donkey HTTP gateway\nEndpoints: /dashboard /api/status /api/logs /api/events /api/chat /v1/models /v1/chat/completions\n", log)

    of "health":
      await client.sendResponse("200 OK", "text/plain", "ok\n", log)

    of "dashboard":
      await client.sendResponse("200 OK", "text/html", buildDashboardHtml(), log)

    of "status":
      await client.sendJson(buildStatusBody(ctx.statusFn()), log)

    of "logs":
      let n = parseQueryInt(rawPath, "n", 50)
      await client.sendJson(buildLogsBody(ctx.logFn(n)), log)

    of "sessions":
      if req.meth != "GET":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let limit = parseQueryInt(rawPath, "limit", DashboardDefaultLimit)
        let offset = parseQueryInt(rawPath, "offset", 0)
        let res = handleSessionsRequest(ctx.sessionsFn, limit, offset)
        await client.sendResponse(httpStatusLine(res.status), res.contentType,
                                  res.body, log)

    of "providers":
      if req.meth != "GET":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let res = handleProvidersRequest(ctx.providersFn)
        await client.sendResponse(httpStatusLine(res.status), res.contentType,
                                  res.body, log)

    of "session_task":
      if req.meth != "POST":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let bodyResult = await client.readRequestBodyStrict(contentLength, deadline)
        if bodyResult.isErr:
          await client.sendResponse("400 Bad Request", "application/json",
                                    "{\"error\":\"request body incomplete\"}\n", log)
          return
        let res = handleSessionActionRequest(ctx.sessionActionFn, sessionTaskUser,
                                             bodyResult.get(), authHeader, ctx.authToken)
        await client.sendResponse(httpStatusLine(res.status), res.contentType,
                                  res.body, log)

    of "events":
      if not tryAcquireSseConnection():
        await client.sendResponse("503 Service Unavailable", "text/plain",
                                  "too many event streams\n", log)
        return
      try:
        if not await client.sendSseHeaders(log):
          return
        ## Push a heartbeat comment immediately to confirm stream started.
        if not await client.sendRaw(": connected\n\n"):
          return
        ## Poll loop: push log + agent event snapshots every SseHeartbeatIntervalMs.
        for _ in 0 ..< SseMaxPollCycles:
          await sleepAsync(chronos.milliseconds(SseHeartbeatIntervalMs))
          let entries = ctx.logFn(100)
          if entries.len > 0:
            if not await client.sendSseData("logs", buildLogsBody(entries)):
              break
          var agentEvents = 0
          if ctx.eventFn != nil:
            let evs = ctx.eventFn(100)
            agentEvents = evs.len
            if evs.len > 0:
              if not await client.sendSseData("agent", buildAgentEventsBody(evs)):
                break
          if entries.len == 0 and agentEvents == 0:
            ## Heartbeat comment to keep connection alive.
            if not await client.sendRaw(": heartbeat\n\n"):
              break
      finally:
        releaseSseConnection()

    of "chat":
      let methAction = routeChatMethod(req.meth)
      case methAction
      of "chat":
        if not chatRequestAllowed(origin, contentType, ctx.authToken):
          await client.sendResponse("403 Forbidden", "application/json",
                                    "{\"error\":\"cross-origin chat requires a token\"}\n", log)
        elif ctx.inboundFn == nil:
          await client.sendResponse("503 Service Unavailable", "application/json",
                                    "{\"error\":\"inbound handler not configured\"}\n", log)
        else:
          let body = await client.readRequestBody(contentLength, deadline)
          if body.len == 0:
            await client.sendResponse("400 Bad Request", "application/json",
                                      "{\"error\":\"empty body\"}\n", log)
          else:
            let msgResult = parseChatPost(body)
            if msgResult.isErr:
              await client.sendResponse("400 Bad Request", "application/json",
                                        "{\"error\":\"" & msgResult.error & "\"}\n", log)
            else:
              ctx.inboundFn(msgResult.get())
              await client.sendResponse("202 Accepted", "application/json",
                                        "{\"status\":\"accepted\"}\n", log)
      of "chat_get":
        await client.sendResponse("200 OK", "application/json",
                                  "{\"info\":\"POST to /api/chat to send messages\"}\n", log)
      else:
        await client.sendResponse("405 Method Not Allowed", "text/plain", "", log)

    of "acp_pair", "acp_pair_poll":
      ## Pairing an editor (E10.2): no credential yet; the poll is
      ## authenticated by the pairing's secret.
      if req.meth != "POST":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      elif contentLength > MaxEditorRequestBytes:
        await client.sendResponse("413 Payload Too Large", "application/json",
                                  "{\"error\":\"body too large\"}\n", log)
      else:
        let body = await client.readRequestBody(contentLength, deadline)
        if action == "acp_pair":
          let name = parsePairRequest(body)
          let started =
            if name.isErr: Result[PairingStarted, string].err(name.error)
            else: ctx.editors.beginPairing(name.get)
          if started.isErr:
            await client.sendResponse("429 Too Many Requests", "application/json",
                                      $(%* {"error": started.error}) & "\n", log)
          else:
            await client.sendResponse("200 OK", "application/json",
              $pairStartedBody(started.get.code, started.get.secret,
                               int(EditorPairingTtlMs div 1000)) & "\n", log)
        else:
          let secret = parsePollRequest(body)
          if secret.isErr:
            await client.sendResponse("400 Bad Request", "application/json",
                                      $(%* {"error": secret.error}) & "\n", log)
          else:
            let collected = ctx.editors.collectPairing(secret.get)
            if collected.isErr:
              log.warn("editor pairing: " & collected.error)
              await client.sendResponse("500 Internal Server Error", "application/json",
                                        "{\"error\":\"the credential could not be saved\"}\n", log)
            else:
              let reply = pollReply(collected.get.state, collected.get.token)
              await client.sendResponse(httpStatusLine(reply.status), "application/json",
                                        $reply.body & "\n", log)

    of "acp_approve":
      ## The person answered an approval in the editor (E10.4): the same
      ## handler as a channel's button, as the person the credential names.
      let person = ctx.editors.personFor(parseBearerToken(authHeader))
      if person.isErr:
        await client.sendResponse("401 Unauthorized", "application/json",
                                  "{\"error\":\"unknown editor; pair again\"}\n", log)
      elif req.meth != "POST":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      elif contentLength > MaxEditorRequestBytes:
        await client.sendResponse("413 Payload Too Large", "application/json",
                                  "{\"error\":\"body too large\"}\n", log)
      else:
        let body = await client.readRequestBody(contentLength, deadline)
        let callback = parseApproveRequest(body)
        if callback.isErr:
          await client.sendResponse("400 Bad Request", "application/json",
                                    $(%* {"error": callback.error}) & "\n", log)
        elif ctx.approvalInput.isNil:
          await client.sendResponse("503 Service Unavailable", "application/json",
                                    "{\"error\":\"approvals are not available\"}\n", log)
        else:
          let reply = ctx.approvalInput(person.get, callback.get)
          await client.sendResponse("200 OK", "application/json",
            $(%* {"result": reply.get("")}) & "\n", log)

    of "acp_editor_result":
      ## The editor's answer to a request the daemon sent through the stream
      ## (E10.5): only the person whose turn asked can answer it.
      let person = ctx.editors.personFor(parseBearerToken(authHeader))
      if person.isErr:
        await client.sendResponse("401 Unauthorized", "application/json",
                                  "{\"error\":\"unknown editor; pair again\"}\n", log)
      elif req.meth != "POST":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      elif contentLength > MaxEditorResultBytes:
        await client.sendResponse("413 Payload Too Large", "application/json",
                                  "{\"error\":\"body too large\"}\n", log)
      elif ctx.editorFiles.isNil:
        await client.sendResponse("503 Service Unavailable", "application/json",
                                  "{\"error\":\"editor requests are not available\"}\n", log)
      else:
        let body = await client.readRequestBody(contentLength, deadline)
        let answer = parseEditorResult(body)
        if answer.isErr:
          await client.sendResponse("400 Bad Request", "application/json",
                                    $(%* {"error": answer.error}) & "\n", log)
        else:
          let taken = ctx.editorFiles.answer(person.get, answer.get.id,
                                             answer.get.content, answer.get.error)
          if taken.isErr:
            await client.sendResponse("404 Not Found", "application/json",
                                      $(%* {"error": taken.error}) & "\n", log)
          else:
            await client.sendResponse("200 OK", "application/json", "{}\n", log)

    of "acp_chat":
      ## An editor's turn (E10.2): its credential says who the person is;
      ## the same stream as /v1/chat/completions.
      let person = ctx.editors.personFor(parseBearerToken(authHeader))
      if person.isErr:
        await client.sendResponse("401 Unauthorized", "application/json",
                                  "{\"error\":\"unknown editor; pair again\"}\n", log)
      elif req.meth != "POST":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let body = await client.readRequestBody(contentLength, deadline)
        if not agentChatStreamRequested(body):
          await client.sendResponse("400 Bad Request", "application/json",
                                    "{\"error\":\"the editor route streams: set stream to true\"}\n", log)
        else:
          let openSse: AgentStreamOpenFn = proc(): Future[bool] {.async.} =
            return await client.sendSseHeaders(log)
          let sendSse: AgentStreamSendFn = proc(chunk: string): Future[bool] {.async.} =
            return await client.sendRaw(chunk)
          let streamResult = await runAgentStream(
            body            = body,
            bridge          = ctx.chatBridge,
            dispatch        = ctx.agentDispatchFn,
            authorize       = ctx.authorizeFn,
            tokenConfigured = true,
            now             = agentNowSeconds,
            openStream      = openSse,
            send            = sendSse,
            acquireSlot     = tryAcquireSseConnection,
            releaseSlot     = releaseSseConnection,
            streamNow       = agentClockMs,
            timeoutMs       = ctx.agentTimeoutMs,
            model           = ctx.modelName,
            asUser          = person.get)
          if streamResult.outcome == asPreflightError:
            await client.sendResponse(httpStatusLine(streamResult.reply.status),
                                      "application/json",
                                      streamResult.reply.body & "\n", log)

    of "openai_chat":
      if req.meth != "POST":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let body = await client.readRequestBody(contentLength, deadline)
        if agentChatStreamRequested(body):
          let openSse: AgentStreamOpenFn = proc(): Future[bool] {.async.} =
            return await client.sendSseHeaders(log)
          let sendSse: AgentStreamSendFn = proc(chunk: string): Future[bool] {.async.} =
            return await client.sendRaw(chunk)
          let streamResult = await runAgentStream(
            body            = body,
            bridge          = ctx.chatBridge,
            dispatch        = ctx.agentDispatchFn,
            authorize       = ctx.authorizeFn,
            tokenConfigured = ctx.authToken.len > 0,
            now             = agentNowSeconds,
            openStream      = openSse,
            send            = sendSse,
            acquireSlot     = tryAcquireSseConnection,
            releaseSlot     = releaseSseConnection,
            streamNow       = agentClockMs,
            timeoutMs       = ctx.agentTimeoutMs,
            model           = ctx.modelName,
          )
          if streamResult.outcome == asPreflightError:
            await client.sendResponse(httpStatusLine(streamResult.reply.status),
                                      "application/json",
                                      streamResult.reply.body & "\n", log)
        else:
          let reply = await runAdmittedAgentTurn(
            body            = body,
            bridge          = ctx.chatBridge,
            dispatch        = ctx.agentDispatchFn,
            authorize       = ctx.authorizeFn,
            tokenConfigured = ctx.authToken.len > 0,
            now             = agentNowSeconds,
            timeoutMs       = ctx.agentTimeoutMs,
            model           = ctx.modelName,
          )
          await client.sendResponse(httpStatusLine(reply.status), "application/json",
                                    reply.body & "\n", log)

    of "openai_models":
      if req.meth != "GET":
        await client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        await client.sendJson(buildOpenAiModels(ctx.modelName, epochTime().int64), log)

    of "notfound":
      await client.sendResponse("404 Not Found", "text/plain", "Not found\n", log)

    else:
      await client.sendResponse("405 Method Not Allowed", "text/plain", "", log)

  except CancelledError:
    discard
  except CatchableError as e:
    log.warn("http_gateway: connection handler error: " & e.msg)
    recordWebhookFailure("http_gateway", e.msg)

# ── Serving ───────────────────────────────────────────────────────────────────

proc newGatewayContext*(statusFn: GatewayStatusFn;
                        logFn:    GatewayLogFn;
                        eventFn:  GatewayEventFn = nil;
                        inboundFn: GatewayInboundFn = nil;
                        sessionsFn: GatewaySessionsFn = nil;
                        providersFn: GatewayProvidersFn = nil;
                        sessionActionFn: GatewaySessionActionFn = nil;
                        authToken = "";
                        agentDispatchFn: GatewayAgentDispatchFn = nil;
                        authorizeFn: AuthorizeFn = nil;
                        chatBridge: ChatBridge = nil;
                        modelName = "";
                        agentTimeoutMs = 0;
                        editors: EditorRegistry = nil;
                        approvalInput: GatewayApprovalInputFn = nil;
                        editorFiles: EditorFileRequests = nil;
                        log:       Logger = newLogger("http_gateway")
                       ): Result[GatewayContext, string] =
  ## What every connection is served with. The providers are called on the
  ## loop that runs the gateway, so they need no locking. A private bridge is
  ## never fed by the daemon outbox drainer: every turn would register and
  ## poll a queue nobody drains, ending in 504.
  if agentDispatchFn != nil and chatBridge == nil:
    return err("http_gateway: the agent endpoint requires the shared ChatBridge")
  ok(GatewayContext(
    statusFn: statusFn, logFn: logFn, eventFn: eventFn, inboundFn: inboundFn,
    agentDispatchFn: agentDispatchFn, sessionsFn: sessionsFn,
    providersFn: providersFn, sessionActionFn: sessionActionFn,
    authorizeFn: authorizeFn,
    chatBridge: if chatBridge != nil: chatBridge
                else: newChatBridge(agentClockMs, agentNap),
    modelName: modelName,
    agentTimeoutMs:
      if agentTimeoutMs > 0: agentTimeoutMs
      else: resolveAgentTimeoutMs(""),
    authToken: authToken,
    editors: editors,
    approvalInput: approvalInput,
    editorFiles: editorFiles,
    log: log))

proc serveGatewayConnection*(ctx: GatewayContext; conn: GatewayConnection)
    {.async: (raises: []).} =
  ## Serves one accepted connection: admission (a connection cap), then the
  ## request. The server closes the connection afterwards.
  if not tryAcquireHttpConnection():
    await conn.sendResponse("503 Service Unavailable", "text/plain",
                            "too many connections\n", ctx.log)
    return
  try:
    await handleGatewayConn(ctx, conn)
  finally:
    releaseHttpConnection()
