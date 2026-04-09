## MiniMaxAdapter unit tests.
## Covers OpenAI-compatible response parsing and request building.

import std/[json, unittest, strutils]
import results
import donkey/adapters/provider/minimax
import donkey/domain/message
import donkey/ports/provider

suite "MiniMaxAdapter construction":

  test "apiKey and model are stored":
    let a = newMiniMaxAdapter("MY_KEY", "MiniMax-M2.7")
    check a.apiKey == "MY_KEY"
    check a.model  == "MiniMax-M2.7"

suite "MiniMaxAdapter caps":

  test "declares minimax name":
    let a = newMiniMaxAdapter("k", model = "MiniMax-M2")
    check a.caps.name == "minimax/MiniMax-M2"

  test "streaming is true (OpenAI-compatible)":
    check newMiniMaxAdapter("k").caps.streaming == true

  test "toolCalling is true":
    check newMiniMaxAdapter("k").caps.toolCalling == true

suite "MiniMaxAdapter buildBody":

  test "model is present":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newMiniMaxAdapter("k", model = "MiniMax-M2.5").buildBody(req)
    check body["model"].getStr() == "MiniMax-M2.5"

  test "system prompt goes to messages":
    let req  = CompletionRequest(system: "You are helpful", messages: newHistory())
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["messages"][0]["role"].getStr() == "system"
    check body["messages"][0]["content"].getStr() == "You are helpful"

  test "user message uses standard role format":
    var h = newHistory()
    h.addUser("hello")
    let req  = CompletionRequest(system: "", messages: h)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["messages"][0]["role"].getStr() == "user"
    check body["messages"][0]["content"].getStr() == "hello"

  test "reasoning_split is present":
    let req  = CompletionRequest(system: "", messages: newHistory(), reasoning: true)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body{"reasoning_split"}.getBool() == true

  test "max_tokens present when maxTokens set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 256)
    let body = newMiniMaxAdapter("k").buildBody(req)
    check body["max_tokens"].getInt() == 256

suite "MiniMaxAdapter parseResponse":

  test "extracts text from OpenAI format (message.content)":
    let j = %* {
      "choices": [{"message": {"role": "assistant", "content": "Hello from MiniMax"}}],
      "usage": {"prompt_tokens": 5, "completion_tokens": 3}
    }
    let resp = parseMiniMaxResponse(j).get()
    check resp.text         == "Hello from MiniMax"
    check resp.inputTokens  == 5
    check resp.outputTokens == 3

  test "handles missing usage gracefully":
    let j = %* {"choices": [{"message": {"role": "assistant", "content": "Hi"}}]}
    let resp = parseMiniMaxResponse(j).get()
    check resp.text         == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0

  test "returns error for error field":
    let j = %* {
      "error": {"message": "invalid api key", "code": "2049"}
    }
    let r = parseMiniMaxResponse(j)
    check r.isErr
    check "invalid api key" in r.error
    check "2049" in r.error

  test "returns error for empty choices":
    let j = %* {"choices": []}
    let r = parseMiniMaxResponse(j)
    check r.isErr

  test "returns error for completely empty response":
    let j = %* {}
    let r = parseMiniMaxResponse(j)
    check r.isErr

  test "returns error instead of raising on malformed response":
    let j = newJArray()
    let r = parseMiniMaxResponse(j)
    check r.isErr
    check "Invalid MiniMax response" in r.error
