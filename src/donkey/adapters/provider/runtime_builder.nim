## Concrete provider runtime builder for session bootstrap wiring.

import ../../domain/message
import ../../core/pipeops
import ../../ports/provider
import zhipu
import openrouter
import anthropic
import gemini
import minimax

proc makeFn[A](a: A): CompleteFn =
  result = proc(req: CompletionRequest): Result[CompletionResponse, string] =
    a.complete(req)

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
  of "gemini":
    ProviderBundle(
      completeFn: makeFn(newGeminiAdapter(spec.apiKey, model = spec.modelName))
    )
  of "minimax":
    ProviderBundle(
      completeFn: makeFn(newMiniMaxAdapter(spec.apiKey, model = spec.modelName))
    )
  else:
    ProviderBundle(
      completeFn: makeFn(newZhipuAdapter(spec.apiKey, model = spec.modelName))
    )
