## HTTP gateway unit tests — pure logic only, no real sockets.
## Tests: request parsing, SSE formatting, JSON serialization, route dispatch.

import std/[json, strutils, unittest]
import donkey/app/http_gateway
import donkey/core/agent_events
import donkey/core/pipeops
import donkey/core/types
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
