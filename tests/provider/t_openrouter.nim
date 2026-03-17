## OpenRouterAdapter unit tests — no real HTTP calls.
## Tests: caps(), buildBody JSON shape, required headers, response parsing.

import std/[json, strutils, unittest]
import donkey/adapters/provider/openrouter
import donkey/domain/message

suite "OpenRouterAdapter caps":

  test "streaming is true":
    check newOpenRouterAdapter("key").caps().streaming

  test "toolCalling is true":
    check newOpenRouterAdapter("key").caps().toolCalling

  test "name includes model":
    let a = newOpenRouterAdapter("key", model = "gpt-4o")
    check a.caps().name.contains("gpt-4o")

  test "does not require user turn first":
    check not newOpenRouterAdapter("key").caps().requiresUserFirst

suite "OpenRouterAdapter buildBody":

  test "system prompt becomes first message with role system":
    var h = newHistory()
    h.addUser("hi")
    let req  = CompletionRequest(system: "You are Donkey.", messages: h)
    let body = newOpenRouterAdapter("k").buildBody(req)
    let msgs = body["messages"]
    check msgs[0]["role"].getStr()    == "system"
    check msgs[0]["content"].getStr().contains("Donkey")

  test "model field is set":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOpenRouterAdapter("k", model = "mistral-7b").buildBody(req)
    check body["model"].getStr() == "mistral-7b"

  test "no system message when empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newOpenRouterAdapter("k").buildBody(req)
    check body["messages"].len == 0

  test "max_tokens present when set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 256)
    let body = newOpenRouterAdapter("k").buildBody(req)
    check body["max_tokens"].getInt() == 256

  test "max_tokens absent when zero":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 0)
    let body = newOpenRouterAdapter("k").buildBody(req)
    check not body.hasKey("max_tokens")

  test "history order preserved":
    var h = newHistory()
    h.addUser("q")
    h.addAssistant("a")
    let body = newOpenRouterAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs[0]["role"].getStr() == "user"
    check msgs[1]["role"].getStr() == "assistant"

suite "OpenRouterAdapter required headers":

  test "HTTP-Referer header is set":
    let a = newOpenRouterAdapter("key")
    check a.referer.contains("donkey")

  test "X-Title header is set":
    let a = newOpenRouterAdapter("key")
    check a.xTitle.len > 0

suite "OpenRouterAdapter parseResponse":

  test "extracts text from choices[0].message.content":
    let j = %* {
      "choices": [{"message": {"content": "Hello!"}}],
      "usage": {"prompt_tokens": 10, "completion_tokens": 5}
    }
    let resp = parseOpenRouterResponse(j)
    check resp.text         == "Hello!"
    check resp.inputTokens  == 10
    check resp.outputTokens == 5

  test "handles missing usage gracefully":
    let j = %* {"choices": [{"message": {"content": "Hi"}}]}
    let resp = parseOpenRouterResponse(j)
    check resp.text        == "Hi"
    check resp.inputTokens  == 0
    check resp.outputTokens == 0
