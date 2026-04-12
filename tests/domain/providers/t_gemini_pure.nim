## gemini_pure.nim unit tests.
## Tests: geminiRole, textPart, functionCallPart, functionResponsePart,
## toGeminiContent, appendContent, buildGeminiContents, buildGeminiRequest,
## parseGeminiResponse.

import std/[json, tables, unittest]
import donkey/domain/providers/gemini_pure
import donkey/core/pipeops
import donkey/domain/message

suite "geminiRole":
  test "assistant maps to model":
    check geminiRole(roleAssistant) == "model"

  test "tool maps to user":
    check geminiRole("tool") == "user"

  test "user passes through":
    check geminiRole(roleUser) == roleUser

  test "system passes through":
    check geminiRole("system") == "system"

suite "textPart":
  test "produces text part":
    let part = textPart("hello")
    check part == %* {"text": "hello"}

suite "functionCallPart":
  test "produces functionCall part":
    let tc = ToolCallRequest(id: "call_1", name: "calc", inputJson: """{"x":1}""")
    let part = functionCallPart(tc)
    check part{"functionCall"}{"name"}.getStr() == "calc"
    check part{"functionCall"}{"args"} == %* {"x": 1}

  test "handles invalid json gracefully":
    let tc = ToolCallRequest(id: "call_2", name: "bad", inputJson: "not json")
    let part = functionCallPart(tc)
    check part{"functionCall"}{"name"}.getStr() == "bad"
    check part{"functionCall"}{"args"}.kind == JObject

suite "functionResponsePart":
  test "produces functionResponse part":
    let msg = ChatMessage(role: "tool", text: """{"result":42}""", toolCallId: "call_1")
    let part = functionResponsePart(msg, "calc")
    check part{"functionResponse"}{"name"}.getStr() == "calc"
    check part{"functionResponse"}{"response"} == %* {"result": 42}
    check part{"functionResponse"}{"id"}.getStr() == "call_1"

  test "handles invalid json gracefully":
    let msg = ChatMessage(role: "tool", text: "plain text", toolCallId: "call_2")
    let part = functionResponsePart(msg, "func")
    check part{"functionResponse"}{"response"} == %* {"result": "plain text"}

suite "toGeminiContent":
  test "user message":
    let msg = ChatMessage(role: roleUser, text: "hello")
    let content = toGeminiContent(msg)
    check content{"role"}.getStr() == "user"
    check content{"parts"}[0]{"text"}.getStr() == "hello"

  test "assistant message":
    let msg = ChatMessage(role: roleAssistant, text: "hi")
    let content = toGeminiContent(msg)
    check content{"role"}.getStr() == "model"
    check content{"parts"}[0]{"text"}.getStr() == "hi"

  test "assistant with tool calls":
    let msg = ChatMessage(
      role: roleAssistant,
      text: "using calc",
      toolCalls: @[
        ToolCallRequest(id: "call_1", name: "calc", inputJson: """{"x":1}""")
      ],
    )
    let content = toGeminiContent(msg)
    check content{"role"}.getStr() == "model"
    check content{"parts"}[0]{"text"}.getStr() == "using calc"
    check content{"parts"}[1]{"functionCall"}{"name"}.getStr() == "calc"

suite "appendContent":
  test "appends new role":
    var contents: seq[JsonNode] = @[]
    let content = %* {"role": "user", "parts": [{"text": "hello"}]}
    appendContent(contents, content)
    check contents.len == 1

  test "merges same role":
    var contents: seq[JsonNode] = @[]
    appendContent(contents, %* {"role": "user", "parts": [{"text": "one"}]})
    appendContent(contents, %* {"role": "user", "parts": [{"text": "two"}]})
    check contents.len == 1
    check contents[0]["parts"].len == 2

  test "does not merge different roles":
    var contents: seq[JsonNode] = @[]
    appendContent(contents, %* {"role": "user", "parts": [{"text": "hello"}]})
    appendContent(contents, %* {"role": "model", "parts": [{"text": "hi"}]})
    check contents.len == 2

suite "buildGeminiContents":
  test "empty messages":
    let (contents, toolNames) = buildGeminiContents(@[])
    check contents.len == 0
    check toolNames.len == 0

  test "user and assistant":
    let msgs = @[
      ChatMessage(role: roleUser, text: "hello"),
      ChatMessage(role: roleAssistant, text: "hi"),
    ]
    let (contents, _) = buildGeminiContents(msgs)
    check contents.len == 2
    check contents[0]{"role"}.getStr() == "user"
    check contents[1]{"role"}.getStr() == "model"

  test "tracks tool call IDs":
    let msgs = @[
      ChatMessage(
        role: roleAssistant,
        text: "",
        toolCalls: @[ToolCallRequest(id: "call_1", name: "calc", inputJson: "{}")]
      ),
      ChatMessage(role: "tool", text: "42", toolCallId: "call_1"),
    ]
    let (contents, toolNames) = buildGeminiContents(msgs)
    check toolNames["call_1"] == "calc"
    check contents[1]{"role"}.getStr() == "user"
    check contents[1]{"parts"}[0]{"functionResponse"}{"name"}.getStr() == "calc"

suite "buildGeminiRequest":
  test "basic request":
    let req = CompletionRequest(
      system: "You are Gemini.",
      messages: @[ChatMessage(role: roleUser, text: "hi")],
    )
    let body = buildGeminiRequest(req)
    check body.hasKey("systemInstruction")
    check body["systemInstruction"]["parts"][0]{"text"}.getStr() == "You are Gemini."
    check body["contents"][0]{"role"}.getStr() == "user"

  test "maxTokens sets generationConfig":
    let req = CompletionRequest(
      system: "",
      messages: @[],
      maxTokens: 1024,
    )
    let body = buildGeminiRequest(req)
    check body["generationConfig"]["maxOutputTokens"].getInt() == 1024

  test "tools serialized":
    let req = CompletionRequest(
      system: "",
      messages: @[],
      tools: @[
        ToolDescription(
          name: "get_weather",
          description: "Get weather",
          schemaJson: """{"type":"object","properties":{"city":{"type":"string"}}}""",
        )
      ],
    )
    let body = buildGeminiRequest(req)
    check body["tools"][0]["functionDeclarations"][0]{"name"}.getStr() == "get_weather"

suite "parseGeminiResponse":
  test "extracts text":
    let j = %* {
      "candidates": [{
        "content": {"parts": [{"text": "Hello from Gemini"}]}
      }],
      "usageMetadata": {
        "promptTokenCount": 10,
        "candidatesTokenCount": 6
      }
    }
    let resp = parseGeminiResponse(j).value
    check resp.text == "Hello from Gemini"
    check resp.inputTokens == 10
    check resp.outputTokens == 6

  test "handles missing usageMetadata":
    let j = %* {
      "candidates": [{"content": {"parts": [{"text": "hi"}]}}]
    }
    let resp = parseGeminiResponse(j).value
    check resp.text == "hi"
    check resp.inputTokens == 0
    check resp.outputTokens == 0

  test "parses functionCall":
    let j = %* {
      "candidates": [{
        "content": {"parts": [
          {"text": "Using calc"},
          {"functionCall": {"id": "call_1", "name": "calc", "args": {"x": 1}}}
        ]}
      }],
      "usageMetadata": {"promptTokenCount": 12, "candidatesTokenCount": 5}
    }
    let resp = parseGeminiResponse(j).value
    check resp.text == "Using calc"
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id == "call_1"
    check resp.toolCalls[0].name == "calc"
