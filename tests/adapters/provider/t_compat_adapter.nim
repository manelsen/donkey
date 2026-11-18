## t_compat_adapter.nim — the generic OpenAI-compatible adapter (US-001).
##
## The adapter is the only consumer of `CompatProfile.endpoint` and
## `CompatProfile.extraHeaders`; NVIDIA is its first real profile. Everything
## here is pure: no network, no provider, no Docker. The SSE body consumer is
## tested with a `StringStream`, so a non-SSE 2xx body cannot be mistaken for an
## empty success.

import std/[json, streams, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/compat
import donkey/domain/providers/openai_pure
import donkey/domain/providers/profile_nvidia
import donkey/adapters/provider/compat_adapter

const TestModel = "nvidia/nemotron-3.5-super-vl-120b-a12b"

proc nvidiaAdapter(): CompatAdapter =
  newCompatAdapter("key-123", model = TestModel, providerName = "NVIDIA",
                   profileFn = nvidiaCompatProfile)

func headerValue(headers: seq[(string, string)]; name: string): string =
  for (key, value) in headers:
    if key == name:
      return value
  ""

suite "compat adapter — request body (NVIDIA golden)":

  test "system and text keep the OpenAI shape":
    let req = CompletionRequest(
      system: "seja breve",
      messages: @[ChatMessage(role: roleUser, text: "oi")])
    let body = nvidiaAdapter().buildBody(req)
    check body["model"].getStr() == TestModel
    check body["messages"][0]["role"].getStr() == "system"
    check body["messages"][0]["content"].getStr() == "seja breve"
    check body["messages"][1]["role"].getStr() == "user"
    check body["messages"][1]["content"].getStr() == "oi"
    check body["stream"].getBool() == false
    check not body.hasKey("include_reasoning")

  test "the body is buildCompatRequestBody of the profile":
    var h = newHistory()
    h.addUser("oi")
    let req = CompletionRequest(system: "s", messages: h)
    check nvidiaAdapter().buildBody(req) ==
          buildCompatRequestBody(nvidiaCompatProfile(), TestModel, req)

  test "tools are carried and the tool result omits `name`":
    let req = CompletionRequest(
      messages: @[
        ChatMessage(role: roleAssistant, text: "",
                    toolCalls: @[ToolCallRequest(id: "t1", name: "search",
                                                 inputJson: """{"q":"x"}""")]),
        ChatMessage(role: roleTool, text: "resultado", toolCallId: "t1")],
      tools: @[ToolDescription(name: "search", description: "busca",
                               schemaJson: """{"type":"object"}""")])
    let body = nvidiaAdapter().buildBody(req)
    check body["tools"][0]["function"]["name"].getStr() == "search"
    check body["messages"][0]["tool_calls"][0]["id"].getStr() == "t1"
    check body["messages"][1]["role"].getStr() == "tool"
    check body["messages"][1]["tool_call_id"].getStr() == "t1"
    check not body["messages"][1].hasKey("name")

  test "an image data URL is preserved as a content part":
    let url = "data:image/png;base64,QUJD"
    let req = CompletionRequest(
      messages: @[ChatMessage(role: roleUser, text: "o que é?", imageUrl: url)])
    let body = nvidiaAdapter().buildBody(req)
    let content = body["messages"][0]["content"]
    check content.kind == JArray
    check content[0]["type"].getStr() == "text"
    check content[0]["text"].getStr() == "o que é?"
    check content[1]["type"].getStr() == "image_url"
    check content[1]["image_url"]["url"].getStr() == url

  test "reasoning=true sends no Donkey-only reasoning field":
    let body = nvidiaAdapter().buildBody(CompletionRequest(reasoning: true))
    check not body.hasKey("include_reasoning")
    check not body.hasKey("reasoning_effort")

  test "the streaming body flips `stream`":
    let body = nvidiaAdapter().buildBody(CompletionRequest(), stream = true)
    check body["stream"].getBool()

suite "compat adapter — headers and URL":

  test "requestHeaders carry Authorization, Content-Type and profile extras":
    let adapter = nvidiaAdapter()
    let headers = adapter.requestHeaders(nvidiaCompatProfile())
    check headerValue(headers, "Authorization") == "Bearer key-123"
    check headerValue(headers, "Content-Type") == "application/json"
    check headerValue(headers, "X-BILLING-INVOKE-ORIGIN") == "Donkey"
    check headerValue(headers, "X-BILLING-INVOKE-ORIGIN") != "HermesAgent"

  test "requestUrl is the profile endpoint":
    check requestUrl(nvidiaCompatProfile()) ==
          "https://integrate.api.nvidia.com/v1/chat/completions"

  test "the billing header is scoped to the cloud endpoint":
    ## NIM local endpoints do not belong to build.nvidia.com billing.
    let local = nvidiaCompatProfileAt("http://localhost:8000/v1/chat/completions")
    check headerValue(nvidiaAdapter().requestHeaders(local),
                      NvidiaBillingHeaderName) == ""
    check headerValue(nvidiaAdapter().requestHeaders(nvidiaCompatProfile()),
                      NvidiaBillingHeaderName) == "Donkey"

  test "a custom profile endpoint and extras flow through unchanged":
    var profile = nvidiaCompatProfileAt("http://127.0.0.1:9/v1/chat")
    profile.extraHeaders.add(("X-Extra", "1"))
    let adapter = nvidiaAdapter()
    check requestUrl(profile) == "http://127.0.0.1:9/v1/chat"
    check headerValue(adapter.requestHeaders(profile), "X-Extra") == "1"

suite "compat adapter — response parsing":

  test "parses content, reasoning_content, usage and tool calls":
    let body = parseJson("""{
      "choices": [{"message": {
        "content": "olá",
        "reasoning_content": "pensei",
        "tool_calls": [{"id": "t1", "type": "function",
                        "function": {"name": "search", "arguments": "{\"q\":\"x\"}"}}]
      }}],
      "usage": {"prompt_tokens": 7, "completion_tokens": 3}
    }""")
    let parsed = parseCompatBody(body)
    check parsed.isOk
    let response = parsed.get()
    check response.text == "olá"
    check response.reasoning == "pensei"
    check response.inputTokens == 7
    check response.outputTokens == 3
    check response.toolCalls.len == 1
    check response.toolCalls[0].name == "search"
    check response.toolCalls[0].inputJson == """{"q":"x"}"""

  test "an invalid body is an error, not an exception":
    let parsed = parseCompatBody(parseJson("""{"error": {"message": "nope"}}"""))
    check parsed.isErr
    check parsed.error.len > 0

  test "parseCompatBody is openai_pure.parseResponseFrom":
    let body = parseJson("""{"choices": [{"message": {"content": "x"}}]}""")
    check parseCompatBody(body).get().text == parseResponseFrom(body).get().text

suite "compat adapter — caps and streaming wiring":

  test "caps advertise streaming and tools with an unknown context":
    let c = nvidiaAdapter().caps()
    check c.name == "nvidia/" & TestModel
    check c.streaming
    check c.toolCalling
    check c.nativeTools.len == 0
    check c.maxContextTokens == 0          ## unknown until modelLimits (US-002)
    check c.requiresUserFirst == false

  test "makeStreamFn returns a callable stream function":
    check nvidiaAdapter().makeStreamFn() != nil

  test "an empty providerName falls back to OpenAI in caps":
    let adapter = newCompatAdapter("k", model = "m",
                                   profileFn = nvidiaCompatProfile)
    check adapter.caps().name == "openai/m"

suite "compat adapter — streaming consumer (no network)":

  test "a non-SSE 2xx body is an error, not an empty success":
    ## An HTML error page or a JSON error with status 200 must surface; the
    ## old loop returned `ok(text: "")`.
    let res = consumeCompatSse(
      newStringStream("<html>upstream failure</html>\n"), nil)
    check res.isErr
    check res.error.contains("non-SSE")

  test "a malformed data line surfaces the parse error":
    let res = consumeCompatSse(newStringStream("data: {oops\n"), nil)
    check res.isErr
    check res.error.contains("stream")

  test "content deltas, usage and [DONE] accumulate":
    let sse =
      "data: {\"choices\":[{\"delta\":{\"content\":\"ol\"}}]}\n" &
      "data: {\"choices\":[{\"delta\":{\"content\":\"á\"}}]," &
      "\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":1}}\n" &
      "data: [DONE]\n"
    let res = consumeCompatSse(newStringStream(sse), nil)
    check res.isOk
    check res.get().text == "olá"
    check res.get().inputTokens == 2
    check res.get().outputTokens == 1

  test "an SSE stream with only [DONE] is a legitimate empty success":
    let res = consumeCompatSse(newStringStream("data: [DONE]\n"), nil)
    check res.isOk
    check res.get().text == ""

  test "keepalive comments and blank lines are ignored":
    let sse = ": keep-alive\n\n" &
              "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n" &
              "data: [DONE]\n"
    let res = consumeCompatSse(newStringStream(sse), nil)
    check res.isOk
    check res.get().text == "ok"
