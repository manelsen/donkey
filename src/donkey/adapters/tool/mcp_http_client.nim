## mcp_http_client.nim — an MCP server reached over Streamable HTTP.
##
## Same ToolPort as the stdio client (`mcp_client.nim`), different transport:
## each JSON-RPC message is a POST (`domain/tools/mcp_http_pure` builds the
## headers and reads the answer). The client keeps the session id the server
## hands out on `initialize`, repeats it with the protocol version, and starts
## a new session once when the server answers 404 for a forgotten one. A 401
## is reported as is: credentials are the caller's business (a static bearer
## today, OAuth later).
##
## The transport is `HttpRuntimePort`; production builds a `StdHttpAdapter`
## that does not repeat a POST (a tool call may have side effects) and does
## not follow redirects (the bearer must not travel to another host).

import std/json
import ../../core/app_meta
import ../../core/pipeops
import ../../domain/tools/mcp_http_pure
import ../../ports/http
import ../../ports/tool
import ../http/std_http
import ./mcp_client

const McpHttpTimeoutSec* = 60

type
  McpHttpState = object
    sessionId:   string
    initialized: bool
    nextId:      int

  McpHttpTokenFn* = proc(forceRefresh: bool): Result[string, string] {.gcsafe.}
    ## An OAuth token source (`mcp_oauth.mcpTokenSource`); `forceRefresh`
    ## after the server refused the current token.

  McpHttpClient* = object
    url*:     string
    bearer*:  string           ## a static token; ignored when tokenFn is set
    tokenFn*: McpHttpTokenFn
    http*:    HttpRuntimePort
    state:    ref McpHttpState

proc productionPort(): HttpRuntimePort =
  newStdHttpAdapter(timeout = McpHttpTimeoutSec, maxRetries = 1,
                    retryNonIdempotent = false,
                    returnServerError = true).toRuntimePort()

proc newMcpHttpClient*(url: string; bearer = "";
                       http = HttpRuntimePort();
                       tokenFn: McpHttpTokenFn = nil): McpHttpClient =
  var state = new(McpHttpState)
  state.nextId = 1
  McpHttpClient(url: url, bearer: bearer, tokenFn: tokenFn,
                http: if http.postNoRedirect != nil: http else: productionPort(),
                state: state)

proc currentBearer(c: McpHttpClient; forceRefresh = false): Result[string, string] =
  if c.tokenFn != nil: c.tokenFn(forceRefresh) else: ok(c.bearer)

proc post(c: McpHttpClient; message: JsonNode;
          forceRefresh = false): Result[HttpResponse, string] =
  let bearer = ? c.currentBearer(forceRefresh)
  let headers = mcpRequestHeaders(
    c.state.sessionId,
    (if c.state.initialized: McpProtocolVersion else: ""),
    bearer)
  let post = if c.http.postNoRedirect != nil: c.http.postNoRedirect else: c.http.post
  post(c.url, $message, headers)

proc call(c: McpHttpClient; meth: string; params: JsonNode): Result[JsonNode, string] =
  let id = c.state.nextId
  inc c.state.nextId
  let message = %* {"jsonrpc": "2.0", "id": id, "method": meth, "params": params}
  var resp = ? c.post(message)
  if resp.status == 401 and c.tokenFn != nil:
    ## The server refused the token: refresh it once and send again.
    resp = ? c.post(message, forceRefresh = true)
  if meth == "initialize":
    let session = headerValue(resp.headers, "Mcp-Session-Id")
    if session.len > 0:
      c.state.sessionId = session
  readMcpResponse(resp, id)

proc initialize(c: McpHttpClient): Result[void, string] =
  if c.state.initialized:
    return ok()
  c.state.sessionId = ""
  discard ? c.call("initialize", %* {
    "protocolVersion": McpProtocolVersion,
    "capabilities": {},
    "clientInfo": {"name": AppSlug, "version": AppVersion}})
  c.state.initialized = true
  let notified = ? c.post(%* {"jsonrpc": "2.0", "method": "notifications/initialized"})
  if notified.status >= 400:
    c.state.initialized = false
    return err("mcp: notifications/initialized refused (HTTP " & $notified.status & ")")
  ok()

proc request(c: McpHttpClient; meth: string; params: JsonNode): Result[JsonNode, string] =
  ## One call in an initialized session; a forgotten session is started again
  ## once.
  ? c.initialize()
  let first = c.call(meth, params)
  if first.isErr and first.error == McpSessionExpired:
    c.state.initialized = false
    ? c.initialize()
    return c.call(meth, params)
  first

proc listTools*(c: var McpHttpClient): Result[seq[ToolSchema], string] =
  let res = ? c.request("tools/list", newJObject())
  let tools = res{"tools"}
  if tools.isNil or tools.kind != JArray:
    return err("mcp: tools/list without a tools array")
  var schemas: seq[ToolSchema]
  for item in tools:
    schemas.add(parseToolSchema(item))
  ok(schemas)

proc invoke*(c: var McpHttpClient; call: ToolCall): Result[ToolResult, string] =
  let res = ? c.request("tools/call", %* {
    "name": call.name,
    "arguments": (if call.input.isNil: newJObject() else: call.input)})
  ok(parseToolResult(call.id, res))

proc close*(c: var McpHttpClient) =
  ## The session is left to expire on the server; nothing to release here.
  c.state.initialized = false
  c.state.sessionId = ""

proc toRuntimePort*(c: McpHttpClient): ToolRuntimePort =
  var client = c
  ToolRuntimePort(
    listTools: proc(): Result[seq[ToolSchema], string] {.gcsafe.} = client.listTools(),
    invoke:    proc(call: ToolCall): Result[ToolResult, string] {.gcsafe.} = client.invoke(call),
    close:     proc() {.gcsafe.} = client.close(),
  )
