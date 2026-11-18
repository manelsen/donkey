## t_nvidia.nim — NVIDIA NIM end-to-end wiring (US-001).
##
## The bundle must come from the generic `CompatAdapter` through the descriptor,
## not from the Zhipu fallback at the bottom of `runtime_builder`. No network:
## the bundle is built, never called.

import std/[os, unittest]
import donkey/adapters/provider/compat_adapter
import donkey/adapters/provider/runtime_builder
import donkey/core/providers/provider_defaults
import donkey/core/providers/smart_routing
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_nvidia
import donkey/ports/provider

suite "nvidia provider bundle":

  test "the runtime builder wires the compat adapter, not the Zhipu fallback":
    let bundle = buildProviderBundle(
      ProviderSpec(providerName: "nvidia", apiKey: "nvapi-test"))
    check bundle.completeFn != nil
    check bundle.streamFn != nil   ## the Zhipu fallback has no streamFn

  test "the descriptor supplies the default model":
    check providerDefaultModelFor("nvidia") == DefaultModelNvidia
    check descriptorOr("nvidia").defaultModel == DefaultModelNvidia
    check providerDefaultModelFor("nim") == DefaultModelNvidia
    ## Resolution must never fall back to the generic glm-4.7.
    check defaultModelForProvider("nvidia") == DefaultModelNvidia
    check defaultModelForProvider("nvidia") != "glm-4.7"

  test "the profile endpoint is the descriptor endpoint":
    let had = existsEnv("NVIDIA_BASE_URL")
    let previous = getEnv("NVIDIA_BASE_URL")
    delEnv("NVIDIA_BASE_URL")
    defer:
      if had: putEnv("NVIDIA_BASE_URL", previous) else: delEnv("NVIDIA_BASE_URL")
    check nvidiaCompatProfile().id == "nvidia"
    check nvidiaCompatProfile().endpoint == providerEndpointFor("nvidia")
    check nvidiaCompatProfile().endpoint == descriptorOr("nvidia").baseUrl

  test "caps advertise streaming and tool calling":
    let adapter = newCompatAdapter(
      "nvapi-test", model = DefaultModelNvidia, providerName = "NVIDIA",
      profileFn = nvidiaCompatProfile)
    let c = adapter.caps()
    check c.name == "nvidia/" & DefaultModelNvidia
    check c.streaming
    check c.toolCalling
    check c.nativeTools.len == 0
    check c.maxContextTokens == 0      ## limits arrive with the catalog (US-005)
