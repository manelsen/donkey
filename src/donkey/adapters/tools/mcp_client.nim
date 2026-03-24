## MCP Client Protocol — ToolPort adapter for Model Context Protocol servers.
##
## Communicates with external MCP servers over stdio using JSON-RPC 2.0.
## Each MCP server is spawned as a subprocess; stdin/stdout carry JSON-RPC messages.
##
## MCP Protocol Overview:
##   - Initialize: send initialize request, receive server capabilities
##   - tools/list: enumerate available tools
##   - tools/call: invoke a tool by name with input arguments

import std/[json, strutils, osproc, streams, os]
import ../../ports/tool
import ../../core/pipeops

type
  McpClient* = object
    ## Low-level MCP client for one server process.
    ## Manages JSON-RPC communication over stdio.
    command*: string
    args*: seq[string]
    workingDir*: string
    process*: Process
    requestId*: int
    initialized*: bool
    info*: McpServerInfo

  McpServerInfo* = object
    ## Metadata about a connected MCP server.
    name*: string
    version*: string

const
  MCP_PROTOCOL_VERSION* = "2024-11-05"

# ── JSON-RPC Helpers ─────────────────────────────────────────────────────────

proc nextId*(client: var McpClient): string =
  client.requestId.inc
  result = $client.requestId

proc sendJson*(client: var McpClient; body: JsonNode): void =
  ## Send a JSON-RPC message to the MCP server's stdin.
  let line = body.pretty
  client.process.inputStream.writeLine(line)
  client.process.inputStream.flush

proc recvJson*(client: var McpClient): Result[JsonNode, string] =
  ## Receive a JSON-RPC message from the MCP server's stdout.
  try:
    let line = client.process.outputStream.readLine
    if line.len == 0:
      return err("MCP server closed stdout")
    parseJson(line).ok
  except JsonParsingError as e:
    err("MCP parse error: " & e.msg)
  except CatchableError as e:
    err("MCP read error: " & e.msg)

proc callJsonRpc*(client: var McpClient; rpcMethod: string; params: JsonNode = %* {}): Result[JsonNode, string] =
  ## Send a JSON-RPC request and wait for response.
  let id = client.nextId
  let request = %* {
    "jsonrpc": "2.0",
    "id": id,
    "method": rpcMethod,
    "params": params
  }
  client.sendJson(request)
  
  while true:
    let response = ? client.recvJson
    # Handle both response and notification messages
    if response.hasKey("id") and response{"id"}.getStr("") == id:
      if response.hasKey("error"):
        return err(response{"error"}.pretty)
      return ok(response{"result"})
    # Skip notifications (no id) - continue waiting for our response
    elif not response.hasKey("id"):
      discard

# ── MCP Protocol Methods ────────────────────────────────────────────────────

proc initialize*(client: var McpClient): Result[McpServerInfo, string] =
  ## Send initialize handshake to the MCP server.
  let params = %* {
    "protocolVersion": MCP_PROTOCOL_VERSION,
    "capabilities": {},
    "clientInfo": {
      "name": "donkey-mcp-client",
      "version": "1.0.0"
    }
  }
  let rpcResult = ? client.callJsonRpc("initialize", params)
  client.initialized = true
  let info = McpServerInfo(
    name: rpcResult{"serverInfo"}{"name"}.getStr("unknown"),
    version: rpcResult{"serverInfo"}{"version"}.getStr("unknown")
  )
  client.info = info
  ok(info)

proc listToolsMcp*(client: var McpClient): Result[seq[ToolSchema], string] =
  ## Call the MCP server's tools/list method.
  if not client.initialized:
    return err("MCP client not initialized")
  let rpcResult = ? client.callJsonRpc("tools/list")
  var tools: seq[ToolSchema] = @[]
  for item in rpcResult{"tools"}:
    let name = item{"name"}.getStr("")
    if name.len == 0:
      continue
    tools.add ToolSchema(
      name: name,
      description: item{"description"}.getStr(""),
      inputSchema: item{"inputSchema"}
    )
  ok(tools)

proc callToolMcp*(client: var McpClient; name: string; input: JsonNode): Result[JsonNode, string] =
  ## Call the MCP server's tools/call method.
  if not client.initialized:
    return err("MCP client not initialized")
  let params = %* {
    "name": name,
    "arguments": input
  }
  client.callJsonRpc("tools/call", params)

# ── Client Lifecycle ─────────────────────────────────────────────────────────

proc newMcpClient*(command: string; args: seq[string] = @[]; workingDir: string = ""): Result[McpClient, string] =
  ## Spawn an MCP server process and initialize the connection.
  let workDir = if workingDir.len > 0: workingDir else: getCurrentDir()
  try:
    let process = startProcess(
      command,
      workingDir = workDir,
      args = args,
      env = nil,
      options = {poStdErrToStdOut, poUsePath}
    )
    if process.inputStream == nil or process.outputStream == nil:
      process.kill
      return err("Failed to create stdio streams for MCP server")
    var client = McpClient(
      command: command,
      args: args,
      workingDir: workDir,
      process: process,
      requestId: 0,
      initialized: false
    )
    let info = ? client.initialize
    client.info = info
    ok(client)
  except CatchableError as e:
    err("Failed to spawn MCP server: " & e.msg)

proc close*(client: var McpClient) =
  ## Terminate the MCP server process.
  if client.process != nil:
    client.process.kill
    client.process.close
    client.process = nil

proc isRunning*(client: McpClient): bool =
  ## Check if the MCP server process is still running.
  client.process != nil and client.process.running

# ── ToolPort Conformance ─────────────────────────────────────────────────────

proc listTools*(client: McpClient): Result[seq[ToolSchema], string] =
  ## List all available tools from the connected MCP server.
  if not client.initialized:
    let empty: seq[ToolSchema] = @[]
    return ok(empty)
  # Return an empty list - actual tools are discovered via mcp_list_tools tool
  # This is a meta-adapter that provides MCP management tools
  let empty2: seq[ToolSchema] = @[]
  ok(empty2)

proc invoke*(client: var McpClient; call: ToolCall): Result[ToolResult, string] =
  case call.name
  of "mcp_list_tools":
    # List all tools available on this MCP server
    if not client.initialized:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"MCP client not initialized\"}", isError: true))
    let tools = ? client.listToolsMcp
    var toolsArray: seq[JsonNode] = @[]
    for tool in tools:
      var toolObj = newJObject()
      toolObj["name"] = %tool.name
      toolObj["description"] = %tool.description
      toolObj["inputSchema"] = tool.inputSchema
      toolsArray.add toolObj
    let toolsJson = %toolsArray
    ok(ToolResult(callId: call.id, output: toolsJson.pretty, isError: false))
  of "mcp_call_tool":
    # Call a tool on the MCP server
    if not client.initialized:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"MCP client not initialized\"}", isError: true))
    let toolName = call.input{"toolName"}
    let arguments = call.input{"arguments"}
    if toolName.isNil or toolName.kind != JString or toolName.getStr("").len == 0:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"toolName is required\"}", isError: true))
    let args = if arguments.isNil or arguments.kind != JObject: newJObject() else: arguments
    let rpcResult = ? client.callToolMcp(toolName.getStr(""), args)
    ok(ToolResult(callId: call.id, output: rpcResult.pretty, isError: false))
  of "mcp_server_info":
    # Get information about the connected MCP server
    if not client.initialized:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"MCP client not initialized\"}", isError: true))
    var infoObj = newJObject()
    infoObj["name"] = %client.info.name
    infoObj["version"] = %client.info.version
    infoObj["command"] = %client.command
    infoObj["running"] = %client.isRunning
    let infoJson = infoObj
    ok(ToolResult(callId: call.id, output: infoJson.pretty, isError: false))
  of "mcp_ping":
    # Health check - is the server still responsive?
    if not client.initialized:
      return ok(ToolResult(callId: call.id, output: "{\"error\": \"MCP client not initialized\"}", isError: true))
    let running = client.isRunning
    var pingObj = newJObject()
    pingObj["ok"] = %running
    pingObj["server"] = %client.info.name
    let pingJson = pingObj
    ok(ToolResult(callId: call.id, output: pingJson.pretty, isError: false))
  else:
    ok(ToolResult(callId: call.id, output: "{\"error\": \"unknown tool: " & call.name & "\"}", isError: true))

# ── Module Exports ──────────────────────────────────────────────────────────

export McpClient, McpServerInfo, newMcpClient, close, isRunning
export MCP_PROTOCOL_VERSION
