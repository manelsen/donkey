## mcp_sync_client — the synchronous MCP stdio client, kept for Deno skills.
##
## MCP servers use the asynchronous client (mcp_client, E5.0). Deno skills
## still use this one because their tools are listed while a session is
## built, which is synchronous: their calls still hold the event loop until
## that path is made asynchronous too. stderr shares the pipe with stdout (an
## unread pipe would stall a chatty skill), so the reader skips every line
## that is not the response it waits for: logs, notifications, stale replies.
##
## Protocol:
##   1. Spawn process (command + args)
##   2. Send "initialize" handshake
##   3. "tools/list" → seq[ToolSchema]
##   4. "tools/call" → ToolResult
##
## Timeout: 30 seconds for each round-trip.

import std/[json, osproc, streams, strutils]
import ../../ports/tool
import ../../core/pipeops
import ../../core/app_meta
import ./mcp_client

# ── Adapter type ──────────────────────────────────────────────────────────────

type
  McpClientAdapter* = object
    command*:     string
    args*:        seq[string]
    process:      Process
    initialized*: bool
    nextId:       int

proc listTools*(c: var McpClientAdapter): Result[seq[ToolSchema], string] {.gcsafe.}
proc invoke*(c: var McpClientAdapter; call: ToolCall): Result[ToolResult, string] {.gcsafe.}
proc close*(c: var McpClientAdapter) {.gcsafe.}

proc toRuntimePort*(c: McpClientAdapter): ToolRuntimePort =
  var client = c
  ToolRuntimePort(
    listTools: proc(): Result[seq[ToolSchema], string] {.gcsafe.} = client.listTools(),
    invoke:    proc(call: ToolCall): Result[ToolResult, string] {.gcsafe.} = client.invoke(call),
    close:     proc() {.gcsafe.} = client.close(),
  )

# ── Constructor ───────────────────────────────────────────────────────────────

proc newMcpClient*(command: string; args: seq[string] = @[]): McpClientAdapter =
  McpClientAdapter(command: command, args: args, initialized: false, nextId: 1)

# ── Internal I/O ──────────────────────────────────────────────────────────────

proc ensureStarted(c: var McpClientAdapter): Result[void, string] =
  if c.process != nil and c.process.running():
    return ok()
  try:
    c.process = startProcess(
      c.command,
      args    = c.args,
      options = {poUsePath, poStdErrToStdOut}
    )
    ok()
  except CatchableError as e:
    err("Failed to start MCP process '" & c.command & "': " & e.msg)

proc sendLine(c: var McpClientAdapter; line: string): Result[void, string] =
  try:
    let inp = c.process.inputStream()
    inp.writeLine(line)
    inp.flush()
    ok()
  except CatchableError as e:
    err("Write to MCP stdin failed: " & e.msg)

proc readLine(c: var McpClientAdapter): Result[string, string] =
  try:
    let outp = c.process.outputStream()
    ok(outp.readLine())
  except CatchableError as e:
    err("Read from MCP stdout failed: " & e.msg)

proc rpc(c: var McpClientAdapter;
         meth:   string;
         params: JsonNode): Result[JsonNode, string] =
  let id  = c.nextId
  inc c.nextId
  let req = buildRequest(id, meth, params)
  ? c.sendLine(req)
  var resp: JsonNode
  while true:
    let line = ? c.readLine()
    if line.len == 0 and not c.process.running():
      return err("MCP process '" & c.command & "' exited")
    try:
      let msg = parseJson(line)
      if msg.kind == JObject and not msg.hasKey("method") and
          msg{"id"}.getInt(-1) == id:
        resp = msg
        break
    except CatchableError:
      discard   ## a log line or other text: not ours
  try:
    if resp.hasKey("error"):
      let errNode = resp["error"]
      let msg = errNode.getOrDefault("message").getStr($errNode)
      return err("MCP error from '" & meth & "': " & msg)
    if not resp.hasKey("result"):
      return err("MCP response missing 'result' for method '" & meth & "'")
    ok(resp["result"])
  except CatchableError as e:
    err("Failed to parse MCP response: " & e.msg)

proc initialize(c: var McpClientAdapter): Result[void, string] =
  if c.initialized:
    return ok()
  ? c.ensureStarted()
  let params = %* {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {"name": AppSlug, "version": AppVersion}
  }
  let _ = ? c.rpc("initialize", params)
  # Send initialized notification (no response expected)
  let notif = $(%* {"jsonrpc": "2.0", "method": "notifications/initialized", "params": %* {}})
  ? c.sendLine(notif)
  c.initialized = true
  ok()

# ── ToolPort conformance ──────────────────────────────────────────────────────

proc listTools*(c: var McpClientAdapter): Result[seq[ToolSchema], string] =
  ? c.initialize()
  let resultNode = ? c.rpc("tools/list", %* {})
  let toolsNode = resultNode.getOrDefault("tools")
  if toolsNode == nil or toolsNode.kind != JArray:
    return err("tools/list response missing 'tools' array")
  var schemas: seq[ToolSchema]
  for item in toolsNode:
    schemas.add(parseToolSchema(item))
  ok(schemas)

proc invoke*(c: var McpClientAdapter; call: ToolCall): Result[ToolResult, string] =
  ? c.initialize()
  let params = %* {
    "name":      call.name,
    "arguments": call.input
  }
  let resultNode = ? c.rpc("tools/call", params)
  ok(parseToolResult(call.id, resultNode))

proc close*(c: var McpClientAdapter) =
  ## Terminates the subprocess if running.
  if c.process != nil:
    c.process.terminate()
    discard c.process.waitForExit()
    c.process.close()
    c.process = nil
  c.initialized = false
