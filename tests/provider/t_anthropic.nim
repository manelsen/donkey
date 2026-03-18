## AnthropicAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, system as top-level field,
## message role mapping, response parsing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/anthropic
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

suite "AnthropicAdapter parseResponse":

  test "extracts text from content[0].text":
    let j = %* {
      "content": [{"type": "text", "text": "Hello from Anthropic"}],
      "usage": {"input_tokens": 8, "output_tokens": 4}
    }
    let resp = parseAnthropicResponse(j)
    check resp.text         == "Hello from Anthropic"
    check resp.inputTokens  == 8
    check resp.outputTokens == 4

  test "handles missing usage gracefully":
    let j = %* {"content": [{"type": "text", "text": "Hi"}]}
    let resp = parseAnthropicResponse(j)
    check resp.text        == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0

  test "extracts toolCalls from tool_use content blocks":
    let j = %* {
      "stop_reason": "tool_use",
      "content": [{
        "type":  "tool_use",
        "id":    "toolu_abc",
        "name":  "search",
        "input": {"q": "nim lang"}
      }],
      "usage": {"input_tokens": 10, "output_tokens": 0}
    }
    let resp = parseAnthropicResponse(j)
    check resp.toolCalls.len          == 1
    check resp.toolCalls[0].id        == "toolu_abc"
    check resp.toolCalls[0].name      == "search"
    check resp.toolCalls[0].inputJson.contains("nim lang")

suite "AnthropicAdapter tool calling (buildBody)":

  test "tools array in Anthropic format when req.tools non-empty":
    let tools = @[ToolDescription(name: "search", description: "web search", schemaJson: "{}")]
    let req  = CompletionRequest(system: "", messages: newHistory(), tools: tools)
    let body = newAnthropicAdapter("k").buildBody(req)
    check body.hasKey("tools")
    check body["tools"].len                      == 1
    check body["tools"][0]["name"].getStr()        == "search"
    check body["tools"][0]["description"].getStr() == "web search"
    check body["tools"][0].hasKey("input_schema")

  test "tools absent when req.tools empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newAnthropicAdapter("k").buildBody(req)
    check not body.hasKey("tools")

  test "tool result message becomes user turn with tool_result block":
    var h = newHistory()
    h.addToolResult(callId = "toolu_abc", toolName = "search", output = "results")
    let body = newAnthropicAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs[0]["role"].getStr() == "user"
    let blk = msgs[0]["content"][0]
    check blk["type"].getStr()        == "tool_result"
    check blk["tool_use_id"].getStr() == "toolu_abc"
    check blk["content"].getStr()     == "results"
