## Compat profile tests (US-002): the OpenAI-shaped transport must reproduce
## the current openai_pure payloads and add only declarative extras.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/compat
import donkey/domain/providers/openai_pure

proc userImage(text, url: string): ConversationHistory =
  @[ChatMessage(role: roleUser, text: text, imageUrl: url)]

proc runTests*() =
  suite "compat profile defaults":

    test "the default profile carries the OpenAI endpoint and no extras":
      let profile = defaultOpenAiProfile()
      check profile.id == "openai"
      check profile.endpoint == "https://api.openai.com/v1/chat/completions"
      check profile.extraHeaders.len == 0
      check profile.payloadExtras.isNil
      check profile.supportsImages

    test "a named profile keeps a custom endpoint":
      let profile = defaultOpenAiProfile(
        endpoint = "https://api.deepseek.com/v1/chat/completions", id = "deepseek")
      check profile.id == "deepseek"
      check profile.endpoint == "https://api.deepseek.com/v1/chat/completions"

  suite "compat request body":

    test "text and system match openai_pure byte for byte":
      var h = newHistory()
      h.addUser("oi")
      h.addAssistant("olá")
      let req = CompletionRequest(system: "seja breve", messages: h)
      check buildCompatRequestBody(defaultOpenAiProfile(), "gpt", req) ==
            buildRequestBody("gpt", req)

    test "tools and tool results match openai_pure":
      var h = newHistory()
      h.addUser("consulte")
      h.add(ChatMessage(role: roleAssistant, text: "",
                        toolCalls: @[ToolCallRequest(id: "t1", name: "search",
                                                     inputJson: """{"q":"x"}""")]))
      h.add(ChatMessage(role: roleTool, text: "resultado", toolCallId: "t1"))
      let req = CompletionRequest(
        messages: h,
        tools: @[ToolDescription(name: "search", description: "busca",
                                 schemaJson: """{"type":"object"}""")])
      check buildCompatRequestBody(defaultOpenAiProfile(), "gpt", req) ==
            buildRequestBody("gpt", req)

    test "an image turn matches openai_pure when the profile supports images":
      let req = CompletionRequest(
        messages: userImage("o que é?", "data:image/png;base64,QUJD"))
      check buildCompatRequestBody(defaultOpenAiProfile(), "gpt", req) ==
            buildRequestBody("gpt", req)

    test "a profile without image support drops the image and keeps the text":
      var profile = defaultOpenAiProfile()
      profile.supportsImages = false
      let req = CompletionRequest(
        messages: userImage("o que é?", "data:image/png;base64,QUJD"))
      let body = buildCompatRequestBody(profile, "gpt", req)
      let content = body["messages"][0]["content"]
      check content.kind == JString
      check content.getStr() == "o que é?"

    test "payload extras merge at the top level without dropping base fields":
      var profile = defaultOpenAiProfile()
      profile.payloadExtras = %* {"thinking": {"type": "enabled"}}
      let body = buildCompatRequestBody(profile, "glm", CompletionRequest())
      check body["model"].getStr() == "glm"
      check body["stream"].getBool() == false
      check body["thinking"]["type"].getStr() == "enabled"

    test "a profile can carry the provider wire quirks":
      var profile = defaultOpenAiProfile()
      profile.quirks = OpenAiWireQuirks(
        toolResultName: false, toolCallsEmptyContent: true,
        imageEmptyTextPart: false, imageWithToolCalls: false,
        toolChoiceAuto: true, omitStreamKey: true,
        includeReasoningField: false)
      let req = CompletionRequest(
        messages: @[ChatMessage(role: roleUser, text: "oi")],
        tools: @[ToolDescription(name: "search", description: "b",
                                 schemaJson: """{"type":"object"}""")],
        reasoning: true)
      let body = buildCompatRequestBody(profile, "glm", req)
      check not body.hasKey("stream")
      check body["tool_choice"].getStr() == "auto"
      check not body.hasKey("include_reasoning")

    test "reasoning extras merge only when reasoning is requested":
      var profile = defaultOpenAiProfile()
      profile.reasoningExtras = %* {"thinking": {"type": "enabled"}}
      let plain = buildCompatRequestBody(profile, "glm", CompletionRequest())
      check not plain.hasKey("thinking")
      let reasoning = CompletionRequest(reasoning: true)
      check buildCompatRequestBody(profile, "glm", reasoning)["thinking"]["type"].getStr() ==
            "enabled"

    test "stream extras merge only for streaming requests":
      var profile = defaultOpenAiProfile()
      profile.streamExtras = %* {"stream_options": {"include_usage": true}}
      check not buildCompatRequestBody(profile, "m", CompletionRequest()).hasKey("stream_options")
      let streaming = buildCompatRequestBody(profile, "m", CompletionRequest(), stream = true)
      check streaming["stream_options"]["include_usage"].getBool()

    test "streaming is carried through":
      let body = buildCompatRequestBody(defaultOpenAiProfile(), "gpt",
                                        CompletionRequest(), stream = true)
      check body["stream"].getBool()

when isMainModule:
  runTests()
