## mcp_http_pure.nim — MCP Streamable HTTP, the pure part.
##
## MCP spec 2025-06-18, "Transports / Streamable HTTP": every JSON-RPC message
## is a POST to one endpoint, accepting `application/json` and
## `text/event-stream`. The answer comes back as a JSON body or as an SSE
## stream that may carry server notifications before it. The server may hand
## out a session id on `initialize` (`Mcp-Session-Id`), which every later
## request repeats along with `MCP-Protocol-Version`; a 404 means the server no
## longer knows that session and the client must initialize again.

import std/[json, strutils]
import ../../core/pipeops
import ../../ports/http

const
  McpProtocolVersion* = "2025-06-18"
  McpSessionExpired* = "mcp: session expired"
  McpUnauthorized* = "mcp: unauthorized (401)"

func headerValue*(headers: seq[HttpHeader]; name: string): string =
  for h in headers:
    if h.name.toLowerAscii == name.toLowerAscii:
      return h.value

func mcpRequestHeaders*(sessionId, protocolVersion, bearer: string): seq[HttpHeader] =
  result = @[(name: "Content-Type", value: "application/json"),
             (name: "Accept", value: "application/json, text/event-stream")]
  if sessionId.len > 0:
    result.add((name: "Mcp-Session-Id", value: sessionId))
  if protocolVersion.len > 0:
    result.add((name: "MCP-Protocol-Version", value: protocolVersion))
  if bearer.len > 0:
    result.add((name: "Authorization", value: "Bearer " & bearer))

func sseMessages*(body: string): seq[string] =
  ## The `data` of each SSE event; multi-line data joined with "\n".
  var data: seq[string]
  for raw in body.splitLines():
    let line = raw.strip(leading = false, chars = {'\r'})
    if line.len == 0:
      if data.len > 0:
        result.add(data.join("\n"))
        data = @[]
    elif line.startsWith("data:"):
      var value = line[5 .. ^1]
      if value.startsWith(" "): value = value[1 .. ^1]
      data.add(value)
  if data.len > 0:
    result.add(data.join("\n"))

proc answerFor(message: JsonNode; requestId: int): Result[JsonNode, string] =
  ## `ok(nil)` when this message is not the answer to `requestId`.
  if message.kind != JObject or not message.hasKey("id"): return ok(JsonNode(nil))
  if message["id"].getInt(-1) != requestId: return ok(JsonNode(nil))
  if message.hasKey("error"):
    let e = message["error"]
    return err("mcp error: " & e{"message"}.getStr($e))
  if message.hasKey("result"):
    return ok(message["result"])
  err("mcp: answer without result or error")

proc readMcpResponse*(resp: HttpResponse; requestId: int): Result[JsonNode, string] =
  ## The `result` of the answer to `requestId`. (A proc only because
  ## `parseJson` is not a `func`; no I/O.)
  if resp.status == 404: return err(McpSessionExpired)
  if resp.status == 401: return err(McpUnauthorized)
  if resp.status < 200 or resp.status >= 300:
    return err("mcp: HTTP " & $resp.status & ": " & resp.body)
  let contentType = headerValue(resp.headers, "Content-Type").toLowerAscii
  var messages: seq[JsonNode]
  try:
    if contentType.startsWith("text/event-stream"):
      for data in sseMessages(resp.body):
        messages.add(parseJson(data))
    else:
      let parsed = parseJson(resp.body)
      if parsed.kind == JArray:
        for item in parsed: messages.add(item)
      else:
        messages.add(parsed)
  except CatchableError as e:
    return err("mcp: unreadable response: " & e.msg)
  for message in messages:
    let answer = ? answerFor(message, requestId)
    if not answer.isNil:
      return ok(answer)
  err("mcp: no answer for request " & $requestId)
