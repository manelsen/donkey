## Concrete provider runtime builder for session bootstrap wiring.
##
## Identity comes from the descriptor table: endpoint, default model and
## aliases. Only deviations that are not endpoints stay here: the zai/zai-coding
## Anthropic fallback, Zen's multi-protocol routing, the Groq/OpenCode/Zen
## provider labels, and the model prefix those gateways accept.

import std/[options, strutils]
import ../../domain/message
import ../../domain/providers/descriptors
import ../../core/pipeops
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

func providerEndpointFor*(id: string): string =
  ## Wire URL for a provider, from the descriptor table. Unknown ids fall back
  ## to zai-coding, matching `buildProviderSpec`.
  descriptorOr(id).baseUrl

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

proc buildProviderBundle*(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
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
  else:
    ProviderBundle(
      completeFn: makeFn(newZhipuAdapter(spec.apiKey, model = spec.modelName))
    )
