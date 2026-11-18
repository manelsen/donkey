## Characterization for the descriptor-backed factory helpers in
## runtime_builder. They must return exactly the metadata the descriptor table
## already declares, so the builder and the catalog stop repeating it.

import std/unittest
import donkey/adapters/provider/runtime_builder
import donkey/domain/providers/descriptors

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
]

suite "descriptor factory":

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
