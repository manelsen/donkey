## GeminiAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, role mapping (assistant→model),
## tool serialization, alternation normalization, response parsing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/gemini
import donkey/domain/message

suite "GeminiAdapter caps":

  test "requiresUserFirst is true":
    check newGeminiAdapter("key").caps().requiresUserFirst

  test "name includes model":
    let a = newGeminiAdapter("key", model = "gemini-2.0-flash")
    check a.caps().name.contains("gemini")

  test "streaming not yet reported":
    check not newGeminiAdapter("key").caps().streaming

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

  test "tools are serialized as function declarations":
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
    let body = newGeminiAdapter("k").buildBody(req)
    check body.hasKey("tools")
    check body["tools"][0]["functionDeclarations"][0]["name"].getStr() == "read_file"
    check body["tools"][0]["functionDeclarations"][0]["parameters"]["type"].getStr() == "object"

  test "assistant tool calls become functionCall parts":
    let h = @[
      ChatMessage(
        role: roleAssistant,
        text: "Vou chamar uma função.",
        toolCalls: @[
          ToolCallRequest(id: "call_1", name: "calc", inputJson: """{"expression":"2+2"}""")
        ],
      )
    ]
    let body = newGeminiAdapter("k").buildBody(CompletionRequest(system: "", messages: h))
    let parts = body["contents"][0]["parts"]
    check body["contents"][0]["role"].getStr() == "model"
    check parts[0]["text"].getStr() == "Vou chamar uma função."
    check parts[1]["functionCall"]["name"].getStr() == "calc"
    check parts[1]["functionCall"]["args"]["expression"].getStr() == "2+2"

  test "tool result becomes user functionResponse part":
    let h = @[
      ChatMessage(
        role: roleAssistant,
        text: "",
        toolCalls: @[
          ToolCallRequest(id: "call_1", name: "calc", inputJson: """{"expression":"2+2"}""")
        ],
      ),
      ChatMessage(role: "tool", text: """{"result":"4"}""", toolCallId: "call_1"),
    ]
    let body = newGeminiAdapter("k").buildBody(CompletionRequest(system: "", messages: h))
    let responsePart = body["contents"][1]["parts"][0]["functionResponse"]
    check body["contents"][1]["role"].getStr() == "user"
    check responsePart["name"].getStr() == "calc"
    check responsePart["response"]["result"].getStr() == "4"

  test "adjacent user turns are merged to satisfy alternation":
    let h = @[
      ChatMessage(role: roleUser, text: "one"),
      ChatMessage(role: roleUser, text: "two"),
    ]
    let body = newGeminiAdapter("k").buildBody(CompletionRequest(system: "", messages: h))
    check body["contents"].len == 1
    check body["contents"][0]["role"].getStr() == "user"
    check body["contents"][0]["parts"][0]["text"].getStr() == "one"
    check body["contents"][0]["parts"][1]["text"].getStr() == "two"

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

  test "parses functionCall parts from response":
    let j = %* {
      "candidates": [{
        "content": {"parts": [
          {"text": "Vou usar uma tool."},
          {"functionCall": {"id": "call_7", "name": "read_file",
                            "args": {"path": "src/app.nim"}}}
        ]}
      }],
      "usageMetadata": {
        "promptTokenCount": 12,
        "candidatesTokenCount": 5
      }
    }
    let resp = parseGeminiResponse(j)
    check resp.text == "Vou usar uma tool."
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id == "call_7"
    check resp.toolCalls[0].name == "read_file"
    check parseJson(resp.toolCalls[0].inputJson)["path"].getStr() == "src/app.nim"

suite "GeminiAdapter buildUrl":

  test "api key is in query string":
    let a   = newGeminiAdapter("my-api-key", model = "gemini-2.0-flash")
    let url = a.buildUrl()
    check url.contains("key=my-api-key")

  test "model is in url path":
    let a   = newGeminiAdapter("k", model = "gemini-2.0-flash")
    let url = a.buildUrl()
    check url.contains("gemini-2.0-flash")
