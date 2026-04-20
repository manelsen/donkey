import std/unittest
import donkey/core/onboarding/onboarding
import donkey/core/pipeops
import donkey/domain/agent_message
import donkey/domain/personality

suite "core onboarding decisions":

  test "wake up decision advances to mode choice with keyboard":
    let decision = decideOnboardingTurn(OnboardingRuntime(phase: opWakeUp), "")
    check decision.kind == oekWakeUp
    check decision.handled
    check decision.onboarding.phase == opModeChoice
    check decision.keyboard.len > 0

  test "guided phases reject text and keep state":
    let decision = decideOnboardingTurn(OnboardingRuntime(phase: opGuidedTone), "oi")
    check decision.kind == oekButtonOnly
    check decision.handled
    check decision.replyText.contains("botões")
    check decision.onboarding.phase == opGuidedTone

  test "free convo and profile phases route to effectful handlers":
    check decideOnboardingTurn(OnboardingRuntime(phase: opFreeConvo), "").kind == oekFreeConvoText
    check decideOnboardingTurn(OnboardingRuntime(phase: opUserTimezone), "").kind == oekUserProfileText
    check decideOnboardingTurn(OnboardingRuntime(phase: opDone), "").kind == oekDone

  test "control decision decodes personality callbacks":
    let res = decideOnboardingControl(
      newTaskMsg("1", tkPersonalityChoice, "u1", "personality:mode:guided"),
      OnboardingRuntime(phase: opModeChoice),
      IdentityRuntime(),
    )
    check not res.isErr
    let decision = res.get()
    check decision.kind == oekGuidedChoice
    check decision.dim == "mode"
    check decision.value == "guided"

  test "control decision decodes name callbacks":
    let res = decideOnboardingControl(
      newTaskMsg("1", tkNameChoice, "u1", "name:Donkey"),
      OnboardingRuntime(phase: opNameChoice),
      IdentityRuntime(),
    )
    check not res.isErr
    let decision = res.get()
    check decision.kind == oekNameChoice
    check decision.name == "Donkey"

  test "final profile step re-saves agent identity":
    let onboarding = OnboardingRuntime(
      phase: opUserLanguage,
      userName: "Void",
      timezone: "America/Sao_Paulo",
    )
    let identity = IdentityRuntime(
      name: "Ostervalt",
      traits: PersonalityTraits(
        energy: "neutro",
        tone: "casual",
        length: "moderado",
        initiative: "proativo",
      ),
      identityLoaded: true,
    )
    let ctx = startUserProfileContext(onboarding, identity, "Português brasileiro").get()
    check ctx.onboarding.phase == opDone
    check ctx.saveUserMd
    check ctx.saveIdentity
    check ctx.replyText.contains("Serei Ostervalt")

  test "parse user profile ready extracts conversational profile":
    let parsed = parseUserProfileReady("""USER_PROFILE_READY:
name: Manel Moura
call_me: Void
timezone: UTC-3
language: Português
treatment: com franqueza
about: criador do Donkey
""")
    check parsed.isSome
    let profile = parsed.get()
    check profile.callMe == "Void"
    check profile.timezone == "UTC-3"
    check profile.treatment == "com franqueza"

  test "merge and parse onboarding prefs preserve conversational progress":
    let prefs = mergeOnboardingPrefs(
      "provider = \"zai-coding\"",
      OnboardingRuntime(
        phase: opUserTimezone,
        userName: "Void",
        timezone: "",
        language: "",
        userTreatment: "com franqueza",
      ),
    )
    let parsed = parseOnboardingPrefs(prefs)
    check parsed.phase == opUserTimezone
    check parsed.userName == "Void"
    check parsed.userTreatment == "com franqueza"
    check prefs.contains("provider = \"zai-coding\"")

  test "clear onboarding prefs removes snapshot keys only":
    let cleared = clearOnboardingPrefs("""
provider = "zai-coding"
onboarding_phase = "opNameChoice"
onboarding_user_name = "Void"
""")
    check cleared.contains("provider = \"zai-coding\"")
    check not cleared.contains("onboarding_phase")
    check not cleared.contains("onboarding_user_name")
