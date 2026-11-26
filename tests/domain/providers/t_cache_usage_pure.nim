## Prompt cache usage (E8.3): each dialect reports cached tokens its own way;
## inputTokens is always the whole prompt, cacheRead and cacheWrite the
## parts served from and written to the cache.

import std/[json, unittest]
import donkey/domain/providers/cache_usage_pure

proc runTests*() =
  suite "cache usage by dialect":

    test "Anthropic: input_tokens is only the uncached rest":
      let u = anthropicUsage(%* {"input_tokens": 40, "cache_creation_input_tokens": 1000,
                                 "cache_read_input_tokens": 5000, "output_tokens": 9})
      check u == CacheUsage(inputTokens: 6040, cacheRead: 5000, cacheWrite: 1000)

    test "Anthropic without caching":
      check anthropicUsage(%* {"input_tokens": 40}) == CacheUsage(inputTokens: 40)

    test "OpenAI and compatibles: cached_tokens inside prompt_tokens":
      let u = openAiUsage(%* {"prompt_tokens": 3000,
                              "prompt_tokens_details": {"cached_tokens": 2048}})
      check u == CacheUsage(inputTokens: 3000, cacheRead: 2048)

    test "OpenRouter also reports what it wrote":
      let u = openAiUsage(%* {"prompt_tokens": 3000, "prompt_tokens_details":
                              {"cached_tokens": 0, "cache_write_tokens": 2900}})
      check u == CacheUsage(inputTokens: 3000, cacheWrite: 2900)

    test "DeepSeek: prompt_cache_hit_tokens":
      let u = openAiUsage(%* {"prompt_tokens": 3000, "prompt_cache_hit_tokens": 2500,
                              "prompt_cache_miss_tokens": 500})
      check u == CacheUsage(inputTokens: 3000, cacheRead: 2500)

    test "Gemini: cachedContentTokenCount inside promptTokenCount":
      let u = geminiUsage(%* {"promptTokenCount": 3000, "cachedContentTokenCount": 1024})
      check u == CacheUsage(inputTokens: 3000, cacheRead: 1024)

    test "Bedrock Converse: inputTokens is only the uncached rest":
      let u = bedrockUsage(%* {"inputTokens": 40, "cacheReadInputTokens": 5000,
                               "cacheWriteInputTokens": 1000})
      check u == CacheUsage(inputTokens: 6040, cacheRead: 5000, cacheWrite: 1000)

    test "missing or malformed usage is zero":
      check anthropicUsage(nil) == CacheUsage()
      check openAiUsage(%* "x") == CacheUsage()
      check geminiUsage(newJNull()) == CacheUsage()

when isMainModule:
  runTests()
