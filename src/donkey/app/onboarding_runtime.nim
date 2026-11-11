## onboarding_runtime.nim — onboarding state machine, control tasks, profile capture.
## Extracted from orchestrator.nim (issue #5).

import std/options
import std/strutils
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../core/log
import ../core/outbound/outbound
import ../core/onboarding/onboarding
import ../domain/agent_message
import ../domain/message
import ../domain/personality
import ../ports/memory
import ../ports/provider
import ./prompt_building

export onboarding

# ── Pipeline helpers ──────────────────────────────────────────────────────────

proc safeComplete(fn: CompleteFn; req: CompletionRequest
                 ): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try: fn(req)
  except Exception as e: err(e.msg)

proc unwrapOrReplyError*[T](globalOutbox: AsyncQueue[OutboundMessage];
                            uid: UserId;
                            channel: ChannelKind;
                            replyTo: string;
                            pipelineResult: Result[T, string]): Future[Option[T]] {.async.} =
  if pipelineResult.isErr:
    await sendPipelineError(globalOutbox, uid, channel, replyTo, pipelineResult.error)
    return none(T)
  some(pipelineResult.get())

# ── Free conversation pipeline ────────────────────────────────────────────────

proc completeFreeConvo*(completeFn: CompleteFn): proc(ctx: FreeConvoContext): Result[FreeConvoContext, string] {.gcsafe, raises: [].} =
  result =
    proc(ctx: FreeConvoContext): Result[FreeConvoContext, string] {.gcsafe, raises: [].} =
      let resp = safeComplete(completeFn, ctx.request)
      if resp.isErr:
        return err(resp.error)
      var nextCtx = ctx
      nextCtx.rawText = resp.value.text
      ok(nextCtx)

proc finalizeFreeConvoIdentity*(completeFn: CompleteFn): proc(ctx: FreeConvoContext): Result[FreeConvoContext, string] {.gcsafe, raises: [].} =
  result =
    proc(ctx: FreeConvoContext): Result[FreeConvoContext, string] {.gcsafe, raises: [].} =
      if completeFn.isNil:
        discard
      if ctx.parsedTraits.isNone:
        return ok(ctx)
      var nextCtx = ctx
      nextCtx.onboarding.phase = opNameChoice
      ok(nextCtx)

proc finalizeGuidedChoice*(completeFn: CompleteFn): proc(ctx: GuidedChoiceContext): Result[GuidedChoiceContext, string] {.gcsafe, raises: [].} =
  result =
    proc(ctx: GuidedChoiceContext): Result[GuidedChoiceContext, string] {.gcsafe, raises: [].} =
      if completeFn.isNil:
        discard
      if not ctx.needsNames:
        return ok(ctx)
      ok(ctx)

# ── Control task results ──────────────────────────────────────────────────────

type ResetControlContext* = object
  history*:       ConversationHistory
  sessionId*:     string
  replyText*:     string
  shouldPersist*: bool

type DebugControlContext* = object
  debugMode*: bool
  replyText*: string

type CompactControlContext* = object
  history*:       ConversationHistory
  replyText*:     string
  tokensSaved*:   int

type ControlTaskResult* = object
  history*:       ConversationHistory
  onboarding*:    OnboardingRuntime
  identity*:      IdentityRuntime
  debugMode*:     bool
  showReasoning*: bool
  handled*:       bool
  resetApplied*:  bool

proc startResetControlContext*(history: ConversationHistory;
                               sessionId: string): Result[ResetControlContext, string] =
  ok(ResetControlContext(
    history: newHistory(),
    sessionId: sessionId,
    replyText: "Conversa reiniciada.",
    shouldPersist: true,
  ))

proc startDebugControlContext*(debugMode: bool): Result[DebugControlContext, string] =
  let nextDebugMode = not debugMode
  ok(DebugControlContext(
    debugMode: nextDebugMode,
    replyText:
      (if nextDebugMode:
        "🔍 Debug mode ON — tokens e tool calls serão exibidos."
      else:
        "🔕 Debug mode OFF."),
  ))

proc startCompactControlContext*(history: ConversationHistory): Result[CompactControlContext, string] =
  ## Triggers session compaction to manage token limits.
  ## Currently a stub that reports compaction as unavailable without F2+ memory.
  let historyLen = history.len
  let estimatedTokens = historyLen * 50  ## rough estimate
  if estimatedTokens < 8000:
    return ok(CompactControlContext(
      history: history,
      replyText: "Contexto ainda dentro do limite. Nada a compactar.",
      tokensSaved: 0,
    ))
  ## With F2+ memory, this would run silentMemoryTurn and truncate history
  return ok(CompactControlContext(
    history: history,
    replyText: "Compaction requer memória F2+ (PostgreSQL). Sessão contínua.",
    tokensSaved: 0,
  ))

# ── Safe memory operations ────────────────────────────────────────────────────

proc safeSaveSession*(memory: MemoryRuntimePort;
                     uid: UserId;
                     sessionId: string;
                     history: ConversationHistory) {.gcsafe, raises: [].} =
  try:
    memory.saveSession(uid, sessionId, history)
  except Exception:
    discard

proc safeSaveIdentity*(memory: MemoryRuntimePort;
                      uid: UserId;
                      traits: PersonalityTraits;
                      name: string) {.gcsafe, raises: [].} =
  try:
    memory.saveIdentity(uid, traits, name)
  except Exception:
    discard

proc safeSaveUserMd*(memory: MemoryRuntimePort;
                    uid: UserId;
                    content: string) {.gcsafe, raises: [].} =
  try:
    memory.saveUserMd(uid, content)
  except Exception:
    discard

proc safeLoadIdentity*(memory: MemoryRuntimePort;
                      uid: UserId): (string, PersonalityTraits) {.gcsafe, raises: [].} =
  try:
    memory.loadIdentity(uid)
  except Exception:
    ("", PersonalityTraits())

proc safeHasProfile*(memory: MemoryRuntimePort;
                    uid: UserId): bool {.gcsafe, raises: [].}

proc safeLoadPreferences(memory: MemoryRuntimePort;
                         uid: UserId): string {.gcsafe, raises: [].} =
  try:
    memory.loadContext(uid).preferencesMd
  except Exception:
    ""

proc safeSavePreferences(memory: MemoryRuntimePort;
                         uid: UserId;
                         content: string) {.gcsafe, raises: [].} =
  try:
    memory.savePreferences(uid, content)
  except Exception:
    discard

func mergeTraits(primary, fallback: PersonalityTraits): PersonalityTraits =
  result = primary
  if result.energy.len == 0:
    result.energy = fallback.energy
  if result.tone.len == 0:
    result.tone = fallback.tone
  if result.length.len == 0:
    result.length = fallback.length
  if result.initiative.len == 0:
    result.initiative = fallback.initiative

proc persistOnboardingSnapshot(memory: MemoryRuntimePort;
                               uid: UserId;
                               onboarding: OnboardingRuntime;
                               identity: IdentityRuntime) {.gcsafe, raises: [].} =
  let traits = mergeTraits(onboarding.traits, identity.traits)
  if identity.name.len > 0 or traits.hasTraitValues:
    safeSaveIdentity(memory, uid, traits, identity.name)
  let currentPrefs = safeLoadPreferences(memory, uid)
  let nextPrefs =
    if onboarding.phase == opDone:
      clearOnboardingPrefs(currentPrefs)
    else:
      mergeOnboardingPrefs(currentPrefs, onboarding)
  safeSavePreferences(memory, uid, nextPrefs)

proc safeRestoreOnboardingState*(memory: MemoryRuntimePort;
                                 uid: UserId): (OnboardingRuntime, IdentityRuntime)
                                 {.gcsafe, raises: [].} =
  let prefs = safeLoadPreferences(memory, uid)
  var onboarding = parseOnboardingPrefs(prefs)
  let (name, storedTraits) = safeLoadIdentity(memory, uid)
  onboarding.traits = mergeTraits(onboarding.traits, storedTraits)
  if onboarding.phase == opWakeUp and not safeHasProfile(memory, uid):
    if name.len > 0:
      onboarding.phase = opUserName
    elif onboarding.traits.hasTraitValues:
      onboarding.phase = opNameChoice
  let identityTraits = mergeTraits(storedTraits, onboarding.traits)
  (
    onboarding,
    IdentityRuntime(
      name: name,
      traits: identityTraits,
      identityLoaded: name.len > 0 or identityTraits.hasTraitValues,
    )
  )

proc safeHasProfile*(memory: MemoryRuntimePort;
                    uid: UserId): bool {.gcsafe, raises: [].} =
  try:
    memory.hasProfile(uid)
  except Exception:
    false

proc safeHasCompletedBootstrap*(memory: MemoryRuntimePort;
                               uid: UserId): bool {.gcsafe, raises: [].} =
  try:
    memory.loadContext(uid).userMd.strip.len > 0
  except Exception:
    false

proc safeAppendMemory*(memory: MemoryRuntimePort;
                      uid: UserId;
                      text: string) {.gcsafe, raises: [].} =
  try:
    memory.appendMemory(uid, text)
  except Exception:
    discard

proc safeResetBootstrap*(memory: MemoryRuntimePort;
                        uid: UserId): bool {.gcsafe, raises: [].} =
  try:
    memory.resetBootstrap(uid)
    true
  except Exception:
    false

# ── Reply helpers ─────────────────────────────────────────────────────────────

proc sendReplyText*(globalOutbox: AsyncQueue[OutboundMessage];
                    uid: UserId;
                    channel: ChannelKind;
                    replyTo: string;
                    text: string;
                    editTargetId = "";
                    replaceKeyboard = false;
                    replacementSlot = ""): Future[void] {.async.} =
  await globalOutbox.put(OutboundMessage(
    userId: uid,
    channel: channel,
    text: text,
    replyTo: replyTo,
    editTargetId: editTargetId,
    replaceKeyboard: replaceKeyboard,
    replacementSlot: replacementSlot,
  ))

proc sendReplyKeyboard*(globalOutbox: AsyncQueue[OutboundMessage];
                        uid: UserId;
                        channel: ChannelKind;
                        replyTo: string;
                        text: string;
                        keyboard: seq[seq[(string, string)]];
                        editTargetId = "";
                        replacementSlot = ""): Future[void] {.async.} =
  await globalOutbox.put(OutboundMessage(
    userId: uid,
    channel: channel,
    text: text,
    replyTo: replyTo,
    keyboard: keyboard,
    editTargetId: editTargetId,
    replaceKeyboard: editTargetId.len > 0,
    replacementSlot: replacementSlot,
  ))

proc sendPipelineError*(globalOutbox: AsyncQueue[OutboundMessage];
                       uid: UserId;
                       channel: ChannelKind;
                       replyTo: string;
                       errMsg: string): Future[void] {.async.} =
  await sendReplyText(
    globalOutbox, uid, channel, replyTo,
    "Desculpe, erro: " & errMsg)

proc sendNamePrompt*(globalOutbox: AsyncQueue[OutboundMessage];
                    uid: UserId;
                    channel: ChannelKind;
                    replyTo: string;
                    replacementSlot = ""): Future[void] {.async.} =
  await sendReplyText(globalOutbox, uid, channel, replyTo, "Qual será meu nome?",
    replacementSlot = replacementSlot)

proc persistUserProfile*(memory: MemoryRuntimePort;
                        uid: UserId;
                        profileCtx: UserProfileContext) =
  if profileCtx.saveIdentity:
    safeSaveIdentity(memory, uid, profileCtx.identity.traits, profileCtx.identity.name)
  if profileCtx.saveUserMd:
    safeSaveUserMd(memory, uid, profileCtx.userMd)
  persistOnboardingSnapshot(memory, uid, profileCtx.onboarding, profileCtx.identity)

# ── Guided personality choice ─────────────────────────────────────────────────

proc handleGuidedPersonalityChoice*(globalOutbox: AsyncQueue[OutboundMessage];
                                   memory: MemoryRuntimePort;
                                   completeFn: CompleteFn;
                                   uid: UserId;
                                   channel: ChannelKind;
                                   replyTo: string;
                                   onboarding: OnboardingRuntime;
                                   dim: string;
                                   valor: string): Future[OnboardingRuntime] {.async.} =
  result = onboarding
  let pipelineResult =
    startGuidedChoiceContext(onboarding, dim, valor) >>=
    finalizeGuidedChoice(completeFn)
  let guidedOpt = await unwrapOrReplyError(
    globalOutbox, uid, channel, replyTo, pipelineResult)
  if guidedOpt.isNone:
    return

  let guidedCtx = guidedOpt.get()
  result = guidedCtx.onboarding
  persistOnboardingSnapshot(memory, uid, result,
    IdentityRuntime(traits: result.traits, identityLoaded: result.traits.hasTraitValues))
  let replacementSlot = replacementSlotFor(channel, "bootstrap")

  if guidedCtx.keyboard.len > 0:
    await sendReplyKeyboard(globalOutbox, uid, channel, replyTo,
      guidedCtx.replyText, guidedCtx.keyboard,
      replacementSlot = replacementSlot)
  elif guidedCtx.needsNames:
    await sendNamePrompt(globalOutbox, uid, channel, replyTo, replacementSlot)
  elif guidedCtx.replyText.len > 0:
    await sendReplyText(globalOutbox, uid, channel, replyTo, guidedCtx.replyText,
      replacementSlot = replacementSlot)

# ── Free conversation onboarding ──────────────────────────────────────────────

proc handleFreeConvoOnboarding*(globalOutbox: AsyncQueue[OutboundMessage];
                               memory: MemoryRuntimePort;
                               completeFn: CompleteFn;
                               uid: UserId;
                               channel: ChannelKind;
                               replyTo: string;
                               userText: string;
                               history: ConversationHistory;
                               onboarding: OnboardingRuntime): Future[(ConversationHistory, OnboardingRuntime)] {.async.} =
  result = (history, onboarding)
  let pipelineResult =
    startFreeConvoContext(history, onboarding, userText) >>=
    withFreeConvoRequest >>=
    completeFreeConvo(completeFn) >>=
    parseFreeConvoReply >>=
    finalizeFreeConvoIdentity(completeFn)
  let freeOpt = await unwrapOrReplyError(
    globalOutbox, uid, channel, replyTo, pipelineResult)
  if freeOpt.isNone:
    return

  let freeCtx = freeOpt.get()
  result = (freeCtx.history, freeCtx.onboarding)
  persistOnboardingSnapshot(memory, uid, freeCtx.onboarding,
    IdentityRuntime(traits: freeCtx.onboarding.traits,
                    identityLoaded: freeCtx.onboarding.traits.hasTraitValues))

  if freeCtx.visibleText.len > 0:
    await sendReplyText(globalOutbox, uid, channel, replyTo, freeCtx.visibleText)

  if freeCtx.parsedTraits.isSome:
    let replacementSlot = replacementSlotFor(channel, "bootstrap")
    await sendNamePrompt(globalOutbox, uid, channel, replyTo, replacementSlot)

# ── Agent name onboarding ─────────────────────────────────────────────────────

proc handleAgentNameOnboarding*(globalOutbox: AsyncQueue[OutboundMessage];
                               memory: MemoryRuntimePort;
                               completeFn: CompleteFn;
                               uid: UserId;
                               channel: ChannelKind;
                               replyTo: string;
                               userText: string;
                               history: ConversationHistory;
                               onboarding: OnboardingRuntime;
                               identity: IdentityRuntime): Future[(ConversationHistory, OnboardingRuntime, IdentityRuntime)] {.async.} =
  result = (history, onboarding, identity)

  let directName = extractAgentName(userText)
  if directName.len > 0:
    let pipelineResult = startUserProfileContext(onboarding, identity, directName)
    let profileOpt = await unwrapOrReplyError(globalOutbox, uid, channel, replyTo, pipelineResult)
    if profileOpt.isNone:
      return
    let profileCtx = profileOpt.get()
    persistUserProfile(memory, uid, profileCtx)
    result = (history, profileCtx.onboarding, profileCtx.identity)
    if profileCtx.replyText.len > 0:
      await sendReplyText(globalOutbox, uid, channel, replyTo, profileCtx.replyText)
    return

  var nextHistory = addUserTurn(history, userText, "")
  let req = buildPrompt(
    NameChoiceSystemPrompt & "\n\n" & buildPersonalityPrompt(onboarding.traits, ""),
    nextHistory, "")
  let resp = safeComplete(completeFn, req)
  if resp.isErr:
    await sendPipelineError(globalOutbox, uid, channel, replyTo, resp.error)
    return

  nextHistory.addAssistant(resp.value.text)
  nextHistory.trimTo(20)
  let visibleText = stripNameReady(resp.value.text)
  let parsedName = parseNameReady(resp.value.text)

  if visibleText.len > 0:
    await sendReplyText(globalOutbox, uid, channel, replyTo, visibleText)

  if parsedName.isSome:
    let profileResult = startUserProfileContext(onboarding, identity, parsedName.get())
    let profileOpt = await unwrapOrReplyError(globalOutbox, uid, channel, replyTo, profileResult)
    if profileOpt.isNone:
      result = (nextHistory, onboarding, identity)
      return
    let profileCtx = profileOpt.get()
    persistUserProfile(memory, uid, profileCtx)
    result = (nextHistory, profileCtx.onboarding, profileCtx.identity)
    if profileCtx.replyText.len > 0:
      await sendReplyText(globalOutbox, uid, channel, replyTo, profileCtx.replyText)
    return

  result = (nextHistory, onboarding, identity)

# ── User profile advancement ──────────────────────────────────────────────────

proc advanceUserProfileOnboarding*(globalOutbox: AsyncQueue[OutboundMessage];
                                  memory: MemoryRuntimePort;
                                  completeFn: CompleteFn;
                                  uid: UserId;
                                  channel: ChannelKind;
                                  replyTo: string;
                                  userText: string;
                                  history: ConversationHistory;
                                  onboarding: OnboardingRuntime;
                                  identity: IdentityRuntime): Future[(ConversationHistory, OnboardingRuntime, IdentityRuntime)] {.async.} =
  result = (history, onboarding, identity)

  if onboarding.phase != opUserName:
    let pipelineResult = startUserProfileContext(onboarding, identity, userText)
    let profileOpt = await unwrapOrReplyError(
      globalOutbox, uid, channel, replyTo, pipelineResult)
    if profileOpt.isNone:
      return

    let profileCtx = profileOpt.get()
    result = (history, profileCtx.onboarding, profileCtx.identity)
    persistUserProfile(memory, uid, profileCtx)
    if profileCtx.replyText.len > 0:
      await sendReplyText(globalOutbox, uid, channel, replyTo, profileCtx.replyText)
    return

  var nextHistory = addUserTurn(history, userText, "")
  let req = buildPrompt(UserProfileSystemPrompt, nextHistory, "")
  let resp = safeComplete(completeFn, req)
  if resp.isErr:
    await sendPipelineError(globalOutbox, uid, channel, replyTo, resp.error)
    return

  nextHistory.addAssistant(resp.value.text)
  nextHistory.trimTo(20)
  let visibleText = stripUserProfileReady(resp.value.text)
  let parsedProfile = parseUserProfileReady(resp.value.text)

  if visibleText.len > 0:
    await sendReplyText(globalOutbox, uid, channel, replyTo, visibleText)

  if parsedProfile.isNone:
    result = (nextHistory, onboarding, identity)
    return

  let profile = parsedProfile.get()
  var nextOnboarding = onboarding
  nextOnboarding.userName = if profile.name.len > 0: profile.name else: profile.callMe
  nextOnboarding.timezone = profile.timezone
  nextOnboarding.language = profile.language
  nextOnboarding.userTreatment = profile.treatment
  nextOnboarding.userAbout = profile.about
  nextOnboarding.phase = opDone

  let profileCtx = UserProfileContext(
    onboarding: nextOnboarding,
    identity: identity,
    replyText:
      "Tudo certo! Serei " & identity.name & " e vou te chamar de " & profile.callMe &
      ".\n\nPronto para conversar. Como posso ajudar?",
    userMd: buildUserMd(
      nextOnboarding.userName,
      profile.callMe,
      nextOnboarding.timezone,
      nextOnboarding.language,
      treatment = nextOnboarding.userTreatment,
      about = nextOnboarding.userAbout,
    ),
    saveIdentity: identity.name.len > 0,
    saveUserMd: true,
    advanced: true,
  )
  persistUserProfile(memory, uid, profileCtx)
  if profileCtx.replyText.len > 0:
    await sendReplyText(globalOutbox, uid, channel, replyTo, profileCtx.replyText)
  result = (nextHistory, nextOnboarding, identity)

# ── Control task handlers ─────────────────────────────────────────────────────

proc handleResetControlTask*(globalOutbox: AsyncQueue[OutboundMessage];
                            memory: MemoryRuntimePort;
                            uid: UserId;
                            channel: ChannelKind;
                            replyTo: string;
                            log: Logger;
                            sessionId: string;
                            history: ConversationHistory): Future[(ConversationHistory, OnboardingRuntime, bool)] {.async.} =
  log.info($uid & " (" & $channel & ") reset bootstrap: started")
  let pipelineResult = startResetControlContext(history, sessionId)
  let resetOpt = await unwrapOrReplyError(
    globalOutbox, uid, channel, replyTo, pipelineResult)
  if resetOpt.isNone:
    return (history, OnboardingRuntime(), false)
  let resetCtx = resetOpt.get()
  if resetCtx.shouldPersist:
    safeSaveSession(memory, uid, resetCtx.sessionId, history)
  if not safeResetBootstrap(memory, uid):
    log.warn($uid & " (" & $channel & ") reset bootstrap: failed")
    await sendReplyText(globalOutbox, uid, channel, replyTo,
      "Falha ao reiniciar bootstrap. Tente novamente.")
    return (history, OnboardingRuntime(), false)
  var nextOnboarding = OnboardingRuntime(phase: opWakeUp)
  let wakeup = decideOnboardingTurn(nextOnboarding, "")
  nextOnboarding = wakeup.onboarding
  log.info($uid & " (" & $channel & ") reset bootstrap: completed; onboarding ready")
  let replacementSlot = replacementSlotFor(channel, "bootstrap")
  if wakeup.kind == oekWakeUp and wakeup.keyboard.len > 0:
    await sendReplyKeyboard(globalOutbox, uid, channel, replyTo,
      "✅ Bootstrap reiniciado.\n\n" & wakeup.replyText,
      wakeup.keyboard,
      replacementSlot = replacementSlot)
  else:
    await sendReplyText(globalOutbox, uid, channel, replyTo,
      "✅ Bootstrap reiniciado. Pronto para recomeçar.",
      replacementSlot = replacementSlot)
  (resetCtx.history, nextOnboarding, true)

proc handleDebugToggleControlTask*(globalOutbox: AsyncQueue[OutboundMessage];
                                  uid: UserId;
                                  channel: ChannelKind;
                                  replyTo: string;
                                  debugMode: bool): Future[bool] {.async.} =
  result = debugMode
  let pipelineResult = startDebugControlContext(debugMode)
  let debugOpt = await unwrapOrReplyError(
    globalOutbox, uid, channel, replyTo, pipelineResult)
  if debugOpt.isNone:
    return
  let debugCtx = debugOpt.get()
  result = debugCtx.debugMode
  await sendReplyText(globalOutbox, uid, channel, replyTo, debugCtx.replyText)

proc handleCompactControlTask*(globalOutbox: AsyncQueue[OutboundMessage];
                            uid: UserId;
                            channel: ChannelKind;
                            replyTo: string;
                            history: ConversationHistory): Future[ConversationHistory] {.async.} =
  let pipelineResult = startCompactControlContext(history)
  let compactOpt = await unwrapOrReplyError(
    globalOutbox, uid, channel, replyTo, pipelineResult)
  if compactOpt.isNone:
    return history
  let compactCtx = compactOpt.get()
  await sendReplyText(globalOutbox, uid, channel, replyTo, compactCtx.replyText)
  compactCtx.history

proc handleNewSessionTask*(globalOutbox: AsyncQueue[OutboundMessage];
                        memory: MemoryRuntimePort;
                        uid: UserId;
                        channel: ChannelKind;
                        replyTo: string;
                        sessionId: string;
                        history: ConversationHistory): Future[ConversationHistory] {.async.} =
  ## /new archives the current session and starts a fresh one.
  let pipelineResult = startResetControlContext(history, sessionId)
  let resetOpt = await unwrapOrReplyError(
    globalOutbox, uid, channel, replyTo, pipelineResult)
  if resetOpt.isNone:
    return history
  let resetCtx = resetOpt.get()
  if resetCtx.shouldPersist:
    safeSaveSession(memory, uid, resetCtx.sessionId, history)
  await sendReplyText(globalOutbox, uid, channel, replyTo,
    "Nova conversa iniciada. 👋")
  resetCtx.history

proc handleOnboardingControlTask*(globalOutbox: AsyncQueue[OutboundMessage];
                                 memory: MemoryRuntimePort;
                                 completeFn: CompleteFn;
                                 uid: UserId;
                                 channel: ChannelKind;
                                 replyTo: string;
                                 msg: AgentMessage;
                                 onboarding: OnboardingRuntime;
                                 identity: IdentityRuntime): Future[(OnboardingRuntime, IdentityRuntime, bool)] {.async.} =
  result = (onboarding, identity, false)
  let decision = decideOnboardingControl(msg, onboarding, identity).valueOr:
    return

  case decision.kind
  of oekGuidedChoice:
    result[0] = await handleGuidedPersonalityChoice(
      globalOutbox, memory, completeFn, uid, channel, replyTo,
      decision.onboarding, decision.dim, decision.value)
    result[2] = decision.handled

  of oekNameChoice:
    let profileResult = startUserProfileContext(decision.onboarding, decision.identity, decision.name)
    let profileOpt = await unwrapOrReplyError(globalOutbox, uid, channel, replyTo, profileResult)
    if profileOpt.isSome:
      let profileCtx = profileOpt.get()
      persistUserProfile(memory, uid, profileCtx)
      result[0] = profileCtx.onboarding
      result[1] = profileCtx.identity
      if profileCtx.replyText.len > 0:
        await sendReplyText(globalOutbox, uid, channel, replyTo, profileCtx.replyText)
    result[2] = decision.handled

  else:
    discard

# ── Onboarding turn handler ───────────────────────────────────────────────────

type OnboardingTurnResult* = object
  history*:            ConversationHistory
  onboarding*:         OnboardingRuntime
  identity*:           IdentityRuntime
  handled*:            bool

proc handleOnboardingTurn*(globalOutbox: AsyncQueue[OutboundMessage];
                          memory: MemoryRuntimePort;
                          completeFn: CompleteFn;
                          uid: UserId;
                          channel: ChannelKind;
                          replyTo: string;
                          userText: string;
                          history: ConversationHistory;
                          onboarding: OnboardingRuntime;
                          identity: IdentityRuntime): Future[OnboardingTurnResult] {.async.} =
  result.history = history
  result.onboarding = onboarding
  result.identity = identity
  let decision = decideOnboardingTurn(result.onboarding, userText)
  result.onboarding = decision.onboarding

  case decision.kind
  of oekWakeUp:
    let replacementSlot = replacementSlotFor(channel, "bootstrap")
    await sendReplyKeyboard(
      globalOutbox, uid, channel, replyTo,
      decision.replyText, decision.keyboard,
      replacementSlot = replacementSlot)

  of oekButtonOnly:
    if replacementSlotFor(channel, "bootstrap").len == 0:
      await sendReplyText(globalOutbox, uid, channel, replyTo, decision.replyText)

  of oekFreeConvoText:
    (result.history, result.onboarding) = await handleFreeConvoOnboarding(
      globalOutbox, memory, completeFn, uid, channel, replyTo,
      userText |> strutils.strip, result.history, result.onboarding)

  of oekUserProfileText:
    if result.onboarding.phase == opNameChoice:
      (result.history, result.onboarding, result.identity) = await handleAgentNameOnboarding(
        globalOutbox, memory, completeFn, uid, channel, replyTo,
        userText |> strutils.strip, result.history, result.onboarding, result.identity)
    else:
      (result.history, result.onboarding, result.identity) = await advanceUserProfileOnboarding(
        globalOutbox, memory, completeFn, uid, channel, replyTo,
        userText |> strutils.strip, result.history, result.onboarding, result.identity)

  of oekDone:
    return OnboardingTurnResult(
      history: result.history,
      onboarding: result.onboarding,
      identity: result.identity,
      handled: false,
    )

  else:
    discard

  result.handled = decision.handled
