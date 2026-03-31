## ZenAdapter — Multi-protocol gateway for LLM providers.
##
## Maps opencode/<provider>/<model> IDs to specific adapter implementations.
## This allows the system to use a single "provider" key while switching
## backend protocols dynamically.

import std/[strutils, json]
import ../../core/pipeops
import ../../domain/message
import ../../ports/provider
import ./openai, ./anthropic, ./gemini, ./deepseek, ./openrouter, ./minimax, ./zhipu, ./ollama

type
  ZenProviderKind* = enum
    zpkOpenAI
    zpkAnthropic
    zpkGemini
    zpkDeepSeek
    zpkOpenRouter
    zpkMiniMax
    zpkZhipu
    zpkOllama
    zpkUnknown

  ZenAdapter* = object
    apiKey*:   string
    model*:    string
    kind:      ZenProviderKind
    realModel: string

# ── Routing Logic ─────────────────────────────────────────────────────────────

proc parseZenModel*(modelId: string): (ZenProviderKind, string) =
  ## Parses "opencode/openai/gpt-4o" -> (zpkOpenAI, "gpt-4o")
  if not modelId.startsWith("opencode/"):
    return (zpkUnknown, modelId)
  
  let parts = modelId.split("/", 2)
  if parts.len < 3:
    return (zpkUnknown, modelId)
  
  let provStr = parts[1].toLowerAscii()
  let modelStr = parts[2]
  
  let kind = case provStr
    of "openai":     zpkOpenAI
    of "anthropic":  zpkAnthropic
    of "gemini":     zpkGemini
    of "deepseek":   zpkDeepSeek
    of "openrouter": zpkOpenRouter
    of "minimax":    zpkMiniMax
    of "zhipu":      zpkZhipu
    of "ollama":     zpkOllama
    else:            zpkUnknown
  
  (kind, modelStr)

# ── Concept Conformance ───────────────────────────────────────────────────────

proc caps*(a: ZenAdapter): ProviderCaps =
  case a.kind
  of zpkOpenAI:     newOpenAIAdapter(a.apiKey, a.realModel).caps()
  of zpkAnthropic:  newAnthropicAdapter(a.apiKey, a.realModel).caps()
  of zpkGemini:     newGeminiAdapter(a.apiKey, a.realModel).caps()
  of zpkDeepSeek:   newDeepSeekAdapter(a.apiKey, a.realModel).caps()
  of zpkOpenRouter: newOpenRouterAdapter(a.apiKey, a.realModel).caps()
  of zpkMiniMax:    newMiniMaxAdapter(a.apiKey, a.realModel).caps()
  of zpkZhipu:      newZhipuAdapter(a.apiKey, a.realModel).caps()
  of zpkOllama:     newOllamaAdapter(a.realModel).caps()
  else:             ProviderCaps(name: "unknown")

proc complete*(a: ZenAdapter; req: CompletionRequest): Result[CompletionResponse, string] =
  case a.kind
  of zpkOpenAI:     newOpenAIAdapter(a.apiKey, a.realModel).complete(req)
  of zpkAnthropic:  newAnthropicAdapter(a.apiKey, a.realModel).complete(req)
  of zpkGemini:     newGeminiAdapter(a.apiKey, a.realModel).complete(req)
  of zpkDeepSeek:   newDeepSeekAdapter(a.apiKey, a.realModel).complete(req)
  of zpkOpenRouter: newOpenRouterAdapter(a.apiKey, a.realModel).complete(req)
  of zpkMiniMax:    newMiniMaxAdapter(a.apiKey, a.realModel).complete(req)
  of zpkZhipu:      newZhipuAdapter(a.apiKey, a.realModel).complete(req)
  of zpkOllama:     newOllamaAdapter(a.realModel).complete(req)
  else:             err("ZenAdapter: unknown provider kind for model " & a.model)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newZenAdapter*(apiKey, modelId: string): ZenAdapter =
  let (kind, realModel) = parseZenModel(modelId)
  ZenAdapter(
    apiKey: apiKey,
    model: modelId,
    kind: kind,
    realModel: realModel
  )
