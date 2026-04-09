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
