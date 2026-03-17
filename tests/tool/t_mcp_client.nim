## McpClientAdapter unit tests — no real subprocess spawning.
## Tests cover: JSON-RPC message building (pure funcs), parseToolSchema,
## parseToolResult. Integration tests (real subprocess) live separately.

import std/[json, strutils, unittest]
import donkey/adapters/tool/mcp_client
import donkey/ports/tool

# ── JSON-RPC message building ─────────────────────────────────────────────────

suite "buildRequest":

  test "has jsonrpc 2.0 field":
    let msg = buildRequest(1, "tools/list", %* {})
    check msg.contains("\"jsonrpc\"")
    check msg.contains("2.0")

  test "has id field":
    let msg = buildRequest(42, "tools/list", %* {})
    check msg.contains("\"id\"")
    check msg.contains("42")

  test "has method field":
    let msg = buildRequest(1, "tools/call", %* {})
    check msg.contains("\"method\"")
    check msg.contains("tools/call")

  test "has params field":
    let msg = buildRequest(1, "tools/list", %* {"foo": "bar"})
    check msg.contains("\"params\"")
    check msg.contains("foo")

  test "serialises to valid JSON":
    let msg = buildRequest(7, "initialize", %* {"protocolVersion": "2024-11-05"})
    let parsed = parseJson(msg)
    check parsed["jsonrpc"].getStr() == "2.0"
    check parsed["id"].getInt()      == 7
    check parsed["method"].getStr()  == "initialize"

# ── parseToolSchema ───────────────────────────────────────────────────────────

suite "parseToolSchema":

  test "parses name and description":
    let j = %* {
      "name": "read_file",
      "description": "Reads a file from disk",
      "inputSchema": {"type": "object", "properties": {}}
    }
    let schema = parseToolSchema(j)
    check schema.name        == "read_file"
    check schema.description == "Reads a file from disk"

  test "preserves inputSchema as JsonNode":
    let inputSch = %* {"type": "object", "required": ["path"],
                        "properties": {"path": {"type": "string"}}}
    let j = %* {"name": "t", "description": "d", "inputSchema": inputSch}
    let schema = parseToolSchema(j)
    check schema.inputSchema["type"].getStr() == "object"
    check schema.inputSchema["required"][0].getStr() == "path"

  test "empty description when absent":
    let j = %* {"name": "foo", "inputSchema": %* {}}
    let schema = parseToolSchema(j)
    check schema.description == ""

  test "name field is required — present":
    let j = %* {"name": "bar", "description": "x", "inputSchema": %* {}}
    let schema = parseToolSchema(j)
    check schema.name == "bar"

# ── parseToolResult ───────────────────────────────────────────────────────────

suite "parseToolResult":

  test "parses successful text result":
    let callId = "call-1"
    let j = %* {
      "content": [{"type": "text", "text": "hello world"}],
      "isError": false
    }
    let res = parseToolResult(callId, j)
    check res.callId  == "call-1"
    check res.output  == "hello world"
    check res.isError == false

  test "parses error result":
    let j = %* {
      "content": [{"type": "text", "text": "something failed"}],
      "isError": true
    }
    let res = parseToolResult("id-x", j)
    check res.isError == true
    check res.output.contains("something failed")

  test "concatenates multiple content items":
    let j = %* {
      "content": [
        {"type": "text", "text": "part1"},
        {"type": "text", "text": "part2"}
      ],
      "isError": false
    }
    let res = parseToolResult("id-2", j)
    check res.output.contains("part1")
    check res.output.contains("part2")

  test "isError defaults to false when absent":
    let j = %* {"content": [{"type": "text", "text": "ok"}]}
    let res = parseToolResult("id-3", j)
    check res.isError == false

# ── ToolSchema / ToolCall / ToolResult types ──────────────────────────────────

suite "ToolPort types":

  test "ToolSchema has name, description, inputSchema":
    let s = ToolSchema(name: "x", description: "y", inputSchema: %* {})
    check s.name        == "x"
    check s.description == "y"

  test "ToolCall has id, name, input":
    let c = ToolCall(id: "c1", name: "read", input: %* {"path": "/tmp/f"})
    check c.id   == "c1"
    check c.name == "read"

  test "ToolResult has callId, output, isError":
    let r = ToolResult(callId: "c1", output: "data", isError: false)
    check r.callId  == "c1"
    check r.isError == false
