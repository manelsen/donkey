## ZhipuAdapter unit tests — no real HTTP calls.
## Tests cover: caps(), buildBody JSON shape, tool serialization and response parsing.

import std/[json, strutils, unittest]
import results
import donkey/adapters/provider/zhipu
import donkey/domain/message

suite "ZhipuAdapter caps":

  test "name includes model":
    let a = newZhipuAdapter("dummy", model = "glm-4.7")
    check a.caps().name == "zai-coding/glm-4.7"

  test "native tools declared":
    let caps = newZhipuAdapter("x").caps()
    check "web_search"       in caps.nativeTools
    check "code_interpreter" in caps.nativeTools

  test "toolCalling is true":
    check newZhipuAdapter("x").caps().toolCalling

  test "streaming is false":
    check not newZhipuAdapter("x").caps().streaming

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

  test "tools are serialized with tool_choice auto":
    let req = CompletionRequest(
      system: "",
      messages: newHistory(),
      tools: @[
        ToolDescription(
          name: "read_file",
          description: "Read a file",
          schemaJson: """{"type":"object","properties":{"path":{"type":"string"}}}""",
        )
      ],
    )
    let body = newZhipuAdapter("k").buildBody(req)
    check body.hasKey("tools")
    check body.hasKey("tool_choice")
    check body["tool_choice"].getStr() == "auto"
    check body["tools"][0]["function"]["name"].getStr() == "read_file"

  test "assistant tool calls are serialized":
    var h = newHistory()
    h.addAssistantWithToolCalls("", @[ToolCallRequest(
      id: "call_1", name: "bash", inputJson: "{\"command\":\"ls\"}")])
    let body = newZhipuAdapter("k").buildBody(
      CompletionRequest(system: "", messages: h))
    let tcs = body["messages"][0]["tool_calls"]
    check tcs.len == 1
    check tcs[0]["id"].getStr() == "call_1"
    check tcs[0]["function"]["name"].getStr() == "bash"

suite "ZhipuAdapter parseResponse":

  test "extracts text and usage":
    let j = %* {
      "choices": [{"message": {"content": "Hello from Zhipu"}}],
      "usage": {"prompt_tokens": 9, "completion_tokens": 4}
    }
    let resp = parseZhipuResponse(j).get()
    check resp.text == "Hello from Zhipu"
    check resp.inputTokens == 9
    check resp.outputTokens == 4

  test "handles missing usage gracefully":
    let j = %* {"choices": [{"message": {"content": "plain text"}}]}
    let resp = parseZhipuResponse(j).get()
    check resp.text == "plain text"
    check resp.inputTokens == 0
    check resp.outputTokens == 0

  test "parses tool_calls from response":
    let j = %* {
      "choices": [{
        "message": {
          "content": "",
          "tool_calls": [{
            "id": "call_9",
            "type": "function",
            "function": {"name": "read_file", "arguments": "{\"path\":\"src/app.nim\"}"}
          }]
        }
      }],
      "usage": {"prompt_tokens": 11, "completion_tokens": 5}
    }
    let resp = parseZhipuResponse(j).get()
    check resp.toolCalls.len == 1
    check resp.toolCalls[0].id == "call_9"
    check resp.toolCalls[0].name == "read_file"
    check parseJson(resp.toolCalls[0].inputJson)["path"].getStr() == "src/app.nim"
