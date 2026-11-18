## Concrete provider runtime builder for session bootstrap wiring.
##
## Identity comes from the descriptor table: endpoint, default model and
## aliases. Only deviations that are not endpoints stay here: the zai/zai-coding
## Anthropic fallback, Zen's multi-protocol routing, the Groq/OpenCode/Zen
## provider labels, and the model prefix those gateways accept.

import std/[net, options, os, strutils]
import ../../domain/message
import ../../domain/providers/compat
import ../../domain/providers/descriptors
import ../../domain/providers/profile_nvidia
import ../../domain/providers/profile_alibaba
import ../../domain/providers/profile_fireworks
import ../../core/pipeops
import ../../ports/http
import ../../ports/provider
import ../../core/providers/smart_routing
import zhipu
import openrouter
import anthropic
import gemini
import minimax
import ollama
import openai
import deepseek
import compat_adapter

func chatCompletionsEndpoint(base: string): string =
  ## `NVIDIA_BASE_URL=http://localhost:8000/v1` → `.../v1/chat/completions`.
  ## An already-complete endpoint is left alone.
  var value = base.strip
  while value.endsWith("/"):
    value.setLen(value.len - 1)
  if value.endsWith("/chat/completions"): value
  else: value & "/chat/completions"

func overrideEndpointSafe(url: string): bool =
  ## A `baseUrlEnv` override carries the provider key on every call: plain
  ## http is only acceptable on loopback (local NIM), never to a remote host.
  ## Userinfo is rejected for both schemes: `https://api.nvidia.com@evil/v1`
  ## would otherwise pass the https shortcut and send the key to `evil`.
  let lower = url.strip().toLowerAscii()
  let schemeEnd = lower.find("://")
  if schemeEnd <= 0:
    return false
  var authority = lower[schemeEnd + 3 .. ^1]
  ## RFC 3986: the authority ends at the first `/`, `?` or `#`. Cutting only at
  ## `/` dragged a query into the authority, and an `@` there rejected a
  ## legitimate override.
  var endIdx = authority.len
  for delim in ['/', '?', '#']:
    let at = authority.find(delim)
    if at >= 0 and at < endIdx:
      endIdx = at
  authority = authority[0 ..< endIdx]
  if '@' in authority:
    return false
  if lower.startsWith("https://"):
    return true
  if not lower.startsWith("http://"):
    return false
  var host = authority
  let colon = host.rfind(':')
  if colon >= 0: host = host[0 ..< colon]
  host = host.strip(chars = {'[', ']'})
  if host == "localhost":
    return true
  try:
    let ip = parseIpAddress(host)
    if ip.family == IPv4:
      return ip.address_v4[0] == 127'u8
    $ip == "::1"
  except ValueError:
    false


proc providerEndpointFor*(id: string): string {.gcsafe.} =
  ## Wire URL for a provider. A descriptor `baseUrlEnv` override wins over the
  ## table (docs: `NVIDIA_BASE_URL`, `DASHSCOPE_BASE_URL`); unknown ids fall
  ## back to zai-coding, matching `buildProviderSpec`.
  let descriptor = descriptorOr(id)
  let override =
    if descriptor.baseUrlEnv.len > 0: getEnv(descriptor.baseUrlEnv).strip()
    else: ""
  if override.len == 0 or not overrideEndpointSafe(override):
    ## An unsafe override is ignored rather than used: falling back to the
    ## provider's real endpoint is the safe failure, and the key never travels
    ## over cleartext to a remote host.
    return descriptor.baseUrl
  case descriptor.transport
  of ptOpenAiChat: chatCompletionsEndpoint(override)
  else: override

func providerDefaultModelFor*(id: string): string =
  ## Default model id for a provider, from the descriptor table.
  descriptorOr(id).defaultModel

proc makeFn[A](a: A): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    a.complete(req)

proc fallbackOnError*(primary: CompleteFn; fallback: CompleteFn): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    let primaryResp = primary(req)
    if primaryResp.isOk or fallback == nil:
      return primaryResp
    fallback(req)

func stripProviderPrefix(model: string): string =
  if model.startsWith("opencode/"): model["opencode/".len .. ^1]
  elif model.startsWith("opencode-go/"): model["opencode-go/".len .. ^1]
  elif model.startsWith("zen/"): model["zen/".len .. ^1]
  elif model.startsWith("opencode-zen/"): model["opencode-zen/".len .. ^1]
  else: model

# ── Env-aware compat profiles ─────────────────────────────────────────────────
# `CompatProfileFn` is a top-level nimcall proc, so the descriptor's
# `baseUrlEnv` override is read per call instead of being captured.

proc nvidiaProfileFromEnv(): CompatProfile {.gcsafe, nimcall.} =
  nvidiaCompatProfileAt(providerEndpointFor("nvidia"))

proc alibabaProfileFromEnv(): CompatProfile {.gcsafe, nimcall.} =
  alibabaCompatProfileAt(providerEndpointFor("alibaba"))

proc fireworksProfileFromEnv(): CompatProfile {.gcsafe, nimcall.} =
  fireworksCompatProfileAt(providerEndpointFor("fireworks"))

proc buildProviderBundle*(spec: ProviderSpec; http: HttpRuntimePort
                         ): ProviderBundle {.gcsafe.} =
  ## `http` is forwarded only to the compat branches (NVIDIA, Alibaba,
  ## Fireworks). An empty port means production: those branches keep
  ## `newHttpClient`, while a test injects a fake port and observes the request
  ## the bundle actually sends instead of reading the builder source.
  let descriptor = descriptorOr(spec.providerName)
  let canonicalId =
    if providerDescriptor(spec.providerName).isSome: descriptor.id
    else: ""  # unknown provider: keep the zhipu-only fallback, no Anthropic retry
  case canonicalId
  of "openrouter":
    let adapter = newOpenRouterAdapter(spec.apiKey, model = spec.modelName)
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "anthropic":
    let adapter = newAnthropicAdapter(spec.apiKey, model = spec.modelName)
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "zai-anthropic":
    let adapter = newAnthropicAdapter(
      spec.apiKey,
      model = spec.modelName,
      baseUrl = providerEndpointFor("zai-anthropic"),
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "gemini":
    ProviderBundle(
      completeFn: makeFn(newGeminiAdapter(spec.apiKey, model = spec.modelName))
    )
  of "minimax":
    ProviderBundle(
      completeFn: makeFn(newMiniMaxAdapter(spec.apiKey, model = spec.modelName))
    )
  of "zai":
    let primary = makeFn(newZaiAdapter(spec.apiKey, model = spec.modelName))
    let compatible = makeFn(newAnthropicAdapter(
      spec.apiKey,
      model = spec.modelName,
      baseUrl = providerEndpointFor("zai-anthropic"),
    ))
    ProviderBundle(
      completeFn: fallbackOnError(primary, compatible)
    )
  of "zai-coding":
    let primary = makeFn(newZaiCodingAdapter(spec.apiKey, model = spec.modelName))
    let compatible = makeFn(newAnthropicAdapter(
      spec.apiKey,
      model = spec.modelName,
      baseUrl = providerEndpointFor("zai-anthropic"),
    ))
    ProviderBundle(
      completeFn: fallbackOnError(primary, compatible)
    )
  of "ollama":
    ## For Ollama, apiKey field is repurposed as baseUrl override.
    ## Empty → descriptor base URL (standard local Ollama).
    let adapter = newOllamaAdapter(
      model = spec.modelName,
      baseUrl = if spec.apiKey.len > 0: spec.apiKey
                else: providerEndpointFor("ollama"))
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "openai":
    let adapter = newOpenAIAdapter(spec.apiKey, model = spec.modelName)
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "deepseek":
    let adapter = newDeepSeekAdapter(spec.apiKey, model = spec.modelName)
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "groq":
    let adapter = newOpenAIAdapter(
      spec.apiKey,
      model = if spec.modelName.len > 0: spec.modelName
              else: providerDefaultModelFor("groq"),
      endpoint = providerEndpointFor("groq"),
      providerName = "Groq",
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "opencode-go":
    let rawModel = if spec.modelName.len > 0: spec.modelName
                   else: providerDefaultModelFor("opencode-go")
    let adapter = newOpenAIAdapter(
      spec.apiKey,
      model = stripProviderPrefix(rawModel),
      endpoint = providerEndpointFor("opencode-go"),
      providerName = "OpenCode Go",
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "zen":
    let rawModel = if spec.modelName.len > 0: spec.modelName
                   else: providerDefaultModelFor("zen")
    let adapter = newOpenAIAdapter(
      spec.apiKey,
      model = stripProviderPrefix(rawModel),
      endpoint = providerEndpointFor("zen"),
      providerName = "OpenCode Zen",
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "nvidia":
    ## NVIDIA NIM speaks the OpenAI dialect; everything provider-specific is
    ## data in `nvidiaCompatProfile`, so there is no NVIDIA adapter file.
    let adapter = newCompatAdapter(
      spec.apiKey,
      model = if spec.modelName.len > 0: spec.modelName
              else: providerDefaultModelFor("nvidia"),
      providerName = "NVIDIA",
      profileFn = nvidiaProfileFromEnv,
      http = http,
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "alibaba":
    ## DashScope speaks the OpenAI dialect under `compatible-mode`; everything
    ## provider-specific is data in `alibabaCompatProfile`, so there is no
    ## Alibaba adapter file.
    let adapter = newCompatAdapter(
      spec.apiKey,
      model = if spec.modelName.len > 0: spec.modelName
              else: providerDefaultModelFor("alibaba"),
      providerName = "Alibaba",
      profileFn = alibabaProfileFromEnv,
      http = http,
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "fireworks":
    ## Fireworks speaks the OpenAI dialect; the attribution headers and the
    ## `reasoning_effort: "none"` off-switch are data in
    ## `fireworksCompatProfile`, so there is no Fireworks adapter file.
    let adapter = newCompatAdapter(
      spec.apiKey,
      model = if spec.modelName.len > 0: spec.modelName
              else: providerDefaultModelFor("fireworks"),
      providerName = "Fireworks",
      profileFn = fireworksProfileFromEnv,
      http = http,
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  else:
    ProviderBundle(
      completeFn: makeFn(newZhipuAdapter(spec.apiKey, model = spec.modelName))
    )

proc buildProviderBundle*(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
  ## The production entry point. Kept as a real one-argument overload (not a
  ## default parameter) so the proc still converts to `ProviderRuntimeBuilder`
  ## where the builder is passed as a value.
  buildProviderBundle(spec, HttpRuntimePort())
