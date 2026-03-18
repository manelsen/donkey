## GeminiAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, role mapping (assistant→model),
## systemInstruction placement, response parsing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/gemini
import donkey/domain/message

suite "GeminiAdapter caps":

  test "requiresUserFirst is true":
    check newGeminiAdapter("key").caps().requiresUserFirst

  test "name includes model":
    let a = newGeminiAdapter("key", model = "gemini-2.0-flash")
    check a.caps().name.contains("gemini")

  test "streaming reported":
    check newGeminiAdapter("key").caps().streaming

suite "GeminiAdapter buildBody":

  test "user role maps to 'user'":
    var h = newHistory()
    h.addUser("hello")
    let body = newGeminiAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["contents"][0]["role"].getStr() == "user"

  test "assistant role maps to 'model'":
    var h = newHistory()
    h.addUser("q")
    h.addAssistant("a")
    let body = newGeminiAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["contents"][1]["role"].getStr() == "model"

  test "text is inside parts array":
    var h = newHistory()
    h.addUser("ping")
    let body = newGeminiAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let parts = body["contents"][0]["parts"]
    check parts[0]["text"].getStr() == "ping"

  test "systemInstruction present when system non-empty":
    let req  = CompletionRequest(system: "You are Donkey.", messages: newHistory())
    let body = newGeminiAdapter("k").buildBody(req)
    check body.hasKey("systemInstruction")
    check body["systemInstruction"]["parts"][0]["text"].getStr().contains("Donkey")

  test "no systemInstruction when system empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newGeminiAdapter("k").buildBody(req)
    check not body.hasKey("systemInstruction")

  test "generationConfig present with maxOutputTokens when maxTokens set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 1024)
    let body = newGeminiAdapter("k").buildBody(req)
    check body.hasKey("generationConfig")
    check body["generationConfig"]["maxOutputTokens"].getInt() == 1024

suite "GeminiAdapter parseResponse":

  test "extracts text from candidates[0].content.parts[0].text":
    let j = %* {
      "candidates": [{
        "content": {"parts": [{"text": "Hello from Gemini"}]}
      }],
      "usageMetadata": {
        "promptTokenCount": 10,
        "candidatesTokenCount": 6
      }
    }
    let resp = parseGeminiResponse(j)
    check resp.text         == "Hello from Gemini"
    check resp.inputTokens  == 10
    check resp.outputTokens == 6

  test "handles missing usageMetadata gracefully":
    let j = %* {
      "candidates": [{"content": {"parts": [{"text": "hi"}]}}]
    }
    let resp = parseGeminiResponse(j)
    check resp.text         == "hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0

  test "extracts toolCalls from functionCall parts":
    let j = %* {
      "candidates": [{
        "content": {
          "parts": [{
            "functionCall": {
              "name": "search",
              "args": {"q": "nim lang"}
            }
          }]
        },
        "finishReason": "STOP"
      }],
      "usageMetadata": {"promptTokenCount": 5, "candidatesTokenCount": 0}
    }
    let resp = parseGeminiResponse(j)
    check resp.toolCalls.len      == 1
    check resp.toolCalls[0].name  == "search"
    check resp.toolCalls[0].inputJson.contains("nim lang")

suite "GeminiAdapter tool calling (buildBody)":

  test "tools as functionDeclarations when req.tools non-empty":
    let tools = @[ToolDescription(name: "search", description: "web search", schemaJson: "{}")]
    let req  = CompletionRequest(system: "", messages: newHistory(), tools: tools)
    let body = newGeminiAdapter("k").buildBody(req)
    check body.hasKey("tools")
    let decls = body["tools"][0]["functionDeclarations"]
    check decls.len                    == 1
    check decls[0]["name"].getStr()        == "search"
    check decls[0]["description"].getStr() == "web search"

  test "tools absent when req.tools empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newGeminiAdapter("k").buildBody(req)
    check not body.hasKey("tools")

  test "tool result message becomes user turn with functionResponse part":
    var h = newHistory()
    h.addToolResult(callId = "ignored", toolName = "search", output = "results")
    let body = newGeminiAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let contents = body["contents"]
    check contents[0]["role"].getStr() == "user"
    let part = contents[0]["parts"][0]
    check part.hasKey("functionResponse")
    check part["functionResponse"]["name"].getStr() == "search"

suite "GeminiAdapter buildUrl":

  test "api key is in query string":
    let a   = newGeminiAdapter("my-api-key", model = "gemini-2.0-flash")
    let url = a.buildUrl()
    check url.contains("key=my-api-key")

  test "model is in url path":
    let a   = newGeminiAdapter("k", model = "gemini-2.0-flash")
    let url = a.buildUrl()
    check url.contains("gemini-2.0-flash")
