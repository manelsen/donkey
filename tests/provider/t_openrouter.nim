## OpenRouterAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, required headers, response parsing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/openrouter
import donkey/core/pipeops
import donkey/domain/message

proc runTests*() =
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

  suite "OpenRouterAdapter prompt cache markers for Claude (E8.2)":

    proc req(): CompletionRequest =
      var h = newHistory()
      h.addUser("oi")
      h.addAssistant("olá")
      h.addUser("tudo bem?")
      CompletionRequest(system: "Você é o Donkey.", messages: h)

    test "anthropic/* models: the system and the last message carry a marker":
      let body = newOpenRouterAdapter("key", model = "anthropic/claude-sonnet-5.5").buildBody(req())
      let msgs = body["messages"]
      check msgs[0]["role"].getStr == "system"
      check msgs[0]["content"] == %* [{"type": "text", "text": "Você é o Donkey.",
                                       "cache_control": {"type": "ephemeral"}}]
      check msgs[msgs.len - 1]["content"] == %* [{"type": "text", "text": "tudo bem?",
                                                  "cache_control": {"type": "ephemeral"}}]
      check msgs[1]["content"].kind == JString   ## the earlier turns are untouched

    test "a single message without a system prompt still carries the marker":
      var h = newHistory()
      h.addUser("oi")
      let body = newOpenRouterAdapter("key", model = "anthropic/claude-sonnet-5.5").buildBody(
        CompletionRequest(messages: h))
      check body["messages"][0]["content"][0]["cache_control"] == %* {"type": "ephemeral"}

    test "other models: no markers (their caches are automatic)":
      let body = newOpenRouterAdapter("key", model = "openai/gpt-5").buildBody(req())
      check "cache_control" notin $body

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
      let resp = parseOpenRouterResponse(j).get()
      check resp.text         == "Hello!"
      check resp.inputTokens  == 10
      check resp.outputTokens == 5

    test "handles missing usage gracefully":
      let j = %* {"choices": [{"message": {"content": "Hi"}}]}
      let resp = parseOpenRouterResponse(j).get()
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
      let resp = parseOpenRouterResponse(j).get()
      check resp.toolCalls.len == 1
      check resp.toolCalls[0].id        == "call_abc123"
      check resp.toolCalls[0].name      == "calc"
      check resp.toolCalls[0].inputJson == "{\"expression\":\"2+2\"}"

    test "toolCalls is empty when no tool_calls field":
      let j = %* {"choices": [{"message": {"content": "plain text"}}]}
      let resp = parseOpenRouterResponse(j).get()
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

  suite "OpenRouter Gemini thought signatures":
    ## Gemini 3 behind an OpenAI-compatible gateway returns each tool call's
    ## signature in `extra_content` and wants it back; only a real one, and
    ## only to a Gemini/Gemma model (strict providers reject the key) —
    ## hermes agent/transports/chat_completions.py.
    proc roundWith(sig: string): CompletionRequest =
      CompletionRequest(messages: @[
        ChatMessage(role: roleUser, text: "hora?"),
        ChatMessage(role: roleAssistant, toolCalls: @[
          ToolCallRequest(id: "c1", name: "clock", inputJson: "{}", signature: sig)]),
        ChatMessage(role: roleTool, text: "12:00", toolCallId: "c1")])

    test "the response's signature is kept, in either shape":
      for extra in [%* {"google": {"thought_signature": "sig-g"}},
                    %* {"thought_signature": "sig-g"}]:
        let r = parseOpenRouterResponse(%* {"choices": [{"message": {
          "content": "", "tool_calls": [{"id": "c1", "type": "function",
            "function": {"name": "clock", "arguments": "{}"},
            "extra_content": extra}]}}]})
        check r.isOk
        check r.get.toolCalls[0].signature == "sig-g"

    test "the streamed delta keeps it too":
      let chunk = parseOpenRouterSseLine("""data: {"choices":[{"delta":{"tool_calls":[""" &
        """{"index":0,"id":"c1","function":{"name":"clock","arguments":"{}"},""" &
        """"extra_content":{"google":{"thought_signature":"sig-s"}}}]}}]}""")
      check chunk.isOk
      check chunk.get.toolCalls[0].signature == "sig-s"

    test "a Gemini model gets the signature back on its tool call":
      let body = newOpenRouterAdapter("k", model = "google/gemini-3-flash").buildBody(roundWith("sig-g"))
      check body["messages"][1]["tool_calls"][0]["extra_content"] ==
        %* {"google": {"thought_signature": "sig-g"}}

    test "no signature, or a non-Gemini model, sends no extra_content":
      let gemini = newOpenRouterAdapter("k", model = "google/gemini-3-flash")
      check not ($gemini.buildBody(roundWith(""))).contains("extra_content")
      let other = newOpenRouterAdapter("k", model = "anthropic/claude-sonnet-5")
      check not ($other.buildBody(roundWith("sig-g"))).contains("extra_content")

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

    test "parseOpenRouterSseLine extracts streaming tool call fragments":
      let line = """data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{\"path\":"}}]}}]}"""
      let parsed = parseOpenRouterSseLine(line)
      check not parsed.isErr
      let chunk = parsed.value
      check chunk.toolCalls.len == 1
      check chunk.toolCalls[0].index == 0
      check chunk.toolCalls[0].id == "call_1"
      check chunk.toolCalls[0].name == "read_file"
      check chunk.toolCalls[0].arguments == "{\"path\":"

    test "parseOpenRouterSseLine handles done sentinel":
      let parsed = parseOpenRouterSseLine("data: [DONE]")
      check not parsed.isErr
      let chunk = parsed.value
      check chunk.done

when isMainModule:
  runTests()
