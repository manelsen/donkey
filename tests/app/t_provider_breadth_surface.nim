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
import donkey/app/credential_runtime
import donkey/config/environment
import donkey/core/providers/provider_defaults
import donkey/core/providers/smart_routing
import donkey/domain/providers/descriptors

const
  NvidiaEnv = "NVIDIA_API_KEY"
  AlibabaEnv = "DASHSCOPE_API_KEY"

proc withEnv(name, value: string; body: proc()) =
  ## Run `body` with `name` set to `value` ("" clears it) in the installed
  ## credentials, and clear it afterwards.
  setCredentialForTest(name, value)
  try:
    body()
  finally:
    setCredentialForTest(name, "")

proc withoutEnv(name: string; body: proc()) =
  withEnv(name, "", body)

proc has(values: seq[string]; wanted: string): bool =
  for value in values:
    if value == wanted:
      return true

proc runTests*() =
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
          let availability = detectProviderAvailability()
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
              check not detectProviderAvailability().nvidia
              check not detectProviderAvailability().alibaba

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
      check providerKeyFromEnv(environmentOf({"ZHIPU_API_KEY": "zk-alt"}),
                               "zai-coding") == "zk-alt"

    test "setup detects the plural *_KEYS form":
      check providerKeyFromEnv(environmentOf({"OPENAI_API_KEYS": "sk-first,sk-second"}),
                               "openai") == "sk-first"

    test "an endpoint-configured provider never yields an API key":
      check providerKeyFromEnv(environmentOf({"OLLAMA_BASE_URL": "http://localhost:11434"}),
                               "ollama") == ""

  suite "fireworks breadth — descriptor to availability":

    const FireworksEnv = "FIREWORKS_API_KEY"

    test "Fireworks identity comes from the descriptor table":
      let descriptor = descriptorOr("fireworks")
      check descriptor.id == "fireworks"
      check descriptor.envNames == @[FireworksEnv]
      check descriptor.defaultModel == DefaultModelFireworks
      check descriptor.transport == ptOpenAiChat
      check providerDescriptor("fw").get().id == "fireworks"
      check providerDescriptor("fireworks-ai").get().id == "fireworks"

    test "an empty model resolves to the descriptor default":
      check defaultModelForProvider("fireworks") == DefaultModelFireworks
      let spec = buildProviderSpec(
        ProviderPrefs(providerName: "fireworks", modelName: ""))
      check spec.modelName == DefaultModelFireworks
      check spec.modelName != "glm-4.7"

    test "the daemon status surface lists Fireworks when its env key exists":
      withEnv(FireworksEnv, "fw-test"):
        let availability = detectProviderAvailability()
        check availability.fireworks
        check availableProviderNames(availability).has("fireworks")
        check detectProviderAvailability().fireworks

    test "unset env leaves Fireworks unavailable":
      withoutEnv(FireworksEnv):
        withoutEnv("FIREWORKS_API_KEYS"):
          check not detectProviderAvailability().fireworks
          check not detectProviderAvailability().fireworks

  suite "mistral breadth — descriptor to availability":

    const MistralEnv = "MISTRAL_API_KEY"

    test "Mistral identity comes from the descriptor table":
      let descriptor = descriptorOr("mistral")
      check descriptor.id == "mistral"
      check descriptor.envNames == @[MistralEnv]
      check descriptor.defaultModel == DefaultModelMistral
      check descriptor.transport == ptOpenAiChat
      check providerDescriptor("mistralai").get().id == "mistral"
      check providerDescriptor("mistral-ai").get().id == "mistral"

    test "an empty model resolves to the descriptor default":
      let spec = buildProviderSpec(
        ProviderPrefs(providerName: "mistral", modelName: ""))
      check spec.modelName == DefaultModelMistral

    test "the daemon status surface lists Mistral when its env key exists":
      withEnv(MistralEnv, "ms-test"):
        let availability = detectProviderAvailability()
        check availability.mistral
        check availableProviderNames(availability).has("mistral")

    test "unset env leaves Mistral unavailable":
      withoutEnv(MistralEnv):
        withoutEnv("MISTRAL_API_KEYS"):
          check not detectProviderAvailability().mistral

  suite "bedrock breadth — two credentials, one region":

    test "a Bedrock API key makes it available":
      withEnv("AWS_BEARER_TOKEN_BEDROCK", "bdk"):
        check detectProviderAvailability().bedrock
        check availableProviderNames(detectProviderAvailability()).has("bedrock")

    test "IAM credentials make it available, and reach the spec":
      withEnv("AWS_ACCESS_KEY_ID", "AKID"):
        withEnv("AWS_SECRET_ACCESS_KEY", "secret"):
          withEnv("AWS_SESSION_TOKEN", "tok"):
            check detectProviderAvailability().bedrock
            let spec = buildProviderSpec(ProviderPrefs(providerName: "bedrock"))
            check spec.awsAccessKeyId == "AKID"
            check spec.awsSecretAccessKey == "secret"
            check spec.awsSessionToken == "tok"
            check spec.modelName == DefaultModelBedrock

    test "an access key without its secret is not a credential":
      withEnv("AWS_ACCESS_KEY_ID", "AKID"):
        check not detectProviderAvailability().bedrock

    test "the endpoint follows AWS_REGION, then AWS_DEFAULT_REGION, then us-east-1":
      check buildProviderSpec(ProviderPrefs(providerName: "bedrock")).baseUrl ==
        "https://bedrock-runtime.us-east-1.amazonaws.com"
      withEnv("AWS_DEFAULT_REGION", "sa-east-1"):
        check buildProviderSpec(ProviderPrefs(providerName: "bedrock")).baseUrl ==
          "https://bedrock-runtime.sa-east-1.amazonaws.com"
        withEnv("AWS_REGION", "eu-west-1"):
          check buildProviderSpec(ProviderPrefs(providerName: "bedrock")).baseUrl ==
            "https://bedrock-runtime.eu-west-1.amazonaws.com"

    test "IAM credentials never leak into another provider's spec":
      withEnv("AWS_ACCESS_KEY_ID", "AKID"):
        check buildProviderSpec(ProviderPrefs(providerName: "openai")).awsAccessKeyId == ""

when isMainModule:
  runTests()
