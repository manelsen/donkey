## t_alibaba.nim — Alibaba DashScope end-to-end wiring (US-003, audit F1/F6,
## review E4).
##
## The bundle must come from the generic `CompatAdapter` through the
## descriptor, not from the Zhipu fallback at the bottom of `runtime_builder`.
##
## The branch is pinned behaviourally: the bundle is built with an injected
## `HttpRuntimePort` and `completeFn` is called, so the test asserts the request
## the bundle actually produced. A profile swapped at the builder's call site
## fails here; a source grep would not. No network: the port answers.

import std/[json, os, strutils, unittest]
import donkey/adapters/provider/compat_adapter
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/core/providers/provider_defaults
import donkey/domain/message
import donkey/domain/providers/compat
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_alibaba
import donkey/ports/http
import donkey/ports/provider

type
  Capture = ref object
    url:     string
    body:    string
    headers: seq[HttpHeader]

proc recordingPort(cap: Capture): HttpRuntimePort =
  HttpRuntimePort(
    postNoRedirect: proc (url, body: string; headers: seq[HttpHeader] = @[]):
                     Result[HttpResponse, string] {.gcsafe.} =
      cap.url = url
      cap.body = body
      cap.headers = headers
      ok(HttpResponse(status: 200,
                      body: """{"choices":[{"message":{"content":"ok"}}]}""")),
  )

func headerValue(headers: seq[HttpHeader]; name: string): string =
  for header in headers:
    if header.name.toLowerAscii() == name.toLowerAscii():
      return header.value
  ""

proc completeThroughPort(spec: ProviderSpec; req: CompletionRequest;
                         cap: Capture): Result[CompletionResponse, string] =
  buildProviderBundle(spec, http = recordingPort(cap)).completeFn(req)

proc runTests*() =
  suite "alibaba provider bundle":

    test "the runtime builder wires the compat adapter, not the Zhipu fallback":
      let bundle = buildProviderBundle(
        ProviderSpec(providerName: "alibaba", apiKey: "dashscope-test"))
      check bundle.completeFn != nil
      check bundle.streamFn != nil   ## the Zhipu fallback has no streamFn

    test "the alias names reach the same real bundle":
      for name in ["dashscope", "alibaba-cloud", "aliyun"]:
        check descriptorOr(name).id == "alibaba"
        var cap = Capture()
        let res = completeThroughPort(
          ProviderSpec(providerName: name, apiKey: "dashscope-test"),
          CompletionRequest(), cap)
        require res.isOk
        check cap.url == descriptorOr("alibaba").baseUrl

    test "the bundle's request is the Alibaba profile, not another compat profile":
      ## Endpoint per provider, the credential, and the DashScope-only body
      ## difference: no `reasoning_effort` at all (Fireworks would send "none"
      ## with reasoning off), no billing header (that is NVIDIA's), and no
      ## Donkey-only reasoning field.
      var cap = Capture()
      let res = completeThroughPort(
        ProviderSpec(providerName: "alibaba", apiKey: "dashscope-test"),
        CompletionRequest(system: "s",
                          messages: @[ChatMessage(role: roleUser, text: "oi")],
                          reasoning: false), cap)
      require res.isOk
      check cap.url ==
            "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"
      check headerValue(cap.headers, "Authorization") == "Bearer dashscope-test"
      check headerValue(cap.headers, "Content-Type") == "application/json"
      check cap.headers.len == 2              ## the profile adds no extras
      check headerValue(cap.headers, "X-BILLING-INVOKE-ORIGIN") == ""
      check headerValue(cap.headers, "X-Title") == ""
      let body = parseJson(cap.body)
      check body["model"].getStr() == DefaultModelAlibaba
      check not body.hasKey("reasoning_effort")
      check not body.hasKey("include_reasoning")
      check not body.hasKey("preserve_thinking")

    test "the request equals what the Alibaba profile builds, header for header":
      ## Review E4: no source grep. The bundle's request is compared with the
      ## request the Alibaba profile itself builds, so a builder arm wired to
      ## another profile (or to the Zhipu fallback) fails on URL, header or body.
      let model = DefaultModelAlibaba
      let req = CompletionRequest(
        system: "seja breve",
        messages: @[ChatMessage(role: roleUser, text: "oi")],
        reasoning: true)
      let profile = alibabaCompatProfileAt(
        providerEndpointFor("alibaba"))
      let expectedBody = buildCompatRequestBody(profile, model, req)
      let expectedHeaders = newCompatAdapter(
        "dashscope-test", model = model, providerName = "Alibaba",
        profileFn = alibabaCompatProfile
      ).requestHeaders(profile)
      var cap = Capture()
      let res = completeThroughPort(
        ProviderSpec(providerName: "alibaba", apiKey: "dashscope-test",
                     modelName: model), req, cap)
      require res.isOk
      check cap.url == profile.endpoint
      check cap.headers.len == expectedHeaders.len
      for (name, value) in expectedHeaders:
        check headerValue(cap.headers, name) == value
      check parseJson(cap.body) == expectedBody
      ## DashScope carries neither the Fireworks off switch nor the NIM billing
      ## header, which is what tells the two compat arms apart.
      check not parseJson(cap.body).hasKey("reasoning_effort")
      check headerValue(cap.headers, "X-BILLING-INVOKE-ORIGIN") == ""

    test "the DASHSCOPE_BASE_URL override is what the bundle posts to":
      var cap = Capture()
      let res = completeThroughPort(
        ProviderSpec(providerName: "alibaba", apiKey: "dashscope-test",
                     baseUrl: "https://dashscope.example/v1/"),
        CompletionRequest(), cap)
      require res.isOk
      check cap.url == "https://dashscope.example/v1/chat/completions"

    test "the descriptor supplies the default model":
      check providerDefaultModelFor("alibaba") == DefaultModelAlibaba
      check descriptorOr("alibaba").defaultModel == DefaultModelAlibaba
      check DefaultModelAlibaba == "qwen3.8-max"

    test "caps advertise streaming and tools with an unknown context":
      let adapter = newCompatAdapter(
        "dashscope-test", model = DefaultModelAlibaba, providerName = "Alibaba",
        profileFn = alibabaCompatProfile)
      let c = adapter.caps()
      check c.name == "alibaba/" & DefaultModelAlibaba
      check c.streaming
      check c.toolCalling
      check c.maxContextTokens == 0
      check c.requiresUserFirst == false

    test "the profile endpoint is the descriptor endpoint":
      check alibabaCompatProfile().id == "alibaba"
      check alibabaCompatProfile().endpoint == providerEndpointFor("alibaba")
      check alibabaCompatProfile().endpoint == descriptorOr("alibaba").baseUrl
      ## Images are decided per model before the call (media_pure.visionSupport);
      ## the transport sends what it is given, so Qwen-VL keeps its images.
      check alibabaCompatProfile().supportsImages

when isMainModule:
  runTests()
