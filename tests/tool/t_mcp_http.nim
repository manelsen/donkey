## MCP over Streamable HTTP (MCP spec 2025-06-18, "Transports").
##
## Pure part: request headers and reading a response, which is either JSON or
## an SSE stream that may carry notifications before the answer. Client part:
## the initialize handshake, the session id the server hands out, the bearer,
## and one re-initialization when the server forgets the session (404). The
## transport is an injected `HttpRuntimePort` scripted per request.

import std/[json, strutils, unittest]
import chronos
import donkey/adapters/tool/mcp_http_client
import donkey/core/pipeops
import donkey/domain/tools/mcp_http_pure
import donkey/ports/http
import donkey/ports/tool

type
  Sent = object
    body:    JsonNode
    headers: seq[HttpHeader]
  Script = ref object
    replies: seq[HttpResponse]
    sent:    seq[Sent]

proc scriptedPort(s: Script): HttpRuntimePort =
  HttpRuntimePort(
    postNoRedirect: proc (url, body: string; headers: seq[HttpHeader] = @[]):
                     Result[HttpResponse, string] {.gcsafe.} =
      s.sent.add(Sent(body: parseJson(body), headers: headers))
      if s.replies.len == 0:
        return err("no scripted reply")
      result = ok(s.replies[0])
      s.replies.delete(0))

func json(body: string; headers: seq[HttpHeader] = @[]): HttpResponse =
  HttpResponse(status: 200, body: body,
               headers: @[(name: "Content-Type", value: "application/json")] & headers)

func sse(body: string): HttpResponse =
  HttpResponse(status: 200, body: body,
               headers: @[(name: "Content-Type", value: "text/event-stream")])

const Accepted = HttpResponse(status: 202, body: "")

func headerOf(headers: seq[HttpHeader]; name: string): string =
  for h in headers:
    if h.name.toLowerAscii == name.toLowerAscii: return h.value

proc initReplies(session = "s-1"; id = 1): seq[HttpResponse] =
  @[json("""{"jsonrpc":"2.0","id":""" & $id & ""","result":{"protocolVersion":"2025-06-18",
            "capabilities":{"tools":{}},"serverInfo":{"name":"t","version":"1"}}}""",
         @[(name: "Mcp-Session-Id", value: session)]),
    Accepted]

proc runTests*() =
  suite "mcp_http_pure — reading a response":
    test "a JSON response gives the result of the matching id":
      let r = readMcpResponse(json("""{"jsonrpc":"2.0","id":7,"result":{"ok":1}}"""), 7)
      check r.isOk and r.get == %* {"ok": 1}

    test "an SSE stream may carry notifications before the answer":
      let body = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\n\n" &
                 "data: {\"jsonrpc\":\"2.0\",\n" &
                 "data: \"id\":3,\"result\":{\"tools\":[]}}\n\n"
      let r = readMcpResponse(sse(body), 3)
      check r.isOk and r.get == %* {"tools": []}

    test "a JSON-RPC error is an error with the server's message":
      let r = readMcpResponse(json("""{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"no such tool"}}"""), 2)
      check r.isErr and "no such tool" in r.error

    test "a response without our id is an error":
      check readMcpResponse(json("""{"jsonrpc":"2.0","id":9,"result":{}}"""), 2).isErr

    test "a forgotten session and a refused token are told apart":
      check readMcpResponse(HttpResponse(status: 404, body: "gone"), 1).error == McpSessionExpired
      check readMcpResponse(HttpResponse(status: 401, body: ""), 1).error == McpUnauthorized

    test "request headers: content type, accept, session, protocol, bearer":
      let h = mcpRequestHeaders(sessionId = "s-1", protocolVersion = "2025-06-18",
                                bearer = "tok")
      check h.headerOf("Accept") == "application/json, text/event-stream"
      check h.headerOf("Content-Type") == "application/json"
      check h.headerOf("Mcp-Session-Id") == "s-1"
      check h.headerOf("MCP-Protocol-Version") == "2025-06-18"
      check h.headerOf("Authorization") == "Bearer tok"
      let bare = mcpRequestHeaders("", "", "")
      check bare.headerOf("Mcp-Session-Id") == ""
      check bare.headerOf("Authorization") == ""

  suite "mcp http client":
    test "initialize, then tools/list with the session id and the bearer":
      let s = Script(replies: initReplies() & @[sse(
        "data: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"echo\"," &
        "\"description\":\"d\",\"inputSchema\":{\"type\":\"object\"}}]}}\n\n")])
      var c = newMcpHttpClient("https://mcp.example.test/mcp", bearer = "tok",
                               http = scriptedPort(s))
      let tools = waitFor c.listToolsAsync()
      check tools.isOk
      check tools.get.len == 1 and tools.get[0].name == "echo"
      check s.sent[0].body["method"].getStr == "initialize"
      check s.sent[0].headers.headerOf("Mcp-Session-Id") == ""
      check s.sent[1].body["method"].getStr == "notifications/initialized"
      check not s.sent[1].body.hasKey("id")
      for later in s.sent[1 .. ^1]:
        check later.headers.headerOf("Mcp-Session-Id") == "s-1"
        check later.headers.headerOf("MCP-Protocol-Version") == "2025-06-18"
      for every in s.sent:
        check every.headers.headerOf("Authorization") == "Bearer tok"

    test "tools/call returns the text content":
      let s = Script(replies: initReplies() & @[json(
        """{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"oi"}],"isError":false}}""")])
      var c = newMcpHttpClient("https://mcp.example.test/mcp", http = scriptedPort(s))
      let r = waitFor c.invokeAsync(ToolCall(id: "c1", name: "echo", input: %* {"x": 1}))
      check r.isOk and r.get.output == "oi" and r.get.callId == "c1"
      check s.sent[2].body["params"] == %* {"name": "echo", "arguments": {"x": 1}}

    test "a forgotten session is re-initialized once and the call retried":
      let s = Script(replies: initReplies("s-1") &
        @[HttpResponse(status: 404, body: "")] & initReplies("s-2", id = 3) &
        @[json("""{"jsonrpc":"2.0","id":4,"result":{"tools":[]}}""")])
      var c = newMcpHttpClient("https://mcp.example.test/mcp", http = scriptedPort(s))
      let r = waitFor c.listToolsAsync()
      check r.isOk
      check s.sent[^1].headers.headerOf("Mcp-Session-Id") == "s-2"

    test "a refused token is reported, not retried":
      let s = Script(replies: @[HttpResponse(status: 401, body: "")])
      var c = newMcpHttpClient("https://mcp.example.test/mcp", http = scriptedPort(s))
      let r = waitFor c.listToolsAsync()
      check r.isErr and "unauthorized" in r.error.toLowerAscii
      check s.sent.len == 1


  suite "mcp http client — off the loop (E5 follow-up)":

    test "the loop keeps running while a request is in flight":
      let slow: McpHttpPost = proc(url, body: string; headers: seq[HttpHeader]):
          Future[Result[HttpResponse, string]] {.async: (raises: []), gcsafe.} =
        try: await sleepAsync(chronos.milliseconds(300))
        except CancelledError: return err("cancelled")
        try:
          let msg = parseJson(body)
          let id = msg{"id"}.getInt(0)
          if id == 0: return ok(Accepted)
          if msg{"method"}.getStr == "initialize":
            return ok(initReplies(id = id)[0])
          return ok(json("""{"jsonrpc":"2.0","id":""" & $id & ""","result":{"tools":[]}}"""))
        except CatchableError as e: return err(e.msg)
      var c = newMcpHttpClient("https://mcp.example.test/mcp", postAsync = slow)
      var ticks = 0
      proc ticker() {.async.} =
        for _ in 0 ..< 30:
          await sleepAsync(chronos.milliseconds(25))
          inc ticks
      let ticking = ticker()
      check (waitFor c.listToolsAsync()).isOk
      waitFor ticking
      check ticks == 30

    test "two sessions' calls on one client do not mix, nor start two sessions":
      var inits = 0
      let server: McpHttpPost = proc(url, body: string; headers: seq[HttpHeader]):
          Future[Result[HttpResponse, string]] {.async: (raises: []), gcsafe.} =
        try: await sleepAsync(chronos.milliseconds(20))
        except CancelledError: return err("cancelled")
        try:
          let msg = parseJson(body)
          let id = msg{"id"}.getInt(0)
          if id == 0: return ok(Accepted)
          if msg{"method"}.getStr == "initialize":
            {.cast(gcsafe).}: inc inits
            return ok(initReplies(id = id)[0])
          let who = msg{"params"}{"arguments"}{"who"}.getStr
          return ok(json("""{"jsonrpc":"2.0","id":""" & $id &
            ""","result":{"content":[{"type":"text","text":"""" & who & """"}]}}"""))
        except CatchableError as e: return err(e.msg)
      var c = newMcpHttpClient("https://mcp.example.test/mcp", postAsync = server)
      let a = c.invokeAsync(ToolCall(id: "a", name: "echo", input: %* {"who": "a"}))
      let b = c.invokeAsync(ToolCall(id: "b", name: "echo", input: %* {"who": "b"}))
      check (waitFor a).get.output == "a"
      check (waitFor b).get.output == "b"
      check inits == 1

    test "the job sent to a worker carries only data and answers an error, not a hang":
      let r = mcpHttpPostJob(McpHttpPostJob(url: "https://127.0.0.1:9/mcp", body: "{}",
                                            headers: @[], timeoutSec: 2))
      check r.isErr

when isMainModule:
  runTests()
