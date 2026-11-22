## t_nvidia.nim — NVIDIA NIM end-to-end wiring (US-001, review E4).
##
## The bundle must come from the generic `CompatAdapter` through the
## descriptor, not from the Zhipu fallback at the bottom of `runtime_builder`.
##
## Wiring is pinned behaviourally: the bundle is built with an injected
## `HttpRuntimePort` and `completeFn` is called, so the test asserts the request
## the bundle actually produced. The NIM billing header is scoped to the hosted
## endpoint, which is only observable on the wire. No network: the port answers.

import std/[json, os, strutils, unittest]
import donkey/adapters/provider/compat_adapter
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/core/providers/provider_defaults
import donkey/core/providers/smart_routing
import donkey/domain/message
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_nvidia
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
  suite "nvidia provider bundle":

    test "the runtime builder wires the compat adapter, not the Zhipu fallback":
      let bundle = buildProviderBundle(
        ProviderSpec(providerName: "nvidia", apiKey: "nvapi-test"))
      check bundle.completeFn != nil
      check bundle.streamFn != nil   ## the Zhipu fallback has no streamFn

    test "the alias posts to the hosted endpoint with the billing header":
      for name in ["nvidia", "nim"]:
        check descriptorOr(name).id == "nvidia"
        var cap = Capture()
        let res = completeThroughPort(
          ProviderSpec(providerName: name, apiKey: "nvapi-test"),
          CompletionRequest(reasoning: true), cap)
        require res.isOk
        check cap.url == "https://integrate.api.nvidia.com/v1/chat/completions"
        check headerValue(cap.headers, "Authorization") == "Bearer nvapi-test"
        check headerValue(cap.headers, NvidiaBillingHeaderName) ==
              NvidiaBillingHeaderValue
        let body = parseJson(cap.body)
        check body["model"].getStr() == DefaultModelNvidia
        check not body.hasKey("include_reasoning")
        check not body.hasKey("reasoning_effort")

    test "the billing header is absent from a local NIM endpoint":
      ## `NVIDIA_BASE_URL` (carried in the spec) moves the bundle from hosted
      ## to local — and it stops claiming build.nvidia.com billing.
      var cap = Capture()
      let res = completeThroughPort(
        ProviderSpec(providerName: "nvidia", apiKey: "nvapi-test",
                     baseUrl: "http://127.0.0.1:8000/v1/"),
        CompletionRequest(), cap)
      require res.isOk
      check cap.url == "http://127.0.0.1:8000/v1/chat/completions"
      check headerValue(cap.headers, NvidiaBillingHeaderName) == ""
      check headerValue(cap.headers, "Authorization") == "Bearer nvapi-test"

    test "the descriptor supplies the default model":
      check providerDefaultModelFor("nvidia") == DefaultModelNvidia
      check descriptorOr("nvidia").defaultModel == DefaultModelNvidia
      check providerDefaultModelFor("nim") == DefaultModelNvidia
      ## Resolution must never fall back to the generic glm-4.7.
      check defaultModelForProvider("nvidia") == DefaultModelNvidia
      check defaultModelForProvider("nvidia") != "glm-4.7"

    test "the profile endpoint is the descriptor endpoint":
      check nvidiaCompatProfile().id == "nvidia"
      check nvidiaCompatProfile().endpoint == providerEndpointFor("nvidia")
      check nvidiaCompatProfile().endpoint == descriptorOr("nvidia").baseUrl

    test "caps advertise streaming and tool calling":
      let adapter = newCompatAdapter(
        "nvapi-test", model = DefaultModelNvidia, providerName = "NVIDIA",
        profileFn = nvidiaCompatProfile)
      let c = adapter.caps()
      check c.name == "nvidia/" & DefaultModelNvidia
      check c.streaming
      check c.toolCalling
      check c.nativeTools.len == 0
      check c.maxContextTokens == 0      ## limits arrive with the catalog (US-005)

when isMainModule:
  runTests()
