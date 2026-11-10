## Concrete provider runtime builder for session bootstrap wiring.

import std/strutils
import ../../domain/message
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

const
  ZaiAnthropicBaseUrl = "https://api.z.ai/api/anthropic"
  GroqEndpoint        = "https://api.groq.com/openai/v1/chat/completions"
  OpenCodeGoEndpoint  = "https://opencode.ai/zen/go/v1/chat/completions"
  ZenEndpoint         = "https://opencode.ai/zen/v1/chat/completions"

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
  case spec.providerName
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
      baseUrl = ZaiAnthropicBaseUrl,
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
      baseUrl = ZaiAnthropicBaseUrl,
    ))
    ProviderBundle(
      completeFn: fallbackOnError(primary, compatible)
    )
  of "zai-coding":
    let primary = makeFn(newZaiCodingAdapter(spec.apiKey, model = spec.modelName))
    let compatible = makeFn(newAnthropicAdapter(
      spec.apiKey,
      model = spec.modelName,
      baseUrl = ZaiAnthropicBaseUrl,
    ))
    ProviderBundle(
      completeFn: fallbackOnError(primary, compatible)
    )
  of "ollama":
    ## For Ollama, apiKey field is repurposed as baseUrl override.
    ## Empty → http://localhost:11434 (standard local Ollama).
    let adapter = newOllamaAdapter(model = spec.modelName,
                                   baseUrl = if spec.apiKey.len > 0: spec.apiKey
                                             else: OllamaDefaultBaseUrl)
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
      model = if spec.modelName.len > 0: spec.modelName else: GroqDefaultModel,
      endpoint = GroqEndpoint,
      providerName = "Groq",
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "opencode-go", "opencode":
    let rawModel = if spec.modelName.len > 0: spec.modelName else: OpenCodeGoDefaultModel
    let adapter = newOpenAIAdapter(
      spec.apiKey,
      model = stripProviderPrefix(rawModel),
      endpoint = OpenCodeGoEndpoint,
      providerName = "OpenCode Go",
    )
    ProviderBundle(
      completeFn: makeFn(adapter),
      streamFn:   adapter.makeStreamFn(),
    )
  of "zen", "opencode-zen":
    let rawModel = if spec.modelName.len > 0: spec.modelName else: ZenDefaultModel
    let adapter = newOpenAIAdapter(
      spec.apiKey,
      model = stripProviderPrefix(rawModel),
      endpoint = ZenEndpoint,
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
