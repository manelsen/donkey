## HTTP gateway unit tests — pure logic only, no real sockets.
## Tests: request parsing, SSE formatting, JSON serialization, route dispatch.

import std/[json, strutils, unittest]
import donkey/app/http_gateway
import donkey/ports/ipc

suite "http_gateway request parsing":

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
    let st = DaemonStatus(uptimeSec: 42, sessionCount: 2, memoryBackend: "md")
    let body = buildStatusBody(st)
    let j = parseJson(body)
    check j{"uptimeSec"}.getBiggestInt() == 42

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
