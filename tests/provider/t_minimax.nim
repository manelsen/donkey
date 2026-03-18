## MiniMaxAdapter unit tests — no real HTTP calls.
## MiniMax M2 uses OpenAI-compatible format via api.minimax.io/v1.

import std/[json, strutils, unittest]
import donkey/adapters/provider/minimax
import donkey/domain/message

suite "MiniMaxAdapter caps":

  test "toolCalling is true (M2 supports tool calling)":
    check newMiniMaxAdapter("key").caps().toolCalling

  test "name includes model":
    let a = newMiniMaxAdapter("key", model = "MiniMax-M2")
    check a.caps().name.contains("MiniMax-M2")

  test "does not require user turn first":
    check not newMiniMaxAdapter("key").caps().requiresUserFirst

suite "MiniMaxAdapter buildBody":

  test "model field is present":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newMiniMaxAdapter("k", model = "MiniMax-M2").buildBody(req)
    check body["model"].getStr() == "MiniMax-M2"

  test "user role is 'user' (OpenAI-compatible)":
    var h = newHistory()
    h.addUser("hello")
    let body = newMiniMaxAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["messages"][0]["role"].getStr() == "user"

  test "assistant role is 'assistant' (OpenAI-compatible)":
    var h = newHistory()
    h.addUser("q")
    h.addAssistant("a")
    let body = newMiniMaxAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["messages"][1]["role"].getStr() == "assistant"

  test "system prompt as first message with role=system":
    let req  = CompletionRequest(system: "You are Donkey.", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    let msgs = body["messages"]
    check msgs[0]["role"].getStr()    == "system"
    check msgs[0]["content"].getStr() == "You are Donkey."

  test "no system message when system empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["messages"].len == 0

  test "messages use 'content' field (not 'text')":
    var h = newHistory()
    h.addUser("hi there")
    let body = newMiniMaxAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["messages"][0]["content"].getStr() == "hi there"

  test "max_tokens present when set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 256)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["max_tokens"].getInt() == 256

suite "MiniMaxAdapter parseResponse":

  test "extracts text from choices[0].message.content":
    let j = %* {
      "choices": [{"message": {"role": "assistant", "content": "Hello from M2"}}],
      "usage": {"prompt_tokens": 5, "completion_tokens": 3}
    }
    let resp = parseMiniMaxResponse(j)
    check resp.text         == "Hello from M2"
    check resp.inputTokens  == 5
    check resp.outputTokens == 3

  test "handles missing usage gracefully":
    let j = %* {"choices": [{"message": {"role": "assistant", "content": "Hi"}}]}
    let resp = parseMiniMaxResponse(j)
    check resp.text         == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0

  test "extracts tool_calls when finish_reason is tool_calls":
    let j = %* {
      "choices": [{
        "finish_reason": "tool_calls",
        "message": {
          "role": "assistant",
          "content": nil,
          "tool_calls": [{
            "id":       "call_m2",
            "type":     "function",
            "function": {"name": "calculator", "arguments": "{\"expr\":\"2+2\"}"}
          }]
        }
      }],
      "usage": {"prompt_tokens": 8, "completion_tokens": 0}
    }
    let resp = parseMiniMaxResponse(j)
    check resp.toolCalls.len          == 1
    check resp.toolCalls[0].id        == "call_m2"
    check resp.toolCalls[0].name      == "calculator"
    check resp.toolCalls[0].inputJson == "{\"expr\":\"2+2\"}"

suite "MiniMaxAdapter tool calling (buildBody)":

  test "tools array included when req.tools non-empty":
    let tools = @[ToolDescription(name: "calc", description: "calculator", schemaJson: "{}")]
    let req  = CompletionRequest(system: "", messages: newHistory(), tools: tools)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body.hasKey("tools")
    check body["tools"].len == 1
    let fn = body["tools"][0]["function"]
    check fn["name"].getStr() == "calc"

  test "tools absent when req.tools empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    check not body.hasKey("tools")

  test "tool result message serialized as role=tool":
    var h = newHistory()
    h.addToolResult(callId = "call_m2", toolName = "calc", output = "4")
    let body = newMiniMaxAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs[0]["role"].getStr()         == "tool"
    check msgs[0]["tool_call_id"].getStr() == "call_m2"
    check msgs[0]["content"].getStr()      == "4"
