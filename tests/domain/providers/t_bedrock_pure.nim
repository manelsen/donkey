## Bedrock Converse translation, pure. The rules come from the Converse API:
## roles alternate and start with a user turn, tool results ride in a user
## message, empty text blocks are rejected, a toolUse/toolResult block needs a
## `toolConfig`, tool ids match [a-zA-Z0-9_-]{1,64}, and images are bytes with
## a format.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/bedrock_pure

proc runTests*() =
  suite "bedrock_pure — request":
    test "system and a plain user turn":
      let body = converseBody(CompletionRequest(system: "seja breve",
        messages: @[ChatMessage(role: roleUser, text: "oi")]))
      check body["system"] == %* [{"text": "seja breve"}]
      check body["messages"] == %* [{"role": "user", "content": [{"text": "oi"}]}]
      check not body.hasKey("toolConfig")
      check not body.hasKey("inferenceConfig")

    test "a Claude model: cache points after the system and the last message (E8.2)":
      check bedrockCaches("anthropic.claude-sonnet-5-5")
      check bedrockCaches("us.anthropic.claude-opus-5-5")
      check not bedrockCaches("meta.llama4-maverick-17b-instruct-v1:0")
      let body = converseBody(CompletionRequest(system: "seja breve",
        messages: @[ChatMessage(role: roleUser, text: "oi")]), cache = true)
      check body["system"] == %* [{"text": "seja breve"}, {"cachePoint": {"type": "default"}}]
      check body["messages"] == %* [{"role": "user", "content": [{"text": "oi"},
                                                               {"cachePoint": {"type": "default"}}]}]

    test "maxTokens goes in inferenceConfig":
      let body = converseBody(CompletionRequest(maxTokens: 512,
        messages: @[ChatMessage(role: roleUser, text: "oi")]))
      check body["inferenceConfig"]["maxTokens"].getInt == 512

    test "a tool round: toolUse in the assistant turn, toolResult in a user turn":
      let req = CompletionRequest(
        tools: @[ToolDescription(name: "clock", description: "hora",
                                 schemaJson: """{"type":"object"}""")],
        messages: @[
          ChatMessage(role: roleUser, text: "que horas são?"),
          ChatMessage(role: roleAssistant, toolCalls: @[
            ToolCallRequest(id: "call_1", name: "clock", inputJson: """{"tz":"UTC"}""")]),
          ChatMessage(role: roleTool, text: "12:00", toolCallId: "call_1")])
      let body = converseBody(req)
      check body["toolConfig"]["tools"][0]["toolSpec"]["name"].getStr == "clock"
      check body["toolConfig"]["tools"][0]["toolSpec"]["inputSchema"]["json"] ==
        %* {"type": "object"}
      let msgs = body["messages"]
      check msgs.len == 3
      check msgs[1]["role"].getStr == "assistant"
      check msgs[1]["content"][0]["toolUse"] ==
        %* {"toolUseId": "call_1", "name": "clock", "input": {"tz": "UTC"}}
      check msgs[2]["role"].getStr == "user"
      check msgs[2]["content"][0]["toolResult"] ==
        %* {"toolUseId": "call_1", "content": [{"text": "12:00"}]}

    test "consecutive tool results and the next user text share one user turn":
      let req = CompletionRequest(
        tools: @[ToolDescription(name: "t", schemaJson: "{}")],
        messages: @[
          ChatMessage(role: roleUser, text: "a"),
          ChatMessage(role: roleAssistant, toolCalls: @[
            ToolCallRequest(id: "x", name: "t", inputJson: "{}"),
            ToolCallRequest(id: "y", name: "t", inputJson: "{}")]),
          ChatMessage(role: roleTool, text: "1", toolCallId: "x"),
          ChatMessage(role: roleTool, text: "2", toolCallId: "y"),
          ChatMessage(role: roleUser, text: "e agora?")])
      let msgs = converseBody(req)["messages"]
      check msgs.len == 3
      check msgs[2]["content"].len == 3
      check msgs[2]["content"][2] == %* {"text": "e agora?"}

    test "the conversation starts with a user turn and has no empty text":
      let msgs = converseBody(CompletionRequest(messages: @[
        ChatMessage(role: roleAssistant, text: "olá"),
        ChatMessage(role: roleUser, text: ""),
        ChatMessage(role: roleUser, text: "oi")]))["messages"]
      check msgs[0]["role"].getStr == "user"
      for m in msgs:
        for part in m["content"]:
          if part.hasKey("text"): check part["text"].getStr.len > 0
      for i in 1 ..< msgs.len:
        check msgs[i]["role"] != msgs[i - 1]["role"]

    test "without tools in the request, tool blocks from history become text":
      let msgs = converseBody(CompletionRequest(messages: @[
        ChatMessage(role: roleUser, text: "a"),
        ChatMessage(role: roleAssistant, toolCalls: @[
          ToolCallRequest(id: "x", name: "clock", inputJson: "{}")]),
        ChatMessage(role: roleTool, text: "12:00", toolCallId: "x")]))["messages"]
      check not ($msgs).contains("toolUse")
      check not ($msgs).contains("toolResult")
      check ($msgs).contains("clock")
      check ($msgs).contains("12:00")

    test "tool ids are made valid the same way on both sides":
      check bedrockToolId("call.abc:1") == "call_abc_1"
      check bedrockToolId("ok-id_9") == "ok-id_9"
      check bedrockToolId("").len > 0
      check bedrockToolId('x'.repeat(80)).len == 64

    test "an inline image becomes bytes with its format":
      let msgs = converseBody(CompletionRequest(messages: @[
        ChatMessage(role: roleUser, text: "veja",
                    imageUrl: "data:image/jpeg;base64,QUJD")]))["messages"]
      check msgs[0]["content"][1] ==
        %* {"image": {"format": "jpeg", "source": {"bytes": "QUJD"}}}

    test "a non-inline image is not sent (Converse takes bytes, not URLs)":
      let msgs = converseBody(CompletionRequest(messages: @[
        ChatMessage(role: roleUser, text: "veja",
                    imageUrl: "https://example.test/a.png")]))["messages"]
      check msgs[0]["content"].len == 1

  suite "bedrock_pure — response":
    test "text, tool calls, reasoning and usage":
      let r = parseConverseResponse(%* {
        "output": {"message": {"role": "assistant", "content": [
          {"reasoningContent": {"reasoningText": {"text": "pensando"}}},
          {"text": "vou ver"},
          {"toolUse": {"toolUseId": "t1", "name": "clock", "input": {"a": 1}}}]}},
        "stopReason": "tool_use",
        "usage": {"inputTokens": 10, "outputTokens": 5}})
      check r.isOk
      let resp = r.get
      check resp.text == "vou ver"
      check resp.reasoning == "pensando"
      check resp.inputTokens == 10 and resp.outputTokens == 5
      check resp.toolCalls.len == 1
      check resp.toolCalls[0].id == "t1"
      check parseJson(resp.toolCalls[0].inputJson) == %* {"a": 1}

    test "an error body is an error":
      check parseConverseResponse(%* {"message": "The security token is invalid"}).isErr

  suite "bedrock_pure — endpoint":
    test "the model id is encoded in the path":
      check converseUrl("https://bedrock-runtime.us-east-1.amazonaws.com",
                        "us.anthropic.claude-v2:1") ==
        "https://bedrock-runtime.us-east-1.amazonaws.com/model/us.anthropic.claude-v2%3A1/converse"

    test "the runtime URL of a region, and the region of a runtime URL":
      check bedrockRuntimeUrl("eu-west-1") == "https://bedrock-runtime.eu-west-1.amazonaws.com"
      check regionOfRuntimeUrl("https://bedrock-runtime.eu-west-1.amazonaws.com") == "eu-west-1"
      check regionOfRuntimeUrl("http://127.0.0.1:9") == "us-east-1"

when isMainModule:
  runTests()
