## t_compat_fireworks.nim — Fireworks AI through the generic CompatAdapter
## (US-004).
##
## Fireworks speaks the OpenAI chat/completions dialect. Everything
## provider-specific is data in `fireworksCompatProfile`: the attribution
## headers and `reasoning_effort: "none"` when reasoning is disabled. There is
## no Fireworks adapter file. Pure: no network, no provider, no Docker.
##
## Verified against Hermes (read-only):
##   - `hermes_cli/providers.py:75-76`: FIREWORKS_API_KEY; hosted base URL
##     `https://api.fireworks.ai/inference/v1` (no `*_BASE_URL` env var;
##     the docs point at `model.base_url`).
##   - `plugins/model-providers/fireworks/__init__.py:9-49`: aliases
##     `fireworks-ai`/`fw`; attribution headers; `fallback_models[0]` is
##     `accounts/fireworks/models/kimi-k2p6`; `enabled=false` maps to
##     `reasoning_effort: "none"` (the Donkey default model is a choice, not a
##     Hermes default — that is `accounts/fireworks/models/glm-5p2`).
##   - `website/docs/integrations/providers.md:227-229,293`: slash-form model
##     ids and the default endpoint.
##   - `agent/transports/chat_completions.py:40-46,288`: strict providers
##     (Fireworks named) reject `extra_content`; no vision claim.
##
## Vision is **not** verified in those sources, so the profile suppresses
## images: absence is never a promise (PRD FR-3).

import std/[json, options, strutils, unittest]
import donkey/core/pipeops
import donkey/core/providers/provider_defaults
import donkey/domain/message
import donkey/domain/providers/compat
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_fireworks
import donkey/adapters/provider/compat_adapter
import donkey/ports/http

const TestModel = "accounts/fireworks/models/kimi-k2p6"

proc fireworksAdapter(): CompatAdapter =
  newCompatAdapter("key-fw", model = TestModel, providerName = "Fireworks",
                   profileFn = fireworksCompatProfile)

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
  newCompatAdapter("key-fw", model = TestModel, providerName = "Fireworks",
                   profileFn = fireworksCompatProfile,
                   http = recordingPort(cap, status = status))

proc runTests*() =
  suite "fireworks compat — descriptor":

    test "the descriptor is the Fireworks identity from the PRD table":
      let descriptor = providerDescriptor("fireworks").get()
      check descriptor.id == "fireworks"
      check descriptor.transport == ptOpenAiChat
      check descriptor.authType == atApiKey
      check descriptor.envNames == @["FIREWORKS_API_KEY"]
      check descriptor.baseUrl ==
            "https://api.fireworks.ai/inference/v1/chat/completions"
      check descriptor.baseUrlEnv == ""   ## no Fireworks endpoint env in Hermes
      check descriptor.defaultModel == DefaultModelFireworks
      check descriptor.defaultModel == "accounts/fireworks/models/kimi-k2p6"
      check not descriptor.aggregator

    test "aliases are exactly the two the Hermes profile declares":
      let descriptor = providerDescriptor("fireworks").get()
      check descriptor.aliases == @["fireworks-ai", "fw"]
      check providerDescriptor("fireworks-ai").get().id == "fireworks"
      check providerDescriptor("fw").get().id == "fireworks"
      ## No invented aliases swallow a typo.
      check providerDescriptor("kimi").isNone
      check providerDescriptor("kimi-k2p6").isNone
      check providerDescriptor("fireworksai").isNone
      check providerDescriptor("fireworks-aii").isNone

  suite "fireworks compat — golden request":

    test "system and text produce the exact OpenAI body plus reasoning_effort none":
      let req = CompletionRequest(
        system: "seja breve",
        messages: @[ChatMessage(role: roleUser, text: "oi")])
      let body = fireworksAdapter().buildBody(req)
      let expected = parseJson("""{
      "model": "accounts/fireworks/models/kimi-k2p6",
      "messages": [
        {"role": "system", "content": "seja breve"},
        {"role": "user", "content": "oi"}
      ],
      "stream": false,
      "reasoning_effort": "none"
    }""")
      check body == expected

    test "the body is buildCompatRequestBody of the profile":
      let req = CompletionRequest(
        system: "s",
        messages: @[ChatMessage(role: roleUser, text: "oi")])
      check fireworksAdapter().buildBody(req) ==
            buildCompatRequestBody(fireworksCompatProfile(), TestModel, req)

    test "reasoning=true removes reasoning_effort and adds no other reasoning key":
      let body = fireworksAdapter().buildBody(CompletionRequest(reasoning: true))
      check not body.hasKey("reasoning_effort")
      check not body.hasKey("reasoning")
      check not body.hasKey("include_reasoning")
      check not body.hasKey("thinking")

    test "the profile carries reasoning_effort only as an off extra":
      let profile = fireworksCompatProfile()
      check profile.reasoningOffExtras == %* {"reasoning_effort": "none"}
      check profile.reasoningExtras.isNil

    test "tools are carried and the tool result keeps the OpenAI shape":
      let req = CompletionRequest(
        messages: @[
          ChatMessage(role: roleAssistant, text: "",
                      toolCalls: @[ToolCallRequest(id: "t1", name: "search",
                                                   inputJson: """{"q":"x"}""")]),
          ChatMessage(role: roleTool, text: "resultado", toolCallId: "t1")],
        tools: @[ToolDescription(name: "search", description: "busca",
                                 schemaJson: """{"type":"object"}""")])
      let body = fireworksAdapter().buildBody(req)
      check body["tools"][0]["function"]["name"].getStr() == "search"
      check body["messages"][0]["tool_calls"][0]["id"].getStr() == "t1"
      check body["messages"][1]["role"].getStr() == "tool"
      check body["messages"][1]["tool_call_id"].getStr() == "t1"
      check body["messages"][1].hasKey("name")   ## OpenAI default, not the NIM quirk

    test "an image is suppressed because vision is unverified":
      let url = "data:image/png;base64,QUJD"
      let req = CompletionRequest(
        messages: @[ChatMessage(role: roleUser, text: "o que é?", imageUrl: url)])
      let body = fireworksAdapter().buildBody(req)
      let content = body["messages"][0]["content"]
      check content.kind == JString
      check content.getStr() == "o que é?"
      check not ($body).contains("image_url")
      check not ($body).contains(url)

    test "the streaming body flips `stream` and keeps the off extra":
      let body = fireworksAdapter().buildBody(CompletionRequest(), stream = true)
      check body["stream"].getBool()
      check not body.hasKey("stream_options")
      check body["reasoning_effort"].getStr() == "none"

  suite "fireworks compat — headers and URL":

    test "requestHeaders carry the credential plus the attribution headers":
      let adapter = fireworksAdapter()
      let headers = adapter.requestHeaders(fireworksCompatProfile())
      check headerValue(headers, "Authorization") == "Bearer key-fw"
      check headerValue(headers, "Content-Type") == "application/json"
      check headerValue(headers, "HTTP-Referer").len > 0
      check headerValue(headers, "X-Title") == "Donkey"
      check headerValue(headers, "User-Agent") == "Donkey"
      check headers.len == 5
      for (_, value) in headers:
        check not value.contains("Hermes")

    test "requestUrl is the descriptor endpoint":
      check requestUrl(fireworksCompatProfile()) ==
            "https://api.fireworks.ai/inference/v1/chat/completions"
      check fireworksCompatProfile().endpoint == descriptorOr("fireworks").baseUrl

    test "an explicit endpoint flows through unchanged":
      check requestUrl(fireworksCompatProfileAt("http://127.0.0.1:9/v1/chat")) ==
            "http://127.0.0.1:9/v1/chat"

  suite "fireworks compat — request on the wire (injected port)":
    ## `complete` is the only consumer of the endpoint and extra headers, so the
    ## port is where the profile becomes observable.

    test "complete posts the Fireworks body and headers to the descriptor endpoint":
      let cap = WireCapture()
      let res = wireAdapter(cap).complete(CompletionRequest(
        messages: @[ChatMessage(role: roleUser, text: "oi")]))
      require res.isOk
      check res.get().text == "ok"
      check cap.url == "https://api.fireworks.ai/inference/v1/chat/completions"
      check headerValue(cap.headers, "Authorization") == "Bearer key-fw"
      check headerValue(cap.headers, "Content-Type") == "application/json"
      check headerValue(cap.headers, "X-Title") == "Donkey"
      check headerValue(cap.headers, "HTTP-Referer") == FireworksReferer
      let body = parseJson(cap.body)
      check body["model"].getStr() == TestModel
      check body["reasoning_effort"].getStr() == "none"
      check not body.hasKey("include_reasoning")

    test "reasoning on omits the off switch and every reasoning key":
      let cap = WireCapture()
      let res = wireAdapter(cap).complete(CompletionRequest(reasoning: true))
      require res.isOk
      let body = parseJson(cap.body)
      check not body.hasKey("reasoning_effort")
      check not body.hasKey("include_reasoning")
      check not body.hasKey("reasoning")

    test "a non-2xx from the port is an error naming Fireworks":
      let cap = WireCapture()
      let res = wireAdapter(cap, status = 429).complete(CompletionRequest())
      check res.isErr
      check res.error.contains("429")
      check res.error.contains("Fireworks")

  suite "fireworks compat — golden response":

    test "content, usage and tool calls parse":
      let body = parseJson("""{
      "choices": [{"message": {
        "content": "olá",
        "tool_calls": [{"id": "t1", "type": "function",
                        "function": {"name": "search", "arguments": "{\"q\":\"x\"}"}}]
      }}],
      "usage": {"prompt_tokens": 7, "completion_tokens": 3}
    }""")
      let parsed = parseCompatBody(body)
      check parsed.isOk
      let response = parsed.get()
      check response.text == "olá"
      check response.inputTokens == 7
      check response.outputTokens == 3
      check response.toolCalls.len == 1
      check response.toolCalls[0].name == "search"
      check response.toolCalls[0].inputJson == """{"q":"x"}"""

    test "an error body is a Result, not an exception":
      let parsed = parseCompatBody(parseJson("""{"error": {"message": "nope"}}"""))
      check parsed.isErr
      check parsed.error.len > 0

  suite "fireworks compat — caps and purity":

    test "caps advertise streaming and tools with an unknown context":
      let c = fireworksAdapter().caps()
      check c.name == "fireworks/" & TestModel
      check c.streaming
      check c.toolCalling
      check c.nativeTools.len == 0
      check c.maxContextTokens == 0          ## unverified until modelLimits
      check c.requiresUserFirst == false

    test "makeStreamFn returns a callable stream function":
      check fireworksAdapter().makeStreamFn() != nil

    test "the profile is pure data, not transport code":
      const profileSource = staticRead(
        "../../../src/donkey/domain/providers/profile_fireworks.nim")
      check not profileSource.contains("toJson")
      check not profileSource.contains("buildBody")
      check not profileSource.contains("newHttpClient")
      check not profileSource.contains("httpclient")

when isMainModule:
  runTests()
