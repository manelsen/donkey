## Golden tests for the Zhipu compat profile (US-003).
##
## The adapter must only declare its deviations (thinking, native tools) and
## let the shared compat transport serialize the request.

import std/[json, unittest]
import donkey/adapters/provider/zhipu
import donkey/domain/message
import donkey/domain/providers/compat

proc userImage(text, url: string): seq[ChatMessage] =
  @[ChatMessage(role: roleUser, text: text, imageUrl: url)]

suite "Zhipu compat profile":

  test "defaults to the Z.AI coding endpoint and declares only its quirks":
    let profile = zhipuCompatProfile()
    check profile.id == "zai-coding"
    check profile.endpoint == ZhipuEndpoint
    check profile.extraHeaders.len == 0
    check profile.payloadExtras.isNil
    check profile.supportsImages
    check profile.streamExtras.isNil
    check profile.quirks.toolResultName == false
    check profile.quirks.toolCallsEmptyContent
    check profile.quirks.imageEmptyTextPart == false
    check profile.quirks.imageWithToolCalls == false
    check profile.quirks.toolChoiceAuto
    check profile.quirks.omitStreamKey
    check profile.quirks.includeReasoningField == false

  test "the endpoint is overridable":
    let profile = zhipuCompatProfile("https://example.test/v4/chat/completions")
    check profile.endpoint == "https://example.test/v4/chat/completions"

  test "non-stream body carries no stream and no include_reasoning":
    let body = buildCompatRequestBody(zhipuCompatProfile(), "glm-4.7",
                                      CompletionRequest(reasoning: true))
    check not body.hasKey("stream")
    check not body.hasKey("include_reasoning")

  test "reasoning adds thinking.type=enabled":
    let plain = buildCompatRequestBody(zhipuCompatProfile(), "glm-4.7",
                                       CompletionRequest())
    check not plain.hasKey("thinking")
    let body = buildCompatRequestBody(zhipuCompatProfile(), "glm-4.7",
                                      CompletionRequest(reasoning: true))
    check body["thinking"]["type"].getStr() == "enabled"

  test "tools present adds tool_choice=auto":
    let req = CompletionRequest(
      tools: @[ToolDescription(name: "web_search", description: "busca",
                               schemaJson: """{"type":"object"}""")])
    let body = buildCompatRequestBody(zhipuCompatProfile(), "glm-4.7", req)
    check body["tool_choice"].getStr() == "auto"
    check body["tools"][0]["function"]["name"].getStr() == "web_search"

  test "tool result has no name field":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleTool, text: "resultado", toolCallId: "t1")])
    let body = buildCompatRequestBody(zhipuCompatProfile(), "glm-4.7", req)
    let msg = body["messages"][0]
    check msg["role"].getStr() == "tool"
    check msg["tool_call_id"].getStr() == "t1"
    check msg["content"].getStr() == "resultado"
    check not msg.hasKey("name")

  test "assistant tool call with empty text keeps content empty string":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleAssistant, text: "",
                  toolCalls: @[ToolCallRequest(id: "t1", name: "bash",
                                               inputJson: """{"command":"ls"}""")])])
    let body = buildCompatRequestBody(zhipuCompatProfile(), "glm-4.7", req)
    let msg = body["messages"][0]
    check msg["content"].getStr() == ""
    check msg["tool_calls"][0]["function"]["name"].getStr() == "bash"

  test "an image plus tool calls drops the image and keeps content a string":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleAssistant, text: "veja",
                  imageUrl: "data:image/png;base64,QUJD",
                  toolCalls: @[ToolCallRequest(id: "t1", name: "bash",
                                               inputJson: "{}")])])
    let body = buildCompatRequestBody(zhipuCompatProfile(), "glm-4.7", req)
    let content = body["messages"][0]["content"]
    check content.kind == JString
    check content.getStr() == "veja"

  test "a plain image turn still becomes a content array":
    let req = CompletionRequest(messages: userImage("o que é?", "data:image/png;base64,QUJD"))
    let body = buildCompatRequestBody(zhipuCompatProfile(), "glm-4.7", req)
    let content = body["messages"][0]["content"]
    check content.kind == JArray
    check content[0]["type"].getStr() == "text"
    check content[1]["image_url"]["url"].getStr() == "data:image/png;base64,QUJD"
