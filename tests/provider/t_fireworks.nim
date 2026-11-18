## t_fireworks.nim — Fireworks end-to-end wiring (US-004).
##
## The bundle must come from the generic `CompatAdapter` through the descriptor,
## not from the Zhipu fallback at the bottom of `runtime_builder`. No network:
## the bundle is built, never called.

import std/[strutils, unittest]
import donkey/adapters/provider/compat_adapter
import donkey/adapters/provider/runtime_builder
import donkey/core/pipeops
import donkey/core/providers/provider_defaults
import donkey/domain/providers/descriptors
import donkey/domain/providers/profile_fireworks
import donkey/ports/provider

suite "fireworks provider bundle":

  test "the runtime builder wires the compat adapter, not the Zhipu fallback":
    let bundle = buildProviderBundle(
      ProviderSpec(providerName: "fireworks", apiKey: "fw-test"))
    check bundle.completeFn != nil
    check bundle.streamFn != nil   ## the Zhipu fallback has no streamFn

  test "the alias names reach the same real bundle":
    for name in ["fireworks-ai", "fw"]:
      let bundle = buildProviderBundle(
        ProviderSpec(providerName: name, apiKey: "fw-test"))
      check descriptorOr(name).id == "fireworks"
      check bundle.completeFn != nil
      check bundle.streamFn != nil

  test "the fireworks branch selects fireworksCompatProfile, not another profile":
    ## The bundle is opaque, so the branch's profile choice is pinned at the
    ## call site. Deleting `of "fireworks":` fails the streamFn test above;
    ## swapping the profile removes one of these lines.
    const source = staticRead(
      "../../src/donkey/adapters/provider/runtime_builder.nim")
    check "of \"fireworks\":" in source
    check "profileFn = fireworksProfileFromEnv" in source
    check "fireworksCompatProfileAt(providerEndpointFor(\"fireworks\"))" in source

  test "the descriptor supplies the default model":
    check providerDefaultModelFor("fireworks") == DefaultModelFireworks
    check descriptorOr("fireworks").defaultModel == DefaultModelFireworks
    check providerDefaultModelFor("fw") == DefaultModelFireworks
    check DefaultModelFireworks == "accounts/fireworks/models/kimi-k2p6"

  test "caps advertise streaming and tools with an unknown context":
    let adapter = newCompatAdapter(
      "fw-test", model = DefaultModelFireworks, providerName = "Fireworks",
      profileFn = fireworksCompatProfile)
    let c = adapter.caps()
    check c.name == "fireworks/" & DefaultModelFireworks
    check c.streaming
    check c.toolCalling
    check c.maxContextTokens == 0
    check c.requiresUserFirst == false

  test "the profile endpoint is the descriptor endpoint":
    check fireworksCompatProfile().id == "fireworks"
    check fireworksCompatProfile().endpoint == providerEndpointFor("fireworks")
    check fireworksCompatProfile().endpoint == descriptorOr("fireworks").baseUrl
    check fireworksCompatProfile().supportsImages == FireworksSupportsImages
    check not fireworksCompatProfile().supportsImages
