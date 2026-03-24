## Tests for MCP Client Protocol adapter.

import std/[json, strutils, unittest]
import donkey/adapters/tools/mcp_client
import donkey/core/pipeops
import donkey/ports/tool

suite "MCP Client Protocol":

  test "McpClient spawn with invalid command returns error":
    let result = newMcpClient("nonexistent_command_xyz")
    check result.isErr
    check "Failed to spawn" in result.error

  test "McpClient initial state":
    let result = newMcpClient("echo", @["hello"])
    # This will fail because echo doesn't speak JSON-RPC, but we can check the process started
    discard

  test "JSON-RPC message formatting":
    var client = McpClient(requestId: 0)
    let id = client.nextId
    check id == "1"
    let id2 = client.nextId
    check id2 == "2"

  test "McpServerInfo initialization":
    let info = McpServerInfo(name: "test-server", version: "1.0.0")
    check info.name == "test-server"
    check info.version == "1.0.0"

  test "isRunning returns false for uninitialized client":
    let client = McpClient()
    check client.isRunning == false

  test "newMcpClient with empty command returns error":
    let result = newMcpClient("")
    check result.isErr

  test "McpClient close on nil process is safe":
    var client = McpClient()
    client.close()  # Should not crash
    check true

  test "listTools returns empty for uninitialized client":
    let client = McpClient()
    let result = listTools(client)
    check result.isOk
    let empty: seq[ToolSchema] = @[]
    check result.get == empty

  test "invoke with unknown tool returns error":
    var client = McpClient()
    let call = ToolCall(id: "1", name: "unknown_tool", input: newJObject())
    let result = invoke(client, call)
    check result.isOk
    let toolResult = result.get
    check toolResult.callId == "1"
    check toolResult.isError == true
    check "unknown tool" in toolResult.output

  test "invoke mcp_list_tools without initialization returns error":
    var client = McpClient()
    let call = ToolCall(id: "1", name: "mcp_list_tools", input: newJObject())
    let result = invoke(client, call)
    check result.isOk
    let toolResult = result.get
    check toolResult.isError == true
    check "not initialized" in toolResult.output

  test "invoke mcp_call_tool without initialization returns error":
    var client = McpClient()
    var input = newJObject()
    input["toolName"] = %"test"
    let call = ToolCall(id: "1", name: "mcp_call_tool", input: input)
    let result = invoke(client, call)
    check result.isOk
    let toolResult = result.get
    check toolResult.isError == true
    check "not initialized" in toolResult.output

  test "invoke mcp_call_tool without toolName field returns error":
    var client = McpClient()
    # No toolName field at all
    let call = ToolCall(id: "1", name: "mcp_call_tool", input: newJObject())
    let result = invoke(client, call)
    check result.isOk
    let toolResult = result.get
    check toolResult.isError == true
    check "not initialized" in toolResult.output

  test "invoke mcp_call_tool with nil toolName returns error":
    var client = McpClient()
    var input = newJObject()
    input["toolName"] = newJNull()
    let call = ToolCall(id: "1", name: "mcp_call_tool", input: input)
    let result = invoke(client, call)
    check result.isOk
    let toolResult = result.get
    check toolResult.isError == true
    check "not initialized" in toolResult.output

  test "invoke mcp_server_info without initialization returns error":
    var client = McpClient()
    let call = ToolCall(id: "1", name: "mcp_server_info", input: newJObject())
    let result = invoke(client, call)
    check result.isOk
    let toolResult = result.get
    check toolResult.isError == true
    check "not initialized" in toolResult.output

  test "invoke mcp_ping without initialization returns error":
    var client = McpClient()
    let call = ToolCall(id: "1", name: "mcp_ping", input: newJObject())
    let result = invoke(client, call)
    check result.isOk
    let toolResult = result.get
    check toolResult.isError == true
    check "not initialized" in toolResult.output

  test "MCP_PROTOCOL_VERSION is set":
    check MCP_PROTOCOL_VERSION == "2024-11-05"
