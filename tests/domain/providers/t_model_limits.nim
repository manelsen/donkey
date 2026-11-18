## model_limits — verified provider limits with conservative unknowns.
##
## A missing fact is never a promise: context, output, vision and tools stay
## 0/false until a source proves otherwise (PRD FR-3).

import std/[strutils, unittest]
import donkey/core/providers/provider_defaults
import donkey/domain/providers/model_limits
import donkey/domain/providers/profile_alibaba
import donkey/domain/providers/profile_nvidia

suite "model limits":

  test "an unknown provider is conservative: 0/false/empty":
    let limits = modelLimits("invented", "invented/model")
    check limits.contextWindow == 0
    check limits.maxOutputTokens == 0
    check not limits.supportsVision
    check not limits.supportsTools
    check limits.source == mlsUnknown
    check limits.sourceRef.len == 0

  test "an empty provider and model are unknown too":
    let limits = modelLimits("", "")
    check limits.contextWindow == 0
    check limits.maxOutputTokens == 0
    check not limits.supportsVision
    check not limits.supportsTools
    check limits.source == mlsUnknown
    check limits.sourceRef.len == 0

  test "a known provider with an unlisted model does not borrow the default":
    let limits = modelLimits("nvidia", "nvidia/some-other-model")
    check limits.contextWindow == 0
    check limits.maxOutputTokens == 0
    check not limits.supportsVision
    check not limits.supportsTools
    check limits.source == mlsUnknown
    check limits.sourceRef.len == 0

  test "NVIDIA vision and tools are verified; context stays unverified":
    let limits = modelLimits("nvidia", DefaultModelNvidia)
    check limits.supportsVision
    check limits.supportsTools
    check limits.maxOutputTokens == 16384
    # No verified context window in the Hermes source: absence is not a promise.
    check limits.contextWindow == 0
    check limits.source == mlsVerified
    check limits.sourceRef.len > 0

  test "provider ids are matched case-insensitively and trimmed":
    let canonical = modelLimits("nvidia", DefaultModelNvidia)
    let padded = modelLimits("  NVIDIA  ", DefaultModelNvidia)
    check padded.contextWindow == canonical.contextWindow
    check padded.maxOutputTokens == canonical.maxOutputTokens
    check padded.supportsVision == canonical.supportsVision
    check padded.supportsTools == canonical.supportsTools
    check padded.source == canonical.source
    check padded.sourceRef == canonical.sourceRef

  test "the verified table is ordered by provider then model":
    for i in 1 ..< ModelLimitEntries.len:
      let previous = ModelLimitEntries[i - 1]
      let current = ModelLimitEntries[i]
      check previous.provider < current.provider or
            (previous.provider == current.provider and
             previous.model < current.model)

  test "repeated lookups are deterministic":
    let first = modelLimits("nvidia", DefaultModelNvidia)
    for _ in 0 ..< 8:
      let again = modelLimits("nvidia", DefaultModelNvidia)
      check again.contextWindow == first.contextWindow
      check again.maxOutputTokens == first.maxOutputTokens
      check again.supportsVision == first.supportsVision
      check again.supportsTools == first.supportsTools
      check again.source == first.source
      check again.sourceRef == first.sourceRef

  test "vision metadata agrees with the compat profile":
    # The profile and the limits read the same verified fact; the shared
    # constant lives in provider_defaults so they cannot drift.
    let limits = modelLimits("nvidia", DefaultModelNvidia)
    check limits.supportsVision == nvidiaCompatProfile().supportsImages
    check limits.supportsVision == NvidiaSupportsImages

  test "unverified providers keep the conservative vision constants":
    check AlibabaSupportsImages == false
    check FireworksSupportsImages == false
    check not modelLimits("alibaba", "qwen3.8-max").supportsVision
    check not modelLimits("fireworks", "accounts/fireworks/models/kimi-k2p6").supportsVision

  test "Alibaba vision metadata agrees with the compat profile":
    ## Same guard as NVIDIA: the profile must read the shared constant. A
    ## literal `false` would be indistinguishable by value, so the profile
    ## source is pinned too; changing either side fails here.
    check alibabaCompatProfile().supportsImages == AlibabaSupportsImages
    check AlibabaSupportsImages == false
    check modelLimits("alibaba", DefaultModelAlibaba).source == mlsUnknown
    const profileSource = staticRead(
      "../../../src/donkey/domain/providers/profile_alibaba.nim")
    check "supportsImages: AlibabaSupportsImages" in profileSource
