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
## Asynchronous (PRD-roadmap E5 follow-up): a request is sent through
## `postAsync`. The daemon makes it a job on the blocking executor
## (`mcpHttpPostJob`: plain data in, the response out), so no call holds the
## event loop; one call at a time per server, which every session shares.
## Without one, the injected `HttpRuntimePort` is used directly (tests). The
## production transport does not repeat a POST (a tool call may have side
## effects) and does not follow redirects (the bearer must not travel to
## another host). The token source still runs on the loop: a refresh is rare
## and bounded by its own deadline.

import std/json
import chronos
import chronos/asyncsync
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
    lock:        AsyncLock

  McpHttpTokenFn* = proc(forceRefresh: bool): Result[string, string] {.gcsafe.}
    ## An OAuth token source (`mcp_oauth.mcpTokenSource`); `forceRefresh`
    ## after the server refused the current token.

  McpHttpPost* = proc(url, body: string; headers: seq[HttpHeader]):
      Future[Result[HttpResponse, string]] {.async: (raises: []), gcsafe.}

  McpHttpPostJob* = object
    ## One POST as plain data, for a worker of the blocking executor.
    url*:        string
    body*:       string
    headers*:    seq[HttpHeader]
    timeoutSec*: int

  McpHttpClient* = object
    url*:       string
    bearer*:    string           ## a static token; ignored when tokenFn is set
    tokenFn*:   McpHttpTokenFn
    http*:      HttpRuntimePort
    postAsync*: McpHttpPost
    state:      ref McpHttpState

proc productionPort(timeoutSec = McpHttpTimeoutSec): HttpRuntimePort =
  newStdHttpAdapter(timeout = timeoutSec, maxRetries = 1,
                    retryNonIdempotent = false,
                    returnServerError = true).toRuntimePort()

proc mcpHttpPostJob*(job: McpHttpPostJob): Result[HttpResponse, string]
    {.nimcall, gcsafe, raises: [].} =
  ## The blocking half, for a worker: its own transport, built from data.
  try:
    productionPort(job.timeoutSec).postNoRedirect(job.url, job.body, job.headers)
  except CatchableError as e:
    err("mcp: " & e.msg)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("mcp: " & e.msg)

proc syncPost(http: HttpRuntimePort): McpHttpPost =
  ## A transport answered in place (tests, or no executor).
  result = proc(url, body: string; headers: seq[HttpHeader]):
      Future[Result[HttpResponse, string]] {.async: (raises: []), gcsafe.} =
    let post = if http.postNoRedirect != nil: http.postNoRedirect else: http.post
    try:
      return post(url, body, headers)
    except CatchableError as e:
      return err("mcp: " & e.msg)
    except Exception as e:  ## effect boundary: callee raises are unannotated
      return err("mcp: " & e.msg)

proc newMcpHttpClient*(url: string; bearer = "";
                       http = HttpRuntimePort();
                       tokenFn: McpHttpTokenFn = nil;
                       postAsync: McpHttpPost = nil): McpHttpClient =
  var state = new(McpHttpState)
  state.nextId = 1
  state.lock = newAsyncLock()
  let port = if http.postNoRedirect != nil or http.post != nil: http else: productionPort()
  McpHttpClient(url: url, bearer: bearer, tokenFn: tokenFn, http: port,
                postAsync: if postAsync != nil: postAsync else: syncPost(port),
                state: state)

proc currentBearer(c: McpHttpClient; forceRefresh = false): Result[string, string] =
  if c.tokenFn == nil:
    return ok(c.bearer)
  try:
    c.tokenFn(forceRefresh)
  except CatchableError as e:
    err("mcp: token: " & e.msg)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("mcp: token: " & e.msg)

proc post(c: McpHttpClient; message: JsonNode;
          forceRefresh = false): Future[Result[HttpResponse, string]] {.async: (raises: []).} =
  let bearer = ? c.currentBearer(forceRefresh)
  let headers = mcpRequestHeaders(
    c.state.sessionId,
    (if c.state.initialized: McpProtocolVersion else: ""),
    bearer)
  return await c.postAsync(c.url, $message, headers)

proc call(c: McpHttpClient; meth: string; params: JsonNode): Future[Result[JsonNode, string]] {.async: (raises: []).} =
  let id = c.state.nextId
  inc c.state.nextId
  let message = %* {"jsonrpc": "2.0", "id": id, "method": meth, "params": params}
  var resp = ? await c.post(message)
  if resp.status == 401 and c.tokenFn != nil:
    ## The server refused the token: refresh it once and send again.
    resp = ? await c.post(message, forceRefresh = true)
  if meth == "initialize":
    let session = headerValue(resp.headers, "Mcp-Session-Id")
    if session.len > 0:
      c.state.sessionId = session
  try:
    return readMcpResponse(resp, id)
  except CatchableError as e:
    return err("mcp: unreadable response: " & e.msg)

proc initialize(c: McpHttpClient): Future[Result[void, string]] {.async: (raises: []).} =
  if c.state.initialized:
    return ok()
  c.state.sessionId = ""
  discard ? await c.call("initialize", %* {
    "protocolVersion": McpProtocolVersion,
    "capabilities": {},
    "clientInfo": {"name": AppSlug, "version": AppVersion}})
  c.state.initialized = true
  let notified = ? await c.post(%* {"jsonrpc": "2.0", "method": "notifications/initialized"})
  if notified.status >= 400:
    c.state.initialized = false
    return err("mcp: notifications/initialized refused (HTTP " & $notified.status & ")")
  return ok()

proc request(c: McpHttpClient; meth: string; params: JsonNode): Future[Result[JsonNode, string]] {.async: (raises: []).} =
  ## One call in an initialized session, one at a time per server; a
  ## forgotten session is started again once.
  try:
    await c.state.lock.acquire()
  except CancelledError:
    return err("mcp: cancelled")
  try:
    ? await c.initialize()
    let first = await c.call(meth, params)
    if first.isErr and first.error == McpSessionExpired:
      c.state.initialized = false
      ? await c.initialize()
      return await c.call(meth, params)
    return first
  finally:
    try: c.state.lock.release()
    except AsyncLockError: discard

proc listToolsAsync*(c: McpHttpClient): Future[Result[seq[ToolSchema], string]] {.async: (raises: []).} =
  let res = ? await c.request("tools/list", newJObject())
  let tools = res{"tools"}
  if tools.isNil or tools.kind != JArray:
    return err("mcp: tools/list without a tools array")
  var schemas: seq[ToolSchema]
  for item in tools:
    if item.kind == JObject and item{"name"}.getStr.len > 0:
      schemas.add ToolSchema(name: item{"name"}.getStr,
                             description: item{"description"}.getStr,
                             inputSchema: item{"inputSchema"})
  return ok(schemas)

proc invokeAsync*(c: McpHttpClient; call: ToolCall): Future[Result[ToolResult, string]] {.async: (raises: []).} =
  let res = ? await c.request("tools/call", %* {
    "name": call.name,
    "arguments": (if call.input.isNil: newJObject() else: call.input)})
  try:
    return ok(parseToolResult(call.id, res))
  except CatchableError as e:
    return err("mcp: tools/call result: " & e.msg)

proc toRuntimePort*(c: McpHttpClient): ToolRuntimePort =
  ToolRuntimePort(
    invokeAsync: proc(call: ToolCall): Future[Result[ToolResult, string]]
        {.gcsafe, raises: [CatchableError].} = c.invokeAsync(call))
