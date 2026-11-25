## Which providers stream with tool calls: a descriptor field, checked
## against what the runtime builder really builds, so the two cannot drift.

import std/unittest
import donkey/adapters/provider/runtime_builder
import donkey/domain/providers/descriptors
import donkey/ports/http
import donkey/ports/provider

proc runTests*() =
  suite "stream capability":

    test "the streams that assemble tool calls are marked":
      for id in ["openrouter", "anthropic", "zai-anthropic", "openai", "deepseek",
                 "groq", "opencode-go", "zen", "nvidia", "alibaba", "mistral",
                 "fireworks"]:
        check streamsToolCalls(id)

    test "providers without such a stream are not":
      for id in ["gemini", "minimax", "zai", "zai-coding", "bedrock", "ollama",
                 "nonexistent"]:
        check not streamsToolCalls(id)

    test "a provider marked as streaming tool calls has a stream":
      for d in providerDescriptors():
        if streamsToolCalls(d.id):
          let bundle = buildProviderBundle(
            ProviderSpec(providerName: d.id, modelName: d.defaultModel, apiKey: "k"),
            HttpRuntimePort())
          check bundle.streamFn != nil

    test "aliases resolve to their provider":
      for d in providerDescriptors():
        for alias in d.aliases:
          check streamsToolCalls(alias) == streamsToolCalls(d.id)

when isMainModule:
  runTests()
