## t_compat_reasoning_off.nim — `reasoningOffExtras` (US-001/US-004).
##
## Some providers need a field only when reasoning is *disabled*
## (Fireworks: `reasoning_effort: "none"`). The profile carries it, and
## `buildCompatRequestBody` merges it exactly when `req.reasoning == false`.

import std/[json, unittest]
import donkey/domain/message
import donkey/domain/providers/compat
import donkey/domain/providers/profile_nvidia

suite "compat reasoningOffExtras":

  test "merges at the top level when reasoning is false":
    var profile = defaultOpenAiProfile()
    profile.reasoningOffExtras = %* {"reasoning_effort": "none"}
    let body = buildCompatRequestBody(profile, "m", CompletionRequest())
    check body["reasoning_effort"].getStr() == "none"
    check body["model"].getStr() == "m"
    check body["stream"].getBool() == false

  test "is absent when reasoning is true":
    var profile = defaultOpenAiProfile()
    profile.reasoningOffExtras = %* {"reasoning_effort": "none"}
    profile.reasoningExtras = %* {"thinking": {"type": "enabled"}}
    let body = buildCompatRequestBody(profile, "m",
                                      CompletionRequest(reasoning: true))
    check not body.hasKey("reasoning_effort")
    check body["thinking"]["type"].getStr() == "enabled"

  test "the default profile carries no reasoningOffExtras":
    check defaultOpenAiProfile().reasoningOffExtras.isNil
    let body = buildCompatRequestBody(defaultOpenAiProfile(), "m",
                                      CompletionRequest())
    check not body.hasKey("reasoning_effort")

  test "a non-object reasoningOffExtras is ignored":
    var profile = defaultOpenAiProfile()
    profile.reasoningOffExtras = %* ["not", "an", "object"]
    let body = buildCompatRequestBody(profile, "m", CompletionRequest())
    check not body.hasKey("reasoning_effort")

  test "the NVIDIA profile defines no reasoningOffExtras":
    ## NVIDIA has no verified "off" field; only Fireworks will set one.
    check nvidiaCompatProfile().reasoningOffExtras.isNil
    let body = buildCompatRequestBody(nvidiaCompatProfile(), "m",
                                      CompletionRequest(reasoning: false))
    check not body.hasKey("reasoning_effort")
