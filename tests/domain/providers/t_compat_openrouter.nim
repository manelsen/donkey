## OpenRouter compat profile tests (US-005): the required headers, the wire
## quirks and the streaming extras live in the profile, not in the adapter.
##
## Pure: no network.

import std/[json, strutils, unittest]
import donkey/adapters/provider/openrouter
import donkey/domain/message
import donkey/domain/providers/compat

proc userImage(text, url: string): ConversationHistory =
  @[ChatMessage(role: roleUser, text: text, imageUrl: url)]

proc runTests*() =
  suite "OpenRouter compat profile":

    test "carries the OpenRouter endpoint by default":
      let profile = openRouterCompatProfile()
      check profile.id == "openrouter"
      check profile.endpoint == OpenRouterEndpoint
      check profile.supportsImages

    test "endpoint, referer and X-Title are overridable":
      let profile = openRouterCompatProfile(
        endpoint = "http://localhost:1234/chat",
        referer = "https://example.test",
        xTitle = "my-app")
      check profile.endpoint == "http://localhost:1234/chat"
      check profile.extraHeaders == @[("HTTP-Referer", "https://example.test"),
                                      ("X-Title", "my-app")]

    test "carries the two required headers":
      let profile = openRouterCompatProfile()
      check profile.extraHeaders == @[("HTTP-Referer", OpenRouterReferer),
                                      ("X-Title", OpenRouterTitle)]

    test "profileFor reflects the adapter's endpoint, referer and X-Title":
      let a = newOpenRouterAdapter(
        "key",
        endpoint = "http://localhost:8080/chat",
        referer = "https://audit.test",
        xTitle = "audit-app")
      let profile = a.profileFor()
      check profile.endpoint == "http://localhost:8080/chat"
      check profile.extraHeaders == @[("HTTP-Referer", "https://audit.test"),
                                      ("X-Title", "audit-app")]

    test "profileFor falls back to the OpenRouter endpoint when empty":
      let profile = newOpenRouterAdapter("key", endpoint = "").profileFor()
      check profile.endpoint == OpenRouterEndpoint

    test "carries the OpenRouter wire quirks":
      let q = openRouterCompatProfile().quirks
      check not q.toolResultName
      check q.emptyContentKey
      check q.toolCallsEmptyContent
      check q.imageEmptyTextPart
      check not q.imageWithToolCalls
      check q.toolChoiceAuto
      check q.omitStreamKey
      check q.includeReasoningField
      check openRouterCompatProfile().reasoningExtras.isNil

  suite "OpenRouter compat non-streaming body":

    test "omits stream and stream_options":
      let body = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                        CompletionRequest())
      check not body.hasKey("stream")
      check not body.hasKey("stream_options")

    test "tool_choice is auto when tools are present":
      let req = CompletionRequest(
        tools: @[ToolDescription(name: "calc", description: "math",
                                 schemaJson: """{"type":"object"}""")])
      let body = buildCompatRequestBody(openRouterCompatProfile(), "m", req)
      check body["tool_choice"].getStr() == "auto"
      check body["tools"].len == 1

    test "no tool_choice when there are no tools":
      let body = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                        CompletionRequest())
      check not body.hasKey("tools")
      check not body.hasKey("tool_choice")

    test "include_reasoning only when reasoning is requested":
      let plain = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                         CompletionRequest())
      check not plain.hasKey("include_reasoning")
      let reasoning = buildCompatRequestBody(
        openRouterCompatProfile(), "m", CompletionRequest(reasoning: true))
      check reasoning["include_reasoning"].getBool()

  suite "OpenRouter compat streaming body":

    test "sets stream and stream_options.include_usage":
      let body = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                        CompletionRequest(), stream = true)
      check body["stream"].getBool()
      check body["stream_options"]["include_usage"].getBool()

  suite "OpenRouter compat image handling":

    test "image with empty text keeps an empty text part before the image":
      let req = CompletionRequest(messages: userImage("", "data:image/png;base64,QUJD"))
      let content = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                           req)["messages"][0]["content"]
      check content.kind == JArray
      check content.len == 2
      check content[0]["type"].getStr() == "text"
      check content[0]["text"].getStr() == ""
      check content[1]["type"].getStr() == "image_url"

    test "image plus tool calls drops the image and keeps a string content":
      let req = CompletionRequest(messages: @[ChatMessage(
        role: roleAssistant, text: "",
        imageUrl: "data:image/png;base64,QUJD",
        toolCalls: @[ToolCallRequest(id: "c1", name: "bash",
                                     inputJson: """{"command":"ls"}""")])])
      let msg = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                       req)["messages"][0]
      check msg["content"].kind == JString
      check msg["content"].getStr() == ""
      check msg["tool_calls"].len == 1

  suite "OpenRouter compat tool messages":

    test "tool result carries no name field":
      var h = newHistory()
      h.addToolResult("call_x", "calc", "4")
      let msg = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                       CompletionRequest(messages: h))["messages"][0]
      check msg["role"].getStr() == "tool"
      check msg["tool_call_id"].getStr() == "call_x"
      check not msg.hasKey("name")

    test "assistant tool call with empty text has content empty string":
      var h = newHistory()
      h.addAssistantWithToolCalls("", @[ToolCallRequest(
        id: "call_1", name: "bash", inputJson: """{"command":"ls"}""")])
      let msg = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                       CompletionRequest(messages: h))["messages"][0]
      check msg["role"].getStr() == "assistant"
      check msg["content"].kind == JString
      check msg["content"].getStr() == ""
      check msg["tool_calls"][0]["function"]["name"].getStr() == "bash"

  suite "OpenRouter compat empty plain turns":

    test "empty user and assistant turns keep content as an empty string":
      let req = CompletionRequest(messages: @[
        ChatMessage(role: roleUser, text: ""),
        ChatMessage(role: roleAssistant, text: ""),
      ])
      let msgs = buildCompatRequestBody(openRouterCompatProfile(), "m",
                                        req)["messages"]
      check msgs.len == 2
      for msg in msgs:
        check msg.hasKey("content")
        check msg["content"].kind == JString
        check msg["content"].getStr() == ""

  suite "OpenRouter compat golden mixed body":

    test "system, image, tool call, tool result, tools and reasoning":
      var h = newHistory()
      h.addUserWithImage("o que é?", "data:image/png;base64,QUJD")
      h.addAssistantWithToolCalls("", @[ToolCallRequest(
        id: "call_1", name: "calc", inputJson: """{"expression":"2+2"}""")])
      h.addToolResult("call_1", "calc", "4")
      let req = CompletionRequest(
        system: "seja breve",
        messages: h,
        maxTokens: 512,
        tools: @[ToolDescription(name: "calc", description: "Evaluate math",
                                 schemaJson: """{"type":"object","properties":{"expression":{"type":"string"}}}""")],
        reasoning: true)
      let body = buildCompatRequestBody(openRouterCompatProfile(),
                                        "anthropic/claude-sonnet", req)

      check body["model"].getStr() == "anthropic/claude-sonnet"
      check body["max_tokens"].getInt() == 512
      check body["include_reasoning"].getBool()
      check not body.hasKey("stream")
      check not body.hasKey("stream_options")

      let msgs = body["messages"]
      check msgs.len == 4
      check msgs[0]["role"].getStr() == "system"
      check msgs[0]["content"].getStr() == "seja breve"

      check msgs[1]["role"].getStr() == "user"
      check msgs[1]["content"].kind == JArray
      check msgs[1]["content"].len == 2
      check msgs[1]["content"][0]["type"].getStr() == "text"
      check msgs[1]["content"][0]["text"].getStr() == "o que é?"
      check msgs[1]["content"][1]["type"].getStr() == "image_url"
      check msgs[1]["content"][1]["image_url"]["url"].getStr() ==
            "data:image/png;base64,QUJD"

      check msgs[2]["role"].getStr() == "assistant"
      check msgs[2]["content"].kind == JString
      check msgs[2]["content"].getStr() == ""
      check msgs[2]["tool_calls"].len == 1
      check msgs[2]["tool_calls"][0]["id"].getStr() == "call_1"
      check msgs[2]["tool_calls"][0]["type"].getStr() == "function"
      check msgs[2]["tool_calls"][0]["function"]["name"].getStr() == "calc"
      check not msgs[2].hasKey("tool_call_id")

      check msgs[3]["role"].getStr() == "tool"
      check msgs[3]["tool_call_id"].getStr() == "call_1"
      check msgs[3]["content"].getStr().contains("4")
      check not msgs[3].hasKey("name")

      check body["tools"].len == 1
      check body["tools"][0]["function"]["name"].getStr() == "calc"
      check body["tool_choice"].getStr() == "auto"

  suite "OpenRouter compat production builders":

    test "buildBody and buildStreamBody use the adapter profile":
      let a = newOpenRouterAdapter("k", model = "mistral-7b",
                                   endpoint = "http://localhost:9/chat")
      let req = CompletionRequest(messages: @[ChatMessage(role: roleUser,
                                                          text: "oi")])
      check a.buildBody(req) ==
            buildCompatRequestBody(a.profileFor(), "mistral-7b", req)
      check a.buildStreamBody(req) ==
            buildCompatRequestBody(a.profileFor(), "mistral-7b", req,
                                   stream = true)
      check a.buildStreamBody(req)["stream"].getBool()
      check not a.buildBody(req).hasKey("stream")

when isMainModule:
  runTests()
