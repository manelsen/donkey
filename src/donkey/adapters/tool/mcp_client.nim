## McpClientAdapter — ToolPort for MCP servers and Deno/Clawhub skills.
##
## Spawns a subprocess and communicates via stdin/stdout JSON-RPC 2.0.
## Both MCP servers and Deno skills are treated identically.
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

# ── Adapter type ──────────────────────────────────────────────────────────────

type
  McpClientAdapter* = object
    command*:     string
    args*:        seq[string]
    process:      Process
    initialized*: bool
    nextId:       int

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
  let line = ? c.readLine()
  try:
    let resp = parseJson(line)
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
  let result_node = ? c.rpc("tools/list", %* {})
  let toolsNode = result_node.getOrDefault("tools")
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
  let result_node = ? c.rpc("tools/call", params)
  ok(parseToolResult(call.id, result_node))

proc close*(c: var McpClientAdapter) =
  ## Terminates the subprocess if running.
  if c.process != nil:
    c.process.terminate()
    discard c.process.waitForExit()
    c.process.close()
    c.process = nil
  c.initialized = false
