## Tests for domain/providers/openai_pure — OpenAI wire-format helpers.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/providers/openai_pure
import donkey/domain/message

suite "openai_pure buildMessagesArray":

  test "converts user message correctly":
    let msgs = @[ChatMessage(role: "user", text: "hello")]
    let arr = msgs |> buildMessagesArray
    check arr.kind == JArray
    check arr.len == 1
    check arr[0]["role"].str == "user"
    check arr[0]["content"].str == "hello"

  test "converts assistant message correctly":
    let msgs = @[ChatMessage(role: "assistant", text: "hi there")]
    let arr = msgs |> buildMessagesArray
    check arr[0]["role"].str == "assistant"
    check arr[0]["content"].str == "hi there"

  test "converts system message correctly":
    let msgs = @[ChatMessage(role: "system", text: "you are helpful")]
    let arr = msgs |> buildMessagesArray
    check arr[0]["role"].str == "system"
    check arr[0]["content"].str == "you are helpful"

  test "converts message with tool calls":
    let msgs = @[
      ChatMessage(
        role:  "assistant",
        text:  "I'll search for that",
        toolCalls: @[
          ToolCallRequest(id: "call_abc", name: "web_search", inputJson: "{\"query\":\"nim lang\"}")
        ]
      )
    ]
    let arr = msgs |> buildMessagesArray
    check arr[0]["tool_calls"].len == 1
    check arr[0]["tool_calls"][0]["id"].str == "call_abc"
    check arr[0]["tool_calls"][0]["type"].str == "function"
    check arr[0]["tool_calls"][0]["function"]["name"].str == "web_search"
    check arr[0]["tool_calls"][0]["function"]["arguments"].str == "{\"query\":\"nim lang\"}"

  test "empty messages returns empty array":
    let msgs: seq[ChatMessage] = @[]
    let arr = msgs |> buildMessagesArray
    check arr.len == 0

  test "converts multiple messages":
    let msgs = @[
      ChatMessage(role: "system", text: "you are helpful"),
      ChatMessage(role: "user", text: "hello"),
      ChatMessage(role: "assistant", text: "hi there"),
    ]
    let arr = msgs |> buildMessagesArray
    check arr.len == 3
    check arr[0]["role"].str == "system"
    check arr[1]["role"].str == "user"
    check arr[2]["role"].str == "assistant"

suite "openai_pure buildToolsArray":

  test "converts tool description to OpenAI format":
    let tools = @[
      ToolDescription(
        name:        "get_weather",
        description: "Get weather for a location",
        schemaJson:  """{"type":"object","properties":{"location":{"type":"string"}}}"""
      )
    ]
    let arr = tools |> buildToolsArray
    check arr.len == 1
    check arr[0]["type"].str == "function"
    check arr[0]["function"]["name"].str == "get_weather"
    check arr[0]["function"]["description"].str == "Get weather for a location"
    check arr[0]["function"]["parameters"]["type"].str == "object"

  test "empty tools returns empty array":
    let tools: seq[ToolDescription] = @[]
    let arr = tools |> buildToolsArray
    check arr.len == 0

  test "converts multiple tools":
    let tools = @[
      ToolDescription(name: "tool_a", description: "A", schemaJson: "{}"),
      ToolDescription(name: "tool_b", description: "B", schemaJson: "{}"),
    ]
    let arr = tools |> buildToolsArray
    check arr.len == 2
    check arr[0]["function"]["name"].str == "tool_a"
    check arr[1]["function"]["name"].str == "tool_b"

suite "openai_pure buildRequestBody":

  test "builds minimal request body":
    let req = CompletionRequest(
      system:   "you are helpful",
      messages: @[ChatMessage(role: "user", text: "hello")],
    )
    let body = buildRequestBody("gpt-4", req)
    check body["model"].str == "gpt-4"
    check body["messages"].len == 2  ## system + user
    check body["messages"][0]["role"].str == "system"
    check body["messages"][1]["role"].str == "user"
    check body["stream"].bval == false

  test "includes tools when present":
    let req = CompletionRequest(
      system:   "you are helpful",
      messages: @[ChatMessage(role: "user", text: "hello")],
      tools:    @[
        ToolDescription(name: "test", description: "t", schemaJson: "{}")
      ],
    )
    let body = buildRequestBody("gpt-4", req)
    check body.hasKey("tools")
    check body["tools"].len == 1

  test "includes max_tokens when set":
    let req = CompletionRequest(
      system:   "you are helpful",
      messages: @[ChatMessage(role: "user", text: "hello")],
      maxTokens: 500,
    )
    let body = buildRequestBody("gpt-4", req)
    check body["max_tokens"].num == 500

  test "excludes max_tokens when zero":
    let req = CompletionRequest(
      system:   "you are helpful",
      messages: @[ChatMessage(role: "user", text: "hello")],
      maxTokens: 0,
    )
    let body = buildRequestBody("gpt-4", req)
    check not body.hasKey("max_tokens")

  test "sets stream flag":
    let req = CompletionRequest(
      system:   "you are helpful",
      messages: @[ChatMessage(role: "user", text: "hello")],
    )
    let body = buildRequestBody("gpt-4", req, stream = true)
    check body["stream"].bval == true

suite "openai_pure parseResponseFrom":

  test "parses basic text response":
    let json = parseJson("""
    {
      "id": "chatcmpl-123",
      "model": "gpt-4",
      "choices": [
        {
          "message": {"role": "assistant", "content": "Hello!"},
          "finish_reason": "stop"
        }
      ],
      "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isOk
    let resp = result.get()
    check resp.text == "Hello!"
    check resp.inputTokens == 10
    check resp.outputTokens == 5
    check resp.toolCalls.len == 0

  test "parses response with tool calls":
    let json = parseJson("""
    {
      "id": "chatcmpl-123",
      "model": "gpt-4",
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": null,
            "tool_calls": [
              {
                "id": "call_abc123",
                "type": "function",
                "function": {"name": "get_weather", "arguments": "{\"location\":\"NYC\"}"}
              }
            ]
          },
          "finish_reason": "tool_calls"
        }
      ],
      "usage": {"prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isOk
    let resp = result.get()
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id == "call_abc123"
    check resp.toolCalls[0].name == "get_weather"
    check resp.toolCalls[0].inputJson == "{\"location\":\"NYC\"}"

  test "returns error for empty choices":
    let json = parseJson("""
    {
      "id": "chatcmpl-123",
      "model": "gpt-4",
      "choices": [],
      "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isErr

  test "handles missing usage gracefully":
    let json = parseJson("""
    {
      "id": "chatcmpl-123",
      "model": "gpt-4",
      "choices": [
        {
          "message": {"role": "assistant", "content": "Hi!"},
          "finish_reason": "stop"
        }
      ]
    }
    """)
    let result = parseResponseFrom(json)
    check result.isOk
    let resp = result.get()
    check resp.inputTokens == 0
    check resp.outputTokens == 0

suite "openai_pure toolResultToOpenAIMessage":

  test "formats tool result correctly":
    let msg = toolResultToOpenAIMessage("call_abc", "get_weather", "The weather is sunny")
    check msg["role"].str == "tool"
    check msg["tool_call_id"].str == "call_abc"
    check msg["content"].str == "The weather is sunny"

  test "handles empty output":
    let msg = toolResultToOpenAIMessage("call_xyz", "test_tool", "")
    check msg["content"].str == ""

suite "openai_pure messageToOpenAI":

  test "preserves role and content":
    let msg = ChatMessage(role: "user", text: "hello world")
    let om = msg |> messageToOpenAI
    check om.role == "user"
    check om.content == "hello world"

  test "converts tool calls":
    let msg = ChatMessage(
      role:  "assistant",
      text:  "searching...",
      toolCalls: @[
        ToolCallRequest(id: "tc1", name: "search", inputJson: "{}")
      ]
    )
    let om = msg |> messageToOpenAI
    check om.toolCalls.len == 1
    check om.toolCalls[0].id == "tc1"
    check om.toolCalls[0].function.name == "search"

  test "marks tool result message":
    let msg = ChatMessage(
      role:       "tool",
      text:       "tool output here",
      toolCallId: "call_123",
    )
    let om = msg |> messageToOpenAI
    check om.toolCallId == "call_123"

suite "openai_pure image content":

  test "an image message becomes a content array":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: "user", text: "what is this?",
                  imageUrl: "data:image/png;base64,QUJD")])
    let body = buildRequestBody("gpt-4", req)
    let msg = body["messages"][0]
    check msg["role"].getStr() == "user"
    check msg["content"].kind == JArray
    check msg["content"][0]["type"].getStr() == "text"
    check msg["content"][0]["text"].getStr() == "what is this?"
    check msg["content"][1]["type"].getStr() == "image_url"
    check msg["content"][1]["image_url"]["url"].getStr() ==
          "data:image/png;base64,QUJD"

  test "an image without text still carries the image":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: "user", text: "",
                  imageUrl: "data:image/jpeg;base64,QUJD")])
    let body = buildRequestBody("gpt-4", req)
    let content = body["messages"][0]["content"]
    check content.kind == JArray
    check content.len == 1
    check content[0]["image_url"]["url"].getStr() ==
          "data:image/jpeg;base64,QUJD"

  test "a message without an image keeps string content":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: "user", text: "hello")])
    let body = buildRequestBody("gpt-4", req)
    check body["messages"][0]["content"].kind == JString

suite "openai_pure wire quirks":

  test "tool result name is optional":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleTool, text: "saída", toolCallId: "t1")])
    let withName = buildRequestBodyWithQuirks(
      "m", req, quirks = defaultOpenAiQuirks())
    check withName["messages"][0]["name"].getStr() == "saída"
    var noName = defaultOpenAiQuirks()
    noName.toolResultName = false
    let without = buildRequestBodyWithQuirks("m", req, quirks = noName)
    check not without["messages"][0].hasKey("name")

  test "tool_call_id is only emitted for a tool message":
    let userReq = CompletionRequest(messages: @[
      ChatMessage(role: roleUser, text: "x", toolCallId: "t1")])
    let userBody = buildRequestBodyWithQuirks("m", userReq)
    check not userBody["messages"][0].hasKey("tool_call_id")
    let toolReq = CompletionRequest(messages: @[
      ChatMessage(role: roleTool, text: "r", toolCallId: "t1")])
    let toolBody = buildRequestBodyWithQuirks("m", toolReq)
    check toolBody["messages"][0]["tool_call_id"].getStr() == "t1"

  test "an empty plain turn can keep an empty content string":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleUser, text: "")])
    let default = buildRequestBodyWithQuirks("m", req)
    check not default["messages"][0].hasKey("content")
    var quirks = defaultOpenAiQuirks()
    quirks.emptyContentKey = true
    let body = buildRequestBodyWithQuirks("m", req, quirks = quirks)
    check body["messages"][0]["content"].getStr() == ""

  test "an assistant tool call can carry empty content":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleAssistant, text: "",
                  toolCalls: @[ToolCallRequest(id: "t1", name: "search",
                                               inputJson: "{}")])])
    let default = buildRequestBodyWithQuirks("m", req)
    check not default["messages"][0].hasKey("content")
    var emptyContent = defaultOpenAiQuirks()
    emptyContent.toolCallsEmptyContent = true
    let body = buildRequestBodyWithQuirks("m", req, quirks = emptyContent)
    check body["messages"][0]["content"].getStr() == ""

  test "tool_choice auto is added only with tools":
    let req = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "oi")],
      tools: @[ToolDescription(name: "search", description: "b",
                               schemaJson: """{"type":"object"}""")])
    var quirks = defaultOpenAiQuirks()
    quirks.toolChoiceAuto = true
    let withTools = buildRequestBodyWithQuirks("m", req, quirks = quirks)
    check withTools["tool_choice"].getStr() == "auto"
    let noTools = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "oi")])
    let without = buildRequestBodyWithQuirks("m", noTools, quirks = quirks)
    check not without.hasKey("tool_choice")

  test "the stream key can be omitted for non-streaming requests":
    var quirks = defaultOpenAiQuirks()
    quirks.omitStreamKey = true
    let base = buildRequestBodyWithQuirks("m", CompletionRequest(), quirks = quirks)
    check not base.hasKey("stream")
    let streaming = buildRequestBodyWithQuirks(
      "m", CompletionRequest(), stream = true, quirks = quirks)
    check streaming["stream"].getBool()

  test "an image with empty text can carry an empty text part":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleUser, text: "",
                  imageUrl: "data:image/png;base64,QUJD")])
    let default = buildRequestBodyWithQuirks("m", req)
    check default["messages"][0]["content"].len == 1
    var quirks = defaultOpenAiQuirks()
    quirks.imageEmptyTextPart = true
    let body = buildRequestBodyWithQuirks("m", req, quirks = quirks)
    check body["messages"][0]["content"][0]["type"].getStr() == "text"
    check body["messages"][0]["content"][0]["text"].getStr() == ""
    check body["messages"][0]["content"][1]["type"].getStr() == "image_url"

  test "tool calls can win over an image":
    let req = CompletionRequest(messages: @[
      ChatMessage(role: roleAssistant, text: "q",
                  imageUrl: "data:image/png;base64,QUJD",
                  toolCalls: @[ToolCallRequest(id: "t1", name: "search",
                                               inputJson: "{}")])])
    let default = buildRequestBodyWithQuirks("m", req)
    check default["messages"][0]["content"].kind == JArray
    var quirks = defaultOpenAiQuirks()
    quirks.imageWithToolCalls = false
    let body = buildRequestBodyWithQuirks("m", req, quirks = quirks)
    check body["messages"][0]["content"].getStr() == "q"
    check body["messages"][0].hasKey("tool_calls")

  test "include_reasoning can be suppressed":
    let req = CompletionRequest(reasoning: true)
    check buildRequestBodyWithQuirks("m", req)["include_reasoning"].getBool()
    var quirks = defaultOpenAiQuirks()
    quirks.includeReasoningField = false
    let body = buildRequestBodyWithQuirks("m", req, quirks = quirks)
    check not body.hasKey("include_reasoning")
