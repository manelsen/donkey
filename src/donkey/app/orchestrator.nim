## OrchestratorAgent — per-session actor: debounce → memory → LLM → reply.
##
## Lifecycle:
##   Daemon spawns runOrchestrator as an asyncSpawn task (fire-and-forget).
##   The orchestrator loops forever, one collectWithDebounce cycle per turn.
##
## Onboarding state machine (new users):
##   opWakeUp → send wakeup + mode keyboard → opModeChoice
##   opModeChoice → Guided: opGuidedEnergy … opGuidedInitiative → name gen → opNameChoice
##               → Free: conversational LLM with IDENTITY_READY: marker → opNameChoice
##   opNameChoice → save identity → opUserName → opUserTimezone → opUserLanguage → opDone
##   opDone → normal LLM conversation with personality-aware system prompt.
##
## Debounce:
##   collectWithDebounce awaits the first task message, then keeps collecting
##   additional messages arriving within `DebounceWindowMs` using Chronos
##   withTimeout. Merged text is dispatched to the LLM as a single turn.
##
## Streaming:
##   When a StreamFn is provided, the LLM call runs in a dedicated OS thread
##   so SSE reading does not block the Chronos event loop. Tokens flow via a
##   Nim Channel[string] polled with sleepAsync(30ms). Every StreamFlushMs the
##   orchestrator flushes accumulated tokens to the global outbox as an
##   OutboundMessage with isPartial=true. The final flush has isPartial=false.

import std/json
import std/options
import std/os
import std/strutils except strip
import std/strformat
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../core/log
import ../core/outbound/outbound
import ../core/onboarding/onboarding
import ../core/tooling/tool_loop
import ../core/security/secret_scan
import ../core/agent_events
import ../domain/agent_message
import ../domain/message
import ../domain/personality
import ../domain/more_tools
import ../config/types as cfgTypes
import ./session_manager
import ./sandbox
import ../ports/provider
import ../ports/memory
import ../ports/http
import ../ports/tool
import ./memory_agent
import ./tool_agent
import ./session_state
import ./channel_prefs_parse
import ./native_tools

export onboarding

const
  MaxToolRoundsOrch    = 50   ## hard safety cap; loop ends earlier on repeated calls
  RepeatAbortThreshold = 2    ## abort if same (tool, args) seen ≥ this many times
  DebounceWindowMs*    = 1_200
  StreamFlushMs        = 1_000

type TypingFn* = proc(userId: UserId; channel: ChannelKind) {.gcsafe, raises: [].}

type ToolCallResult = object
  text:          string
  resultKind:    ToolResultKind
  checkpointNow: bool
  newHistory:    Option[ConversationHistory]

type ToolBatchResult = ToolBatchState

type NormalTurnPrep = object
  history:        ConversationHistory
  context:        string
  systemBase:     string
  agentName:      string
  agentTraits:    PersonalityTraits
  identityLoaded: bool
  obPhase:        OnboardingPhase
  showReasoning:  bool

type TypingFlag = ref bool

type OnboardingTurnResult = object
  history:            ConversationHistory
  onboarding:         OnboardingRuntime
  identity:           IdentityRuntime
  handled:            bool

type ControlTaskResult = object
  history:       ConversationHistory
  onboarding:    OnboardingRuntime
  identity:      IdentityRuntime
  debugMode:     bool
  showReasoning: bool
  handled:       bool

type OrchestratorState = object
  history:       ConversationHistory
  debugMode:     bool
  showReasoning: bool
  lastUserId:    UserId
  onboarding:    OnboardingRuntime
  identity:    IdentityRuntime
  turnSeq:     int

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

type UserTurnSetup = object
  uid:         UserId
  streamId:    string
  userText:    string
  isNewUser:   bool
  nativeCtx:   NativeCtx
  typingLoop:  TypingFlag

type ActorMessageResult = object
  stateRuntime: OrchestratorState
  shouldStop:   bool

func providerLabelFromPrefs*(prefs: string): string =
  ## Extracts "provider/model" label from PREFERENCES.md TOML content.
  ## Returns "zai-coding" (default) when not set.
  var prov = "zai-coding"
  var mdl  = ""
  for line in strutils.splitLines(prefs):
    let parts = strutils.split(line, '=', 1)
    if parts.len != 2: continue
    let k = strutils.strip(parts[0])
    let v = strutils.strip(parts[1]).strip(chars = {'"'})
    case k
    of "provider": prov = v
    of "model":    mdl  = v
    else: discard
  if mdl.len > 0: prov & "/" & mdl else: prov

# ── Helpers ────────────────────────────────────────────────────────────────────

proc safeComplete(fn: CompleteFn; req: CompletionRequest
                 ): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try: fn(req)
  except Exception as e: err(e.msg)

func orchToolsSuffix*(tools: seq[ToolDescription]): string =
  if tools.len == 0: return ""
  result = "\n\n## Available tools\n\n"
  result.add "You have access to the following tools. When a task requires one of them, " &
             "call it — do not tell the user you cannot access files, the web, or run commands.\n\n"
  if tools.anyIt(it.name == ManageSkillsToolName):
    result.add "You can install and enable skills for the current user with `manage_skills`. " &
               "Never say your toolset is fixed or that you cannot install skills. " &
               "If the user asks whether you can install skills, how skill installation works, " &
               "or you discover a missing capability that could be provided by a skill, " &
               "use `manage_skills` or explain that you can search/install/enable a skill for them. " &
               "If the user has not provided a specific skill slug or capability yet, ask what they want to add " &
               "or offer to search the registry. " &
               "After installing or enabling a skill, tell the user it becomes available on their next message.\n\n"
  for td in tools:
    result.add &"- **{td.name}**: {td.description}\n"

func buildSystemBase*(agentTraits: PersonalityTraits;
                      agentName: string;
                      toolsSuffix: string): string =
  let personalityPrompt = buildPersonalityPrompt(agentTraits, agentName)
  (if personalityPrompt.len > 0:
     personalityPrompt & "\n\n"
   else:
     "You are a personal AI assistant.\n\n") &
  "Be helpful and remember what the user tells you. " &
  "Respond in the user's preferred language." &
  toolsSuffix

proc addUserTurn*(history: ConversationHistory;
                  userText: string;
                  userImageUrl: string): ConversationHistory =
  result = history
  if userImageUrl.len > 0:
    result.addUserWithImage(userText, userImageUrl)
  else:
    result.addUser(userText)
  result.trimTo(20)

proc buildToolLoopDoneText*(toolCallCount: int): string =
  "✅ " & $toolCallCount & " tool call(s)"

proc genericProviderErrorText(errMsg: string): string =
  let lower = errMsg.toLowerAscii()
  if lower.contains("401") or lower.contains("403") or lower.contains("unauthorized") or lower.contains("api key"):
    return "Desculpe, houve um problema de autenticação com o provedor configurado."
  if lower.contains("400") or lower.contains("bad request") or lower.contains("invalid"):
    return "Desculpe, o provedor rejeitou esta solicitação."
  if lower.contains("429") or lower.contains("rate limit") or lower.contains("500") or
     lower.contains("502") or lower.contains("503") or lower.contains("504") or
     lower.contains("timeout") or lower.contains("server_error") or lower.contains("network"):
    return "Desculpe, o provedor falhou temporariamente. Tente novamente em instantes."
  "Desculpe, ocorreu um erro ao falar com o provedor configurado."

proc explainProviderError(errorExplainFn: CompleteFn;
                          providerErr: string): string {.gcsafe, raises: [].} =
  if errorExplainFn.isNil:
    return genericProviderErrorText(providerErr)
  var h = newHistory()
  h.addUser(
    "Explique este erro de provedor para um usuário final em português do Brasil, " &
    "em no máximo duas frases, sem jargão desnecessário, sem request id, sem JSON cru, " &
    "e com uma orientação prática curta.\n\nErro bruto:\n" & providerErr
  )
  let req = buildPrompt(
    "Você é um explicador de erros de infraestrutura para usuários finais. " &
    "Resuma o problema com linguagem humana, curta e útil.",
    h, "")
  let resp = safeComplete(errorExplainFn, req)
  if resp.isOk and resp.value.text.strip.len > 0:
    return resp.value.text.strip
  genericProviderErrorText(providerErr)

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

proc sendPipelineError(globalOutbox: AsyncQueue[OutboundMessage];
                       uid: UserId;
                       channel: ChannelKind;
                       replyTo: string;
                       errMsg: string): Future[void] {.async.} =
  await sendReplyText(
    globalOutbox, uid, channel, replyTo,
    "Desculpe, erro: " & errMsg)

proc safeLoadIdentity(memory: MemoryRuntimePort;
                      uid: UserId): (string, PersonalityTraits) {.gcsafe, raises: [].} =
  try:
    memory.loadIdentity(uid)
  except Exception:
    ("", PersonalityTraits())

proc safeHasProfile(memory: MemoryRuntimePort;
                    uid: UserId): bool {.gcsafe, raises: [].} =
  try:
    memory.hasProfile(uid)
  except Exception:
    false

proc safeHasCompletedBootstrap(memory: MemoryRuntimePort;
                               uid: UserId): bool {.gcsafe, raises: [].} =
  try:
    memory.loadContext(uid).userMd.strip.len > 0
  except Exception:
    false

proc safeSaveSession(memory: MemoryRuntimePort;
                     uid: UserId;
                     sessionId: string;
                     history: ConversationHistory) {.gcsafe, raises: [].} =
  try:
    memory.saveSession(uid, sessionId, history)
  except Exception:
    discard

proc safeSaveIdentity(memory: MemoryRuntimePort;
                      uid: UserId;
                      traits: PersonalityTraits;
                      name: string) {.gcsafe, raises: [].} =
  try:
    memory.saveIdentity(uid, traits, name)
  except Exception:
    discard

proc safeSaveUserMd(memory: MemoryRuntimePort;
                    uid: UserId;
                    content: string) {.gcsafe, raises: [].} =
  try:
    memory.saveUserMd(uid, content)
  except Exception:
    discard

proc safeAppendMemory(memory: MemoryRuntimePort;
                      uid: UserId;
                      text: string) {.gcsafe, raises: [].} =
  try:
    memory.appendMemory(uid, text)
  except Exception:
    discard

proc safeResetBootstrap(memory: MemoryRuntimePort;
                        uid: UserId): bool {.gcsafe, raises: [].} =
  try:
    memory.resetBootstrap(uid)
    true
  except Exception:
    false

proc unwrapOrReplyError*[T](globalOutbox: AsyncQueue[OutboundMessage];
                            uid: UserId;
                            channel: ChannelKind;
                            replyTo: string;
                            pipelineResult: Result[T, string]): Future[Option[T]] {.async.} =
  if pipelineResult.isErr:
    await sendPipelineError(globalOutbox, uid, channel, replyTo, pipelineResult.error)
    return none(T)
  some(pipelineResult.get())

proc sendNamePrompt(globalOutbox: AsyncQueue[OutboundMessage];
                    uid: UserId;
                    channel: ChannelKind;
                    replyTo: string;
                    replacementSlot = ""): Future[void] {.async.} =
  await sendReplyText(globalOutbox, uid, channel, replyTo, "Qual será meu nome?",
    replacementSlot = replacementSlot)

proc persistUserProfile(memory: MemoryRuntimePort;
                        uid: UserId;
                        profileCtx: UserProfileContext) =
  if profileCtx.saveIdentity:
    safeSaveIdentity(memory, uid, profileCtx.identity.traits, profileCtx.identity.name)
  if profileCtx.saveUserMd:
    safeSaveUserMd(memory, uid, profileCtx.userMd)

func newOrchestratorState*(): OrchestratorState =
  OrchestratorState(
    history: newHistory(),
    debugMode: false,
    showReasoning: true,
    onboarding: OnboardingRuntime(phase: opWakeUp),
    identity: IdentityRuntime(),
  )

func nextTurn*(state: OrchestratorState): OrchestratorState =
  result = state
  inc result.turnSeq

func streamIdFor*(state: OrchestratorState; userId: string): string =
  userId & "-" & $state.turnSeq

func withLastUser*(uid: UserId; state: OrchestratorState): OrchestratorState =
  result = state
  result.lastUserId = uid

func withControlResult*(controlResult: ControlTaskResult;
                        state: OrchestratorState): OrchestratorState =
  result = state
  result.history = controlResult.history
  result.onboarding = controlResult.onboarding
  result.identity = controlResult.identity
  result.debugMode = controlResult.debugMode
  result.showReasoning = controlResult.showReasoning

func withOnboardingResult*(onboardingResult: OnboardingTurnResult;
                           state: OrchestratorState): OrchestratorState =
  result = state
  result.history = onboardingResult.history
  result.onboarding = onboardingResult.onboarding
  result.identity = onboardingResult.identity

func withTurnPrep*(turnPrep: NormalTurnPrep;
                   state: OrchestratorState): OrchestratorState =
  result = state
  result.history = turnPrep.history
  result.identity.name = turnPrep.agentName
  result.identity.traits = turnPrep.agentTraits
  result.identity.identityLoaded = turnPrep.identityLoaded
  result.onboarding.phase = turnPrep.obPhase
  result.showReasoning = turnPrep.showReasoning

func withLoopResult*(loopResult: ToolLoopRunResult;
                     state: OrchestratorState): OrchestratorState =
  result = state
  result.history = loopResult.history

proc decodeUserPayload*(payload: string): (string, string) =
  ## Decodes the session payload envelope produced by ensureSession.
  ## Returns (text, mediaUrl). Plain text payloads pass through unchanged.
  result = (payload, "")
  if payload.len == 0 or payload[0] != '{':
    return
  try:
    let j = parseJson(payload)
    result[0] = j.getOrDefault("text").getStr(payload)
    result[1] = j.getOrDefault("mediaUrl").getStr("")
  except CatchableError:
    discard

# ── Debounce collector ─────────────────────────────────────────────────────────

proc collectWithDebounce(inbox: AsyncQueue[AgentMessage];
                         windowMs: int): Future[AgentMessage] {.async.} =
  ## Waits for the first amkTask, then accumulates more within windowMs.
  ## Returns a single AgentMessage with all payloads joined by "\n\n".
  ## Returns amkCancel immediately if cancel arrives at any point.
  let first = await inbox.get()
  if first.kind != amkTask: return first   ## cancel / stray — pass through

  var texts   = @[first.payload]
  var latest  = first

  while true:
    let nextFut = inbox.get()
    if not (await withTimeout(nextFut, milliseconds(windowMs))):
      break   ## timeout — debounce window closed
    let next = nextFut.read()
    case next.kind
    of amkCancel: return next          ## cancel wins
    of amkTask:
      texts.add(next.payload)
      latest = next
    else: discard

  result         = latest
  result.payload = strutils.join(texts, "\n\n")

# ── Thinking tag filter ────────────────────────────────────────────────────────

func filterThinking*(text: string): string =
  ## Removes completed <thinking>...</thinking> blocks.
  ## If a <thinking> block has no closing tag yet, strips from <thinking> to end.
  const open  = "<thinking>"
  const close = "</thinking>"
  result = ""
  var i = 0
  while i < text.len:
    let s = text.find(open, i)
    if s < 0:
      result.add(text[i .. ^1])
      break
    result.add(text[i ..< s])
    let e = text.find(close, s)
    if e < 0: break
    i = e + close.len

# ── Thread-based streaming ─────────────────────────────────────────────────────

const doneSentinel = "\x00DONE"

type StreamJob* = object
  fn*:  StreamFn
  req*: CompletionRequest
  ch*:  ptr Channel[string]
  res*: ptr CompletionResponse # Output

proc doStreamJob*(job: StreamJob) {.thread, gcsafe.} =
  let res = job.fn(job.req,
                   proc(tok: string) {.gcsafe.} = job.ch[].send(tok))
  if res.isOk:
    job.res[] = res.value
  job.ch[].send(doneSentinel)

proc streamToOutbox(fn:        StreamFn;
                    req:       CompletionRequest;
                    outbox:    AsyncQueue[OutboundMessage];
                    userId:    UserId;
                    ch:        ChannelKind;
                    replyTo:   string;
                    streamId:  string): Future[(string, string)] {.async.} =
  var tokenChan: Channel[string]
  var finalResponse: CompletionResponse
  tokenChan.open(512)

  var t: Thread[StreamJob]
  createThread(t, doStreamJob,
               StreamJob(fn: fn, req: req, ch: addr tokenChan, res: addr finalResponse))

  var accumulated = ""
  var lastFlush   = nowMs()

  while true:
    var (has, tok) = tokenChan.tryRecv()
    while has:
      if tok == doneSentinel:
        let visible = filterThinking(finalResponse.text)
        if visible.len > 0:
          await outbox.put(OutboundMessage(
            userId:    userId,
            channel:   ch,
            text:      visible,
            replyTo:   replyTo,
            streamId:  streamId,
            isPartial: false,
          ))
        else:
          await outbox.put(OutboundMessage(
            userId:    userId,
            channel:   ch,
            text:      "...",
            replyTo:   replyTo,
            streamId:  streamId,
            isPartial: false,
          ))
        tokenChan.close()
        joinThread(t)
        return (finalResponse.text, finalResponse.reasoning)
      accumulated.add(tok)
      (has, tok) = tokenChan.tryRecv()

    let visible = filterThinking(accumulated)
    if visible.len > 0 and nowMs() - lastFlush >= StreamFlushMs:
      lastFlush = nowMs()
      await outbox.put(OutboundMessage(
        userId:    userId,
        channel:   ch,
        text:      visible,
        replyTo:   replyTo,
        streamId:  streamId,
        isPartial: true,
      ))

    await sleepAsync(milliseconds(30))

  tokenChan.close()
  joinThread(t)
  return (finalResponse.text, finalResponse.reasoning)

# ── Name generation helper ─────────────────────────────────────────────────────

proc awaitExpectedReply(outbox: AsyncQueue[AgentMessage];
                        expectedId: string;
                        workerName: string): Future[AgentMessage] {.async.} =
  let reply = await outbox.get()
  if reply.id != expectedId:
    return newErrorMsg(expectedId,
      workerName & ": correlated reply mismatch (expected " & expectedId &
      ", got " & reply.id & ")")
  reply

proc invokeToolAgent(toolInbox: AsyncQueue[AgentMessage];
                     toolOut: AsyncQueue[AgentMessage];
                     msgId: string;
                     round: int;
                     callIndex: int;
                     tc: ToolCallRequest;
                     providerLabel: string;
                     log: Logger): Future[ToolCallResult] {.async.} =
  let payload = $ %* {
    "name": tc.name, "id": tc.id, "inputJson": tc.inputJson
  }
  let taskId = msgId & "-" & $round & "-" & $callIndex
  await toolInbox.put(newTaskMsg(taskId, tkInvokeTool, "", payload))
  let toolReply = await awaitExpectedReply(toolOut, taskId, "ToolAgent")
  log.info("[tool] (" & tc.name & ") -> [" & providerLabel & "] |" &
           $toolReply.text.len & "|")
  ToolCallResult(
    text: toolReply.text,
    resultKind: if toolReply.kind == amkError: trkOperationalError else: trkOutput,
  )

proc executeToolCall(globalOutbox: AsyncQueue[OutboundMessage];
                     toolInbox: AsyncQueue[AgentMessage];
                     toolOut: AsyncQueue[AgentMessage];
                     nativeCtx: NativeCtx;
                     state: SessionState;
                     history: ConversationHistory;
                     uid: UserId;
                     channel: ChannelKind;
                     msgId: string;
                     round: int;
                     callIndex: int;
                     tc: ToolCallRequest;
                     providerLabel: string;
                     debugMode: bool;
                     log: Logger): Future[ToolCallResult] {.async.} =
  if debugMode:
    await globalOutbox.put(OutboundMessage(
      userId: uid, channel: channel, text: buildToolDebugCallText(tc)))

  log.info("[tool] (" & tc.name & ") <- [" & providerLabel & "] |" &
           $tc.inputJson.len & "|")
  pushAgentEvent(AgentEvent(
    kind:     aekToolCall,
    userId:   $uid,
    channel:  $channel,
    toolName: tc.name,
    summary:  tc.inputJson[0 ..< min(tc.inputJson.len, 80)],
  ))

  let nr = await executeNativeTool(tc, nativeCtx, state, history)
  if nr.handled:
    return ToolCallResult(
      text: nr.text,
      resultKind: nr.resultKind,
      checkpointNow: nr.checkpointNow,
      newHistory: nr.newHistory,
    )

  let toolResult = await invokeToolAgent(
    toolInbox, toolOut, msgId, round, callIndex, tc, providerLabel, log)
  if debugMode:
    await globalOutbox.put(OutboundMessage(
      userId: uid, channel: channel,
      text: buildToolDebugResultText(tc.name, toolResult.text)))
  toolResult

proc processToolCalls(globalOutbox: AsyncQueue[OutboundMessage];
                      toolInbox: AsyncQueue[AgentMessage];
                      toolOut: AsyncQueue[AgentMessage];
                      nativeCtx: NativeCtx;
                      state: SessionState;
                      history: ConversationHistory;
                      uid: UserId;
                      channel: ChannelKind;
                      replyTo: string;
                      msgId: string;
                      round: int;
                      toolStatusId: string;
                      toolCalls: seq[ToolCallRequest];
                      providerLabel: string;
                      debugMode: bool;
                      toolCallCount: int;
                      recentCalls: seq[(string, string)];
                      log: Logger): Future[ToolBatchResult] {.async.} =
  result = newToolBatchState(history, toolCallCount, recentCalls)
  for i, tc in toolCalls:
    let prePlan = planToolBatchItem(
      result.recentCalls, tc, RepeatAbortThreshold, result.toolCallCount + 1, "")
    if prePlan.shouldAbort:
      await globalOutbox.put(OutboundMessage(
        userId: uid,
        channel: channel,
        text: prePlan.abortText,
        replyTo: replyTo,
      ))
      result =
        result |>->
        withAbortedBatch(prePlan)
      break
    result =
      result |>->
      withRegisteredToolCall(tc)

    let toolResult = await executeToolCall(
      globalOutbox, toolInbox, toolOut, nativeCtx, state, result.history,
      uid, channel, msgId, round, i, tc, providerLabel, debugMode, log)
    if toolResult.checkpointNow:
      state.checkpoints.add(result.history)
    ## Warn if tool output appears to contain leaked credentials.
    if hasSecrets(toolResult.text):
      log.warn("tool '" & tc.name & "' output may contain secrets — check tool output")
    pushAgentEvent(AgentEvent(
      kind:     aekToolResult,
      userId:   $uid,
      channel:  $channel,
      toolName: tc.name,
      summary:  toolResult.text[0 ..< min(toolResult.text.len, 80)],
    ))
    result =
      result |>->
      withToolResult(tc, toolResult.text, toolResult.resultKind, toolResult.newHistory)
    let postPlan = planToolBatchItem(
      @[], tc, RepeatAbortThreshold, result.toolCallCount, toolResult.text)
    await globalOutbox.put(OutboundMessage(
      userId: uid,
      channel: channel,
      text: postPlan.progressText,
      streamId: toolStatusId,
      isPartial: true,
    ))

proc prepareNormalTurn(memory: MemoryRuntimePort;
                       memInbox: AsyncQueue[AgentMessage];
                       memOut: AsyncQueue[AgentMessage];
                       uid: UserId;
                       msg: AgentMessage;
                       history: ConversationHistory;
                       identityLoaded: bool;
                       obPhase: OnboardingPhase;
                       agentName: string;
                       agentTraits: PersonalityTraits;
                       toolsSuffix: string): Future[NormalTurnPrep] {.async.} =
  result.agentName = agentName
  result.agentTraits = agentTraits
  result.identityLoaded = identityLoaded
  result.obPhase = obPhase

  let prefs = try: memory.loadContext(uid).preferencesMd |> parseChannelPrefs
              except: defaultChannelPrefs()
  result.showReasoning = prefs.reasoning == "on"

  if not result.identityLoaded:
    (result.agentName, result.agentTraits) = safeLoadIdentity(memory, uid)
    result.identityLoaded = true
    result.obPhase = opDone

  result.systemBase = buildSystemBase(
    result.agentTraits, result.agentName, toolsSuffix)

  await memInbox.put(newTaskMsg(msg.id, tkLoadCtx, msg.userId, msg.payload))
  let ctxReply = await awaitExpectedReply(memOut, msg.id, "MemoryAgent")
  result.context = if ctxReply.kind == amkResult: ctxReply.text else: ""

  let (userText, userImageUrl) = decodeUserPayload(msg.payload)
  result.history = addUserTurn(history, userText, userImageUrl)

proc startTypingLoop*(typingFn: TypingFn;
                      uid: UserId;
                      channel: ChannelKind): TypingFlag =
  var flag: TypingFlag
  new(flag)
  flag[] = true
  proc typingLoopProc() {.async.} =
    while flag[]:
      if typingFn != nil:
        typingFn(uid, channel)
      await sleepAsync(milliseconds(4_000))
  asyncSpawn typingLoopProc()
  flag

proc stopTypingLoop*(flag: TypingFlag) =
  if flag != nil:
    flag[] = false

proc finalizeNormalTurn(globalOutbox: AsyncQueue[OutboundMessage];
                        uid: UserId;
                        channel: ChannelKind;
                        replyTo: string;
                        streamId: string;
                        streamFn: StreamFn;
                        showReasoning: bool;
                        loopResult: ToolLoopRunResult): Future[void] {.async.} =
  if loopResult.toolCallCount > 0:
    await globalOutbox.put(OutboundMessage(
      userId: uid,
      channel: channel,
      text: buildToolLoopDoneText(loopResult.toolCallCount),
      streamId: streamId & "-st",
      isPartial: false,
    ))

  if not loopResult.done or not loopResult.wasStreamed:
    if loopResult.finalText.len > 0:
      var fullText = ""
      if showReasoning and loopResult.reasoning.len > 0:
        let cleanReasoning = loopResult.reasoning.strip()
        if cleanReasoning.len > 0:
          fullText = "> " & cleanReasoning.replace("\n", "\n> ") & "\n\n"
      fullText &= loopResult.finalText

      await globalOutbox.put(OutboundMessage(
        userId: uid,
        channel: channel,
        text: fullText,
        replyTo: replyTo,
      ))

proc buildNativeCtx*(uid: UserId;
                     channel: ChannelKind;
                     globalOutbox: AsyncQueue[OutboundMessage];
                     session: ptr SessionEntry;
                     memory: MemoryRuntimePort;
                     completeFn: CompleteFn;
                     http: HttpRuntimePort;
                     cfg: cfgTypes.DonkeyConfig;
                     tools: seq[ToolDescription];
                     log: Logger;
                     paddockDir: string;
                     sandboxMode: SandboxMode;
                     sandboxRuntimeCmd: string;
                     sandboxImage: string): NativeCtx =
  NativeCtx(
    uid:          uid,
    channel:      channel,
    outbox:       globalOutbox,
    session:      session,
    memory:       memory,
    completeFn:   completeFn,
    http:         http,
    braveApiKey:  getEnv("BRAVE_API_KEY", ""),
    webAllowlist: cfg.webAllowlist,
    toolWebPolicy: cfg.toolWebPolicy,
    tools:        tools,
    log:          log,
    paddockDir:   paddockDir,
    sandboxMode:  sandboxMode,
    sandboxRuntimeCmd: sandboxRuntimeCmd,
    sandboxImage: sandboxImage,
    sandboxAllowHostFallback: cfg.sandboxAllowHostFallback,
    sandboxAllowNetwork: cfg.sandboxAllowNetwork,
    sandboxReadOnlyRootfs: cfg.sandboxReadOnlyRootfs,
  )


proc handleGuidedPersonalityChoice(globalOutbox: AsyncQueue[OutboundMessage];
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

proc handleFreeConvoOnboarding(globalOutbox: AsyncQueue[OutboundMessage];
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

  if freeCtx.visibleText.len > 0:
    await sendReplyText(globalOutbox, uid, channel, replyTo, freeCtx.visibleText)

  if freeCtx.parsedTraits.isSome:
    let replacementSlot = replacementSlotFor(channel, "bootstrap")
    await sendNamePrompt(globalOutbox, uid, channel, replyTo, replacementSlot)

proc handleAgentNameOnboarding(globalOutbox: AsyncQueue[OutboundMessage];
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

proc advanceUserProfileOnboarding(globalOutbox: AsyncQueue[OutboundMessage];
                                  memory: MemoryRuntimePort;
                                  uid: UserId;
                                  channel: ChannelKind;
                                  replyTo: string;
                                  userText: string;
                                  onboarding: OnboardingRuntime;
                                  identity: IdentityRuntime): Future[(OnboardingRuntime, IdentityRuntime)] {.async.} =
  result = (onboarding, identity)
  let pipelineResult = startUserProfileContext(onboarding, identity, userText)
  let profileOpt = await unwrapOrReplyError(
    globalOutbox, uid, channel, replyTo, pipelineResult)
  if profileOpt.isNone:
    return

  let profileCtx = profileOpt.get()
  result = (profileCtx.onboarding, profileCtx.identity)
  persistUserProfile(memory, uid, profileCtx)
  if profileCtx.replyText.len > 0:
    let replacementSlot = replacementSlotFor(channel, "bootstrap")
    await sendReplyText(globalOutbox, uid, channel, replyTo, profileCtx.replyText,
      replacementSlot = replacementSlot)

proc handleResetControlTask(globalOutbox: AsyncQueue[OutboundMessage];
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

proc handleDebugToggleControlTask(globalOutbox: AsyncQueue[OutboundMessage];
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

proc handleCompactControlTask(globalOutbox: AsyncQueue[OutboundMessage];
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

proc handleNewSessionTask(globalOutbox: AsyncQueue[OutboundMessage];
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

proc handleOnboardingControlTask(globalOutbox: AsyncQueue[OutboundMessage];
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
      globalOutbox, completeFn, uid, channel, replyTo,
      decision.onboarding, decision.dim, decision.value)
    result[2] = decision.handled

  of oekNameChoice:
    (result[0], result[1]) = await advanceUserProfileOnboarding(
      globalOutbox, memory, uid, channel, replyTo,
      decision.name, decision.onboarding, decision.identity)
    result[2] = decision.handled

  else:
    discard

proc prepareUserTurnSetup(globalOutbox: AsyncQueue[OutboundMessage];
                          session: ptr SessionEntry;
                          memory: MemoryRuntimePort;
                          completeFn: CompleteFn;
                          http: HttpRuntimePort;
                          tools: seq[ToolDescription];
                          webAllowlist: seq[string];
                          toolWebPolicy: seq[cfgTypes.ToolWebPolicy];
                          paddockDir: string;
                          typingFn: TypingFn;
                          log: Logger;
                          sandboxMode: SandboxMode;
                          sandboxRuntimeCmd: string;
                          sandboxImage: string;
                          msg: AgentMessage;
                          stateRuntime: OrchestratorState): UserTurnSetup =
  result.uid = UserId(msg.userId)
  result.streamId = stateRuntime.streamIdFor(msg.userId)
  (result.userText, _) = msg.payload |> decodeUserPayload
  result.isNewUser = not safeHasProfile(memory, result.uid)
  result.nativeCtx = buildNativeCtx(
    result.uid, msg.channel, globalOutbox, session, memory, completeFn, http,
    cfgTypes.DonkeyConfig(webAllowlist: webAllowlist, toolWebPolicy: toolWebPolicy),
    tools, log,
    paddockDir, sandboxMode, sandboxRuntimeCmd, sandboxImage)
  createDir(paddockDir)
  result.typingLoop = startTypingLoop(typingFn, result.uid, msg.channel)

proc handleControlTask(globalOutbox: AsyncQueue[OutboundMessage];
                       memory: MemoryRuntimePort;
                       completeFn: CompleteFn;
                        uid: UserId;
                       channel: ChannelKind;
                       replyTo: string;
                        msg: AgentMessage;
                       history: ConversationHistory;
                       onboarding: OnboardingRuntime;
                       identity: IdentityRuntime;
                       debugMode: bool;
                       showReasoning: bool;
                       log: Logger;
                       sessionId: string): Future[ControlTaskResult] {.async.} =
  result.history = history
  result.onboarding = onboarding
  result.identity = identity
  result.debugMode = debugMode
  result.showReasoning = showReasoning

  case msg.taskKind
  of tkReset:
    let (nextHistory, nextOnboarding, resetApplied) = await handleResetControlTask(
      globalOutbox, memory, uid, channel, replyTo, log, sessionId, result.history)
    result.history = nextHistory
    if resetApplied:
      result.onboarding = nextOnboarding
      result.identity = IdentityRuntime()
    result.handled = true

  of tkDebugToggle:
    result.debugMode = await handleDebugToggleControlTask(
      globalOutbox, uid, channel, replyTo, result.debugMode)
    result.handled = true

  of tkCompact:
    result.history = await handleCompactControlTask(
      globalOutbox, uid, channel, replyTo, result.history)
    result.handled = true

  of tkNew:
    result.history = await handleNewSessionTask(
      globalOutbox, memory, uid, channel, replyTo, sessionId, result.history)
    result.handled = true

  of tkStop:
    await sendReplyText(globalOutbox, uid, channel, replyTo, "🛑 Parado.")
    result.handled = true

  of tkRestart:
    result.history = await handleNewSessionTask(
      globalOutbox, memory, uid, channel, replyTo, sessionId, result.history)
    result.handled = true

  of tkBind:
    await sendReplyText(globalOutbox, uid, channel, replyTo, "🔗 Bind: funcionalidade em implementação.")
    result.handled = true

  of tkPersonalityChoice, tkNameChoice:
    (result.onboarding, result.identity, result.handled) = await handleOnboardingControlTask(
      globalOutbox, memory, completeFn, uid, channel, replyTo,
      msg, result.onboarding, result.identity)

  else:
    discard

proc handleOnboardingTurn(globalOutbox: AsyncQueue[OutboundMessage];
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
      globalOutbox, completeFn, uid, channel, replyTo,
      userText |> strutils.strip, result.history, result.onboarding)

  of oekUserProfileText:
    if result.onboarding.phase == opNameChoice:
      (result.history, result.onboarding, result.identity) = await handleAgentNameOnboarding(
        globalOutbox, memory, completeFn, uid, channel, replyTo,
        userText |> strutils.strip, result.history, result.onboarding, result.identity)
    else:
      (result.onboarding, result.identity) = await advanceUserProfileOnboarding(
        globalOutbox, memory, uid, channel, replyTo,
        userText |> strutils.strip, result.onboarding, result.identity)

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

proc runToolLoop(globalOutbox: AsyncQueue[OutboundMessage];
                 toolInbox: AsyncQueue[AgentMessage];
                 toolOut: AsyncQueue[AgentMessage];
                 memory: MemoryRuntimePort;
                 completeFn: CompleteFn;
                 errorExplainFn: CompleteFn;
                 streamFn: StreamFn;
                 nativeCtx: NativeCtx;
                 state: SessionState;
                 history: ConversationHistory;
                 uid: UserId;
                 channel: ChannelKind;
                 replyTo: string;
                 msgId: string;
                 streamId: string;
                 systemBase: string;
                 context: string;
                 tools: seq[ToolDescription];
                 providerLabel: string;
                 debugMode: bool;
                 showReasoning: bool;
                 log: Logger): Future[ToolLoopRunResult] {.async.} =
  var loopState = history |> newToolLoopState
  var round = 0
  var recentCalls: seq[(string, string)] = @[]
  let toolStatusId = streamId & "-st"

  while not loopState.done and round < MaxToolRoundsOrch:
    inc round

    let req = buildPrompt(systemBase, loopState.history, context, tools, reasoning = showReasoning)

    if decideToolLoopStreaming(
      round = round,
      toolsCount = tools.len,
      streamingAvailable = streamFn != nil,
    ).useStreaming:
      let (streamText, streamReasoning) = await streamToOutbox(
        streamFn, req, globalOutbox, uid, channel, replyTo, streamId)

      log.info($uid & " (" & $channel & ") <- [" & providerLabel &
               "] |" & $streamText.len & "| stream")
      loopState =
        loopState |>->
        withStreamFinalText(streamText, streamReasoning)
      continue
    let resp = safeComplete(completeFn, req)
    if resp.isErr:
      pushAgentEvent(AgentEvent(
        kind:    aekError,
        userId:  $uid,
        channel: $channel,
        summary: "provider: " & resp.error[0 ..< min(resp.error.len, 80)],
      ))
      await globalOutbox.put(OutboundMessage(
        userId: uid,
        channel: channel,
        text: explainProviderError(errorExplainFn, resp.error),
        replyTo: replyTo,
      ))
      loopState.done = true
      continue

    let r = resp.value
    case decideToolLoopRound(
      round = round,
      toolsCount = tools.len,
      streamingAvailable = false,
      completion = r,
    ).kind
    of tlrkHandleCompletion:
      if r.text.len > 0:
        log.info($uid & " (" & $channel & ") <- [" & providerLabel &
                 "] |" & $r.text.len & "|")
        pushAgentEvent(AgentEvent(
          kind:    aekModelResponse,
          userId:  $uid,
          channel: $channel,
          summary: r.text[0 ..< min(r.text.len, 80)],
        ))
      let completionResult = applyCompletionDecision(
        loopState.history,
        decideCompletion(r, debugMode),
      )
      loopState =
        loopState |>->
        withCompletionResult(completionResult)
      if completionResult.debugText.len > 0:
        await globalOutbox.put(OutboundMessage(
          userId: uid, channel: channel, text: completionResult.debugText))
      continue

    of tlrkHandleToolBatch:
      loopState.history.addAssistantWithToolCalls(r.text, r.toolCalls)
      let batchResult = await processToolCalls(
        globalOutbox, toolInbox, toolOut, nativeCtx, state, loopState.history,
        uid, channel, replyTo, msgId, round, toolStatusId, r.toolCalls,
        providerLabel, debugMode, loopState.toolCallCount, recentCalls, log)
      loopState =
        loopState |>->
        withToolBatchState(batchResult)
      recentCalls = batchResult.recentCalls

    of tlrkUseStreaming:
      discard
  let termination = decideToolLoopTermination(loopState.done, round, MaxToolRoundsOrch)
  if termination.kind == tltkExceededMaxRounds:
    loopState.done = false
    loopState.finalText = termination.replyText
  loopState

proc handleUserTurn(globalOutbox: AsyncQueue[OutboundMessage];
                    memInbox: AsyncQueue[AgentMessage];
                    toolInbox: AsyncQueue[AgentMessage];
                    memOut: AsyncQueue[AgentMessage];
                    toolOut: AsyncQueue[AgentMessage];
                    session: ptr SessionEntry;
                    memory: MemoryRuntimePort;
                    completeFn: CompleteFn;
                    errorExplainFn: CompleteFn;
                    http: HttpRuntimePort;
                    streamFn: StreamFn;
                    tools: seq[ToolDescription];
                    webAllowlist: seq[string];
                    toolWebPolicy: seq[cfgTypes.ToolWebPolicy];
                    paddockDir: string;
                    typingFn: TypingFn;
                    log: Logger;
                    providerLabel: string;
                    sandboxMode: SandboxMode;
                    sandboxRuntimeCmd: string;
                    sandboxImage: string;
                    toolsSuffix: string;
                    state: SessionState;
                    msg: AgentMessage;
                    stateRuntime: OrchestratorState): Future[OrchestratorState] {.async.} =
  result = stateRuntime |> nextTurn
  let turnSetup = prepareUserTurnSetup(
    globalOutbox, session, memory, completeFn, http, tools, webAllowlist, toolWebPolicy,
    paddockDir, typingFn, log,
    sandboxMode, sandboxRuntimeCmd, sandboxImage, msg, result)

  if turnSetup.isNewUser:
    let onboardingResult = await handleOnboardingTurn(
      globalOutbox, memory, completeFn, turnSetup.uid, msg.channel, msg.replyTo, turnSetup.userText,
      result.history, result.onboarding, result.identity)
    result =
      result |>->
      withOnboardingResult(onboardingResult)
    if onboardingResult.handled:
      return

  let turnPrep = await prepareNormalTurn(
    memory, memInbox, memOut, turnSetup.uid, msg, result.history,
    result.identity.identityLoaded, result.onboarding.phase,
    result.identity.name, result.identity.traits, toolsSuffix)
  result =
    result |>->
    withTurnPrep(turnPrep)

  log.info($turnSetup.uid & " (" & $msg.channel & ") -> [" & providerLabel & "] |" &
           $turnSetup.userText.len & "|")
  let loopResult = await runToolLoop(
    globalOutbox, toolInbox, toolOut, memory, completeFn, errorExplainFn, streamFn, turnSetup.nativeCtx,
    state, result.history, turnSetup.uid, msg.channel, msg.replyTo, msg.id, turnSetup.streamId,
    turnPrep.systemBase, turnPrep.context, tools, providerLabel,
    result.debugMode, result.showReasoning, log)
  result =
    result |>->
    withLoopResult(loopResult)

  stopTypingLoop(turnSetup.typingLoop)
  await finalizeNormalTurn(
    globalOutbox, turnSetup.uid, msg.channel, msg.replyTo, turnSetup.streamId, streamFn, result.showReasoning, loopResult)

  # Capture memory from substantive user messages
  if turnSetup.userText.len > 30 and loopResult.finalText.len > 0:
    let memEntry = "- **User:** " & turnSetup.userText[0 ..< min(turnSetup.userText.len, 500)] & "\n" &
      "  **Response:** " & loopResult.finalText[0 ..< min(loopResult.finalText.len, 500)] & "\n"
    safeAppendMemory(memory, turnSetup.uid, memEntry)

proc handleActorCancel(memory:          MemoryRuntimePort;
                       memInbox:         AsyncQueue[AgentMessage];
                       toolInbox:        AsyncQueue[AgentMessage];
                       sessionId:        string;
                       stateRuntime:     OrchestratorState): Future[void] {.async.} =
  ## Save history on cancel so mid-turn rebuilds don't lose context.
  safeSaveSession(memory, stateRuntime.lastUserId, sessionId, stateRuntime.history)
  await memInbox.put(newCancelMsg())
  await toolInbox.put(newCancelMsg())

proc handleActorTask(globalOutbox: AsyncQueue[OutboundMessage];
                     session: ptr SessionEntry;
                     memInbox: AsyncQueue[AgentMessage];
                     toolInbox: AsyncQueue[AgentMessage];
                     memOut: AsyncQueue[AgentMessage];
                     toolOut: AsyncQueue[AgentMessage];
                     memory: MemoryRuntimePort;
                     completeFn: CompleteFn;
                     errorExplainFn: CompleteFn;
                     http: HttpRuntimePort;
                     streamFn: StreamFn;
                     tools: seq[ToolDescription];
                     webAllowlist: seq[string];
                     toolWebPolicy: seq[cfgTypes.ToolWebPolicy];
                     paddockDir: string;
                     typingFn: TypingFn;
                     log: Logger;
                     providerLabel: string;
                     sandboxMode: SandboxMode;
                     sandboxRuntimeCmd: string;
                     sandboxImage: string;
                     sessionId: string;
                     toolsSuffix: string;
                     state: SessionState;
                     msg: AgentMessage;
                     stateRuntime: OrchestratorState): Future[OrchestratorState] {.async.} =
  result = stateRuntime
  let uid = UserId(msg.userId)
  result =
    result |>->
    withLastUser(uid)

  let controlResult = await handleControlTask(
    globalOutbox, memory, completeFn, uid, msg.channel, msg.replyTo, msg,
    result.history, result.onboarding, result.identity,
    result.debugMode, result.showReasoning, log, sessionId)
  result =
    result |>->
    withControlResult(controlResult)
  if controlResult.handled and msg.taskKind == tkUserMsg:
    safeSaveSession(memory, uid, sessionId, result.history)
  if controlResult.handled or msg.taskKind notin {tkUserMsg, tkHeartbeat}:
    return
  if msg.taskKind == tkHeartbeat and not safeHasCompletedBootstrap(memory, uid):
    return

  result = await handleUserTurn(
    globalOutbox, memInbox, toolInbox, memOut, toolOut, session, memory,
    completeFn, errorExplainFn, http, streamFn, tools, webAllowlist, toolWebPolicy, paddockDir, typingFn, log,
    providerLabel, sandboxMode, sandboxRuntimeCmd, sandboxImage, toolsSuffix,
    state, msg, result)
  safeSaveSession(memory, uid, sessionId, result.history)

proc handleActorMessage(inbox: AsyncQueue[AgentMessage];
                        session: ptr SessionEntry;
                        globalOutbox: AsyncQueue[OutboundMessage];
                        memInbox: AsyncQueue[AgentMessage];
                        toolInbox: AsyncQueue[AgentMessage];
                        memOut: AsyncQueue[AgentMessage];
                        toolOut: AsyncQueue[AgentMessage];
                        memory: MemoryRuntimePort;
                        completeFn: CompleteFn;
                        errorExplainFn: CompleteFn;
                        http: HttpRuntimePort;
                        streamFn: StreamFn;
                        tools: seq[ToolDescription];
                        webAllowlist: seq[string];
                        toolWebPolicy: seq[cfgTypes.ToolWebPolicy];
                        paddockDir: string;
                        typingFn: TypingFn;
                        log: Logger;
                        providerLabel: string;
                        sandboxMode: SandboxMode;
                        sandboxRuntimeCmd: string;
                        sandboxImage: string;
                        sessionId: string;
                        toolsSuffix: string;
                        state: SessionState;
                        msg: AgentMessage;
                        stateRuntime: OrchestratorState): Future[ActorMessageResult] {.async.} =
  result.stateRuntime = stateRuntime
  case msg.kind
  of amkCancel:
    await handleActorCancel(memory, memInbox, toolInbox, sessionId, stateRuntime)
    result.shouldStop = true

  of amkTask:
    result.stateRuntime = await handleActorTask(
      globalOutbox, session, memInbox, toolInbox, memOut, toolOut, memory,
      completeFn, errorExplainFn, http, streamFn, tools, webAllowlist, toolWebPolicy, paddockDir, typingFn, log,
      providerLabel, sandboxMode, sandboxRuntimeCmd, sandboxImage, sessionId,
      toolsSuffix, state, msg, stateRuntime)

  else:
    discard

# ── Main orchestrator ──────────────────────────────────────────────────────────

proc runOrchestrator*(inbox:          AsyncQueue[AgentMessage];
                      session:        ptr SessionEntry;
                      globalOutbox:   AsyncQueue[OutboundMessage];
                      memory:         MemoryRuntimePort;
                      completeFn:     CompleteFn;
                      http:           HttpRuntimePort;
                      streamFn:       StreamFn;
                      clients:        seq[ToolRuntimePort];
                      tools:          seq[ToolDescription];
                      paddockDir:     string;
                      state:          SessionState;
                      typingFn:       TypingFn    = nil;
                      searchFn:       SearchFn    = nil;
                      log:            Logger      = newLogger("orch");
                      providerLabel:  string      = "?";
                      skillPrompt:    string      = "";
                      sandboxMode:    SandboxMode = smNone;
                      sandboxRuntimeCmd: string   = "docker";
                      sandboxImage:   string      = "alpine";
                      webAllowlist:   seq[string] = @[];
                      toolWebPolicy:  seq[cfgTypes.ToolWebPolicy] = @[];
                      errorExplainFn: CompleteFn = nil): Future[void] {.async.} =
  ## Persistent actor. Loops: debounce → memory → LLM → reply → repeat.
  let memInbox  = newAsyncQueue[AgentMessage]()
  let toolInbox = newAsyncQueue[AgentMessage]()
  let memOut    = newAsyncQueue[AgentMessage]()
  let toolOut   = newAsyncQueue[AgentMessage]()

  let memAgentFut = runMemoryAgent(memInbox, memOut, memory, searchFn)
  let toolAgentFut = runToolAgent(toolInbox, toolOut, clients)
  sandboxLogLevel(sandboxMode, sandboxImage, sandboxRuntimeCmd, log)

  var stateRuntime = newOrchestratorState()
  let sessionId   = $nowMs()
  pushAgentEvent(AgentEvent(kind: aekSessionStart, summary: "session " & sessionId))
  let toolsSuffix =
    (tools |> orchToolsSuffix) &
    (if skillPrompt.len > 0: "\n\n" & skillPrompt else: "")

  while true:
    let msg = await collectWithDebounce(inbox, DebounceWindowMs)
    let actorResult = await handleActorMessage(
      inbox, session, globalOutbox, memInbox, toolInbox, memOut, toolOut, memory,
      completeFn, errorExplainFn, http, streamFn, tools, webAllowlist, toolWebPolicy, paddockDir, typingFn, log,
      providerLabel, sandboxMode, sandboxRuntimeCmd, sandboxImage, sessionId,
      toolsSuffix, state, msg, stateRuntime)
    stateRuntime = actorResult.stateRuntime
    if actorResult.shouldStop:
      break
  await memAgentFut
  await toolAgentFut
