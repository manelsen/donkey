## The HTTP/1.1 server: sockets, request handling, worker pool and lifecycle.
##
## Extracted from `http_gateway`; state lives in `gateway_types`, pure routing
## in `gateway_routes`, auth policy in `gateway_auth`.

import std/[monotimes, net, os, strutils, times]
import locks
import std/posix
import ../core/pipeops
import ../core/log
import ../domain/providers/openai_compat
import ../domain/gateway/identity_pure
import ../domain/gateway/dashboard_pure
import ../domain/gateway/chat_response
import ../domain/gateway/capacity_pure as capacity
import ./metrics
import ./chat_bridge
import ./agent_chat_runtime
import ./gateway_types
import ./gateway_routes
import ./gateway_auth
import ./dashboard_assets

proc agentNowSeconds(): int64 {.gcsafe, raises: [].} =
  epochTime().int64

proc agentClockMs(): int64 {.gcsafe, raises: [].} =
  int64(epochTime() * 1000)

proc agentNap(ms: int) {.gcsafe, raises: [].} =
  os.sleep(ms)

# ── HTTP helpers ──────────────────────────────────────────────────────────────

proc readHttpLine(s: Socket; deadline: MonoTime): Result[string, string] =
  ## Reads one CRLF/LF line with a bounded length and a total request deadline.
  ## `SO_RCVTIMEO` alone only bounds each blocking recv, not slowloris clients.
  var line = ""
  while line.len < GatewayMaxRequestLine:
    if getMonoTime() > deadline:
      return err("request deadline exceeded")
    var c: char
    let n = s.recv(c.addr, 1)
    if n <= 0:
      return err("connection closed or read timed out")
    if c == '\r':
      var lf: char
      discard s.recv(lf.addr, 1)
      return ok(line)
    if c == '\n':
      return ok(line)
    line.add(c)
  err("request line too long")

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

proc sendSseHeaders(s: Socket; log: Logger): bool =
  ## Sends SSE-specific response headers, keeps connection open.
  ## Returns false when the client is already gone.
  let headers = "HTTP/1.1 200 OK\r\n" &
                CorsHeaders &
                "Content-Type: text/event-stream\r\n" &
                "Cache-Control: no-cache\r\n" &
                "Connection: keep-alive\r\n\r\n"
  try:
    s.send(headers)
    true
  except CatchableError:
    log.warn("http_gateway: sendSseHeaders failed: " & getCurrentExceptionMsg())
    false

proc sendSseData(s: Socket; event, data: string): bool =
  ## Returns false if the connection is broken.
  try:
    s.send(buildSseEvent(event, data))
    true
  except CatchableError:
    false

proc readRequestBody(client: Socket; contentLength: int;
                    deadline: MonoTime): string =
  ## Reads at most `contentLength` bytes before the request deadline. Returns
  ## whatever arrived; the caller validates emptiness.
  if contentLength <= 0:
    return ""
  var buf = newString(contentLength)
  var received = 0
  while received < contentLength:
    if getMonoTime() > deadline:
      break
    let n = client.recv(buf[received].addr, contentLength - received)
    if n <= 0:
      break
    received += n
  if received > 0: buf[0 ..< received] else: ""

proc readRequestBodyStrict(client: Socket; contentLength: int;
                           deadline: MonoTime): Result[string, string] =
  ## Like `readRequestBody`, but refuses a short read: a JSON prefix is not the
  ## body the client declared, and acting on it would accept a truncated
  ## request.
  if contentLength <= 0:
    return ok("")
  var buf = newString(contentLength)
  var received = 0
  while received < contentLength:
    if getMonoTime() > deadline:
      return err("request body incomplete")
    let n = client.recv(buf[received].addr, contentLength - received)
    if n <= 0:
      break
    received += n
  if received != contentLength:
    return err("request body incomplete")
  ok(buf)

proc applyClientTimeouts(sock: Socket; seconds: int = 10): Result[void, string] =
  ## Bounds header reads and sends from a connected client.
  var tv: posix.Timeval
  tv.tv_sec = posix.Time(seconds)
  tv.tv_usec = posix.Suseconds(0)
  if setsockopt(sock.getFd, SOL_SOCKET, SO_RCVTIMEO, addr tv, SockLen(sizeof(tv))) != 0:
    return err("SO_RCVTIMEO failed")
  if setsockopt(sock.getFd, SOL_SOCKET, SO_SNDTIMEO, addr tv, SockLen(sizeof(tv))) != 0:
    return err("SO_SNDTIMEO failed")
  ok()

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

# ── Long-lived worker admission ───────────────────────────────────────────────
#
# Non-streaming agent turns and SSE streams both block a gateway worker for
# their whole lifetime. They share one counter set under `gHttpConnLock` and
# one policy (`capacity.admitLongLived`): at most `MaxLongLivedWorkers` of the
# 8 workers may be long-lived, so `/health`, `/api/*` and `/v1/models` always
# keep the 2 reserved workers. There is no second pool and no class is exempt.

proc resetLongLivedCountersForTest*() {.gcsafe.} =
  ## Test/diagnostic hook: clears both counters. The gateway never calls it and
  ## it must not run while worker threads are serving requests.
  acquire(gHttpConnLock)
  try:
    gActiveAgentTurns = 0
    gActiveSseConnections = 0
  finally:
    release(gHttpConnLock)

proc longLivedOccupancy*(): capacity.LongLivedSnapshot {.gcsafe.} =
  ## Occupancy before the next request is decided. `longLivedWorkers` is the
  ## sum of both classes, never just the larger one.
  acquire(gHttpConnLock)
  try:
    capacity.LongLivedSnapshot(
      pendingTurns:     gActiveAgentTurns,
      sseConnections:   gActiveSseConnections,
      longLivedWorkers: gActiveAgentTurns + gActiveSseConnections,
    )
  finally:
    release(gHttpConnLock)

proc tryReserveLongLived*(kind: capacity.LongLivedKind):
    capacity.CapacityVerdict {.gcsafe.} =
  ## Runs `admitLongLived` against the live counters and increments the class
  ## counter only on `cvAdmit`. A refusal leaves the snapshot untouched, so an
  ## over-capacity request never consumes (or releases) someone else's worker.
  acquire(gHttpConnLock)
  try:
    let snapshot = capacity.LongLivedSnapshot(
      pendingTurns:     gActiveAgentTurns,
      sseConnections:   gActiveSseConnections,
      longLivedWorkers: gActiveAgentTurns + gActiveSseConnections,
    )
    result = capacity.admitLongLived(kind, snapshot)
    if result.admitted:
      case kind
      of capacity.llChatTurn: inc gActiveAgentTurns
      of capacity.llSseConnection: inc gActiveSseConnections
  finally:
    release(gHttpConnLock)

proc releaseLongLived*(kind: capacity.LongLivedKind) {.gcsafe.} =
  acquire(gHttpConnLock)
  try:
    case kind
    of capacity.llChatTurn:
      if gActiveAgentTurns > 0:
        dec gActiveAgentTurns
    of capacity.llSseConnection:
      if gActiveSseConnections > 0:
        dec gActiveSseConnections
  finally:
    release(gHttpConnLock)

proc tryAcquireSseConnection(): bool {.gcsafe.} =
  tryReserveLongLived(capacity.llSseConnection).admitted

proc releaseSseConnection() {.gcsafe.} =
  releaseLongLived(capacity.llSseConnection)

proc runAdmittedAgentTurn*(body: string;
                           bridge: ChatBridge;
                           dispatch: GatewayAgentDispatchFn;
                           authorize: AuthorizeFn;
                           tokenConfigured: bool;
                           now: AgentNowFn;
                           timeoutMs = DefaultAgentTurnTimeoutMs;
                           model = ""): AgentChatReply {.gcsafe.} =
  ## Non-streaming `/v1/chat/completions`: reserve one long-lived worker
  ## before the turn can register or dispatch. A refusal never reaches the
  ## dispatch hook and keeps the streaming path's mapping: `429` with a
  ## `rate_limit_error` body for both capacity verdicts (`cvNoWorker` is a
  ## backlog condition that clears on its own, not a server fault, so `503`
  ## would invite clients to retry a different way for no benefit). The code
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
    runAgentChat(
      body            = body,
      bridge          = bridge,
      dispatch        = dispatch,
      authorize       = authorize,
      tokenConfigured = tokenConfigured,
      now             = now,
      timeoutMs       = timeoutMs,
      model           = model,
    )
  finally:
    releaseLongLived(capacity.llChatTurn)

proc handleGatewayConn(client: Socket;
                        statusFn: GatewayStatusFn;
                        logFn:    GatewayLogFn;
                        eventFn:  GatewayEventFn;
                        inboundFn: GatewayInboundFn;
                        agentDispatchFn: GatewayAgentDispatchFn;
                        sessionsFn: GatewaySessionsFn;
                        providersFn: GatewayProvidersFn;
                        sessionActionFn: GatewaySessionActionFn;
                        authorizeFn: AuthorizeFn;
                        chatBridge: ChatBridge;
                        modelName: string;
                        agentTimeoutMs: int;
                        authToken: string;
                        log:      Logger) {.gcsafe.} =
  defer:
    try: client.close() except CatchableError: discard
  try:
    let deadline = getMonoTime() + initDuration(seconds = GatewayRequestDeadlineSec)
    let requestLineResult = client.readHttpLine(deadline)
    if requestLineResult.isErr:
      client.sendResponse("400 Bad Request", "text/plain",
                          requestLineResult.error & "\n", log)
      return
    let requestLine = requestLineResult.get
    if requestLine.len == 0:
      return

    ## Drain headers with bounded line count/bytes and a total deadline.
    var rawPath = if requestLine.splitWhitespace().len >= 2: requestLine.splitWhitespace()[1] else: "/"
    var contentLength = 0
    var authHeader = ""
    var contentType = ""
    var origin = ""
    var headerLines = 0
    var headerBytes = 0
    while true:
      if headerLines >= GatewayMaxHeaderLines:
        client.sendResponse("400 Bad Request", "text/plain", "too many headers\n", log)
        return
      let headerResult = client.readHttpLine(deadline)
      if headerResult.isErr:
        client.sendResponse("400 Bad Request", "text/plain",
                            headerResult.error & "\n", log)
        return
      inc headerLines
      headerBytes += headerResult.value.len
      if headerBytes > GatewayMaxHeaderBytes:
        client.sendResponse("400 Bad Request", "text/plain", "headers too large\n", log)
        return
      let h = headerResult.value
      if h.len == 0: break
      let lc = h.toLowerAscii()
      if lc.startsWith("content-length:"):
        let val = lc[15..^1].strip()
        try:
          let parsed = parseBiggestInt(val)
          if parsed > MaxApiRequestBytes:
            client.sendResponse("413 Payload Too Large", "application/json",
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
         not isAuthorized(authHeader, authToken):
        client.sendResponse("401 Unauthorized", "application/json",
                            "{\"error\":\"unauthorized\"}\n", log)
        return
      client.sendResponse("204 No Content", "text/plain", "", log)
      return
    var sessionTaskUser = ""
    if action == "notfound" and req.meth == "POST":
      let parsedTaskPath = parseSessionTaskPath(req.path)
      if parsedTaskPath.isOk:
        action = "session_task"
        sessionTaskUser = parsedTaskPath.get()
    case gatewayAuthVerdict(action, authHeader, authToken)
    of gavRejected:
      client.sendResponse("401 Unauthorized", "application/json",
                          "{\"error\":\"unauthorized\"}\n", log)
      return
    of gavNoToken:
      client.sendResponse("401 Unauthorized", "application/json",
                          "{\"error\":\"api routes require DONKEY_HTTP_TOKEN\"}\n", log)
      return
    of gavPublic, gavAllowed:
      discard
    if not isPublicGatewayAction(action) and authToken.len == 0 and origin.len > 0 and
       not isLocalOrigin(origin):
      client.sendResponse("403 Forbidden", "application/json",
                          "{\"error\":\"cross-origin access requires a token\"}\n", log)
      return

    case action
    of "index":
      client.sendResponse("200 OK", "text/plain",
        "Donkey HTTP gateway\nEndpoints: /dashboard /api/status /api/logs /api/events /api/chat /v1/models /v1/chat/completions\n", log)

    of "health":
      client.sendResponse("200 OK", "text/plain", "ok\n", log)

    of "dashboard":
      client.sendResponse("200 OK", "text/html", buildDashboardHtml(), log)

    of "status":
      let st = statusFn()
      client.sendJson(buildStatusBody(st), log)

    of "logs":
      let n = parseQueryInt(rawPath, "n", 50)
      let entries = logFn(n)
      client.sendJson(buildLogsBody(entries), log)

    of "sessions":
      if req.meth != "GET":
        client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let limit = parseQueryInt(rawPath, "limit", DashboardDefaultLimit)
        let offset = parseQueryInt(rawPath, "offset", 0)
        let res = handleSessionsRequest(sessionsFn, limit, offset)
        client.sendResponse(httpStatusLine(res.status), res.contentType,
                            res.body, log)

    of "providers":
      if req.meth != "GET":
        client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let res = handleProvidersRequest(providersFn)
        client.sendResponse(httpStatusLine(res.status), res.contentType,
                            res.body, log)

    of "session_task":
      if req.meth != "POST":
        client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let bodyResult = readRequestBodyStrict(client, contentLength, deadline)
        if bodyResult.isErr:
          client.sendResponse("400 Bad Request", "application/json",
                              "{\"error\":\"request body incomplete\"}\n", log)
          return
        let res = handleSessionActionRequest(sessionActionFn, sessionTaskUser,
                                             bodyResult.get(), authHeader, authToken)
        client.sendResponse(httpStatusLine(res.status), res.contentType,
                            res.body, log)

    of "events":
      if not tryAcquireSseConnection():
        client.sendResponse("503 Service Unavailable", "text/plain",
                            "too many event streams\n", log)
        return
      try:
        if not client.sendSseHeaders(log):
          return
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
          let body = readRequestBody(client, contentLength, deadline)
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

    of "openai_chat":
      if req.meth != "POST":
        client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        let body = readRequestBody(client, contentLength, deadline)
        if agentChatStreamRequested(body):
          var streamNapFn: AgentStreamNapFn = agentNap
          {.cast(gcsafe).}:
            if gAgentStreamNap != nil:
              streamNapFn = gAgentStreamNap
          let openSse = proc(): bool {.gcsafe.} =
            client.sendSseHeaders(log)
          let sendSse = proc(chunk: string): bool {.gcsafe.} =
            try:
              client.send(chunk)
              true
            except CatchableError:
              false
          let streamResult = runAgentStream(
            body            = body,
            bridge          = chatBridge,
            dispatch        = agentDispatchFn,
            authorize       = authorizeFn,
            tokenConfigured = authToken.len > 0,
            now             = agentNowSeconds,
            openStream      = openSse,
            send            = sendSse,
            acquireSlot     = tryAcquireSseConnection,
            releaseSlot     = releaseSseConnection,
            streamNow       = agentClockMs,
            streamNap       = streamNapFn,
            timeoutMs       = agentTimeoutMs,
            model           = modelName,
          )
          if streamResult.outcome == asPreflightError:
            client.sendResponse(httpStatusLine(streamResult.reply.status),
                                "application/json",
                                streamResult.reply.body & "\n", log)
        else:
          let reply = runAdmittedAgentTurn(
            body            = body,
            bridge          = chatBridge,
            dispatch        = agentDispatchFn,
            authorize       = authorizeFn,
            tokenConfigured = authToken.len > 0,
            now             = agentNowSeconds,
            timeoutMs       = agentTimeoutMs,
            model           = modelName,
          )
          client.sendResponse(httpStatusLine(reply.status), "application/json",
                              reply.body & "\n", log)

    of "openai_models":
      if req.meth != "GET":
        client.sendResponse("405 Method Not Allowed", "application/json", "", log)
      else:
        client.sendJson(buildOpenAiModels(modelName, epochTime().int64), log)

    of "notfound":
      client.sendResponse("404 Not Found", "text/plain", "Not found\n", log)

    else:
      client.sendResponse("405 Method Not Allowed", "text/plain", "", log)

  except CatchableError:
    let errMsg = getCurrentExceptionMsg()
    log.warn("http_gateway: connection handler error: " & errMsg)
    recordWebhookFailure("http_gateway", errMsg)

# ── Gateway thread ────────────────────────────────────────────────────────────

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
                          gGatewayInboundFn, gGatewayAgentDispatchFn,
                          gGatewaySessionsFn, gGatewayProvidersFn,
                          gGatewaySessionActionFn,
                          gGatewayAuthorizeFn, gGatewayChatBridge, gGatewayModelName,
                          gGatewayAgentTimeoutMs, gGatewayAuthToken, gGatewayLog)
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
      {.cast(gcsafe).}:
        gGatewayListenerActive = true
    except CatchableError as exc:
      args.log.error("http_gateway: bind " & host & ":" & $args.port & " failed — " & exc.msg)
      {.cast(gcsafe).}:
        gGatewayListenerActive = false
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
  for i in 0 ..< capacity.GatewayWorkerCount:
    try:
      createThread(gGatewayWorkers[i], gatewayWorker, i)
      inc started
    except CatchableError as exc:
      if firstError.len == 0:
        firstError = exc.msg

  if started > 0:
    gGatewayPoolStarted = true
  if started < capacity.GatewayWorkerCount:
    let msg = "http_gateway: started " & $started & "/" &
              $capacity.GatewayWorkerCount &
              " workers — " & firstError
    log.error(msg)
    return err(msg)
  ok()

proc startHttpGateway*(port: int;
                       statusFn: GatewayStatusFn;
                       logFn:    GatewayLogFn;
                       eventFn:  GatewayEventFn = nil;
                       inboundFn: GatewayInboundFn = nil;
                       sessionsFn: GatewaySessionsFn = nil;
                       providersFn: GatewayProvidersFn = nil;
                       sessionActionFn: GatewaySessionActionFn = nil;
                       bindAddr = "127.0.0.1";
                       authToken = "";
                       agentDispatchFn: GatewayAgentDispatchFn = nil;
                       authorizeFn: AuthorizeFn = nil;
                       chatBridge: ChatBridge = nil;
                       modelName = "";
                       agentTimeoutMs = 0;
                       agentStreamNapFn: AgentStreamNapFn = nil;
                       log:       Logger = newLogger("http_gateway")
                      ): Result[void, string] =
  ## A second call would publish a new dispatcher/bridge before binding; even
  ## if the bind failed, the running listener would keep using the new wiring.
  if gGatewayListenerActive:
    return err("http_gateway: already running")
  ## A private bridge is never fed by the daemon outbox drainer: every turn
  ## would register and poll a queue nobody drains, ending in 504.
  if agentDispatchFn != nil and chatBridge == nil:
    return err("http_gateway: the agent endpoint requires the shared ChatBridge")
  if agentStreamNapFn != nil:
    {.cast(gcsafe).}:
      gAgentStreamNap = agentStreamNapFn
  ## Starts the HTTP gateway on a dedicated OS thread.
  ## statusFn, logFn, and eventFn are called on each request; they must be gcsafe.
  ## inboundFn is called when POST /api/chat is received; may be nil.
  ## agentDispatchFn starts `/v1/chat/completions` turns through the same
  ## ingress; `chatBridge` is shared with the daemon outbox drainer.
  {.cast(gcsafe).}:
    gGatewayStatusFn  = statusFn
    gGatewayLogFn     = logFn
    gGatewayEventFn   = eventFn
    gGatewayInboundFn = inboundFn
    gGatewayAgentDispatchFn = agentDispatchFn
    gGatewaySessionsFn = sessionsFn
    gGatewayProvidersFn = providersFn
    gGatewaySessionActionFn = sessionActionFn
    gGatewayAuthorizeFn = authorizeFn
    gGatewayChatBridge = if chatBridge != nil: chatBridge
                         else: newChatBridge(agentClockMs, agentNap)
    gGatewayModelName = modelName
    gGatewayAgentTimeoutMs =
      if agentTimeoutMs > 0: agentTimeoutMs
      else: resolveAgentTimeoutMs(getEnv("DONKEY_HTTP_AGENT_TIMEOUT_SEC"))
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
                           eventFn: eventFn, inboundFn: inboundFn,
                           agentDispatchFn: agentDispatchFn,
                           sessionsFn: sessionsFn,
                           providersFn: providersFn,
                           sessionActionFn: sessionActionFn,
                           authorizeFn: authorizeFn,
                           chatBridge: gGatewayChatBridge,
                           modelName: modelName,
                           agentTimeoutMs: gGatewayAgentTimeoutMs,
                           log: log)
    try:
      createThread(gGatewayThread, gatewayThread, args)
    except CatchableError as exc:
      let msg = "http_gateway: cannot start server thread — " & exc.msg
      log.error(msg)
      return err(msg)
    ok()
