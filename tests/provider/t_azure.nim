## t_azure.nim — Azure OpenAI through the compat path.
##
## Microsoft's v1 GA API (learn.microsoft.com, "Azure OpenAI API version
## lifecycle" and the v1 chat completions REST reference): POST
## {resource}/openai/v1/chat/completions, the key in an `api-key` header,
## `model` holding the deployment name, no api-version needed. The bundle is
## built with an injected port and asserted on the request it sends.

import std/[json, strutils, unittest]
import donkey/adapters/provider/compat_adapter
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_azure
import donkey/ports/http
import donkey/ports/provider

type Capture = ref object
  url:     string
  body:    string
  headers: seq[HttpHeader]
  calls:   int

proc recordingPort(cap: Capture): HttpRuntimePort =
  HttpRuntimePort(
    postNoRedirect: proc (url, body: string; headers: seq[HttpHeader] = @[]):
                     Result[HttpResponse, string] {.gcsafe.} =
      inc cap.calls
      cap.url = url
      cap.body = body
      cap.headers = headers
      ok(HttpResponse(status: 200, body: """{"choices":[{"message":{"content":"ok",
        "tool_calls":[{"id":"call_1","type":"function","function":{"name":"calc",
        "arguments":"{}"}}]}}]}""")))

func headerValue(headers: seq[HttpHeader]; name: string): string =
  for header in headers:
    if header.name.toLowerAscii() == name.toLowerAscii():
      return header.value
  ""

proc spec(baseUrl: string; model = "my-gpt-deployment"): ProviderSpec =
  ProviderSpec(providerName: "azure", apiKey: "az-key", modelName: model, baseUrl: baseUrl)

proc runTests*() =
  suite "azure openai — endpoint":

    test "a resource URL becomes the v1 chat completions endpoint":
      check azureChatEndpoint("https://acme.openai.azure.com").get ==
            "https://acme.openai.azure.com/openai/v1/chat/completions"
      check azureChatEndpoint("https://acme.openai.azure.com/").get ==
            "https://acme.openai.azure.com/openai/v1/chat/completions"
      check azureChatEndpoint("https://acme.services.ai.azure.com/openai/v1/").get ==
            "https://acme.services.ai.azure.com/openai/v1/chat/completions"
      check azureChatEndpoint("https://acme.openai.azure.com/openai/v1/chat/completions").get ==
            "https://acme.openai.azure.com/openai/v1/chat/completions"

    test "no endpoint, or a plain-http one to a remote host, is refused":
      check azureChatEndpoint("").isErr
      check azureChatEndpoint("http://acme.openai.azure.com").isErr

    test "a path that is none of the documented forms is refused, not glued onto":
      check azureChatEndpoint("https://acme.openai.azure.com/openai").isErr
      check azureChatEndpoint("https://acme.openai.azure.com/openai/deployments/x").isErr

    test "plain http is allowed to this machine, IPv6 loopback with a port included":
      check azureChatEndpoint("http://[::1]:8080").get ==
            "http://[::1]:8080/openai/v1/chat/completions"
      check azureChatEndpoint("http://localhost:8080/openai/v1").isOk
      check azureChatEndpoint("http://[::2]:8080").isErr

  suite "azure openai — the request":

    test "the key goes in api-key, never as a bearer; model is the deployment":
      let cap = Capture()
      let res = buildProviderBundle(spec("https://acme.openai.azure.com"),
                                    http = recordingPort(cap)).completeFn(
        CompletionRequest(messages: @[ChatMessage(role: roleUser, text: "oi")]))
      check res.isOk
      check cap.url == "https://acme.openai.azure.com/openai/v1/chat/completions"
      check headerValue(cap.headers, "api-key") == "az-key"
      check headerValue(cap.headers, "Authorization") == ""
      check parseJson(cap.body)["model"].getStr == "my-gpt-deployment"
      check "api-version" notin cap.url

    test "a tool round comes back in the OpenAI shape":
      let cap = Capture()
      let res = buildProviderBundle(spec("https://acme.openai.azure.com"),
                                    http = recordingPort(cap)).completeFn(
        CompletionRequest(messages: @[ChatMessage(role: roleUser, text: "1+1")],
          tools: @[ToolDescription(name: "calc", description: "d",
                                   schemaJson: """{"type":"object"}""")]))
      check res.get.toolCalls.len == 1
      check res.get.toolCalls[0].name == "calc"
      check parseJson(cap.body)["tools"][0]["function"]["name"].getStr == "calc"

    test "without an endpoint the call fails clearly and sends nothing":
      let cap = Capture()
      let res = buildProviderBundle(spec(""), http = recordingPort(cap)).completeFn(
        CompletionRequest(messages: @[ChatMessage(role: roleUser, text: "oi")]))
      check res.isErr and "AZURE_OPENAI_ENDPOINT" in res.error
      check cap.calls == 0

  suite "azure openai — descriptor":

    test "the descriptor, its aliases and its streaming":
      let d = descriptorOr("azure")
      check d.id == "azure"
      check d.envNames == @["AZURE_OPENAI_API_KEY"]
      check d.baseUrlEnv == "AZURE_OPENAI_ENDPOINT"
      check descriptorOr("azure-openai").id == "azure"
      check streamsToolCalls("azure")
      check buildProviderBundle(spec("https://acme.openai.azure.com")).streamFn != nil

when isMainModule:
  runTests()
