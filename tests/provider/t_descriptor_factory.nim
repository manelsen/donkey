## Characterization for the descriptor-backed factory helpers in
## runtime_builder. They must return exactly the metadata the descriptor table
## already declares, so the builder and the catalog stop repeating it.

import std/[os, strutils, unittest]
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/domain/message
import donkey/domain/providers/descriptors
import donkey/ports/http
import donkey/ports/provider

type
  Capture = ref object
    url:     string
    body:    string
    headers: seq[HttpHeader]

proc recordingPort(cap: Capture): HttpRuntimePort =
  ## Answers every compat request so the factory's choice of branch is
  ## observable: URL and credential are captured, no socket is opened.
  HttpRuntimePort(
    postNoRedirect: proc (url, body: string; headers: seq[HttpHeader] = @[]):
                     Result[HttpResponse, string] {.gcsafe.} =
      cap.url = url
      cap.body = body
      cap.headers = headers
      ok(HttpResponse(status: 200,
                      body: """{"choices":[{"message":{"content":"ok"}}]}""",))
  )

func headerValue(headers: seq[HttpHeader]; name: string): string =
  for header in headers:
    if header.name.toLowerAscii() == name.toLowerAscii():
      return header.value
  ""

const EndpointCases = [
  ("openrouter",   "https://openrouter.ai/api/v1/chat/completions"),
  ("openai",       "https://api.openai.com/v1/chat/completions"),
  ("deepseek",     "https://api.deepseek.com/v1/chat/completions"),
  ("ollama",       "http://localhost:11434"),
  ("groq",         "https://api.groq.com/openai/v1/chat/completions"),
  ("opencode-go",  "https://opencode.ai/zen/go/v1/chat/completions"),
  ("zen",          "https://opencode.ai/zen/v1/chat/completions"),
  ("anthropic",    "https://api.anthropic.com/v1/messages"),
  ("zai-anthropic", "https://api.z.ai/api/anthropic"),
  ("gemini",       "https://generativelanguage.googleapis.com/v1beta/models"),
  ("minimax",      "https://api.minimax.io/v1/chat/completions"),
  ("zai",          "https://api.z.ai/api/paas/v4/chat/completions"),
  ("zai-coding",   "https://api.z.ai/api/coding/paas/v4/chat/completions"),
  ("nvidia",       "https://integrate.api.nvidia.com/v1/chat/completions"),
  ("alibaba",      "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"),
]

const DefaultModelCases = [
  ("openrouter",   "openai/gpt-6.1-sol"),
  ("openai",       "gpt-6.1-sol"),
  ("deepseek",     "deepseek-4.1-flash"),
  ("ollama",       "llama3.3"),
  ("groq",         "llama-3.3-70b-versatile"),
  ("opencode-go",  "opencode/deepseek-4.1-flash"),
  ("zen",          "zen/deepseek-4.1-flash"),
  ("anthropic",    "claude-sonnet-5-5"),
  ("zai-anthropic", "glm-4.7"),
  ("gemini",       "gemini-3.8-flash"),
  ("minimax",      "MiniMax-M2"),
  ("zai",          "glm-4.7"),
  ("zai-coding",   "glm-4.7"),
  ("nvidia",       "nvidia/nemotron-3.5-super-vl-120b-a12b"),
  ("alibaba",      "qwen3.8-max"),
]

let hadNvidiaBase = existsEnv("NVIDIA_BASE_URL")
let prevNvidiaBase = getEnv("NVIDIA_BASE_URL")
let hadDashscopeBase = existsEnv("DASHSCOPE_BASE_URL")
let prevDashscopeBase = getEnv("DASHSCOPE_BASE_URL")

proc restoreEnv(name: string; had: bool; previous: string) =
  if had: putEnv(name, previous) else: delEnv(name)

suite "descriptor factory":

  setup:
    ## The tests compare against the hosted endpoints; a local override in the
    ## developer's environment must not change the expectation.
    delEnv("NVIDIA_BASE_URL")
    delEnv("DASHSCOPE_BASE_URL")

  teardown:
    restoreEnv("NVIDIA_BASE_URL", hadNvidiaBase, prevNvidiaBase)
    restoreEnv("DASHSCOPE_BASE_URL", hadDashscopeBase, prevDashscopeBase)

  test "providerEndpointFor returns the descriptor base URL for every provider":
    for (id, expected) in EndpointCases:
      check providerEndpointFor(id) == expected

  test "providerEndpointFor resolves aliases canonically":
    check providerEndpointFor("opencode") == providerEndpointFor("opencode-go")
    check providerEndpointFor("opencode") ==
      "https://opencode.ai/zen/go/v1/chat/completions"
    check providerEndpointFor("opencode-zen") == providerEndpointFor("zen")
    check providerEndpointFor("opencode-zen") ==
      "https://opencode.ai/zen/v1/chat/completions"

  test "providerEndpointFor falls back to zai-coding for unknown ids":
    check providerEndpointFor("does-not-exist") ==
      providerEndpointFor("zai-coding")
    check providerEndpointFor("") == providerEndpointFor("zai-coding")

  test "providerDefaultModelFor returns the descriptor default model":
    for (id, expected) in DefaultModelCases:
      check providerDefaultModelFor(id) == expected

  test "providerDefaultModelFor falls back to zai-coding for unknown ids":
    check providerDefaultModelFor("") == "glm-4.7"
    check providerDefaultModelFor("does-not-exist") ==
      providerDefaultModelFor("zai-coding")

  test "factory stays in sync with the descriptor table":
    for descriptor in providerDescriptors():
      check providerEndpointFor(descriptor.id) == descriptor.baseUrl
      check providerDefaultModelFor(descriptor.id) == descriptor.defaultModel
      for alias in descriptor.aliases:
        check providerEndpointFor(alias) == descriptor.baseUrl
        check providerDefaultModelFor(alias) == descriptor.defaultModel

  test "providerEndpointFor consumes baseUrlEnv when it is set":
    ## `NVIDIA_BASE_URL=http://localhost:8000/v1` (as documented for local NIM)
    ## must resolve to the chat/completions path; an already-complete endpoint
    ## is used as-is.
    let hadNvidia = existsEnv("NVIDIA_BASE_URL")
    let previousNvidia = getEnv("NVIDIA_BASE_URL")
    let hadAlibaba = existsEnv("DASHSCOPE_BASE_URL")
    let previousAlibaba = getEnv("DASHSCOPE_BASE_URL")
    defer:
      if hadNvidia: putEnv("NVIDIA_BASE_URL", previousNvidia)
      else: delEnv("NVIDIA_BASE_URL")
      if hadAlibaba: putEnv("DASHSCOPE_BASE_URL", previousAlibaba)
      else: delEnv("DASHSCOPE_BASE_URL")

    putEnv("NVIDIA_BASE_URL", "http://localhost:8000/v1/")
    check providerEndpointFor("nvidia") ==
          "http://localhost:8000/v1/chat/completions"
    putEnv("NVIDIA_BASE_URL",
           "http://localhost:8000/v1/chat/completions")
    check providerEndpointFor("nvidia") ==
          "http://localhost:8000/v1/chat/completions"

    putEnv("DASHSCOPE_BASE_URL", "https://dashscope.example/v1")
    check providerEndpointFor("alibaba") ==
          "https://dashscope.example/v1/chat/completions"

  test "every chat-completions descriptor has its own streaming branch":
    ## Deleting the `of "nvidia"` (or `of "alibaba"`) branch makes the bundle
    ## fall through to Zhipu, whose streamFn is nil. zai/zai-coding and minimax
    ## are excluded on purpose: their runtime branches chain to non-streaming
    ## adapters.
    for descriptor in providerDescriptors():
      if descriptor.transport == ptOpenAiChat and
         descriptor.id notin ["zai", "zai-coding", "minimax"]:
        let bundle = buildProviderBundle(
          ProviderSpec(providerName: descriptor.id, apiKey: "test-key"))
        check bundle.completeFn != nil
        check bundle.streamFn != nil
  test "a cleartext remote override is ignored, not used":
    putEnv("NVIDIA_BASE_URL", "http://evil.example/v1")
    check providerEndpointFor("nvidia") == descriptorOr("nvidia").baseUrl
    putEnv("NVIDIA_BASE_URL", "http://127.0.0.1:8000/v1/")
    check providerEndpointFor("nvidia").startsWith("http://127.0.0.1:8000/v1")
    putEnv("NVIDIA_BASE_URL", "https://nim.example/v1/")
    check providerEndpointFor("nvidia") ==
      "https://nim.example/v1/chat/completions"

  test "every compat bundle posts to its own descriptor endpoint":
    ## The injected port makes the builder's branch choice black-box: a bundle
    ## wired to another provider's profile posts to that other endpoint.
    for id in ["nvidia", "alibaba", "fireworks"]:
      var cap = Capture()
      let bundle = buildProviderBundle(
        ProviderSpec(providerName: id, apiKey: "key-" & id),
        http = recordingPort(cap))
      let res = bundle.completeFn(CompletionRequest())
      require res.isOk
      check cap.url == providerEndpointFor(id)
      check cap.url == descriptorOr(id).baseUrl
      check headerValue(cap.headers, "Authorization") == "Bearer key-" & id
      check cap.body.len > 0

  test "a userinfo override is ignored, not sent over cleartext":
    ## `localhost:pass@remote.example` hides the real host in the userinfo.
    putEnv("NVIDIA_BASE_URL", "http://localhost:pass@remote.example/v1")
    check providerEndpointFor("nvidia") == descriptorOr("nvidia").baseUrl

  test "a userinfo override is rejected for https too":
    putEnv("NVIDIA_BASE_URL", "https://api.nvidia.com@evil.example/v1")
    check providerEndpointFor("nvidia") == descriptorOr("nvidia").baseUrl

  test "an @ inside the query does not look like userinfo":
    putEnv("NVIDIA_BASE_URL", "https://gateway.example/v1?key=a@b")
    ## The authority is `gateway.example`: the override is accepted (whatever
    ## the resulting URL shape), not silently replaced by the hosted endpoint.
    check providerEndpointFor("nvidia") != descriptorOr("nvidia").baseUrl
