## Tests for domain/providers/anthropic_pure — Anthropic Messages API wire-format helpers.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/providers/anthropic_pure
import donkey/domain/message

suite "anthropic_pure buildMessagesArray":

  test "converts user message correctly":
    let msgs = @[ChatMessage(role: "user", text: "hello")]
    let arr = msgs |> buildMessagesArray
    check arr.kind == JArray
    check arr.len == 1
    check arr[0]["role"].str == "user"
    check arr[0]["content"][0]["type"].str == "text"
    check arr[0]["content"][0]["text"].str == "hello"

  test "converts assistant message correctly":
    let msgs = @[ChatMessage(role: "assistant", text: "hi there")]
    let arr = msgs |> buildMessagesArray
    check arr[0]["role"].str == "assistant"
    check arr[0]["content"][0]["type"].str == "text"
    check arr[0]["content"][0]["text"].str == "hi there"

  test "converts message with tool calls":
    let msgs = @[
      ChatMessage(
        role:  "assistant",
        text:  "I'll search for that",
        toolCalls: @[
          ToolCallRequest(id: "toolu_abc", name: "web_search", inputJson: "{\"query\":\"nim lang\"}")
        ]
      )
    ]
    let arr = msgs |> buildMessagesArray
    check arr[0]["content"].len == 2
    check arr[0]["content"][0]["type"].str == "text"
    check arr[0]["content"][0]["text"].str == "I'll search for that"
    check arr[0]["content"][1]["type"].str == "tool_use"
    check arr[0]["content"][1]["id"].str == "toolu_abc"
    check arr[0]["content"][1]["name"].str == "web_search"
    check arr[0]["content"][1]["input"].pretty == "{\"query\":\"nim lang\"}".parseJson.pretty

  test "converts tool result message":
    let msgs = @[
      ChatMessage(
        role:       "user",
        text:       "The weather is sunny",
        toolCallId: "toolu_abc123",
      )
    ]
    let arr = msgs |> buildMessagesArray
    check arr[0]["role"].str == "user"
    check arr[0]["content"].len == 1
    check arr[0]["content"][0]["type"].str == "tool_result"
    check arr[0]["content"][0]["tool_use_id"].str == "toolu_abc123"
    check arr[0]["content"][0]["content"].str == "The weather is sunny"

  test "empty messages returns empty array":
    let msgs: seq[ChatMessage] = @[]
    let arr = msgs |> buildMessagesArray
    check arr.len == 0

  test "converts multiple messages":
    let msgs = @[
      ChatMessage(role: "user", text: "hello"),
      ChatMessage(role: "assistant", text: "hi there"),
    ]
    let arr = msgs |> buildMessagesArray
    check arr.len == 2
    check arr[0]["role"].str == "user"
    check arr[1]["role"].str == "assistant"

  test "assistant message with text and tool calls":
    let msgs = @[
      ChatMessage(
        role:  "assistant",
        text:  "Let me check the weather",
        toolCalls: @[
          ToolCallRequest(id: "call_1", name: "get_weather", inputJson: "{\"location\":\"NYC\"}"),
          ToolCallRequest(id: "call_2", name: "get_time", inputJson: "{\"tz\":\"EST\"}")
        ]
      )
    ]
    let arr = msgs |> buildMessagesArray
    check arr[0]["content"].len == 3
    check arr[0]["content"][0]["type"].str == "text"
    check arr[0]["content"][1]["type"].str == "tool_use"
    check arr[0]["content"][2]["type"].str == "tool_use"

suite "anthropic_pure buildToolsArray":

  test "converts tool description to Anthropic format":
    let tools = @[
      ToolDescription(
        name:        "get_weather",
        description: "Get weather for a location",
        schemaJson:  """{"type":"object","properties":{"location":{"type":"string"}}}"""
      )
    ]
    let arr = tools |> buildToolsArray
    check arr.len == 1
    check arr[0]["name"].str == "get_weather"
    check arr[0]["description"].str == "Get weather for a location"
    check arr[0]["input_schema"]["type"].str == "object"

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
    check arr[0]["name"].str == "tool_a"
    check arr[1]["name"].str == "tool_b"

  test "falls back to empty schema on invalid JSON":
    let tools = @[
      ToolDescription(name: "bad_tool", description: "Bad", schemaJson: "not json")
    ]
    let arr = tools |> buildToolsArray
    check arr[0]["input_schema"].kind == JObject
    check arr[0]["input_schema"].len == 0

suite "anthropic_pure buildRequestBody":

  test "builds minimal request body":
    let req = CompletionRequest(
      system:   "you are helpful",
      messages: @[ChatMessage(role: "user", text: "hello")],
    )
    let body = buildRequestBody("claude-3-5-sonnet", req)
    check body["model"].str == "claude-3-5-sonnet"
    check body["system"].str == "you are helpful"
    check body["messages"].len == 1
    check body["messages"][0]["role"].str == "user"
    check body["max_tokens"].num == 4096  ## default when not specified
    check body["stream"].bval == false

  test "excludes system when empty":
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "hello")],
    )
    let body = buildRequestBody("claude-3-5-sonnet", req)
    check not body.hasKey("system")
    check body["messages"].len == 1

  test "includes tools when present":
    let req = CompletionRequest(
      system:   "you are helpful",
      messages: @[ChatMessage(role: "user", text: "hello")],
      tools:    @[
        ToolDescription(name: "test", description: "t", schemaJson: "{}")
      ],
    )
    let body = buildRequestBody("claude-3-5-sonnet", req)
    check body.hasKey("tools")
    check body["tools"].len == 1

  test "uses explicit max_tokens when set":
    let req = CompletionRequest(
      system:    "you are helpful",
      messages:  @[ChatMessage(role: "user", text: "hello")],
      maxTokens:  1024,
    )
    let body = buildRequestBody("claude-3-5-sonnet", req)
    check body["max_tokens"].num == 1024

  test "sets stream flag":
    let req = CompletionRequest(
      system:   "you are helpful",
      messages: @[ChatMessage(role: "user", text: "hello")],
    )
    let body = buildRequestBody("claude-3-5-sonnet", req, stream = true)
    check body["stream"].bval == true

suite "anthropic_pure parseResponseFrom":

  test "parses basic text response":
    let json = parseJson("""
    {
      "id": "msg_123",
      "type": "message",
      "role": "assistant",
      "content": [
        {"type": "text", "text": "Hello!"}
      ],
      "stop_reason": "end_turn",
      "model": "claude-3-5-sonnet",
      "usage": {"input_tokens": 10, "output_tokens": 5}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isOk
    let resp = result.get()
    check resp.text == "Hello!"
    check resp.inputTokens == 10
    check resp.outputTokens == 5
    check resp.toolCalls.len == 0

  test "parses response with tool use":
    let json = parseJson("""
    {
      "id": "msg_456",
      "type": "message",
      "role": "assistant",
      "content": [
        {"type": "text", "text": "Let me search for that."},
        {"type": "tool_use", "id": "toolu_abc123", "name": "web_search", "input": {"query": "nim lang"}}
      ],
      "stop_reason": "tool_use",
      "model": "claude-3-5-sonnet",
      "usage": {"input_tokens": 15, "output_tokens": 30}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isOk
    let resp = result.get()
    check resp.text == "Let me search for that."
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id == "toolu_abc123"
    check resp.toolCalls[0].name == "web_search"
    check resp.toolCalls[0].inputJson == "{\"query\":\"nim lang\"}"

  test "parses response with only tool use (no text)":
    let json = parseJson("""
    {
      "id": "msg_789",
      "type": "message",
      "role": "assistant",
      "content": [
        {"type": "tool_use", "id": "toolu_xyz", "name": "get_weather", "input": {"location": "NYC"}}
      ],
      "stop_reason": "tool_use",
      "model": "claude-3-5-sonnet",
      "usage": {"input_tokens": 5, "output_tokens": 25}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isOk
    let resp = result.get()
    check resp.text == ""
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].name == "get_weather"

  test "returns error for empty content":
    let json = parseJson("""
    {
      "id": "msg_empty",
      "type": "message",
      "role": "assistant",
      "content": [],
      "stop_reason": "end_turn",
      "model": "claude-3-5-sonnet",
      "usage": {"input_tokens": 5, "output_tokens": 0}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isErr

  test "returns error for missing content field":
    let json = parseJson("""
    {
      "id": "msg_nocontent",
      "type": "message",
      "role": "assistant",
      "stop_reason": "end_turn",
      "model": "claude-3-5-sonnet",
      "usage": {"input_tokens": 5, "output_tokens": 0}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isErr

  test "handles missing usage gracefully":
    let json = parseJson("""
    {
      "id": "msg_nousage",
      "type": "message",
      "role": "assistant",
      "content": [{"type": "text", "text": "Hi!"}],
      "stop_reason": "end_turn",
      "model": "claude-3-5-sonnet"
    }
    """)
    let result = parseResponseFrom(json)
    check result.isOk
    let resp = result.get()
    check resp.inputTokens == 0
    check resp.outputTokens == 0

  test "handles text block before tool_use block":
    let json = parseJson("""
    {
      "id": "msg_multi",
      "type": "message",
      "role": "assistant",
      "content": [
        {"type": "text", "text": "First I need to look something up."},
        {"type": "tool_use", "id": "call_1", "name": "search", "input": {"q": "test"}},
        {"type": "tool_use", "id": "call_2", "name": "lookup", "input": {"id": "123"}}
      ],
      "stop_reason": "tool_use",
      "model": "claude-3-5-sonnet",
      "usage": {"input_tokens": 10, "output_tokens": 40}
    }
    """)
    let result = parseResponseFrom(json)
    check result.isOk
    let resp = result.get()
    check resp.text == "First I need to look something up."
    check resp.toolCalls.len == 2
    check resp.toolCalls[0].id == "call_1"
    check resp.toolCalls[1].id == "call_2"

suite "anthropic_pure toolResultToAnthropicBlock":

  test "formats tool result correctly":
    let resultBlock = toolResultToAnthropicBlock("toolu_abc", "The weather is sunny")
    check resultBlock["type"].str == "tool_result"
    check resultBlock["tool_use_id"].str == "toolu_abc"
    check resultBlock["content"].str == "The weather is sunny"

  test "handles empty output":
    let resultBlock = toolResultToAnthropicBlock("toolu_xyz", "")
    check resultBlock["content"].str == ""

suite "anthropic_pure contentBlockToJson and jsonToContentBlock":

  test "roundtrips text block":
    let original = textBlock("Hello world")
    let jsonNode = original.contentBlockToJson
    let restored = jsonNode.jsonToContentBlock
    check restored.kind == "text"
    check restored.text == "Hello world"

  test "roundtrips tool_use block":
    let original = toolUseBlock("call_123", "get_weather", "{\"location\":\"NYC\"}")
    let jsonNode = original.contentBlockToJson
    let restored = jsonNode.jsonToContentBlock
    check restored.kind == "tool_use"
    check restored.id == "call_123"
    check restored.name == "get_weather"
    check restored.inputJson == "{\"location\":\"NYC\"}"

  test "roundtrips tool_result block":
    let original = toolResultBlock("call_456", "Sunny, 72F")
    let jsonNode = original.contentBlockToJson
    let restored = jsonNode.jsonToContentBlock
    check restored.kind == "tool_result"
    check restored.toolUseId == "call_456"
    check restored.content == "Sunny, 72F"

suite "anthropic_pure messageToAnthropic":

  test "preserves role and text":
    let msg = ChatMessage(role: "user", text: "hello world")
    let am = msg |> messageToAnthropic
    check am.role == "user"
    check am.content.len == 1
    check am.content[0].kind == "text"
    check am.content[0].text == "hello world"

  test "converts tool calls":
    let msg = ChatMessage(
      role:  "assistant",
      text:  "searching...",
      toolCalls: @[
        ToolCallRequest(id: "tc1", name: "search", inputJson: "{}")
      ]
    )
    let am = msg |> messageToAnthropic
    check am.content.len == 2
    check am.content[0].kind == "text"
    check am.content[1].kind == "tool_use"
    check am.content[1].id == "tc1"
    check am.content[1].name == "search"

  test "tool result uses toolCallId":
    let msg = ChatMessage(
      role:       "user",
      text:       "tool output here",
      toolCallId: "call_123",
    )
    let am = msg |> messageToAnthropic
    check am.content.len == 1
    check am.content[0].kind == "tool_result"
    check am.content[0].toolUseId == "call_123"
    check am.content[0].content == "tool output here"
