## MiniMax compat profile tests (US-004).
##
## MiniMax is fully OpenAI-shaped; its profile must only add
## `reasoning_split: true` and turn off the OpenAI wire behaviours it never
## emitted, so the adapter owns no serialization of its own.

import std/[json, strutils, unittest]
import donkey/adapters/provider/minimax
import donkey/domain/message
import donkey/domain/providers/compat

proc toolCall(id, name, args: string): ToolCallRequest =
  ToolCallRequest(id: id, name: name, inputJson: args)

proc assistantWithCall(text, imageUrl: string): ChatMessage =
  ChatMessage(
    role: roleAssistant,
    text: text,
    imageUrl: imageUrl,
    toolCalls: @[toolCall("t1", "search", """{"q":"x"}""")],
  )

suite "MiniMax compat profile":

  test "defaults to the MiniMax endpoint and stays overridable":
    check miniMaxCompatProfile().endpoint == MiniMaxEndpoint
    check miniMaxCompatProfile(endpoint = "http://localhost:1234").endpoint ==
          "http://localhost:1234"

  test "non-stream body omits stream and include_reasoning":
    let req = CompletionRequest(messages: newHistory())
    let body = buildCompatRequestBody(miniMaxCompatProfile(), MiniMaxDefaultModel, req)
    check not body.hasKey("stream")
    check not body.hasKey("include_reasoning")

  test "reasoning_split is true even when reasoning is not requested":
    let off = buildCompatRequestBody(
      miniMaxCompatProfile(), MiniMaxDefaultModel,
      CompletionRequest(messages: newHistory(), reasoning: false))
    check off["reasoning_split"].getBool() == true
    check not off.hasKey("include_reasoning")

    let on = buildCompatRequestBody(
      miniMaxCompatProfile(), MiniMaxDefaultModel,
      CompletionRequest(messages: newHistory(), reasoning: true))
    check on["reasoning_split"].getBool() == true
    check not on.hasKey("include_reasoning")

  test "a tool result carries no name":
    var h = newHistory()
    h.add(ChatMessage(role: roleTool, text: "output", toolCallId: "t1"))
    let body = buildCompatRequestBody(
      miniMaxCompatProfile(), MiniMaxDefaultModel,
      CompletionRequest(messages: h))
    let msg = body["messages"][0]
    check msg["role"].getStr() == "tool"
    check msg["tool_call_id"].getStr() == "t1"
    check msg["content"].getStr() == "output"
    check not msg.hasKey("name")

  test "an assistant tool call with empty text keeps content as empty string":
    var h = newHistory()
    h.add(assistantWithCall("", ""))
    let body = buildCompatRequestBody(
      miniMaxCompatProfile(), MiniMaxDefaultModel,
      CompletionRequest(messages: h))
    let msg = body["messages"][0]
    check msg["role"].getStr() == "assistant"
    check msg.hasKey("content")
    check msg["content"].getStr() == ""
    check msg["tool_calls"][0]["function"]["name"].getStr() == "search"

  test "an image on a tool-call message is dropped":
    var h = newHistory()
    h.add(assistantWithCall("calling", "data:image/png;base64,QUJD"))
    let body = buildCompatRequestBody(
      miniMaxCompatProfile(), MiniMaxDefaultModel,
      CompletionRequest(messages: h))
    let msg = body["messages"][0]
    check msg["content"].kind == JString
    check msg["content"].getStr() == "calling"
    check msg.hasKey("tool_calls")
    check "image_url" notin $msg

  test "tools are sent without tool_choice":
    let body = buildCompatRequestBody(
      miniMaxCompatProfile(), MiniMaxDefaultModel,
      CompletionRequest(
        messages: newHistory(),
        tools: @[ToolDescription(name: "search", description: "busca",
                                 schemaJson: """{"type":"object"}""")]))
    check body["tools"][0]["function"]["name"].getStr() == "search"
    check not body.hasKey("tool_choice")

  test "max_tokens is carried when set":
    let req = CompletionRequest(messages: newHistory(), maxTokens: 256)
    let body = buildCompatRequestBody(miniMaxCompatProfile(), MiniMaxDefaultModel, req)
    check body["max_tokens"].getInt() == 256
