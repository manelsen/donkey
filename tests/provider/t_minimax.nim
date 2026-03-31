## MiniMaxAdapter unit tests.
## No HTTP calls are made; tests cover JSON construction and response parsing.

import std/[json, unittest]
import donkey/adapters/provider/minimax
import donkey/domain/message
import donkey/ports/provider

suite "MiniMaxAdapter construction":

  test "apiKey and model are stored":
    let a = newMiniMaxAdapter("MY_KEY", "abab6.5s-chat")
    check a.apiKey == "MY_KEY"
    check a.model  == "abab6.5s-chat"

suite "MiniMaxAdapter caps":

  test "declares minimax name":
    let a = newMiniMaxAdapter("k", model = "custom-m")
    check a.caps.name == "minimax/custom-m"

  test "streaming is false":
    check newMiniMaxAdapter("k").caps.streaming == false

  test "toolCalling is false":
    check newMiniMaxAdapter("k").caps.toolCalling == false

suite "MiniMaxAdapter buildBody":

  test "model is present":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newMiniMaxAdapter("k", model = "m1").buildBody(req)
    check body["model"].getStr() == "m1"

  test "system prompt maps to bot_setting":
    let req  = CompletionRequest(system: "You are a helpful assistant", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["bot_setting"][0]["content"].getStr() == "You are a helpful assistant"

  test "user message maps to sender_type USER":
    var h = newHistory()
    h.addUser("hello")
    let req  = CompletionRequest(system: "", messages: h)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["messages"][0]["sender_type"].getStr() == "USER"
    check body["messages"][0]["text"].getStr() == "hello"

  test "assistant message maps to sender_type BOT":
    var h = newHistory()
    h.addAssistant("hi there")
    let req  = CompletionRequest(system: "", messages: h)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["messages"][0]["sender_type"].getStr() == "BOT"
    check body["messages"][0]["text"].getStr() == "hi there"

  test "tokens_to_generate present when maxTokens set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 256)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["tokens_to_generate"].getInt() == 256

suite "MiniMaxAdapter parseResponse":

  test "extracts text from choices[0].messages[0].text":
    let j = %* {
      "choices": [{"messages": [{"sender_type": "BOT", "text": "Hello"}]}],
      "usage": {"prompt_tokens": 5, "completion_tokens": 3}
    }
    let resp = parseMiniMaxResponse(j)
    check resp.text         == "Hello"
    check resp.inputTokens  == 5
    check resp.outputTokens == 3

  test "handles missing usage gracefully":
    let j = %* {"choices": [{"messages": [{"sender_type": "BOT", "text": "Hi"}]}]}
    let resp = parseMiniMaxResponse(j)
    check resp.text         == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0
