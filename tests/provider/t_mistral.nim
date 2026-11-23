## t_mistral.nim — Mistral AI through the compat adapter.
##
## Mistral speaks the OpenAI chat dialect with two strict differences hermes
## records: unknown fields are rejected (no Donkey `include_reasoning`), and a
## tool id must be exactly 9 alphanumeric characters (hermes b33ed35968,
## 9a90a82502), so an id minted elsewhere — Donkey, or another provider before a
## fallback — fails the next call. Pinned on the wire through an injected
## `HttpRuntimePort`; no network.

import std/[json, strutils, unittest]
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/core/providers/provider_defaults
import donkey/core/providers/smart_routing
import donkey/domain/message
import donkey/domain/providers/descriptors
import donkey/domain/providers/media_pure
import donkey/domain/providers/profile_mistral
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

proc send(spec: ProviderSpec; req: CompletionRequest): Capture =
  result = Capture()
  let res = buildProviderBundle(spec, http = recordingPort(result)).completeFn(req)
  doAssert res.isOk, res.error

func isMistralId(id: string): bool =
  id.len == 9 and id.allCharsInSet({'A' .. 'Z', 'a' .. 'z', '0' .. '9'})

proc toolTurn(callId: string): CompletionRequest =
  CompletionRequest(messages: @[
    ChatMessage(role: roleUser, text: "que horas são?"),
    ChatMessage(role: roleAssistant, toolCalls: @[
      ToolCallRequest(id: callId, name: "clock", inputJson: "{}")]),
    ChatMessage(role: roleTool, text: "12:00", toolCallId: callId),
  ])

proc runTests*() =
  suite "mistral provider bundle":

    test "the runtime builder wires the compat adapter":
      let bundle = buildProviderBundle(
        ProviderSpec(providerName: "mistral", apiKey: "ms-test"))
      check bundle.completeFn != nil
      check bundle.streamFn != nil   ## the Zhipu fallback has no streamFn

    test "the hosted endpoint, the bearer key and the default model":
      for name in ["mistral", "mistralai"]:
        check descriptorOr(name).id == "mistral"
        let cap = send(ProviderSpec(providerName: name, apiKey: "ms-test"),
                       CompletionRequest(reasoning: true))
        check cap.url == "https://api.mistral.ai/v1/chat/completions"
        check headerValue(cap.headers, "Authorization") == "Bearer ms-test"
        let body = parseJson(cap.body)
        check body["model"].getStr() == DefaultModelMistral
        ## Strict API: a Donkey-only field is a 422.
        check not body.hasKey("include_reasoning")

    test "MISTRAL_BASE_URL (carried in the spec) moves the endpoint":
      let cap = send(ProviderSpec(providerName: "mistral", apiKey: "ms-test",
                                  baseUrl: "http://127.0.0.1:9000/v1/"),
                     CompletionRequest())
      check cap.url == "http://127.0.0.1:9000/v1/chat/completions"

    test "a tool id minted elsewhere becomes 9 alphanumerics on both sides of the pair":
      let cap = send(ProviderSpec(providerName: "mistral", apiKey: "ms-test"),
                     toolTurn("call_04c3699a572b"))
      let msgs = parseJson(cap.body)["messages"]
      let callId = msgs[1]["tool_calls"][0]["id"].getStr()
      check callId.isMistralId
      check msgs[2]["tool_call_id"].getStr() == callId

    test "a native Mistral id is sent as is":
      let cap = send(ProviderSpec(providerName: "mistral", apiKey: "ms-test"),
                     toolTurn("c9Abb5ZtX"))
      let msgs = parseJson(cap.body)["messages"]
      check msgs[1]["tool_calls"][0]["id"].getStr() == "c9Abb5ZtX"
      check msgs[2]["tool_call_id"].getStr() == "c9Abb5ZtX"

    test "two different ids stay different, and the mapping is stable":
      check mistralToolId("call_a") != mistralToolId("call_b")
      check mistralToolId("call_a") == mistralToolId("call_a")
      check mistralToolId("").isMistralId

    test "the stored history is not rewritten":
      let req = toolTurn("call_04c3699a572b")
      discard send(ProviderSpec(providerName: "mistral", apiKey: "ms-test"), req)
      check req.messages[1].toolCalls[0].id == "call_04c3699a572b"

    test "the default model and the profile endpoint come from the descriptor":
      check providerDefaultModelFor("mistral") == DefaultModelMistral
      check defaultModelForProvider("mistral") == DefaultModelMistral
      check mistralCompatProfile().endpoint == descriptorOr("mistral").baseUrl

    test "Pixtral reads images; other Mistral models are not verified":
      check visionSupport("mistral", "pixtral-large-latest") == vsYes
      check visionSupport("mistral", DefaultModelMistral) == vsUnknown

when isMainModule:
  runTests()
