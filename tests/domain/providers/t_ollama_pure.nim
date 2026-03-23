## ollama_pure.nim unit tests.
## Tests: messageToOllama, buildOllamaRequest, parseOllamaResponse.

import std/[json, unittest]
import donkey/domain/providers/ollama_pure
import donkey/core/pipeops
import donkey/domain/message

# ── messageToOllama tests ────────────────────────────────────────────────────────

suite "messageToOllama":

  test "converts user message":
    let msg = ChatMessage(role: roleUser, text: "hello")
    let j = msg |> messageToOllama
    check j{"role"}.getStr == "user"
    check j{"content"}.getStr == "hello"

  test "converts assistant message":
    let msg = ChatMessage(role: roleAssistant, text: "hi there")
    let j = msg |> messageToOllama
    check j{"role"}.getStr == "assistant"
    check j{"content"}.getStr == "hi there"

  test "converts system message":
    let msg = ChatMessage(role: roleSystem, text: "you are helpful")
    let j = msg |> messageToOllama
    check j{"role"}.getStr == "system"
    check j{"content"}.getStr == "you are helpful"

  test "converts tool result message":
    let msg = ChatMessage(role: "tool", text: "42")
    let j = msg |> messageToOllama
    check j{"role"}.getStr == "tool"
    check j{"content"}.getStr == "42"

  test "converts message with tool calls":
    let msg = ChatMessage(
      role:  roleAssistant,
      text:  "I'll search for that",
      toolCalls: @[
        ToolCallRequest(id: "call_abc", name: "web_search", inputJson: """{"query":"nim lang"}""")
      ]
    )
    let j = msg |> messageToOllama
    check j{"role"}.getStr == "assistant"
    check j{"content"}.getStr == "I'll search for that"
    check j{"tool_calls"}.len == 1
    check j{"tool_calls"}[0]{"function"}{"name"}.getStr == "web_search"
    check j{"tool_calls"}[0]{"function"}{"arguments"} == %* {"query": "nim lang"}

  test "converts message with tool calls and string arguments":
    let msg = ChatMessage(
      role:  roleAssistant,
      text:  "using calc",
      toolCalls: @[
        ToolCallRequest(id: "call_1", name: "calc", inputJson: """{"x":1}""")
      ]
    )
    let j = msg |> messageToOllama
    check j{"tool_calls"}[0]{"function"}{"arguments"} == %* {"x": 1}

  test "converts message with invalid tool call json gracefully":
    let msg = ChatMessage(
      role:  roleAssistant,
      text:  "bad json",
      toolCalls: @[
        ToolCallRequest(id: "call_2", name: "bad", inputJson: "not json at all")
      ]
    )
    let j = msg |> messageToOllama
    check j{"tool_calls"}[0]{"function"}{"name"}.getStr == "bad"
    check j{"tool_calls"}[0]{"function"}{"arguments"}.kind == JObject

  test "converts message with imageUrl":
    let msg = ChatMessage(role: roleUser, text: "look at this", imageUrl: "http://example.com/img.jpg")
    let j = msg |> messageToOllama
    check j{"role"}.getStr == "user"
    check j{"content"}.getStr == "look at this\nhttp://example.com/img.jpg"

# ── buildOllamaRequest tests ────────────────────────────────────────────────────

suite "buildOllamaRequest":

  test "builds basic request":
    let req = CompletionRequest(
      messages: @[
        ChatMessage(role: roleUser, text: "hello")
      ]
    )
    let body = buildOllamaRequest("llama3", req)
    check body{"model"}.getStr == "llama3"
    check body{"stream"}.getBool == false
    check body{"messages"}.len == 1
    check body{"messages"}[0]{"role"}.getStr == "user"
    check body{"messages"}[0]{"content"}.getStr == "hello"

  test "includes system message":
    let req = CompletionRequest(
      system: "you are helpful",
      messages: @[
        ChatMessage(role: roleUser, text: "hello")
      ]
    )
    let body = buildOllamaRequest("llama3", req)
    check body{"messages"}[0]{"role"}.getStr == "system"
    check body{"messages"}[0]{"content"}.getStr == "you are helpful"

  test "sets maxTokens":
    let req = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "hi")],
      maxTokens: 100
    )
    let body = buildOllamaRequest("llama3", req)
    check body{"options"}{"num_predict"}.getInt == 100

  test "omits options when maxTokens is zero":
    let req = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "hi")],
      maxTokens: 0
    )
    let body = buildOllamaRequest("llama3", req)
    check body.hasKey("options") == false

  test "includes tools":
    let req = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "hi")],
      tools: @[
        ToolDescription(
          name: "web_search",
          description: "search the web",
          schemaJson: """{"type":"object","properties":{"query":{"type":"string"}}}"""
        )
      ]
    )
    let body = buildOllamaRequest("llama3", req)
    check body{"tools"}.len == 1
    check body{"tools"}[0]{"type"}.getStr == "function"
    check body{"tools"}[0]{"function"}{"name"}.getStr == "web_search"
    check body{"tools"}[0]{"function"}{"description"}.getStr == "search the web"
    check body{"tools"}[0]{"function"}{"parameters"}.kind == JObject

  test "sets stream true":
    let req = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "hi")]
    )
    let body = buildOllamaRequest("llama3", req, stream = true)
    check body{"stream"}.getBool == true

  test "sets stream false by default":
    let req = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "hi")]
    )
    let body = buildOllamaRequest("llama3", req)
    check body{"stream"}.getBool == false

  test "handles invalid tool schema gracefully":
    let req = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "hi")],
      tools: @[
        ToolDescription(name: "bad", description: "desc", schemaJson: "invalid json")
      ]
    )
    let body = buildOllamaRequest("llama3", req)
    check body{"tools"}[0]{"function"}{"parameters"}.kind == JObject

# ── parseOllamaResponse tests ──────────────────────────────────────────────────

suite "parseOllamaResponse":

  test "parses basic response":
    let j = %* {
      "message": {"role": "assistant", "content": "hello world"},
      "prompt_eval_count": 10,
      "eval_count": 5
    }
    let resp = parseOllamaResponse(j)
    check resp.text == "hello world"
    check resp.inputTokens == 10
    check resp.outputTokens == 5
    check resp.toolCalls.len == 0

  test "parses empty message content":
    let j = %* {
      "message": {"role": "assistant", "content": ""},
      "prompt_eval_count": 5,
      "eval_count": 2
    }
    let resp = parseOllamaResponse(j)
    check resp.text == ""

  test "parses missing message":
    let j = %* {"prompt_eval_count": 0, "eval_count": 0}
    let resp = parseOllamaResponse(j)
    check resp.text == ""
    check resp.toolCalls.len == 0

  test "parses response with tool calls":
    let j = %* {
      "message": {
        "role": "assistant",
        "content": "I'll search for that",
        "tool_calls": [
          {
            "function": {
              "name": "web_search",
              "arguments": {"query": "nim lang"}
            }
          }
        ]
      },
      "prompt_eval_count": 15,
      "eval_count": 20
    }
    let resp = parseOllamaResponse(j)
    check resp.text == "I'll search for that"
    check resp.inputTokens == 15
    check resp.outputTokens == 20
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id == "ollama-0"
    check resp.toolCalls[0].name == "web_search"
    check resp.toolCalls[0].inputJson == """{"query":"nim lang"}"""

  test "generates sequential tool call ids":
    let j = %* {
      "message": {
        "role": "assistant",
        "content": "using tools",
        "tool_calls": [
          {"function": {"name": "calc", "arguments": {}}},
          {"function": {"name": "search", "arguments": {}}}
        ]
      }
    }
    let resp = parseOllamaResponse(j)
    check resp.toolCalls[0].id == "ollama-0"
    check resp.toolCalls[1].id == "ollama-1"

  test "parses tool call with string arguments":
    let j = %* {
      "message": {
        "role": "assistant",
        "content": "calc",
        "tool_calls": [
          {"function": {"name": "calc", "arguments": "{\"x\": 1}"}}
        ]
      }
    }
    let resp = parseOllamaResponse(j)
    check resp.toolCalls[0].inputJson == """{"x": 1}"""

  test "handles missing function in tool_calls gracefully":
    let j = %* {
      "message": {
        "role": "assistant",
        "content": "oops",
        "tool_calls": [
          {"no": "function here"}
        ]
      }
    }
    let resp = parseOllamaResponse(j)
    check resp.toolCalls.len == 0

  test "handles missing arguments in tool_calls gracefully":
    let j = %* {
      "message": {
        "role": "assistant",
        "content": "no args",
        "tool_calls": [
          {"function": {"name": "myfunc"}}
        ]
      }
    }
    let resp = parseOllamaResponse(j)
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].name == "myfunc"
    check resp.toolCalls[0].inputJson == "{}"

  test "handles null arguments in tool_calls":
    var j = %* {
      "message": {
        "role": "assistant",
        "content": "null args",
        "tool_calls": [
          {"function": {"name": "myfunc", "arguments": "null"}}
        ]
      }
    }
    # manually set arguments to JNull to simulate
    j{"message"}{"tool_calls"}[0]{"function"}{"arguments"} = newJNull()
    let resp = parseOllamaResponse(j)
    check resp.toolCalls[0].inputJson == "{}"

  test "handles empty tool_calls array":
    let j = %* {
      "message": {
        "role": "assistant",
        "content": "no tools",
        "tool_calls": []
      }
    }
    let resp = parseOllamaResponse(j)
    check resp.toolCalls.len == 0

  test "defaults token counts to zero when missing":
    let j = %* {"message": {"role": "assistant", "content": "hi"}}
    let resp = parseOllamaResponse(j)
    check resp.inputTokens == 0
    check resp.outputTokens == 0

  test "handles missing tool_calls key":
    let j = %* {
      "message": {"role": "assistant", "content": "no tools field"}
    }
    let resp = parseOllamaResponse(j)
    check resp.toolCalls.len == 0
