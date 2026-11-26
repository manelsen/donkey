## mcp_client — an MCP server over stdio, on the event loop (PRD-roadmap E5.0).
##
## The server is a subprocess speaking JSON-RPC 2.0, one message per line on
## its stdin and stdout; its stderr is left to the daemon's. Everything is
## asynchronous (Chronos asyncproc): a slow tool no longer stops every
## channel, and a request the server makes in the middle of a call (sampling)
## can wait for the person without blocking anything.
##
## While waiting for its own response the client answers the server's
## requests (through `onServerRequest`, or with "method not found"), skips
## notifications and any stale response. One call at a time per server (the
## client is shared by every session), each under a deadline.

import std/[json, strutils]
import chronos
import chronos/asyncproc
import chronos/asyncsync
import ../../ports/tool
import ../../core/pipeops
import ../../core/app_meta

# ── Pure helpers (exported for unit tests) ────────────────────────────────────

func buildRequest*(id: int; meth: string; params: JsonNode): string =
  ## Serialises a JSON-RPC 2.0 request to a string (one line, no trailing \n).
  $(%* {"jsonrpc": "2.0", "id": id, "method": meth, "params": params})

func parseToolSchema*(j: JsonNode): ToolSchema =
  ## Parses one element from a tools/list result array.
  ToolSchema(
    name:        j["name"].getStr(""),
    description: j.getOrDefault("description").getStr(""),
    inputSchema: j.getOrDefault("inputSchema"),
  )

func parseToolResult*(callId: string; j: JsonNode): ToolResult =
  ## Parses the result object from a tools/call response.
  ## MCP content is an array of typed blocks; we join all text blocks.
  var parts: seq[string]
  let content = j.getOrDefault("content")
  if content != nil and content.kind == JArray:
    for item in content:
      if item.getOrDefault("type").getStr("") == "text":
        parts.add(item.getOrDefault("text").getStr(""))
  ToolResult(
    callId:  callId,
    output:  parts.join(""),
    isError: j.getOrDefault("isError").getBool(false),
  )

# ── The client ────────────────────────────────────────────────────────────────

type
  ServerRequestHandler* = proc(meth: string; params: JsonNode; call: ToolCall):
      Future[Result[JsonNode, string]] {.async: (raises: []), gcsafe.}
    ## A request the server makes (sampling/createMessage) during `call` (an
    ## empty call outside one, e.g. the startup listing): the JSON result, or
    ## an error message sent back to the server.

  McpClient* = ref object
    command*:   string
    args*:      seq[string]
    timeoutMs*: int
    onServerRequest*: ServerRequestHandler
    offeredCapabilities*: JsonNode   ## what `initialize` told the server
    process:    AsyncProcessRef
    nextId:     int
    lock:       AsyncLock
    initialized: bool
    schemas:    seq[ToolSchema]      ## from the last tools/list
    listed:     bool                 ## a tools/list has worked

const
  DefaultMcpTimeoutMs* = 120_000
  MaxMcpLineBytes = 16 * 1024 * 1024

proc newMcpClient*(command: string; args: seq[string] = @[];
                   timeoutMs = DefaultMcpTimeoutMs;
                   onServerRequest: ServerRequestHandler = nil): McpClient =
  McpClient(command: command, args: args, timeoutMs: timeoutMs,
            onServerRequest: onServerRequest, nextId: 1, lock: newAsyncLock(),
            offeredCapabilities: newJObject())

func responseLine(id: JsonNode; res: Result[JsonNode, string]): string =
  if res.isOk:
    $(%* {"jsonrpc": "2.0", "id": id, "result": res.get})
  else:
    $(%* {"jsonrpc": "2.0", "id": id,
          "error": {"code": -32601, "message": res.error}})

proc ensureStarted(c: McpClient): Future[Result[void, string]] {.async: (raises: []).} =
  if not c.process.isNil:
    let alive = c.process.running()
    if alive.isOk and alive.get:
      return ok()
  try:
    c.process = await startProcess(c.command, arguments = c.args,
      options = {AsyncProcessOption.UsePath},
      stdinHandle = AsyncProcess.Pipe, stdoutHandle = AsyncProcess.Pipe)
    c.initialized = false
    return ok()
  except CancelledError:
    return err("MCP start cancelled")
  except CatchableError as e:
    return err("Failed to start MCP process '" & c.command & "': " & e.msg)

proc sendLine(c: McpClient; line: string): Future[Result[void, string]] {.async: (raises: []).} =
  try:
    await c.process.stdinStream.write(line & "\n")
    return ok()
  except CancelledError:
    return err("MCP write cancelled")
  except CatchableError as e:
    return err("Write to MCP stdin failed: " & e.msg)

proc exchange(c: McpClient; id: int; line: string; call: ToolCall): Future[Result[JsonNode, string]]
    {.async: (raises: [CancelledError]).} =
  ## Sends one request and reads until its response, serving the server in
  ## between.
  ? await c.sendLine(line)
  while true:
    let text =
      try: await c.process.stdoutStream.readLine(limit = MaxMcpLineBytes, sep = "\n")
      except CancelledError as e: raise e
      except CatchableError as e: return err("Read from MCP stdout failed: " & e.msg)
    if text.len == 0:
      let alive = c.process.running()
      if alive.isErr or not alive.get:
        return err("MCP process '" & c.command & "' exited")
      continue
    let msg =
      try: parseJson(text)
      except CatchableError: continue   ## not JSON-RPC: skip it
    if msg.kind != JObject:
      continue
    ## Our response is known by its id and its result or error, whatever else
    ## it carries.
    let isOurs = msg{"id"}.getInt(-1) == id and
                 (msg.hasKey("result") or msg.hasKey("error"))
    if msg.hasKey("method") and not isOurs:
      if msg.hasKey("id"):
        ## The server asks us something (sampling) before it answers.
        let answer =
          if c.onServerRequest.isNil:
            Result[JsonNode, string].err("Method not found: " & msg{"method"}.getStr)
          else:
            await c.onServerRequest(msg{"method"}.getStr, msg{"params"}, call)
        ? await c.sendLine(responseLine(msg{"id"}, answer))
      continue   ## a notification, or a request now answered
    if msg{"id"}.getInt(-1) != id:
      continue   ## a response to a request that timed out earlier
    if msg.hasKey("error"):
      let e = msg{"error"}
      return err("MCP error: " & e{"message"}.getStr($e))
    if not msg.hasKey("result"):
      return err("MCP response without a result")
    return ok(msg{"result"})

proc rpcUnlocked(c: McpClient; meth: string; params: JsonNode;
                 call = ToolCall()): Future[Result[JsonNode, string]]
    {.async: (raises: [CancelledError]).} =
  let id = c.nextId
  inc c.nextId
  let pending = c.exchange(id, buildRequest(id, meth, params), call)
  let inTime =
    try: await pending.withTimeout(chronos.milliseconds(c.timeoutMs))
    except CancelledError as e: raise e
  if not inTime:
    await pending.cancelAndWait()
    return err("MCP '" & meth & "' timed out after " & $c.timeoutMs & " ms")
  return await pending

proc initialize(c: McpClient): Future[Result[void, string]] {.async: (raises: [CancelledError]).} =
  if c.initialized:
    return ok()
  ? await c.ensureStarted()
  c.offeredCapabilities = newJObject()
  if not c.onServerRequest.isNil:
    c.offeredCapabilities["sampling"] = newJObject()
  discard ? await c.rpcUnlocked("initialize", %* {
    "protocolVersion": "2024-11-05",
    "capabilities": c.offeredCapabilities,
    "clientInfo": {"name": AppSlug, "version": AppVersion}})
  ? await c.sendLine($(%* {"jsonrpc": "2.0", "method": "notifications/initialized",
                            "params": {}}))
  c.initialized = true
  return ok()

proc rpc(c: McpClient; meth: string; params: JsonNode;
         call = ToolCall()): Future[Result[JsonNode, string]]
    {.async: (raises: []).} =
  ## One exchange at a time per server.
  try:
    await c.lock.acquire()
  except CancelledError:
    return err("MCP call cancelled")
  try:
    ? await c.initialize()
    return await c.rpcUnlocked(meth, params, call)
  except CancelledError:
    return err("MCP call cancelled")
  finally:
    try: c.lock.release()
    except AsyncLockError: discard

proc listToolsAsync*(c: McpClient): Future[Result[seq[ToolSchema], string]] {.async: (raises: []).} =
  let res = ? await c.rpc("tools/list", %* {})
  let tools = res{"tools"}
  if tools.isNil or tools.kind != JArray:
    return err("tools/list response missing 'tools' array")
  var schemas: seq[ToolSchema]
  for item in tools:
    if item.kind == JObject and item{"name"}.getStr.len > 0:
      schemas.add ToolSchema(name: item{"name"}.getStr,
                             description: item{"description"}.getStr,
                             inputSchema: item{"inputSchema"})
  c.schemas = schemas
  c.listed = true
  return ok(schemas)

proc invokeAsync*(c: McpClient; call: ToolCall): Future[Result[ToolResult, string]] {.async: (raises: []).} =
  let res = ? await c.rpc("tools/call", %* {"name": call.name, "arguments": call.input}, call)
  try:
    return ok(parseToolResult(call.id, res))
  except CatchableError as e:
    return err("MCP tools/call result: " & e.msg)

proc closeAsync*(c: McpClient) {.async: (raises: []).} =
  if c.process.isNil:
    return
  discard c.process.terminate()
  try: discard await c.process.waitForExit(chronos.seconds(2))
  except CatchableError: discard
  await c.process.closeWait()
  c.process = nil
  c.initialized = false

proc toRuntimePort*(c: McpClient): ToolRuntimePort =
  ## Calls go through `invokeAsync`, which the ToolAgent awaits without
  ## blocking the loop; `listTools` returns what the last listing found.
  ToolRuntimePort(
    listTools: proc(): Result[seq[ToolSchema], string] {.gcsafe.} =
      if c.listed: ok(c.schemas)
      else: err("MCP '" & c.command & "': its tools were never listed"),
    invokeAsync: proc(call: ToolCall): Future[Result[ToolResult, string]]
        {.gcsafe, raises: [CatchableError].} = c.invokeAsync(call),
    close: proc() {.gcsafe.} = asyncSpawn c.closeAsync())
