## Pure onboarding state, events and decisions.

import std/[options, strutils]
import ../pipeops
import ../outbound/outbound
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

const NameChoiceSystemPrompt* = """You are discussing your own name with the user.
The question on the table is: "Qual será meu nome?"
The user may answer directly, may suggest multiple names, or may want a short conversation first about whether you should have a name and what it should mean.

When the user has clearly chosen a single name for you, output this exact block (no extra formatting):

NAME_READY:
name: <chosen name>

Then continue naturally.

If the user has not settled on a single clear name yet, do not output the block. Continue the conversation naturally and help them decide."""

const UserProfileSystemPrompt* = """You are getting to know your user through a short conversational onboarding.
The goals are:
- understand who they are in broad terms, if they want to say
- learn how they would like to be called
- learn how they would like you to address or treat them
- optionally learn language and timezone if they mention them

When you have enough to proceed, output this exact block (no extra formatting):

USER_PROFILE_READY:
name: <their actual name or short self-identifier, or empty if unknown>
call_me: <how they want to be called>
timezone: <their timezone, or empty if unknown>
language: <their preferred language, or empty if unknown>
treatment: <how they want you to address/treat them, or empty if unknown>
about: <brief one-line summary of who they are, or empty if unknown>

Then continue naturally.

It is acceptable to finish with timezone/language unknown. The critical thing is having a stable way to address the user.
If you still do not know how they want to be called, do not output the block yet."""

type
  OnboardingRuntime* = object
    phase*:       OnboardingPhase
    traits*:      PersonalityTraits
    names*:       seq[string]
    userName*:    string
    timezone*:    string
    language*:    string
    userTreatment*: string
    userAbout*:     string

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

func buildUserMd*(name, callMe, timezone, language: string;
                  treatment = "";
                  about = ""): string =
  result = "# User\n\n" &
    "**Name:** " & name & "\n" &
    "**Call me:** " & callMe & "\n" &
    "**Timezone:** " & timezone & "\n" &
    "**Language:** " & language & "\n"
  if treatment.len > 0:
    result &= "**Interaction preferences:** " & treatment & "\n"
  if about.len > 0:
    result &= "**About:** " & about & "\n"

type UserProfileReady* = object
  name*: string
  callMe*: string
  timezone*: string
  language*: string
  treatment*: string
  about*: string

func parseProfileField(line, field: string): string =
  let parts = line.split(':', 1)
  if parts.len == 2 and parts[0].strip == field:
    parts[1].strip
  else:
    ""

func parseUserProfileReady*(text: string): Option[UserProfileReady] =
  let lines = text.splitLines
  var idx = -1
  for i, l in lines:
    if l.strip == "USER_PROFILE_READY:":
      idx = i
      break
  if idx < 0:
    return none(UserProfileReady)

  var profile: UserProfileReady
  for i in (idx + 1) ..< lines.len:
    let l = lines[i].strip
    if l.len == 0:
      break
    if profile.name.len == 0: profile.name = parseProfileField(l, "name")
    if profile.callMe.len == 0: profile.callMe = parseProfileField(l, "call_me")
    if profile.timezone.len == 0: profile.timezone = parseProfileField(l, "timezone")
    if profile.language.len == 0: profile.language = parseProfileField(l, "language")
    if profile.treatment.len == 0: profile.treatment = parseProfileField(l, "treatment")
    if profile.about.len == 0: profile.about = parseProfileField(l, "about")
  if profile.callMe.len == 0:
    return none(UserProfileReady)
  some(profile)

func stripUserProfileReady*(text: string): string =
  let lines = text.splitLines
  var markerIdx = -1
  for i, l in lines:
    if l.strip == "USER_PROFILE_READY:":
      markerIdx = i
      break
  if markerIdx < 0:
    return text
  var blockEnd = markerIdx + 1
  while blockEnd < lines.len and lines[blockEnd].strip.len > 0:
    inc blockEnd
  if blockEnd < lines.len and lines[blockEnd].strip.len == 0:
    inc blockEnd
  var kept: seq[string]
  for i, l in lines:
    if i >= markerIdx and i < blockEnd:
      continue
    kept.add(l)
  kept.join("\n").strip

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

func parseNameReady*(text: string): Option[string] =
  let lines = text.splitLines
  var idx = -1
  for i, l in lines:
    if l.strip == "NAME_READY:":
      idx = i
      break
  if idx < 0:
    return none(string)
  for i in (idx + 1) ..< lines.len:
    let l = lines[i].strip
    if l.len == 0:
      break
    let parts = l.split(':', 1)
    if parts.len == 2 and parts[0].strip == "name":
      let extracted = extractAgentName(parts[1].strip)
      if extracted.len > 0:
        return some(extracted)
  none(string)

func stripNameReady*(text: string): string =
  let lines = text.splitLines
  var markerIdx = -1
  for i, l in lines:
    if l.strip == "NAME_READY:":
      markerIdx = i
      break
  if markerIdx < 0:
    return text

  var blockEnd = markerIdx + 1
  while blockEnd < lines.len and lines[blockEnd].strip.len > 0:
    inc blockEnd
  if blockEnd < lines.len and lines[blockEnd].strip.len == 0:
    inc blockEnd

  var kept: seq[string]
  for i, l in lines:
    if i >= markerIdx and i < blockEnd:
      continue
    kept.add(l)
  kept.join("\n").strip

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
    let chosenName = extractAgentName(txt)
    if chosenName.len == 0:
      return ok(UserProfileContext(
        onboarding: ob,
        identity: id,
        replyText: "Qual será meu nome?",
      ))
    id.name = chosenName
    id.traits = ob.traits
    id.identityLoaded = true
    ob.phase = opUserName
    ok(UserProfileContext(
      onboarding: ob,
      identity: id,
      replyText:
        "Perfeito. Serei " & id.name &
        ".\n\nAgora me conta um pouco sobre você: quem é você, como gostaria de ser chamado e como prefere que eu te trate. Se quiser, já diga também seu idioma e fuso horário.",
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
      saveIdentity: id.name.len > 0,
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
      replyText: interactiveSelectionFallbackText(),
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
