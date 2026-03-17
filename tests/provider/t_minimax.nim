## MiniMaxAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, sender_type mapping,
## bot_setting placement, response parsing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/minimax
import donkey/domain/message

suite "MiniMaxAdapter caps":

  test "streaming is false":
    check not newMiniMaxAdapter("key").caps().streaming

  test "toolCalling is false":
    check not newMiniMaxAdapter("key").caps().toolCalling

  test "name includes model":
    let a = newMiniMaxAdapter("key", model = "abab6.5s-chat")
    check a.caps().name.contains("abab")

suite "MiniMaxAdapter buildBody":

  test "model field is present":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newMiniMaxAdapter("k", model = "abab6.5s-chat").buildBody(req)
    check body["model"].getStr() == "abab6.5s-chat"

  test "user role maps to sender_type USER":
    var h = newHistory()
    h.addUser("hello")
    let body = newMiniMaxAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs[0]["sender_type"].getStr() == "USER"

  test "assistant role maps to sender_type BOT":
    var h = newHistory()
    h.addUser("q")
    h.addAssistant("a")
    let body = newMiniMaxAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["messages"][1]["sender_type"].getStr() == "BOT"

  test "bot_setting present with system content":
    let req  = CompletionRequest(system: "You are Donkey.", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body.hasKey("bot_setting")
    let bs = body["bot_setting"][0]
    check bs["content"].getStr().contains("Donkey")

  test "bot_setting bot_name is Donkey":
    let req  = CompletionRequest(system: "sys", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["bot_setting"][0]["bot_name"].getStr() == "Donkey"

  test "no bot_setting when system empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    check not body.hasKey("bot_setting")

  test "messages have text field":
    var h = newHistory()
    h.addUser("hi there")
    let body = newMiniMaxAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    check body["messages"][0]["text"].getStr() == "hi there"

suite "MiniMaxAdapter parseResponse":

  test "extracts text from choices[0].messages[0].text":
    let j = %* {
      "choices": [{"messages": [{"text": "Hello from MiniMax"}]}],
      "usage": {"prompt_tokens": 5, "completion_tokens": 3}
    }
    let resp = parseMiniMaxResponse(j)
    check resp.text         == "Hello from MiniMax"
    check resp.inputTokens  == 5
    check resp.outputTokens == 3

  test "handles missing usage gracefully":
    let j = %* {"choices": [{"messages": [{"text": "Hi"}]}]}
    let resp = parseMiniMaxResponse(j)
    check resp.text         == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0
