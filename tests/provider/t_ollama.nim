## OllamaAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, response parsing, tool calls.

import std/[json, strutils, unittest]
import donkey/adapters/provider/ollama
import donkey/core/pipeops
import donkey/domain/message

suite "OllamaAdapter caps":

  test "name includes model":
    let a = newOllamaAdapter(model = "llama3")
    check a.caps().name.contains("llama3")

  test "toolCalling is true":
    check newOllamaAdapter().caps().toolCalling

  test "does not require user turn first":
    check not newOllamaAdapter().caps().requiresUserFirst

suite "OllamaAdapter buildBody":

  test "model field is set":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOllamaAdapter(model = "mistral").buildBody(req)
    check body["model"].getStr() == "mistral"

  test "system prompt becomes first message with role system":
    var h = newHistory()
    h.addUser("hi")
    let req  = CompletionRequest(system: "You are Donkey.", messages: h)
    let body = newOllamaAdapter().buildBody(req)
    let msgs = body["messages"]
    check msgs[0]["role"].getStr() == "system"
    check msgs[0]["content"].getStr().contains("Donkey")

  test "no system message when empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOllamaAdapter().buildBody(req)
    check body["messages"].len == 0

  test "stream defaults to false":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOllamaAdapter().buildBody(req)
    check body["stream"].getBool() == false

  test "history order preserved":
    var h = newHistory()
    h.addUser("q")
    h.addAssistant("a")
    let body = newOllamaAdapter().buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs[0]["role"].getStr() == "user"
    check msgs[1]["role"].getStr() == "assistant"

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
    let body = newOllamaAdapter().buildBody(req)
    check body.hasKey("tools")
    let tools = body["tools"]
    check tools.len == 1
    check tools[0]["type"].getStr() == "function"
    check tools[0]["function"]["name"].getStr() == "calc"

  test "no tools key when tools seq empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOllamaAdapter().buildBody(req)
    check not body.hasKey("tools")

suite "OllamaAdapter parseOllamaResponse":

  test "extracts text from message.content":
    let j = %* {
      "message": {"role": "assistant", "content": "Hello from Ollama!"},
      "done": true,
      "prompt_eval_count": 12,
      "eval_count": 7
    }
    let resp = parseOllamaResponse(j)
    check resp.text         == "Hello from Ollama!"
    check resp.inputTokens  == 12
    check resp.outputTokens == 7

  test "handles missing token counts gracefully":
    let j = %* {"message": {"role": "assistant", "content": "Hi"}, "done": true}
    let resp = parseOllamaResponse(j)
    check resp.text         == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0

  test "parses tool_calls from message":
    let j = %* {
      "message": {
        "role": "assistant",
        "content": "",
        "tool_calls": [{
          "function": {
            "name": "calc",
            "arguments": {"expression": "2+2"}
          }
        }]
      },
      "done": true
    }
    let resp = parseOllamaResponse(j)
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].name == "calc"
    check resp.toolCalls[0].inputJson.contains("2+2")

  test "toolCalls is empty when no tool_calls field":
    let j = %* {"message": {"role": "assistant", "content": "plain"}, "done": true}
    let resp = parseOllamaResponse(j)
    check resp.toolCalls.len == 0

  test "synthesizes non-empty id for each tool call":
    let j = %* {
      "message": {
        "role": "assistant", "content": "",
        "tool_calls": [{"function": {"name": "fn", "arguments": {}}}]
      },
      "done": true
    }
    let resp = parseOllamaResponse(j)
    check resp.toolCalls[0].id.len > 0

suite "OllamaAdapter SSE line parsing":

  test "parseOllamaSseLine extracts token from streaming chunk":
    let line = """{"model":"llama3","message":{"role":"assistant","content":"Hel"},"done":false}"""
    let chunk = parseOllamaSseLine(line)
    check not chunk.isErr
    check chunk.value.token == "Hel"
    check not chunk.value.done

  test "parseOllamaSseLine recognises done sentinel":
    let line = """{"model":"llama3","message":{"role":"assistant","content":""},"done":true,"prompt_eval_count":10,"eval_count":5}"""
    let chunk = parseOllamaSseLine(line)
    check not chunk.isErr
    check chunk.value.done
    check chunk.value.inputTokens  == 10
    check chunk.value.outputTokens == 5

  test "parseOllamaSseLine returns empty chunk for blank line":
    let chunk = parseOllamaSseLine("")
    check not chunk.isErr
    check chunk.value.token == ""
    check not chunk.value.done
