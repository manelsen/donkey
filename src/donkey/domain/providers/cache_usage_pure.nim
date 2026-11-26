## Prompt cache usage (E8.3), read the way each dialect reports it.
##
## `inputTokens` is always the whole prompt; `cacheRead` and `cacheWrite`
## are the parts served from and written to the provider's cache. Anthropic
## and Bedrock count the uncached rest only, so their total is the sum;
## OpenAI, its compatibles (DeepSeek, OpenRouter, Zhipu…) and Gemini count
## the cached part inside the prompt total.

import std/json

type CacheUsage* = object
  inputTokens*: int
  cacheRead*:   int
  cacheWrite*:  int

func num(n: JsonNode; key: string): int =
  if n.isNil or n.kind != JObject: return 0
  let v = n.getOrDefault(key)
  if v.isNil or v.kind != JInt: 0 else: v.getInt

func anthropicUsage*(usage: JsonNode): CacheUsage =
  let read = num(usage, "cache_read_input_tokens")
  let write = num(usage, "cache_creation_input_tokens")
  CacheUsage(inputTokens: num(usage, "input_tokens") + read + write,
             cacheRead: read, cacheWrite: write)

func openAiUsage*(usage: JsonNode): CacheUsage =
  let details = if usage.isNil or usage.kind != JObject: nil
                else: usage.getOrDefault("prompt_tokens_details")
  let total = num(usage, "prompt_tokens")
  ## Never more than the prompt, whichever field a provider fills.
  let read = min(total, max(num(details, "cached_tokens"), num(usage, "prompt_cache_hit_tokens")))
  CacheUsage(inputTokens: total, cacheRead: read,
             cacheWrite: num(details, "cache_write_tokens"))

func geminiUsage*(usageMetadata: JsonNode): CacheUsage =
  CacheUsage(inputTokens: num(usageMetadata, "promptTokenCount"),
             cacheRead: num(usageMetadata, "cachedContentTokenCount"))

func bedrockUsage*(usage: JsonNode): CacheUsage =
  let read = num(usage, "cacheReadInputTokens")
  let write = num(usage, "cacheWriteInputTokens")
  CacheUsage(inputTokens: num(usage, "inputTokens") + read + write,
             cacheRead: read, cacheWrite: write)
