## HTTP gateway unit tests — pure logic only, no real sockets.
## Tests: request parsing, SSE formatting, JSON serialization, route dispatch.

import std/[json, strutils, unittest]
import donkey/app/http_gateway
import donkey/app/chat_bridge
import donkey/app/agent_chat_runtime
import donkey/core/agent_events
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/domain/gateway/capacity_pure
import donkey/domain/gateway/identity_pure
import donkey/ports/ipc

suite "http_gateway request parsing":

  test "resolveGatewayPort uses default when unset":
    check resolveGatewayPort("") == GatewayDefaultPort

  test "resolveGatewayPort disables gateway for zero or negative values":
    check resolveGatewayPort("0") == 0
    check resolveGatewayPort("-1") == 0

  test "resolveGatewayPort keeps explicit positive value":
    check resolveGatewayPort("18080") == 18080

  test "resolveGatewayPort falls back on invalid values":
    check resolveGatewayPort("nope") == GatewayDefaultPort

  test "parseGatewayRequest extracts GET /api/status":
    let r = parseGatewayRequest("GET /api/status HTTP/1.1")
    check r.meth == "GET"
    check r.path == "/api/status"

  test "parseGatewayRequest extracts POST /api/chat":
    let r = parseGatewayRequest("POST /api/chat HTTP/1.1")
    check r.meth == "POST"
    check r.path == "/api/chat"

  test "parseGatewayRequest handles root path":
    let r = parseGatewayRequest("GET / HTTP/1.1")
    check r.meth == "GET"
    check r.path == "/"

  test "parseGatewayRequest handles malformed line gracefully":
    let r = parseGatewayRequest("")
    check r.meth == ""
    check r.path == ""

  test "parseGatewayRequest strips query string from path":
    let r = parseGatewayRequest("GET /api/logs?n=20 HTTP/1.1")
    check r.meth == "GET"
    check r.path == "/api/logs"

suite "http_gateway auth":

  test "empty token keeps local behavior":
    check isAuthorized("", "")

  test "bearer token matches case-insensitively on the scheme":
    check isAuthorized("Bearer secret", "secret")
    check isAuthorized("bearer secret", "secret")

  test "wrong or missing token is rejected":
    check not isAuthorized("Bearer nope", "secret")
    check not isAuthorized("", "secret")

  test "local origin validation requires an exact local host":
    check isLocalOrigin("http://localhost:3000")
    check isLocalOrigin("http://127.0.0.1:8080")
    check not isLocalOrigin("http://localhost.evil.com")
    check not isLocalOrigin("http://127.0.0.1.evil.com")
    check not isLocalOrigin("https://localhost/path")

  test "chat without a token requires a local origin and JSON body":
    check chatRequestAllowed("", "application/json", "")
    check chatRequestAllowed("http://localhost:3000", "application/json", "")
    check not chatRequestAllowed("https://evil.example", "application/json", "")
    check not chatRequestAllowed("", "text/plain", "")
    check chatRequestAllowed("https://evil.example", "text/plain", "secret")

  test "non-loopback bind requires a token and explicit insecure opt-in":
    check gatewayBindIsAllowed("127.0.0.1", "")
    check gatewayBindIsAllowed("localhost", "")
    check not gatewayBindIsAllowed("0.0.0.0", "")
    check not gatewayBindIsAllowed("192.168.1.10", "")
    check not gatewayBindIsAllowed("0.0.0.0", "secret")
    check gatewayBindIsAllowed("0.0.0.0", "secret", allowInsecure = true)

suite "http_gateway SSE formatting":

  test "buildSseEvent produces correct SSE format":
    let ev = buildSseEvent("log", "{\"msg\":\"hello\"}")
    check ev.contains("event: log\n")
    check ev.contains("data: {\"msg\":\"hello\"}\n")
    check ev.endsWith("\n\n")

  test "buildSseEvent with empty event produces data-only line":
    let ev = buildSseEvent("", "heartbeat")
    check not ev.contains("event:")
    check ev.contains("data: heartbeat\n")
    check ev.endsWith("\n\n")

suite "http_gateway JSON serialisation":

  test "buildStatusBody returns valid JSON with uptimeSec":
    let st = DaemonStatus(
      uptimeSec: 42,
      sessionCount: 2,
      memoryBackend: "md+magma",
      memoryStats: MemoryStats(
        totalNodes: 12,
        memoryNodes: 8,
        profileNodes: 2,
        preferenceNodes: 1,
        entityNodes: 1,
        embeddingNodes: 11,
        totalEdges: 9,
      ),
    )
    let body = buildStatusBody(st)
    let j = parseJson(body)
    check j{"uptimeSec"}.getBiggestInt() == 42
    check j{"memoryStats"}{"totalNodes"}.getInt() == 12
    check j{"memoryStats"}{"embeddingNodes"}.getInt() == 11

  test "buildLogsBody returns JSON array":
    let entries = @[
      IpcLogEntry(ts: "2026-01-01T00:00:00Z", level: "INFO",
                  subsys: "daemon", msg: "started"),
    ]
    let body = buildLogsBody(entries)
    let j = parseJson(body)
    check j.kind == JArray
    check j.len == 1
    check j[0]{"msg"}.getStr() == "started"

  test "buildLogsBody returns empty array for no entries":
    let body = buildLogsBody(@[])
    let j = parseJson(body)
    check j.kind == JArray
    check j.len == 0

suite "http_gateway agent events serialisation":

  test "buildAgentEventsBody returns JSON array":
    agentEventRingInit()
    pushAgentEvent(AgentEvent(kind: aekToolCall, userId: "u1",
                              toolName: "bash", summary: "ls"))
    let events = agentEventSnapshot(10)
    let body = buildAgentEventsBody(events)
    let j = parseJson(body)
    check j.kind == JArray
    check j.len == 1
    check j[0]{"kind"}.getStr() == "tool_call"
    check j[0]{"userId"}.getStr() == "u1"

  test "buildAgentEventsBody returns empty array for no events":
    agentEventRingInit()
    let body = buildAgentEventsBody(@[])
    let j = parseJson(body)
    check j.kind == JArray
    check j.len == 0

suite "http_gateway route dispatch":

  test "routeGatewayRequest maps GET /api/status to status action":
    let req = GatewayRequest(meth: "GET", path: "/api/status")
    check routeGatewayRequest(req) == "status"

  test "routeGatewayRequest maps GET /api/logs to logs action":
    let req = GatewayRequest(meth: "GET", path: "/api/logs")
    check routeGatewayRequest(req) == "logs"

  test "routeGatewayRequest maps GET /api/events to events action":
    let req = GatewayRequest(meth: "GET", path: "/api/events")
    check routeGatewayRequest(req) == "events"

  test "routeGatewayRequest maps unknown paths to notfound":
    let req = GatewayRequest(meth: "GET", path: "/unknown")
    check routeGatewayRequest(req) == "notfound"

  test "routeGatewayRequest maps root to index action":
    let req = GatewayRequest(meth: "GET", path: "/")
    check routeGatewayRequest(req) == "index"

  test "routeGatewayRequest maps /health to health action":
    let req = GatewayRequest(meth: "GET", path: "/health")
    check routeGatewayRequest(req) == "health"

  test "routeGatewayRequest maps /dashboard":
    check routeGatewayRequest(GatewayRequest(meth: "GET", path: "/dashboard")) ==
          "dashboard"

  test "routeGatewayRequest maps the OpenAI-compatible endpoints":
    check routeGatewayRequest(GatewayRequest(meth: "POST", path: "/v1/chat/completions")) ==
          "openai_chat"
    check routeGatewayRequest(GatewayRequest(meth: "GET", path: "/v1/models")) ==
          "openai_models"

  test "health and index are the only public gateway actions":
    check isPublicGatewayAction("index")
    check isPublicGatewayAction("health")
    check isPublicGatewayAction("dashboard")
    for action in ["status", "logs", "events", "chat", "openai_chat",
                   "openai_models", "notfound"]:
      check not isPublicGatewayAction(action)

  test "routeGatewayRequest maps POST /api/chat to chat action":
    let req = GatewayRequest(meth: "POST", path: "/api/chat")
    check routeGatewayRequest(req) == "chat"

suite "http_gateway chat method routing":

  test "routeChatMethod maps POST to chat":
    check routeChatMethod("POST") == "chat"

  test "routeChatMethod maps GET to chat_get":
    check routeChatMethod("GET") == "chat_get"

  test "routeChatMethod maps unknown methods to method_not_allowed":
    check routeChatMethod("DELETE") == "method_not_allowed"
    check routeChatMethod("PUT") == "method_not_allowed"

suite "http_gateway chat POST parsing":

  test "parseChatPost parses valid JSON with text":
    let result = parseChatPost("""{"text": "hello world"}""")
    check result.isOk
    let msg = result.get()
    check msg.text == "hello world"
    check msg.userId == CliDefaultUserId
    check msg.channelId == "webui"
    check msg.channel == ckCli

  test "parseChatPost parses JSON with custom userId":
    let result = parseChatPost("""{"text": "hi", "userId": "alice"}""")
    check result.isOk
    let msg = result.get()
    check msg.text == "hi"
    check msg.userId == UserId("alice")

  test "parseChatPost rejects empty body":
    let result = parseChatPost("")
    check result.isErr
    check result.error.contains("empty body")

  test "parseChatPost rejects invalid JSON":
    let result = parseChatPost("not json")
    check result.isErr
    check result.error.contains("invalid JSON")

  test "parseChatPost rejects non-object JSON":
    let result = parseChatPost("""["array"]""")
    check result.isErr
    check result.error.contains("expected JSON object")

  test "parseChatPost rejects missing text field":
    let result = parseChatPost("""{"userId": "alice"}""")
    check result.isErr
    check result.error.contains("missing or empty 'text' field")

  test "parseChatPost rejects empty text field":
    let result = parseChatPost("""{"text": ""}""")
    check result.isErr
    check result.error.contains("missing or empty 'text' field")

  test "parseChatPost handles JSON with extra fields":
    let result = parseChatPost("""{"text": "hello", "extra": "ignored"}""")
    check result.isOk
    check result.get().text == "hello"

suite "dashboard page":

  test "the shell carries no token and asks for one":
    let html = buildDashboardHtml()
    check html.contains("<title>Donkey</title>")
    check html.contains("sessionStorage")
    check html.contains("/api/status")
    check html.contains("/api/logs")
    check html.contains("Authorization: 'Bearer '")

  test "the shell has no external asset or inline secret":
    let html = buildDashboardHtml()
    check not html.contains("<script src=")
    check not html.contains("<link rel=\"stylesheet\"")
    check not html.contains("DONKEY_HTTP_TOKEN=")

# ── long-lived capacity (gateway counters + admission) ───────────────────────
#
# The gateway pool has 8 workers; at most 6 may be blocked by long-lived work.
# These tests drive the same counters the streaming and non-streaming paths
# use, so a regression to a second pool (or to no admission at all) is caught
# here without opening a socket.

type CapDispatchMode = enum
  cdmFinal
  cdmRaise
  cdmNothing

var
  capNow: int64 = 1_000
  capBridge {.threadvar.}: ChatBridge
  capDispatched = 0
  capMode = cdmFinal
  capDuringPending = -1
  capDuringSse = -1
  capDuringTotal = -1
  capSseAcquireCalls = 0
  capSseReleaseCalls = 0

proc capClock(): int64 {.gcsafe, raises: [].} =
  capNow

proc capNap(ms: int) {.gcsafe, raises: [].} =
  capNow += int64(ms)

proc capAuthorize(userId: UserId): AuthVerdict {.gcsafe, raises: [].} =
  discard userId
  avAllowed

proc capSample() {.gcsafe.} =
  let occ = longLivedOccupancy()
  capDuringPending = occ.pendingTurns
  capDuringSse = occ.sseConnections
  capDuringTotal = occ.longLivedWorkers

proc capDispatch(msg: InboundMessage) {.gcsafe.} =
  inc capDispatched
  capSample()
  case capMode
  of cdmFinal:
    discard capBridge.deliver(OutboundMessage(
      userId: msg.userId, text: "ok", replyKind: rkFinalAnswer))
  of cdmRaise:
    raise newException(CatchableError, "dispatch exploded")
  of cdmNothing:
    discard

proc capOpenStream(): bool {.gcsafe.} =
  true

proc capSendStream(chunk: string): bool {.gcsafe.} =
  discard chunk
  capSample()
  true

proc capAcquireSse(): bool {.gcsafe.} =
  inc capSseAcquireCalls
  tryReserveLongLived(llSseConnection).admitted

proc capReleaseSse() {.gcsafe.} =
  inc capSseReleaseCalls
  releaseLongLived(llSseConnection)

proc resetCapacity() =
  resetLongLivedCountersForTest()
  capNow = 1_000
  capBridge = newChatBridge(capClock, capNap)
  capDispatched = 0
  capMode = cdmFinal
  capDuringPending = -1
  capDuringSse = -1
  capDuringTotal = -1
  capSseAcquireCalls = 0
  capSseReleaseCalls = 0

proc reserveCapacity(kind: LongLivedKind; n: int): bool =
  for _ in 0 ..< n:
    if not tryReserveLongLived(kind).admitted:
      return false
  true

func capacityBody(user = "alice"; text = "oi"): string =
  $(%* {
    "user": user,
    "messages": [%* {"role": "user", "content": text}],
  })

proc runCapacityTurn(timeoutMs = 100): AgentChatReply =
  runAdmittedAgentTurn(
    body            = capacityBody(),
    bridge          = capBridge,
    dispatch        = capDispatch,
    authorize       = capAuthorize,
    tokenConfigured = true,
    now             = capClock,
    timeoutMs       = timeoutMs,
    model           = "donkey/test",
  )

proc runCapacityStream(timeoutMs = 5_000): AgentStreamResult =
  runAgentStream(
    body            = capacityBody(),
    bridge          = capBridge,
    dispatch        = capDispatch,
    authorize       = capAuthorize,
    tokenConfigured = true,
    now             = capClock,
    openStream      = capOpenStream,
    send            = capSendStream,
    acquireSlot     = capAcquireSse,
    releaseSlot     = capReleaseSse,
    streamNow       = capClock,
    streamNap       = capNap,
    timeoutMs       = timeoutMs,
    model           = "donkey/test",
  )

suite "http_gateway long-lived capacity":

  test "a pool at six refuses a new turn with 429 and never dispatches":
    resetCapacity()
    # 2 pending turns + 4 SSE connections fill all six long-lived workers.
    # The turn queue itself still has room (2 < MaxPendingTurns), so the
    # refusal must come from the shared worker budget.
    check reserveCapacity(llChatTurn, 2)
    check reserveCapacity(llSseConnection, 4)
    check longLivedOccupancy().longLivedWorkers == MaxLongLivedWorkers

    let reply = runCapacityTurn()
    check reply.status == 429
    let node = parseJson(reply.body)
    check node{"error"}{"type"}.getStr() == "rate_limit_error"
    check node{"error"}{"code"}.getStr() == "no_worker"
    check capDispatched == 0
    # A refused request must not consume (or release) a worker.
    check longLivedOccupancy().longLivedWorkers == MaxLongLivedWorkers

  test "a full pending queue refuses with rate_limit_error":
    resetCapacity()
    check reserveCapacity(llChatTurn, MaxPendingTurns)

    let reply = runCapacityTurn()
    check reply.status == 429
    let node = parseJson(reply.body)
    check node{"error"}{"type"}.getStr() == "rate_limit_error"
    check node{"error"}{"code"}.getStr() == "too_many_pending_turns"
    check capDispatched == 0

  test "3 pending turns plus 3 SSE streams refuse the seventh and a release admits it":
    resetCapacity()
    check reserveCapacity(llChatTurn, 3)
    check reserveCapacity(llSseConnection, 3)
    let before = longLivedOccupancy()
    check before.pendingTurns == 3
    check before.sseConnections == 3
    check before.longLivedWorkers == 6

    # Either path is refused: one shared pool, no per-class bypass.
    check not tryReserveLongLived(llChatTurn).admitted
    check not tryReserveLongLived(llSseConnection).admitted

    releaseLongLived(llChatTurn)
    check longLivedOccupancy().longLivedWorkers == 5
    check tryReserveLongLived(llChatTurn).admitted
    let after = longLivedOccupancy()
    check after.pendingTurns == 3
    check after.sseConnections == 3
    check after.longLivedWorkers == 6

  test "a turn that fails after admission releases its slot":
    resetCapacity()
    capMode = cdmRaise

    let failed = runCapacityTurn()
    check failed.status == 502
    check capDispatched == 1
    check capDuringTotal == 1
    check longLivedOccupancy().longLivedWorkers == 0

    capMode = cdmNothing
    capNow = 1_000
    let timedOut = runCapacityTurn(timeoutMs = 30)
    check timedOut.status == 504
    check capDispatched == 2
    check longLivedOccupancy().longLivedWorkers == 0

  test "a completed turn releases its slot and counts exactly one worker":
    resetCapacity()

    let reply = runCapacityTurn()
    check reply.status == 200
    check capDispatched == 1
    check capDuringPending == 1
    check capDuringSse == 0
    check capDuringTotal == 1
    check longLivedOccupancy().longLivedWorkers == 0

  test "the streaming path shares the counters and counts exactly one worker":
    resetCapacity()

    let result = runCapacityStream()
    check result.outcome == asCompleted
    check capDuringPending == 0
    check capDuringSse == 1
    check capDuringTotal == 1
    check capSseAcquireCalls == 1
    check capSseReleaseCalls == 1
    check longLivedOccupancy().longLivedWorkers == 0

  test "a stream is refused when non-streaming turns already filled the pool":
    resetCapacity()
    check reserveCapacity(llChatTurn, 3)
    check reserveCapacity(llSseConnection, 3)

    let refused = runCapacityStream()
    check refused.outcome == asPreflightError
    check refused.reply.status == 429
    check capDispatched == 0
    check capSseReleaseCalls == 0
    let occ = longLivedOccupancy()
    check occ.pendingTurns == 3
    check occ.sseConnections == 3
    check occ.longLivedWorkers == 6

  test "refused turns never consume a long-lived worker":
    resetCapacity()
    check reserveCapacity(llChatTurn, 2)
    check reserveCapacity(llSseConnection, 4)

    for _ in 0 ..< 3:
      check runCapacityTurn().status == 429

    check capDispatched == 0
    let occ = longLivedOccupancy()
    check occ.pendingTurns == 2
    check occ.sseConnections == 4
    check occ.longLivedWorkers == MaxLongLivedWorkers
