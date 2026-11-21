## Provider descriptor table tests: identity, aliases and transports.

import std/[options, sets, unittest]
import donkey/domain/providers/descriptors

proc runTests*() =
  suite "provider descriptors":

    test "every provider used by the runtime has a descriptor":
      for id in ["openrouter", "openai", "deepseek", "ollama", "groq",
                 "opencode-go", "zen", "anthropic", "zai-anthropic", "gemini",
                 "minimax", "zai", "zai-coding"]:
        check providerDescriptor(id).isSome

    test "aliases resolve to the canonical id":
      check providerDescriptor("opencode").get().id == "opencode-go"
      check providerDescriptor("opencode-zen").get().id == "zen"

    test "an unknown provider has no descriptor":
      check providerDescriptor("invented").isNone
      check providerDescriptor("").isNone

    test "the default descriptor is zai-coding":
      check defaultProviderDescriptor().id == "zai-coding"
      check descriptorOr("invented").id == "zai-coding"

    test "ids and aliases are unique":
      var seen: HashSet[string]
      for d in providerDescriptors():
        check d.id notin seen
        seen.incl d.id
        for alias in d.aliases:
          check alias notin seen
          seen.incl alias

    test "the transport family is explicit per provider":
      check providerDescriptor("openrouter").get().transport == ptOpenAiChat
      check providerDescriptor("deepseek").get().transport == ptOpenAiChat
      check providerDescriptor("anthropic").get().transport == ptAnthropicMessages
      check providerDescriptor("zai-anthropic").get().transport == ptAnthropicMessages
      check providerDescriptor("gemini").get().transport == ptGemini
      check providerDescriptor("ollama").get().transport == ptOllama
      check providerDescriptor("zen").get().transport == ptMulti

    test "the descriptor carries env names and a default model":
      let openrouter = providerDescriptor("openrouter").get()
      check openrouter.envNames == @["OPENROUTER_API_KEY"]
      check openrouter.defaultModel == "openai/gpt-6.1-sol"
      check openrouter.aggregator

      let zaiAnthropic = providerDescriptor("zai-anthropic").get()
      check zaiAnthropic.envNames == @[
        "ZAI_ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
        "ZAI_CODING_API_KEY", "ZAI_API_KEY", "ZHIPU_API_KEY"]

    test "ollama is configured by an endpoint, not a credential":
      let ollama = providerDescriptor("ollama").get()
      check ollama.authType == atNone
      check ollama.envNames == @["OLLAMA_BASE_URL"]

when isMainModule:
  runTests()
