## t_compat_alibaba.nim — Alibaba DashScope through the generic CompatAdapter
## (US-003).
##
## DashScope speaks the OpenAI chat/completions dialect under
## `compatible-mode`. Everything provider-specific is data in
## `alibabaCompatProfile`; there is no Alibaba adapter file. Pure: no network,
## no provider, no Docker.
##
## Verified against Hermes (read-only): `hermes_cli/auth.py:212-213`,
## `plugins/model-providers/alibaba/__init__.py:22-25`,
## `website/docs/integrations/providers.md:36,259-260`,
## `hermes_cli/models_catalog_static.py:209-212`. Vision is **not** verified,
## so the profile suppresses images.

import std/[json, options, strutils, unittest]
import donkey/core/pipeops
import donkey/core/providers/provider_defaults
import donkey/domain/message
import donkey/domain/providers/compat
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_alibaba
import donkey/adapters/provider/compat_adapter
import donkey/ports/http

const TestModel = "qwen3.8-max"

proc alibabaAdapter(): CompatAdapter =
  newCompatAdapter("key-dash", model = TestModel, providerName = "Alibaba",
                   profileFn = alibabaCompatProfile)

func headerValue(headers: seq[(string, string)]; name: string): string =
  for (key, value) in headers:
    if key == name:
      return value
  ""

type
  WireCapture = ref object
    url:     string
    body:    string
    headers: seq[HttpHeader]

proc recordingPort(cap: WireCapture;
                   response = """{"choices":[{"message":{"content":"ok"}}]}""";
                   status = 200): HttpRuntimePort =
  ## Answers instead of a socket so `complete` can be asserted on the wire.
  HttpRuntimePort(
    postNoRedirect: proc (url, body: string; headers: seq[HttpHeader] = @[]):
                     Result[HttpResponse, string] {.gcsafe.} =
      cap.url = url
      cap.body = body
      cap.headers = headers
      ok(HttpResponse(status: status, body: response)),
  )

proc wireAdapter(cap: WireCapture; status = 200): CompatAdapter =
  newCompatAdapter("key-dash", model = TestModel, providerName = "Alibaba",
                   profileFn = alibabaCompatProfile,
                   http = recordingPort(cap, status = status))

proc runTests*() =
  suite "alibaba compat — descriptor":

    test "the descriptor is the DashScope intl compatible-mode identity":
      let descriptor = providerDescriptor("alibaba").get()
      check descriptor.id == "alibaba"
      check descriptor.transport == ptOpenAiChat
      check descriptor.authType == atApiKey
      check descriptor.envNames == @["DASHSCOPE_API_KEY"]
      check descriptor.baseUrl ==
            "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"
      check descriptor.baseUrlEnv == "DASHSCOPE_BASE_URL"
      check descriptor.defaultModel == "qwen3.8-max"
      check descriptor.defaultModel == DefaultModelAlibaba
      check not descriptor.aggregator

    test "aliases follow the PRD; `qwen` is not one of them":
      check providerDescriptor("dashscope").get().id == "alibaba"
      check providerDescriptor("alibaba-cloud").get().id == "alibaba"
      check providerDescriptor("aliyun").get().id == "alibaba"
      check providerDescriptor("qwen").isNone
      check providerDescriptor("qwen-dashscope").isNone

  suite "alibaba compat — golden request":

    test "system and text produce the exact OpenAI body":
      let req = CompletionRequest(
        system: "seja breve",
        messages: @[ChatMessage(role: roleUser, text: "oi")])
      let body = alibabaAdapter().buildBody(req)
      let expected = parseJson("""{
      "model": "qwen3.8-max",
      "messages": [
        {"role": "system", "content": "seja breve"},
        {"role": "user", "content": "oi"}
      ],
      "stream": false
    }""")
      check body == expected

    test "the body is buildCompatRequestBody of the profile":
      var h = newHistory()
      h.addUser("oi")
      let req = CompletionRequest(system: "s", messages: h)
      check alibabaAdapter().buildBody(req) ==
            buildCompatRequestBody(alibabaCompatProfile(), TestModel, req)

    test "tools are carried and the tool result keeps the OpenAI shape":
      let req = CompletionRequest(
        messages: @[
          ChatMessage(role: roleAssistant, text: "",
                      toolCalls: @[ToolCallRequest(id: "t1", name: "search",
                                                   inputJson: """{"q":"x"}""")]),
          ChatMessage(role: roleTool, text: "resultado", toolCallId: "t1")],
        tools: @[ToolDescription(name: "search", description: "busca",
                                 schemaJson: """{"type":"object"}""")])
      let body = alibabaAdapter().buildBody(req)
      check body["tools"][0]["function"]["name"].getStr() == "search"
      check body["messages"][0]["tool_calls"][0]["id"].getStr() == "t1"
      check body["messages"][1]["role"].getStr() == "tool"
      check body["messages"][1]["tool_call_id"].getStr() == "t1"
      check body["messages"][1].hasKey("name")   ## OpenAI default, not the NIM quirk

    test "the transport sends the image it is given (the per-model decision is upstream, E3)":
      ## Unverified vision used to mean the transport dropped the image
      ## silently while the turn's marker still promised it. Now a model known
      ## to be text only loses it before the call (media_pure.visionSupport)
      ## and anything else gets it.
      let url = "data:image/png;base64,QUJD"
      let req = CompletionRequest(
        messages: @[ChatMessage(role: roleUser, text: "o que é?", imageUrl: url)])
      let body = alibabaAdapter().buildBody(req)
      check ($body).contains("image_url")
      check ($body).contains(url)

    test "reasoning=true sends no Donkey-only or DashScope-only field":
      let body = alibabaAdapter().buildBody(CompletionRequest(reasoning: true))
      check not body.hasKey("include_reasoning")
      check not body.hasKey("reasoning_effort")
      check not body.hasKey("preserve_thinking")   ## PRD US-003, §11
      check not body.hasKey("clear_thinking")

    test "the streaming body flips `stream` and adds no extras":
      let body = alibabaAdapter().buildBody(CompletionRequest(), stream = true)
      check body["stream"].getBool()
      check not body.hasKey("stream_options")

  suite "alibaba compat — headers and URL":

    test "requestHeaders carry only Authorization and Content-Type":
      let adapter = alibabaAdapter()
      let headers = adapter.requestHeaders(alibabaCompatProfile())
      check headerValue(headers, "Authorization") == "Bearer key-dash"
      check headerValue(headers, "Content-Type") == "application/json"
      check headers.len == 2                  ## the profile adds no extras
      check headerValue(headers, "X-BILLING-INVOKE-ORIGIN") == ""

    test "requestUrl is the compatible-mode endpoint without a double slash":
      let url = requestUrl(alibabaCompatProfile())
      check url ==
            "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"
      check not url.contains("//chat")
      check not url.contains("compatible-mode//")

    test "an explicit endpoint flows through unchanged":
      check requestUrl(alibabaCompatProfileAt("http://127.0.0.1:9/v1/chat")) ==
            "http://127.0.0.1:9/v1/chat"

  suite "alibaba compat — request on the wire (injected port)":
    ## `complete` is the only consumer of the endpoint and extra headers, so the
    ## port is where the profile becomes observable.

    test "complete posts the DashScope body with only the default headers":
      let cap = WireCapture()
      let res = wireAdapter(cap).complete(CompletionRequest(
        messages: @[ChatMessage(role: roleUser, text: "oi")]))
      require res.isOk
      check res.get().text == "ok"
      check cap.url ==
            "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"
      check headerValue(cap.headers, "Authorization") == "Bearer key-dash"
      check headerValue(cap.headers, "Content-Type") == "application/json"
      check cap.headers.len == 2              ## the profile adds no extras
      check headerValue(cap.headers, "X-BILLING-INVOKE-ORIGIN") == ""
      let body = parseJson(cap.body)
      check body["model"].getStr() == TestModel
      check not body.hasKey("reasoning_effort")
      check not body.hasKey("include_reasoning")

    test "reasoning on adds no DashScope-specific field":
      let cap = WireCapture()
      let res = wireAdapter(cap).complete(CompletionRequest(reasoning: true))
      require res.isOk
      let body = parseJson(cap.body)
      check not body.hasKey("preserve_thinking")
      check not body.hasKey("clear_thinking")
      check not body.hasKey("reasoning_effort")

    test "a non-2xx from the port is an error naming Alibaba":
      let cap = WireCapture()
      let res = wireAdapter(cap, status = 400).complete(CompletionRequest())
      check res.isErr
      check res.error.contains("400")
      check res.error.contains("Alibaba")

  suite "alibaba compat — golden response":

    test "content, reasoning_content, usage and tool calls parse":
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

    test "an error body is a Result, not an exception":
      let parsed = parseCompatBody(parseJson("""{"error": {"message": "nope"}}"""))
      check parsed.isErr
      check parsed.error.len > 0

  suite "alibaba compat — caps and wiring":

    test "caps advertise streaming and tools with an unknown context":
      let c = alibabaAdapter().caps()
      check c.name == "alibaba/" & TestModel
      check c.streaming
      check c.toolCalling
      check c.nativeTools.len == 0
      check c.maxContextTokens == 0          ## unverified until modelLimits
      check c.requiresUserFirst == false

    test "makeStreamFn returns a callable stream function":
      check alibabaAdapter().makeStreamFn() != nil

    test "the profile is pure data, not transport code":
      const profileSource = staticRead(
        "../../../src/donkey/domain/providers/profile_alibaba.nim")
      check not profileSource.contains("toJson")
      check not profileSource.contains("buildBody")
      check not profileSource.contains("newHttpClient")
      check not profileSource.contains("httpclient")

when isMainModule:
  runTests()
