## Pure onboarding state, events and decisions.

import std/[options, strutils]
import ../pipeops
import ../../domain/agent_message
import ../../domain/message
import ../../domain/personality

export options, personality

const FreeConvoSystemPrompt* = """You are discovering your own identity through conversation.
Your user will describe your personality, tone, and style.
Listen actively. Ask clarifying questions if needed.
When you have a clear picture of who you should be, output this exact block (no extra formatting):

IDENTITY_READY:
energy: <reservado|neutro|entusiasmo>
tone: <formal|neutro|casual>
length: <conciso|moderado|detalhado>
initiative: <reativo|moderado|proativo>

Then continue the conversation naturally. Only output the block when you are confident about all four dimensions.

## Skills

You can install and enable skills for the user with `manage_skills`. Never say your toolset is fixed or that you cannot install skills. If the user asks whether you can install skills, how skill installation works, or they mention a missing capability, use `manage_skills` or explain that you can search/install/enable a skill for them."""

type
  OnboardingRuntime* = object
    phase*:       OnboardingPhase
    traits*:      PersonalityTraits
    names*:       seq[string]
    userName*:    string
    timezone*:    string
    language*:    string

  IdentityRuntime* = object
    name*:           string
    traits*:         PersonalityTraits
    identityLoaded*: bool

  FreeConvoContext* = object
    history*:      ConversationHistory
    onboarding*:   OnboardingRuntime
    request*:      CompletionRequest
    rawText*:      string
    visibleText*:  string
    parsedTraits*: Option[PersonalityTraits]

  GuidedChoiceContext* = object
    onboarding*: OnboardingRuntime
    replyText*:  string
    keyboard*:   seq[seq[(string, string)]]
    needsNames*: bool
    handled*:    bool

  UserProfileContext* = object
    onboarding*:   OnboardingRuntime
    identity*:     IdentityRuntime
    replyText*:    string
    userMd*:       string
    saveIdentity*: bool
    saveUserMd*:   bool
    advanced*:     bool

  OnboardingControlContext* = object
    onboarding*: OnboardingRuntime
    identity*:   IdentityRuntime
    handled*:    bool
    dim*:        string
    value*:      string
    name*:       string

  OnboardingEventKind* = enum
    oekWakeUp
    oekButtonOnly
    oekFreeConvoText
    oekUserProfileText
    oekDone
    oekGuidedChoice
    oekNameChoice
    oekIgnore

  OnboardingDecision* = object
    kind*:      OnboardingEventKind
    onboarding*: OnboardingRuntime
    identity*:   IdentityRuntime
    replyText*: string
    keyboard*:  seq[seq[(string, string)]]
    handled*:   bool
    dim*:       string
    value*:     string
    name*:      string

func buildUserMd(name, callMe, timezone, language: string): string =
  "# User\n\n" &
  "**Name:** " & name & "\n" &
  "**Call me:** " & callMe & "\n" &
  "**Timezone:** " & timezone & "\n" &
  "**Language:** " & language & "\n"

func startFreeConvoContext*(history: ConversationHistory;
                            onboarding: OnboardingRuntime;
                            userText: string): Result[FreeConvoContext, string] {.gcsafe, raises: [].} =
  var nextHistory = history
  nextHistory.addUser(userText)
  nextHistory.trimTo(20)
  ok(FreeConvoContext(
    history: nextHistory,
    onboarding: onboarding,
  ))

func withFreeConvoRequest*(ctx: FreeConvoContext): Result[FreeConvoContext, string] =
  ok(FreeConvoContext(
    history: ctx.history,
    onboarding: ctx.onboarding,
    request: buildPrompt(FreeConvoSystemPrompt, ctx.history, ""),
    rawText: ctx.rawText,
  ))

func parseFreeConvoReply*(ctx: FreeConvoContext): Result[FreeConvoContext, string] =
  var nextCtx = ctx
  nextCtx.visibleText = stripIdentityReady(ctx.rawText)
  nextCtx.parsedTraits = parseIdentityReady(ctx.rawText)
  nextCtx.history.addAssistant(ctx.rawText)
  if nextCtx.parsedTraits.isSome:
    nextCtx.onboarding.traits = nextCtx.parsedTraits.get()
  ok(nextCtx)

func startGuidedChoiceContext*(onboarding: OnboardingRuntime;
                               dim: string;
                               valor: string): Result[GuidedChoiceContext, string] {.gcsafe, raises: [].} =
  var next = onboarding

  case dim
  of "mode":
    if valor == "guided":
      next.phase = opGuidedEnergy
      let (t, kb) = guidedDimensionMsg(dkEnergy)
      ok(GuidedChoiceContext(onboarding: next, replyText: t, keyboard: kb, handled: true))
    elif valor == "free":
      next.phase = opFreeConvo
      ok(GuidedChoiceContext(
        onboarding: next,
        replyText:
          "Ótimo! Descreva como imagina que eu devo ser — " &
          "meu jeito, meu tom, minha forma de responder. " &
          "Pode ser em poucas palavras ou um parágrafo.",
        handled: true,
      ))
    else:
      err("modo inválido")

  of "energy":
    next.traits.energy = valor
    next.phase = opGuidedTone
    let (t, kb) = guidedDimensionMsg(dkTone)
    ok(GuidedChoiceContext(onboarding: next, replyText: t, keyboard: kb, handled: true))

  of "tone":
    next.traits.tone = valor
    next.phase = opGuidedLength
    let (t, kb) = guidedDimensionMsg(dkLength)
    ok(GuidedChoiceContext(onboarding: next, replyText: t, keyboard: kb, handled: true))

  of "length":
    next.traits.length = valor
    next.phase = opGuidedInitiative
    let (t, kb) = guidedDimensionMsg(dkInitiative)
    ok(GuidedChoiceContext(onboarding: next, replyText: t, keyboard: kb, handled: true))

  of "initiative":
    next.traits.initiative = valor
    next.phase = opNameChoice
    ok(GuidedChoiceContext(onboarding: next, needsNames: true, handled: true))

  else:
    err("dimensão inválida")

func startUserProfileContext*(onboarding: OnboardingRuntime;
                              identity: IdentityRuntime;
                              userText: string): Result[UserProfileContext, string] {.gcsafe, raises: [].} =
  var ob = onboarding
  var id = identity
  let txt = userText.strip

  case ob.phase
  of opNameChoice:
    if txt.len == 0:
      return ok(UserProfileContext(onboarding: ob, identity: id))
    id.name = txt
    id.traits = ob.traits
    id.identityLoaded = true
    ob.phase = opUserName
    ok(UserProfileContext(
      onboarding: ob,
      identity: id,
      replyText:
        "Perfeito. Serei " & id.name &
        ".\n\nAgora me conta sobre você — qual é o seu nome?",
      saveIdentity: true,
      advanced: true,
    ))

  of opUserName:
    ob.userName = txt
    ob.phase = opUserTimezone
    ok(UserProfileContext(
      onboarding: ob,
      identity: id,
      replyText:
        "Ótimo, " & ob.userName & "! Em que fuso horário você está? " &
        "(ex: America/Sao_Paulo, UTC-3, Europa/Lisboa)",
      advanced: true,
    ))

  of opUserTimezone:
    ob.timezone = txt
    ob.phase = opUserLanguage
    ok(UserProfileContext(
      onboarding: ob,
      identity: id,
      replyText:
        "Entendido. Qual idioma prefere que eu use? " &
        "(ex: Português, English, Español)",
      advanced: true,
    ))

  of opUserLanguage:
    ob.language = txt
    ob.phase = opDone
    let userMd = buildUserMd(ob.userName, ob.userName, ob.timezone, ob.language)
    ok(UserProfileContext(
      onboarding: ob,
      identity: id,
      replyText:
        "Tudo certo! Serei " & id.name & " e você é " & ob.userName &
        ".\n\nPronto para conversar. Como posso ajudar?",
      userMd: userMd,
      saveUserMd: true,
      advanced: true,
    ))

  else:
    err("fase inválida para perfil")

func startOnboardingControlContext*(msg: AgentMessage;
                                    onboarding: OnboardingRuntime;
                                    identity: IdentityRuntime): Result[OnboardingControlContext, string] {.gcsafe, raises: [].} =
  case msg.taskKind
  of tkPersonalityChoice:
    let parts = msg.payload.split(':', 2)
    if parts.len != 3:
      return err("invalid personality payload")
    ok(OnboardingControlContext(
      onboarding: onboarding,
      identity: identity,
      handled: true,
      dim: parts[1],
      value: parts[2],
    ))

  of tkNameChoice:
    let raw = msg.payload
    let name = if raw.startsWith("name:"): raw["name:".len .. ^1] else: raw
    if name.len == 0:
      return err("empty name choice")
    ok(OnboardingControlContext(
      onboarding: onboarding,
      identity: identity,
      handled: true,
      name: name,
    ))

  else:
    ok(OnboardingControlContext(
      onboarding: onboarding,
      identity: identity,
      handled: false,
    ))

func decideOnboardingTurn*(onboarding: OnboardingRuntime;
                           userText: string): OnboardingDecision {.gcsafe, raises: [].} =
  let strippedUserText = userText.strip
  case onboarding.phase
  of opWakeUp:
    var next = onboarding
    next.phase = opModeChoice
    OnboardingDecision(
      kind: oekWakeUp,
      onboarding: next,
      replyText: "Olá. Acabei de ligar.\n\nComo quer definir minha personalidade?",
      keyboard: @[@[("Guiado 🎛️", "personality:mode:guided"),
                    ("Livre 💬",   "personality:mode:free")]],
      handled: true,
    )
  of opModeChoice, opGuidedEnergy, opGuidedTone, opGuidedLength, opGuidedInitiative:
    discard strippedUserText
    OnboardingDecision(
      kind: oekButtonOnly,
      onboarding: onboarding,
      replyText: "Use os botões acima para escolher.",
      handled: true,
    )
  of opFreeConvo:
    OnboardingDecision(kind: oekFreeConvoText, onboarding: onboarding, handled: true)
  of opNameChoice, opUserName, opUserTimezone, opUserLanguage:
    OnboardingDecision(kind: oekUserProfileText, onboarding: onboarding, handled: true)
  of opDone:
    OnboardingDecision(kind: oekDone, onboarding: onboarding, handled: false)

func decideOnboardingControl*(msg: AgentMessage;
                              onboarding: OnboardingRuntime;
                              identity: IdentityRuntime): Result[OnboardingDecision, string] {.gcsafe, raises: [].} =
  let ctx = startOnboardingControlContext(msg, onboarding, identity).valueOr:
    return err(error)
  case msg.taskKind
  of tkPersonalityChoice:
    ok(OnboardingDecision(
      kind: oekGuidedChoice,
      onboarding: onboarding,
      identity: identity,
      handled: ctx.handled,
      dim: ctx.dim,
      value: ctx.value,
    ))
  of tkNameChoice:
    ok(OnboardingDecision(
      kind: oekNameChoice,
      onboarding: onboarding,
      identity: identity,
      handled: ctx.handled,
      name: ctx.name,
    ))
  else:
    ok(OnboardingDecision(
      kind: oekIgnore,
      onboarding: onboarding,
      identity: identity,
      handled: false,
    ))
