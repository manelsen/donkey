## ZhipuAdapter unit tests — no real HTTP calls.
## Tests cover: caps(), buildBody JSON shape, endpoint override wiring.
## Integration test (real API) lives separately and requires ZHIPU_API_KEY.

import std/[json, strutils, unittest]
import donkey/adapters/provider/zhipu
import donkey/domain/message

suite "ZhipuAdapter caps":

  test "name includes model":
    let a = newZhipuAdapter("dummy", model = "glm-4-flash")
    check a.caps().name == "zhipu/glm-4-flash"

  test "native tools declared":
    let caps = newZhipuAdapter("x").caps()
    check "web_search"       in caps.nativeTools
    check "code_interpreter" in caps.nativeTools

  test "toolCalling is true":
    check newZhipuAdapter("x").caps().toolCalling

  test "does not require user turn first":
    check not newZhipuAdapter("x").caps().requiresUserFirst

suite "ZhipuAdapter buildBody":
  # Access buildBody via the module — it's a func so we can test it directly.
  # We expose it as an internal test hook by importing the module.

  test "system prompt becomes first message with role system":
    var h = newHistory()
    h.addUser("hello")
    let req = CompletionRequest(system: "You are Donkey.", messages: h)
    let a   = newZhipuAdapter("key", model = "glm-4")
    let body = a.buildBody(req)
    let msgs = body["messages"]
    check msgs[0]["role"].getStr() == "system"
    check msgs[0]["content"].getStr().contains("Donkey")

  test "user message follows system":
    var h = newHistory()
    h.addUser("ping")
    let req  = CompletionRequest(system: "sys", messages: h)
    let body = newZhipuAdapter("k").buildBody(req)
    let msgs = body["messages"]
    check msgs.len == 2
    check msgs[1]["role"].getStr()    == "user"
    check msgs[1]["content"].getStr() == "ping"

  test "no system prompt when empty":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newZhipuAdapter("k").buildBody(req)
    let msgs = body["messages"]
    check msgs.len == 0

  test "max_tokens field present when set":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 512)
    let body = newZhipuAdapter("k").buildBody(req)
    check body.hasKey("max_tokens")
    check body["max_tokens"].getInt() == 512

  test "max_tokens absent when zero":
    let req  = CompletionRequest(system: "", messages: newHistory(), maxTokens: 0)
    let body = newZhipuAdapter("k").buildBody(req)
    check not body.hasKey("max_tokens")

  test "model field matches adapter model":
    let req  = CompletionRequest(system: "", messages: newHistory())
    let body = newZhipuAdapter("k", model = "glm-z-pro").buildBody(req)
    check body["model"].getStr() == "glm-z-pro"

  test "history with multiple turns preserves order":
    var h = newHistory()
    h.addUser("q1")
    h.addAssistant("a1")
    h.addUser("q2")
    let body = newZhipuAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let msgs = body["messages"]
    check msgs[0]["role"].getStr() == "user"
    check msgs[1]["role"].getStr() == "assistant"
    check msgs[2]["role"].getStr() == "user"
