## Parity tests for buildProviderSpec and availability after the descriptor table.
##
## Every case below is the behaviour the hardcoded `case` had before US-001.

import std/[os, strutils, unittest]
import donkey/app/credential_runtime
import donkey/app/session_bootstrap
import donkey/core/pipeops
import donkey/domain/providers/descriptors
import donkey/ports/provider

const SingleKeys = [
  "OPENROUTER_API_KEY", "OPENAI_API_KEY", "DEEPSEEK_API_KEY",
  "GROQ_API_KEY", "OPENCODE_API_KEY", "OPENCODE_GO_API_KEY", "ZEN_API_KEY",
  "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ZAI_ANTHROPIC_API_KEY",
  "ZAI_CODING_API_KEY", "ZAI_API_KEY", "ZHIPU_API_KEY", "GEMINI_API_KEY",
  "MINIMAX_API_KEY", "OLLAMA_BASE_URL",
]

proc clearEnv() =
  resetCredentialPools()
  for name in SingleKeys:
    delEnv(name)
    delEnv(poolEnvName(name))

proc specFor(name: string; model = ""): ProviderSpec =
  resetCredentialPools()
  buildProviderSpec(ProviderPrefs(providerName: name, modelName: model))

proc runTests*() =
  suite "buildProviderSpec parity":

    setup: clearEnv()
    teardown: clearEnv()

    test "each provider keeps its name, default model and key env":
      type SpecCase = tuple[provider, envName, expectedName, expectedModel: string]
      let cases: seq[SpecCase] = @[
        (provider: "openrouter", envName: "OPENROUTER_API_KEY", expectedName: "openrouter", expectedModel: "openai/gpt-6.1-sol"),
        (provider: "openai", envName: "OPENAI_API_KEY", expectedName: "openai", expectedModel: "gpt-6.1-sol"),
        (provider: "deepseek", envName: "DEEPSEEK_API_KEY", expectedName: "deepseek", expectedModel: "deepseek-4.1-flash"),
        (provider: "groq", envName: "GROQ_API_KEY", expectedName: "groq", expectedModel: "llama-3.3-70b-versatile"),
        (provider: "anthropic", envName: "ANTHROPIC_API_KEY", expectedName: "anthropic", expectedModel: "claude-sonnet-5-5"),
        (provider: "gemini", envName: "GEMINI_API_KEY", expectedName: "gemini", expectedModel: "gemini-3.8-flash"),
        (provider: "minimax", envName: "MINIMAX_API_KEY", expectedName: "minimax", expectedModel: "MiniMax-M2"),
        (provider: "zai", envName: "ZAI_API_KEY", expectedName: "zai", expectedModel: "glm-4.7"),
        (provider: "zai-coding", envName: "ZAI_CODING_API_KEY", expectedName: "zai-coding", expectedModel: "glm-4.7"),
      ]
      for c in cases:
        putEnv(c.envName, "key-" & c.provider)
        let spec = specFor(c.provider)
        check spec.providerName == c.expectedName
        check spec.modelName == c.expectedModel
        check spec.apiKey == "key-" & c.provider

    test "an explicit model overrides the descriptor default":
      putEnv("OPENAI_API_KEY", "k")
      let spec = specFor("openai", model = "gpt-custom")
      check spec.modelName == "gpt-custom"

    test "opencode and opencode-go resolve to the same provider":
      putEnv("OPENCODE_API_KEY", "k")
      let spec = specFor("opencode")
      check spec.providerName == "opencode-go"
      check spec.modelName == "opencode/deepseek-4.1-flash"
      check spec.apiKey == "k"

    test "zen alias keeps the zen identity":
      putEnv("ZEN_API_KEY", "k")
      let spec = specFor("opencode-zen")
      check spec.providerName == "zen"
      check spec.modelName == "zen/deepseek-4.1-flash"
      check spec.apiKey == "k"

    test "ollama uses OLLAMA_BASE_URL as its endpoint":
      putEnv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
      let spec = specFor("ollama")
      check spec.providerName == "ollama"
      check spec.modelName == "llama3.3"
      check spec.apiKey == "http://127.0.0.1:11434"

    test "zai-anthropic keeps the documented fallback order":
      putEnv("ANTHROPIC_AUTH_TOKEN", "from-anthropic-token")
      putEnv("ZAI_CODING_API_KEY", "from-coding")
      let spec = specFor("zai-anthropic")
      check spec.apiKey == "from-anthropic-token"
      check spec.modelName == "glm-4.7"

    test "zai-anthropic falls through to ZHIPU_API_KEY":
      putEnv("ZHIPU_API_KEY", "from-zhipu")
      check specFor("zai-anthropic").apiKey == "from-zhipu"

    test "an unknown provider keeps the zai-coding fallback":
      putEnv("ZAI_CODING_API_KEY", "k")
      let spec = specFor("invented")
      check spec.providerName == "zai-coding"
      check spec.modelName == "glm-4.7"
      check spec.apiKey == "k"

    test "no key configured yields an empty apiKey":
      check specFor("openai").apiKey == ""

  suite "provider availability parity":

    setup: clearEnv()
    teardown: clearEnv()

    test "the plural env alone marks a provider available":
      putEnv("OPENAI_API_KEYS", "a,b")
      check detectProviderAvailability().openai

    test "each provider lights its own field":
      putEnv("OPENROUTER_API_KEY", "k")
      check detectProviderAvailability().openrouter
      clearEnv()

      putEnv("OPENCODE_API_KEY", "k")
      let av = detectProviderAvailability()
      check av.opencodeGo
      check av.zen
      clearEnv()

      putEnv("ZHIPU_API_KEY", "k")
      let zai = detectProviderAvailability()
      check zai.zaiCoding
      check zai.zaiAnthropic

    test "an empty environment leaves every provider unavailable":
      let av = detectProviderAvailability()
      check not av.openrouter
      check not av.anthropic
      check not av.openai
      check not av.deepseek
      check not av.zaiAnthropic
      check not av.gemini
      check not av.minimax
      check not av.zai
      check not av.zaiCoding
      check not av.groq
      check not av.ollama
      check not av.opencodeGo
      check not av.zen

when isMainModule:
  runTests()
