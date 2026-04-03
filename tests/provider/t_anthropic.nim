## AnthropicAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, system as top-level field,
## tool serialization, tool result serialization, response parsing.

import std/[json, strutils, unittest]
import results
import donkey/adapters/provider/anthropic
import donkey/core/pipeops
import donkey/domain/message

suite "AnthropicAdapter caps":

  test "streaming is true":
    check newAnthropicAdapter("key").caps().streaming

  test "toolCalling is true":
    check newAnthropicAdapter("key").caps().toolCalling

  test "does not require user turn first":
    check not newAnthropicAdapter("key").caps().requiresUserFirst

  test "name includes model":
    let a = newAnthropicAdapter("key", model = "claude-opus-4-6")
    check a.caps().name.contains("claude")

suite "AnthropicAdapter buildBody":

  test "baseUrl resolves to v1/messages endpoint":
    let adapter = newAnthropicAdapter("k", baseUrl = "https://api.z.ai/api/anthropic")
    check adapter.messagesUrl() == "https://api.z.ai/api/anthropic/v1/messages"

  test "system is top-level field not a message":
    var h = newHistory()
    h.addUser("hello")
    let req  = CompletionRequest(system: "You are Donkey.", messages: h)
    let body = newAnthropicAdapter("k").buildBody(req)
    # system must be a top-level string, not inside messages array
    check body.hasKey("system")
    check body["system"].getStr().contains("Donkey")
    # messages array should only contain user/assistant turns
    let msgs = body["messages"]
    for m in msgs:
      check m["role"].getStr() != "system"

  test "messages array has user and assistant roles":
    var h = newHistory()
    h.addUser("ping")
    h.addAssistant("pong")
    let body = newAnthropicAdapter("k").buildBody(
      CompletionRequest(system: "s", messages: h))
    let msgs = body["messages"]
    check msgs[0]["role"].getStr() == "user"
    check msgs[1]["role"].getStr() == "assistant"

  test "model field is present":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newAnthropicAdapter("k", model = "claude-opus-4-6").buildBody(req)
    check body["model"].getStr() == "claude-opus-4-6"

  test "max_tokens is always present (required by Anthropic API)":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newAnthropicAdapter("k").buildBody(req)
    check body.hasKey("max_tokens")
    check body["max_tokens"].getInt() > 0

  test "max_tokens uses request value when set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 512)
    let body = newAnthropicAdapter("k").buildBody(req)
    check body["max_tokens"].getInt() == 512

  test "no system field when empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newAnthropicAdapter("k").buildBody(req)
    check not body.hasKey("system") or body["system"].getStr() == ""

  test "content field is a string":
    var h = newHistory()
    h.addUser("test")
    let body = newAnthropicAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["messages"][0]["content"].kind == JString

  test "tools are serialized at top level":
    let req = CompletionRequest(
      system: "",
      messages: newHistory(),
      tools: @[
        ToolDescription(
          name: "read_file",
          description: "Read a file",
          schemaJson: """{"type":"object","properties":{"path":{"type":"string"}}}""",
        )
      ],
    )
    let body = newAnthropicAdapter("k").buildBody(req)
    check body.hasKey("tools")
    check body["tools"][0]["name"].getStr() == "read_file"
    check body["tools"][0]["input_schema"]["type"].getStr() == "object"

  test "assistant tool calls become tool_use blocks":
    let h = @[
      ChatMessage(
        role: roleAssistant,
        text: "Vou usar uma tool.",
        toolCalls: @[
          ToolCallRequest(id: "call_1", name: "calc", inputJson: """{"expression":"2+2"}""")
        ],
      )
    ]
    let body = newAnthropicAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let content = body["messages"][0]["content"]
    check content.kind == JArray
    check content[0]["type"].getStr() == "text"
    check content[1]["type"].getStr() == "tool_use"
    check content[1]["name"].getStr() == "calc"
    check content[1]["input"]["expression"].getStr() == "2+2"

  test "tool result becomes user tool_result block":
    let h = @[
      ChatMessage(role: "tool", text: "4", toolCallId: "call_1")
    ]
    let body = newAnthropicAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["messages"][0]["role"].getStr() == "user"
    check body["messages"][0]["content"][0]["type"].getStr() == "tool_result"
    check body["messages"][0]["content"][0]["tool_use_id"].getStr() == "call_1"
    check body["messages"][0]["content"][0]["content"].getStr() == "4"

suite "AnthropicAdapter parseResponse":

  test "extracts text from content[0].text":
    let j = %* {
      "content": [{"type": "text", "text": "Hello from Anthropic"}],
      "usage": {"input_tokens": 8, "output_tokens": 4}
    }
    let resp = parseAnthropicResponse(j).get()
    check resp.text         == "Hello from Anthropic"
    check resp.inputTokens  == 8
    check resp.outputTokens == 4

  test "handles missing usage gracefully":
    let j = %* {"content": [{"type": "text", "text": "Hi"}]}
    let resp = parseAnthropicResponse(j).get()
    check resp.text        == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0

  test "parses tool_use blocks from response":
    let j = %* {
      "content": [
        {"type": "text", "text": "Vou chamar uma tool."},
        {"type": "tool_use", "id": "call_7", "name": "read_file",
         "input": {"path": "src/app.nim"}}
      ],
      "usage": {"input_tokens": 10, "output_tokens": 3}
    }
    let resp = parseAnthropicResponse(j).get()
    check resp.text == "Vou chamar uma tool."
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id == "call_7"
    check resp.toolCalls[0].name == "read_file"
    check parseJson(resp.toolCalls[0].inputJson)["path"].getStr() == "src/app.nim"

suite "AnthropicAdapter streaming helpers":

  test "buildStreamBody enables stream":
    let body = newAnthropicAdapter("k").buildStreamBody(
      CompletionRequest(system: "", messages: newHistory()))
    check body["stream"].getBool()

  test "parseAnthropicSseLine extracts text delta":
    let line = """data: {"type":"content_block_delta","delta":{"text":"Hel"}}"""
    let parsed = parseAnthropicSseLine(line)
    check not parsed.isErr
    let chunk = parsed.value
    check chunk.token == "Hel"
    check not chunk.done

  test "parseAnthropicSseLine handles message stop":
    let parsed = parseAnthropicSseLine("""data: {"type":"message_stop"}""")
    check not parsed.isErr
    let chunk = parsed.value
    check chunk.done
