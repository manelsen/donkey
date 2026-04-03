## Concrete provider runtime builder for session bootstrap wiring.

import ../../domain/message
import ../../core/pipeops
import ../../ports/provider
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

proc makeFn[A](a: A): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    a.complete(req)

proc fallbackOnError*(primary: CompleteFn; fallback: CompleteFn): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    let primaryResp = primary(req)
    if primaryResp.isOk or fallback == nil:
      return primaryResp
    fallback(req)

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
  else:
    ProviderBundle(
      completeFn: makeFn(newZhipuAdapter(spec.apiKey, model = spec.modelName))
    )
