## The README names every provider the descriptor table routes to (audit of
## 26/11, finding 5): it once said OpenAI, DeepSeek and Ollama were mapped to
## ZAI after each had its own adapter, which misleads an operator about where
## the data goes.

import std/[strutils, unittest]
import donkey/domain/providers/descriptors

const
  ## The table's ids as the README writes them; variants of one provider
  ## (its Anthropic-compatible or coding endpoint) are that provider.
  DisplayName = {"openrouter": "OpenRouter", "openai": "OpenAI", "deepseek": "DeepSeek",
                 "ollama": "Ollama", "groq": "Groq", "opencode-go": "OpenCode Go",
                 "zen": "Zen", "anthropic": "Anthropic", "zai-anthropic": "ZAI",
                 "gemini": "Gemini", "minimax": "MiniMax", "zai": "ZAI",
                 "zai-coding": "ZAI", "nvidia": "NVIDIA", "alibaba": "Alibaba",
                 "fireworks": "Fireworks", "mistral": "Mistral", "azure": "Azure OpenAI",
                 "bedrock": "Bedrock"}

proc runTests*() =
  suite "README providers":
    test "every routed provider is named, and none is said to be mapped to another":
      let readme = readFile("README.md")
      for d in ProviderDescriptors:
        var name = ""
        for (id, display) in DisplayName:
          if id == d.id: name = display
        checkpoint("descriptor " & d.id)
        check name.len > 0                 ## a new descriptor needs its README name here
        check name in readme
      check "mapped to ZAI" notin readme

when isMainModule:
  runTests()
