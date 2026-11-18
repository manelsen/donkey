## t_alibaba.nim — Alibaba DashScope end-to-end wiring (US-003, audit F1/F6).
##
## The bundle must come from the generic `CompatAdapter` through the descriptor,
## not from the Zhipu fallback at the bottom of `runtime_builder`. No network:
## the bundle is built, never called.

import std/[os, strutils, unittest]
import donkey/adapters/provider/compat_adapter
import donkey/adapters/provider/runtime_builder
import donkey/core/providers/provider_defaults
import donkey/domain/providers/descriptors
import donkey/domain/providers/model_limits
import donkey/domain/providers/profile_alibaba
import donkey/ports/provider

suite "alibaba provider bundle":

  test "the runtime builder wires the compat adapter, not the Zhipu fallback":
    let bundle = buildProviderBundle(
      ProviderSpec(providerName: "alibaba", apiKey: "dashscope-test"))
    check bundle.completeFn != nil
    check bundle.streamFn != nil   ## the Zhipu fallback has no streamFn

  test "the alibaba branch selects alibabaCompatProfile, not the NVIDIA one":
    ## The bundle is opaque, so the branch's profile choice is pinned at the
    ## call site. Deleting `of "alibaba":` fails the streamFn test above;
    ## swapping the profile removes this line.
    const source = staticRead(
      "../../src/donkey/adapters/provider/runtime_builder.nim")
    check "of \"alibaba\":" in source
    check "profileFn = alibabaProfileFromEnv" in source
    check "alibabaCompatProfileAt(providerEndpointFor(\"alibaba\"))" in source

  test "the descriptor supplies the default model":
    check providerDefaultModelFor("alibaba") == DefaultModelAlibaba
    check descriptorOr("alibaba").defaultModel == DefaultModelAlibaba
    check DefaultModelAlibaba == "qwen3.8-max"

  test "caps advertise streaming and tools with an unknown context":
    let adapter = newCompatAdapter(
      "dashscope-test", model = DefaultModelAlibaba, providerName = "Alibaba",
      profileFn = alibabaCompatProfile)
    let c = adapter.caps()
    check c.name == "alibaba/" & DefaultModelAlibaba
    check c.streaming
    check c.toolCalling
    check c.maxContextTokens == 0
    check c.requiresUserFirst == false
    check modelLimits("alibaba", DefaultModelAlibaba).source == mlsUnknown

  test "the profile endpoint is the descriptor endpoint":
    let had = existsEnv("DASHSCOPE_BASE_URL")
    let previous = getEnv("DASHSCOPE_BASE_URL")
    delEnv("DASHSCOPE_BASE_URL")
    defer:
      if had: putEnv("DASHSCOPE_BASE_URL", previous) else: delEnv("DASHSCOPE_BASE_URL")
    check alibabaCompatProfile().id == "alibaba"
    check alibabaCompatProfile().endpoint == providerEndpointFor("alibaba")
    check alibabaCompatProfile().endpoint == descriptorOr("alibaba").baseUrl
    check alibabaCompatProfile().supportsImages == AlibabaSupportsImages
    check not alibabaCompatProfile().supportsImages
