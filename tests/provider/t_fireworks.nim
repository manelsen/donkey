## t_fireworks.nim — Fireworks end-to-end wiring (US-004, review E4).
##
## The bundle must come from the generic `CompatAdapter` through the
## descriptor, not from the Zhipu fallback at the bottom of `runtime_builder`.
##
## The branch is pinned behaviourally: the bundle is built with an injected
## `HttpRuntimePort` and `completeFn` is called, so the test asserts the request
## the bundle actually produced (URL, auth header, Fireworks-only body). A
## profile swapped at the builder's call site fails here; a source grep would
## not. No network: the port answers.

import std/[json, strutils, unittest]
import donkey/adapters/provider/compat_adapter
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/core/providers/provider_defaults
import donkey/domain/message
import donkey/domain/providers/compat
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_fireworks
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

suite "fireworks provider bundle":

  test "the runtime builder wires the compat adapter, not the Zhipu fallback":
    let bundle = buildProviderBundle(
      ProviderSpec(providerName: "fireworks", apiKey: "fw-test"))
    check bundle.completeFn != nil
    check bundle.streamFn != nil   ## the Zhipu fallback has no streamFn

  test "the alias names reach the same real bundle":
    for name in ["fireworks-ai", "fw"]:
      check descriptorOr(name).id == "fireworks"
      var cap = Capture()
      let res = completeThroughPort(
        ProviderSpec(providerName: name, apiKey: "fw-test"),
        CompletionRequest(), cap)
      require res.isOk
      check cap.url == descriptorOr("fireworks").baseUrl

  test "the bundle's request is the Fireworks profile, not another compat profile":
    ## Endpoint per provider, the credential, and the Fireworks-only body
    ## difference: no `reasoning_effort`/`include_reasoning` when reasoning is
    ## on. NVIDIA or Alibaba swapped in would either change the endpoint or
    ## leave a billing header / omit nothing.
    var cap = Capture()
    let res = completeThroughPort(
      ProviderSpec(providerName: "fireworks", apiKey: "fw-test"),
      CompletionRequest(system: "s",
                        messages: @[ChatMessage(role: roleUser, text: "oi")],
                        reasoning: true), cap)
    require res.isOk
    check cap.url == "https://api.fireworks.ai/inference/v1/chat/completions"
    check headerValue(cap.headers, "Authorization") == "Bearer fw-test"
    check headerValue(cap.headers, "Content-Type") == "application/json"
    check headerValue(cap.headers, "X-Title") == "Donkey"
    check headerValue(cap.headers, "HTTP-Referer") == FireworksReferer
    check headerValue(cap.headers, "User-Agent") == FireworksUserAgent
    check headerValue(cap.headers, "X-BILLING-INVOKE-ORIGIN") == ""
    check cap.headers.len == 5
    let body = parseJson(cap.body)
    check body["model"].getStr() == DefaultModelFireworks
    check not body.hasKey("reasoning_effort")
    check not body.hasKey("include_reasoning")
    check not body.hasKey("reasoning")

  test "the request equals what the Fireworks profile builds, header for header":
    ## Review E4: no source grep. The bundle's request is compared with the
    ## request the Fireworks profile itself builds, so a builder arm wired to
    ## another profile (or to the Zhipu fallback) fails on URL, header or body.
    let model = DefaultModelFireworks
    let req = CompletionRequest(
      system: "seja breve",
      messages: @[ChatMessage(role: roleUser, text: "oi"),
                  ChatMessage(role: roleUser, text: "e isso?",
                              imageUrl: "data:image/png;base64,QUJD")])
    let profile = fireworksCompatProfileAt(
      descriptorOr("fireworks").baseUrl,
      fireworksReasoningOffExtrasFor(model))
    let expectedBody = buildCompatRequestBody(profile, model, req)
    let expectedHeaders = newCompatAdapter(
      "fw-test", model = model, providerName = "Fireworks",
      profileFn = fireworksCompatProfile
    ).requestHeaders(profile)
    var cap = Capture()
    let res = completeThroughPort(
      ProviderSpec(providerName: "fireworks", apiKey: "fw-test",
                   modelName: model), req, cap)
    require res.isOk
    check cap.url == profile.endpoint
    check cap.headers.len == expectedHeaders.len
    for (name, value) in expectedHeaders:
      check headerValue(cap.headers, name) == value
    check parseJson(cap.body) == expectedBody
    ## The off switch is the per-model one the bundle arm chose, which only the
    ## Fireworks arm produces.
    check parseJson(cap.body)["reasoning_effort"].getStr() == "none"
    check not ($parseJson(cap.body)).contains("image_url")

  test "the off switch is the Fireworks reasoning_effort none":
    ## Only the Fireworks profile carries `reasoning_off` extras, so this is
    ## the second half of the profile proof.
    var cap = Capture()
    let res = completeThroughPort(
      ProviderSpec(providerName: "fireworks", apiKey: "fw-test"),
      CompletionRequest(reasoning: false), cap)
    require res.isOk
    let body = parseJson(cap.body)
    check body["reasoning_effort"].getStr() == "none"
    check not body.hasKey("include_reasoning")

  test "the descriptor supplies the default model":
    check providerDefaultModelFor("fireworks") == DefaultModelFireworks
    check descriptorOr("fireworks").defaultModel == DefaultModelFireworks
    check providerDefaultModelFor("fw") == DefaultModelFireworks
    check DefaultModelFireworks == "accounts/fireworks/models/kimi-k2p6"

  test "caps advertise streaming and tools with an unknown context":
    let adapter = newCompatAdapter(
      "fw-test", model = DefaultModelFireworks, providerName = "Fireworks",
      profileFn = fireworksCompatProfile)
    let c = adapter.caps()
    check c.name == "fireworks/" & DefaultModelFireworks
    check c.streaming
    check c.toolCalling
    check c.maxContextTokens == 0
    check c.requiresUserFirst == false

  test "the profile endpoint is the descriptor endpoint":
    check fireworksCompatProfile().id == "fireworks"
    check fireworksCompatProfile().endpoint == providerEndpointFor("fireworks")
    check fireworksCompatProfile().endpoint == descriptorOr("fireworks").baseUrl
    check fireworksCompatProfile().supportsImages == FireworksSupportsImages
    check not fireworksCompatProfile().supportsImages

suite "fireworks reasoning_effort allowlist (review E2)":
  ## Review E2: reasoning_effort: "none" is not accepted by every Fireworks
  ## model. Muse Spark Open rejects the value even with reasoning off, so the
  ## off switch is an allowlist: a model that is not on it gets no effort field.

  test "a model that accepts the off value keeps the off switch":
    check DefaultModelFireworks in FireworksReasoningNoneModels
    var cap = Capture()
    let res = completeThroughPort(
      ProviderSpec(providerName: "fireworks", apiKey: "fw-test",
                   modelName: DefaultModelFireworks),
      CompletionRequest(reasoning: false), cap)
    require res.isOk
    check parseJson(cap.body)["reasoning_effort"].getStr() == "none"

  test "Muse Spark Open is off the allowlist by default model name":
    check MuseSparkOpenModel notin FireworksReasoningNoneModels

  test "Muse Spark Open never receives reasoning_effort, off or on":
    for reasoning in [false, true]:
      var cap = Capture()
      let res = completeThroughPort(
        ProviderSpec(providerName: "fireworks", apiKey: "fw-test",
                     modelName: MuseSparkOpenModel),
        CompletionRequest(reasoning: reasoning), cap)
      require res.isOk
      let body = parseJson(cap.body)
      check body["model"].getStr() == MuseSparkOpenModel
      check not body.hasKey("reasoning_effort")
      check not body.hasKey("include_reasoning")

  test "the off extras are per model, not per profile":
    check fireworksReasoningOffExtrasFor(DefaultModelFireworks) ==
          %* {"reasoning_effort": "none"}
    check fireworksReasoningOffExtrasFor(MuseSparkOpenModel).len == 0
    check fireworksReasoningOffExtrasFor("accounts/fireworks/models/x").len == 0
