## OpenRouterAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, required headers, response parsing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/openrouter
import donkey/core/pipeops
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

  test "parses tool_calls from response":
    let j = %* {
      "choices": [{
        "message": {
          "content": "",
          "tool_calls": [{
            "id": "call_abc123",
            "type": "function",
            "function": {"name": "calc", "arguments": "{\"expression\":\"2+2\"}"}
          }]
        }
      }],
      "usage": {"prompt_tokens": 20, "completion_tokens": 8}
    }
    let resp = parseOpenRouterResponse(j)
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id        == "call_abc123"
    check resp.toolCalls[0].name      == "calc"
    check resp.toolCalls[0].inputJson == "{\"expression\":\"2+2\"}"

  test "toolCalls is empty when no tool_calls field":
    let j = %* {"choices": [{"message": {"content": "plain text"}}]}
    let resp = parseOpenRouterResponse(j)
    check resp.toolCalls.len == 0

suite "OpenRouterAdapter buildBody with tools":

  test "tools array present when tools provided":
    let req = CompletionRequest(
      system: "",
      messages: newHistory(),
      tools: @[ToolDescription(
        name: "calc",
        description: "Evaluate math",
        schemaJson: "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"}},\"required\":[\"expression\"]}"
      )]
    )
    let body = newOpenRouterAdapter("k").buildBody(req)
    check body.hasKey("tools")
    check body.hasKey("tool_choice")
    check body["tool_choice"].getStr() == "auto"
    let tools = body["tools"]
    check tools.len == 1
    check tools[0]["type"].getStr()              == "function"
    check tools[0]["function"]["name"].getStr()  == "calc"

  test "no tools key when tools seq empty":
    let req = CompletionRequest(system: "", messages: newHistory())
    let body = newOpenRouterAdapter("k").buildBody(req)
    check not body.hasKey("tools")

  test "tool result message serialised with tool_call_id":
    var h = newHistory()
    h.addToolResult("call_x", "calc", "4")
    let body = newOpenRouterAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msg = body["messages"][0]
    check msg["role"].getStr()         == "tool"
    check msg["tool_call_id"].getStr() == "call_x"
    check msg["content"].getStr().contains("""status="output"""")
    check msg["content"].getStr().contains("4")

  test "assistant message with tool_calls serialised correctly":
    var h = newHistory()
    h.addAssistantWithToolCalls("", @[ToolCallRequest(
      id: "call_1", name: "bash", inputJson: "{\"command\":\"ls\"}")])
    let body = newOpenRouterAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msg = body["messages"][0]
    check msg["role"].getStr() == "assistant"
    let tcs = msg["tool_calls"]
    check tcs.len == 1
    check tcs[0]["id"].getStr()                    == "call_1"
    check tcs[0]["function"]["name"].getStr()      == "bash"

suite "OpenRouterAdapter streaming helpers":

  test "buildStreamBody enables stream and usage":
    let body = newOpenRouterAdapter("k").buildStreamBody(
      CompletionRequest(system: "", messages: newHistory()))
    check body["stream"].getBool()
    check body["stream_options"]["include_usage"].getBool()

  test "parseOpenRouterSseLine extracts token delta":
    let line = """data: {"choices":[{"delta":{"content":"Hel"}}]}"""
    let parsed = parseOpenRouterSseLine(line)
    check not parsed.isErr
    let chunk = parsed.value
    check chunk.token == "Hel"
    check not chunk.done

  test "parseOpenRouterSseLine extracts usage when present":
    let line = """data: {"choices":[{"delta":{}}],"usage":{"prompt_tokens":12,"completion_tokens":5}}"""
    let parsed = parseOpenRouterSseLine(line)
    check not parsed.isErr
    let chunk = parsed.value
    check chunk.inputTokens == 12
    check chunk.outputTokens == 5

  test "parseOpenRouterSseLine handles done sentinel":
    let parsed = parseOpenRouterSseLine("data: [DONE]")
    check not parsed.isErr
    let chunk = parsed.value
    check chunk.done
