## t_provider_breadth_surface.nim — NVIDIA and Alibaba reach every provider
## surface without a private list (audit B1/B2 + F2).
##
## Descriptor identity comes first (id + env), then the surfaces: daemon status,
## the channel status line's env detection, setup's env file and default model
## suggestion. No network.

import std/[options, os, strutils, unittest]
import donkey/adapters/channel/common_runtime
import donkey/app/session_bootstrap
import donkey/app/setup_wizard
import donkey/core/providers/provider_defaults
import donkey/core/providers/smart_routing
import donkey/domain/providers/descriptors

const
  NvidiaEnv = "NVIDIA_API_KEY"
  AlibabaEnv = "DASHSCOPE_API_KEY"

proc setOrClear(name, value: string) =
  if value.len > 0: putEnv(name, value) else: delEnv(name)

proc withEnv(name, value: string; body: proc()) =
  ## Run `body` with `name` set to `value` ("" clears it). Restores the old
  ## value, set or unset.
  let had = existsEnv(name)
  let previous = getEnv(name)
  setOrClear(name, value)
  try:
    body()
  finally:
    setOrClear(name, if had: previous else: "")

proc withoutEnv(name: string; body: proc()) =
  withEnv(name, "", body)

proc has(values: seq[string]; wanted: string): bool =
  for value in values:
    if value == wanted:
      return true

suite "nvidia and alibaba breadth — descriptor first":

  test "NVIDIA identity comes from the descriptor table":
    let descriptor = descriptorOr("nvidia")
    check descriptor.id == "nvidia"
    check descriptor.envNames == @[NvidiaEnv]
    check descriptor.baseUrl ==
          "https://integrate.api.nvidia.com/v1/chat/completions"
    check descriptor.baseUrlEnv == "NVIDIA_BASE_URL"
    check descriptor.defaultModel == DefaultModelNvidia
    check descriptor.transport == ptOpenAiChat
    check providerDescriptor("nim").get().id == "nvidia"
    check providerDescriptor("nemotron").isNone   ## PRD: no nemotron alias

  test "Alibaba identity comes from the descriptor table":
    let descriptor = descriptorOr("alibaba")
    check descriptor.id == "alibaba"
    check descriptor.envNames == @[AlibabaEnv]
    check descriptor.baseUrl ==
          "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"
    check descriptor.baseUrlEnv == "DASHSCOPE_BASE_URL"
    check descriptor.defaultModel == DefaultModelAlibaba
    check descriptor.transport == ptOpenAiChat
    check providerDescriptor("dashscope").get().id == "alibaba"
    check providerDescriptor("qwen").isNone

suite "nvidia and alibaba breadth — availability surfaces":

  test "the daemon status surface lists NVIDIA when its env key exists":
    withEnv(NvidiaEnv, "nvapi-test"):
      let availability = detectProviderAvailability()
      check availability.nvidia
      check availableProviderNames(availability).has("nvidia")

  test "the daemon status surface lists Alibaba when its env key exists":
    withEnv(AlibabaEnv, "dashscope-test"):
      let availability = detectProviderAvailability()
      check availability.alibaba
      check availableProviderNames(availability).has("alibaba")

  test "the channel surface derives both from the same env":
    withEnv(NvidiaEnv, "nvapi-test"):
      withEnv(AlibabaEnv, "dashscope-test"):
        let availability = availableProvidersFromEnv()
        check availability.nvidia
        check availability.alibaba

  test "unset env leaves both unavailable":
    withoutEnv(NvidiaEnv):
      withoutEnv("NVIDIA_API_KEYS"):
        withoutEnv(AlibabaEnv):
          withoutEnv("DASHSCOPE_API_KEYS"):
            let availability = detectProviderAvailability()
            check not availability.nvidia
            check not availability.alibaba
            check not availableProvidersFromEnv().nvidia
            check not availableProvidersFromEnv().alibaba

  test "availableProviderNames reports both configured providers":
    let names = availableProviderNames(ProviderAvailability(
      nvidia: true, alibaba: true))
    check names.has("nvidia")
    check names.has("alibaba")

suite "nvidia and alibaba breadth — model resolution (F2)":

  test "an empty model resolves to the descriptor default, never glm-4.7":
    for (provider, expected) in [
        ("nvidia", DefaultModelNvidia), ("alibaba", DefaultModelAlibaba)]:
      check defaultModelForProvider(provider) == expected
      check defaultModelForProvider(provider) != "glm-4.7"
      let spec = buildProviderSpec(
        ProviderPrefs(providerName: provider, modelName: ""))
      check spec.providerName == provider
      check spec.modelName == expected

suite "nvidia and alibaba breadth — setup surface":

  test "setup dedupes an env line shared by two providers":
    ## Selecting OpenCode Go + Zen must not emit OPENCODE_API_KEY twice:
    ## dotenv keeps the first value.
    let env = buildEnvContent(@[("opencode-go", "go-key"), ("zen", "zen-key")], @[])
    check env.count("OPENCODE_API_KEY=") == 1
    check "OPENCODE_API_KEY=go-key" in env
    check "OPENCODE_API_KEY=zen-key" notin env

  test "setup detects a key from any descriptor env name":
    withoutEnv("ZAI_CODING_API_KEY"):
      withoutEnv("ZAI_CODING_API_KEYS"):
        withoutEnv("ZHIPU_API_KEY"):
          withEnv("ZHIPU_API_KEY", "zk-alt"):
            check providerKeyFromEnv("zai-coding") == "zk-alt"

  test "setup detects the plural *_KEYS form":
    withoutEnv("OPENAI_API_KEY"):
      withEnv("OPENAI_API_KEYS", "sk-first,sk-second"):
        check providerKeyFromEnv("openai") == "sk-first"

  test "an endpoint-configured provider never yields an API key":
    check providerKeyFromEnv("ollama") == ""
