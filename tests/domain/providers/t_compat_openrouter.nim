## OpenRouter compat profile tests (US-005): the required headers, the wire
## quirks and the streaming extras live in the profile, not in the adapter.
##
## Pure: no network.

import std/[json, unittest]
import donkey/adapters/provider/openrouter
import donkey/domain/message
import donkey/domain/providers/compat

proc userImage(text, url: string): ConversationHistory =
  @[ChatMessage(role: roleUser, text: text, imageUrl: url)]

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

  test "carries the OpenRouter wire quirks":
    let q = openRouterCompatProfile().quirks
    check not q.toolResultName
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
