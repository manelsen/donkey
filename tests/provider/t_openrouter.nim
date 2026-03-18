## OpenRouterAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, required headers, response parsing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/openrouter
import donkey/domain/message

suite "OpenRouterAdapter caps":

  test "streaming is true":
    check newOpenRouterAdapter("key").caps().streaming

  test "toolCalling is true":
    check newOpenRouterAdapter("key").caps().toolCalling

  test "name includes model":
    let a = newOpenRouterAdapter("key", model = "gpt-4o")
    check a.caps().name.contains("gpt-4o")

  test "does not require user turn first":
    check not newOpenRouterAdapter("key").caps().requiresUserFirst

suite "OpenRouterAdapter buildBody":

  test "system prompt becomes first message with role system":
    var h = newHistory()
    h.addUser("hi")
    let req  = CompletionRequest(system: "You are Donkey.", messages: h)
    let body = newOpenRouterAdapter("k").buildBody(req)
    let msgs = body["messages"]
    check msgs[0]["role"].getStr()    == "system"
    check msgs[0]["content"].getStr().contains("Donkey")

  test "model field is set":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOpenRouterAdapter("k", model = "mistral-7b").buildBody(req)
    check body["model"].getStr() == "mistral-7b"

  test "no system message when empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOpenRouterAdapter("k").buildBody(req)
    check body["messages"].len == 0

  test "max_tokens present when set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 256)
    let body = newOpenRouterAdapter("k").buildBody(req)
    check body["max_tokens"].getInt() == 256

  test "max_tokens absent when zero":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 0)
    let body = newOpenRouterAdapter("k").buildBody(req)
    check not body.hasKey("max_tokens")

  test "history order preserved":
    var h = newHistory()
    h.addUser("q")
    h.addAssistant("a")
    let body = newOpenRouterAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs[0]["role"].getStr() == "user"
    check msgs[1]["role"].getStr() == "assistant"

suite "OpenRouterAdapter required headers":

  test "HTTP-Referer header is set":
    let a = newOpenRouterAdapter("key")
    check a.referer.contains("donkey")

  test "X-Title header is set":
    let a = newOpenRouterAdapter("key")
    check a.xTitle.len > 0

suite "OpenRouterAdapter parseResponse":

  test "extracts text from choices[0].message.content":
    let j = %* {
      "choices": [{"message": {"content": "Hello!"}}],
      "usage": {"prompt_tokens": 10, "completion_tokens": 5}
    }
    let resp = parseOpenRouterResponse(j)
    check resp.text         == "Hello!"
    check resp.inputTokens  == 10
    check resp.outputTokens == 5

  test "handles missing usage gracefully":
    let j = %* {"choices": [{"message": {"content": "Hi"}}]}
    let resp = parseOpenRouterResponse(j)
    check resp.text        == "Hi"
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
            "id":       "call_abc",
            "type":     "function",
            "function": {"name": "search", "arguments": "{\"q\":\"nim\"}"}
          }]
        }
      }],
      "usage": {"prompt_tokens": 10, "completion_tokens": 5}
    }
    let resp = parseOpenRouterResponse(j)
    check resp.toolCalls.len         == 1
    check resp.toolCalls[0].id       == "call_abc"
    check resp.toolCalls[0].name     == "search"
    check resp.toolCalls[0].inputJson == "{\"q\":\"nim\"}"

suite "OpenRouterAdapter tool calling (buildBody)":

  test "tools array included when req.tools non-empty":
    let tools = @[ToolDescription(name: "search", description: "web search", schemaJson: "{}")]
    let req  = CompletionRequest(system: "", messages: newHistory(), tools: tools)
    let body = newOpenRouterAdapter("k").buildBody(req)
    check body.hasKey("tools")
    check body["tools"].len == 1
    let fn = body["tools"][0]["function"]
    check fn["name"].getStr()        == "search"
    check fn["description"].getStr() == "web search"

  test "tools array absent when req.tools empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOpenRouterAdapter("k").buildBody(req)
    check not body.hasKey("tools")

  test "tool result message serialized as role=tool":
    var h = newHistory()
    h.addToolResult(callId = "call_abc", toolName = "search", output = "results")
    let body = newOpenRouterAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs[0]["role"].getStr()         == "tool"
    check msgs[0]["tool_call_id"].getStr() == "call_abc"
    check msgs[0]["content"].getStr()      == "results"

suite "OpenRouterAdapter vision":

  test "user message with imageUrl becomes content array":
    var h = newHistory()
    h.addUserWithImage("what is in this image?", "https://example.com/photo.jpg")
    let body = newOpenRouterAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msg = body["messages"][0]
    check msg["role"].getStr()   == "user"
    check msg["content"].kind    == JArray
    check msg["content"].len     == 2
    check msg["content"][0]["type"].getStr()         == "text"
    check msg["content"][0]["text"].getStr()         == "what is in this image?"
    check msg["content"][1]["type"].getStr()         == "image_url"
    check msg["content"][1]["image_url"]["url"].getStr() == "https://example.com/photo.jpg"

  test "plain user message keeps content as string":
    var h = newHistory()
    h.addUser("plain text")
    let body = newOpenRouterAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msg = body["messages"][0]
    check msg["content"].kind   == JString
    check msg["content"].getStr() == "plain text"

  test "image message and text message can coexist in history":
    var h = newHistory()
    h.addUser("first message")
    h.addUserWithImage("describe this", "https://img.example.com/x.png")
    h.addAssistant("sure, that is a cat")
    let body = newOpenRouterAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs.len                      == 3
    check msgs[0]["content"].kind       == JString
    check msgs[1]["content"].kind       == JArray
    check msgs[2]["content"].getStr()   == "sure, that is a cat"
