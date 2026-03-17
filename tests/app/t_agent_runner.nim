## AgentRunner unit tests — pure logic only (no HTTP, no filesystem).

import std/[strutils, unittest]
import donkey/app/agent_runner

suite "parseOnboardingResponse":

  test "returns complete=false when marker absent":
    let r = parseOnboardingResponse("Hello! What's your name?")
    check not r.complete

  test "extracts all four fields when marker present":
    let text = """
Ótimo! Tenho tudo que preciso.
ONBOARDING_COMPLETE: name=Alice Wonderland|callMe=Alice|tz=UTC-3|lang=pt-BR
"""
    let r = parseOnboardingResponse(text)
    check r.complete
    check r.name   == "Alice Wonderland"
    check r.callMe == "Alice"
    check r.tz     == "UTC-3"
    check r.lang   == "pt-BR"

  test "handles marker at start of line":
    let text = "ONBOARDING_COMPLETE: name=Bob|callMe=Bob|tz=UTC+8|lang=zh-CN"
    let r = parseOnboardingResponse(text)
    check r.complete
    check r.name == "Bob"
    check r.lang == "zh-CN"

  test "handles extra whitespace around marker":
    let text = "  ONBOARDING_COMPLETE: name=X|callMe=X|tz=UTC|lang=en  "
    let r = parseOnboardingResponse(text)
    check r.complete
    check r.name == "X"

  test "returns complete=false for empty string":
    check not parseOnboardingResponse("").complete

  test "partial marker not matched":
    check not parseOnboardingResponse("ONBOARDING_INCOMPL: name=X").complete

suite "OnboardingSystem and DefaultSystem constants":

  test "OnboardingSystem mentions ONBOARDING_COMPLETE":
    check OnboardingSystem.contains("ONBOARDING_COMPLETE")

  test "DefaultSystem is non-empty":
    check DefaultSystem.len > 0
