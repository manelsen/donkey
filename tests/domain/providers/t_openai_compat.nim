## Tests for the OpenAI-compatible gateway wire helpers.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/openai_compat

suite "parseOpenAiChatRequest":

  test "string content becomes a user turn":
    let req = parseOpenAiChatRequest("""
      {"model": "gpt", "messages": [{"role": "user", "content": "oi"}]}
    """).get()
    check req.messages.len == 1
    check req.messages[0].role == roleUser
    check req.messages[0].text == "oi"

  test "system messages go to the top-level system prompt":
    let req = parseOpenAiChatRequest("""
      {"messages": [
        {"role": "system", "content": "seja breve"},
        {"role": "user", "content": "oi"},
        {"role": "assistant", "content": "olá"}
      ]}
    """).get()
    check req.system == "seja breve"
    check req.messages.len == 2
    check req.messages[1].role == roleAssistant

  test "content parts carry text and one image":
    let req = parseOpenAiChatRequest("""
      {"messages": [{"role": "user", "content": [
        {"type": "text", "text": "o que é isso?"},
        {"type": "image_url", "image_url": {"url": "data:image/png;base64,QUJD"}}
      ]}]}
    """).get()
    check req.messages[0].text == "o que é isso?"
    check req.messages[0].imageUrl == "data:image/png;base64,QUJD"

  test "max_tokens is carried":
    let req = parseOpenAiChatRequest("""
      {"messages": [{"role": "user", "content": "oi"}], "max_tokens": 32}
    """).get()
    check req.maxTokens == 32

  test "streaming is rejected explicitly":
    let res = parseOpenAiChatRequest("""
      {"messages": [{"role": "user", "content": "oi"}], "stream": true}
    """)
    check res.isErr
    check res.error.contains("streaming")

  test "tools are rejected explicitly":
    let res = parseOpenAiChatRequest("""
      {"messages": [{"role": "user", "content": "oi"}], "tools": [{"type": "function"}]}
    """)
    check res.isErr
    check res.error.contains("tools")

  test "an empty message list is rejected":
    check parseOpenAiChatRequest("""{"messages": []}""").isErr
    check parseOpenAiChatRequest("""{"messages": [{"role": "system", "content": "x"}]}""").isErr

  test "an unknown role is rejected":
    check parseOpenAiChatRequest(
      """{"messages": [{"role": "tool", "content": "x"}]}""").isErr

  test "invalid JSON is rejected":
    check parseOpenAiChatRequest("not json").isErr

suite "response builders":

  test "chat completion carries choices and usage":
    let node = parseJson(buildOpenAiChatResponse(
      CompletionResponse(text: "olá", inputTokens: 3, outputTokens: 5),
      "donkey/default", "chatcmpl-1", 100))
    check node["object"].getStr() == "chat.completion"
    check node["model"].getStr() == "donkey/default"
    check node["created"].getInt() == 100
    check node["choices"][0]["message"]["content"].getStr() == "olá"
    check node["choices"][0]["finish_reason"].getStr() == "stop"
    check node["usage"]["prompt_tokens"].getInt() == 3
    check node["usage"]["completion_tokens"].getInt() == 5
    check node["usage"]["total_tokens"].getInt() == 8

  test "models lists the configured model":
    let node = parseJson(buildOpenAiModels("donkey/default", 100))
    check node["object"].getStr() == "list"
    check node["data"][0]["id"].getStr() == "donkey/default"
    check node["data"][0]["owned_by"].getStr() == "donkey"
