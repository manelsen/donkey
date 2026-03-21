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
import ../core/onboarding/onboarding
import ../core/tooling/tool_loop
import ../domain/agent_message
import ../domain/message
import ../domain/personality
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

type TypingFlag = ref bool

type OnboardingTurnResult = object
  history:            ConversationHistory
  onboarding:         OnboardingRuntime
  identity:           IdentityRuntime
  handled:            bool

type ControlTaskResult = object
  history:      ConversationHistory
  onboarding:   OnboardingRuntime
  identity:     IdentityRuntime
  debugMode:    bool
  handled:      bool

type OrchestratorState = object
  history:     ConversationHistory
  debugMode:   bool
  lastUserId:  UserId
  onboarding:  OnboardingRuntime
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
  ## Returns "zhipu" (default) when not set.
  var prov = "zhipu"
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

proc generateNames(completeFn: CompleteFn;
                   traits: PersonalityTraits): seq[string] {.gcsafe, raises: [].}

func orchToolsSuffix(tools: seq[ToolDescription]): string =
  if tools.len == 0: return ""
  result = "\n\n## Available tools\n"
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
      if ctx.parsedTraits.isNone:
        return ok(ctx)
      var nextCtx = ctx
      var names: seq[string]
      {.cast(gcsafe).}: names = generateNames(completeFn, nextCtx.onboarding.traits)
      nextCtx.onboarding.names = names
      nextCtx.onboarding.phase = opNameChoice
      ok(nextCtx)

proc finalizeGuidedChoice*(completeFn: CompleteFn): proc(ctx: GuidedChoiceContext): Result[GuidedChoiceContext, string] {.gcsafe, raises: [].} =
  result =
    proc(ctx: GuidedChoiceContext): Result[GuidedChoiceContext, string] {.gcsafe, raises: [].} =
      if not ctx.needsNames:
        return ok(ctx)
      var nextCtx = ctx
      var names: seq[string]
      {.cast(gcsafe).}: names = generateNames(completeFn, nextCtx.onboarding.traits)
      nextCtx.onboarding.names = names
      ok(nextCtx)

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

proc sendReplyText*(globalOutbox: AsyncQueue[OutboundMessage];
                    uid: UserId;
                    channel: ChannelKind;
                    replyTo: string;
                    text: string): Future[void] {.async.} =
  await globalOutbox.put(OutboundMessage(
    userId: uid,
    channel: channel,
    text: text,
    replyTo: replyTo,
  ))

proc sendReplyKeyboard*(globalOutbox: AsyncQueue[OutboundMessage];
                        uid: UserId;
                        channel: ChannelKind;
                        replyTo: string;
                        text: string;
                        keyboard: seq[seq[(string, string)]]): Future[void] {.async.} =
  await globalOutbox.put(OutboundMessage(
    userId: uid,
    channel: channel,
    text: text,
    replyTo: replyTo,
    keyboard: keyboard,
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

func buildNameChoiceKeyboard*(names: seq[string]): seq[seq[(string, string)]] =
  var nameRow: seq[(string, string)] = @[]
  for n in names:
    nameRow.add((n, "name:" & n))
  @[nameRow]

proc unwrapOrReplyError*[T](globalOutbox: AsyncQueue[OutboundMessage];
                            uid: UserId;
                            channel: ChannelKind;
                            replyTo: string;
                            pipelineResult: Result[T, string]): Future[Option[T]] {.async.} =
  if pipelineResult.isErr:
    await sendPipelineError(globalOutbox, uid, channel, replyTo, pipelineResult.error)
    return none(T)
  some(pipelineResult.get())

proc sendNameChoiceOrPrompt(globalOutbox: AsyncQueue[OutboundMessage];
                            uid: UserId;
                            channel: ChannelKind;
                            replyTo: string;
                            names: seq[string];
                            keyboardText: string): Future[void] {.async.} =
  if names.len > 0:
    await sendReplyKeyboard(
      globalOutbox, uid, channel, replyTo,
      keyboardText,
      buildNameChoiceKeyboard(names))
  else:
    await sendReplyText(globalOutbox, uid, channel, replyTo, "Que nome você quer me dar?")

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

proc doStreamJob*(job: StreamJob) {.thread.} =
  {.cast(gcsafe).}:
    discard job.fn(job.req,
                   proc(tok: string) = job.ch[].send(tok))
    job.ch[].send(doneSentinel)

proc streamToOutbox(fn:        StreamFn;
                    req:       CompletionRequest;
                    outbox:    AsyncQueue[OutboundMessage];
                    userId:    UserId;
                    ch:        ChannelKind;
                    replyTo:   string;
                    streamId:  string): Future[string] {.async.} =
  var tokenChan: Channel[string]
  tokenChan.open(512)

  var t: Thread[StreamJob]
  createThread(t, doStreamJob,
               StreamJob(fn: fn, req: req, ch: addr tokenChan))

  var accumulated = ""
  var lastFlush   = nowMs()

  while true:
    var (has, tok) = tokenChan.tryRecv()
    while has:
      if tok == doneSentinel:
        let visible = filterThinking(accumulated)
        if visible.len > 0:
          await outbox.put(OutboundMessage(
            userId:    userId,
            channel:   ch,
            text:      visible,
            replyTo:   replyTo,
            streamId:  streamId,
            isPartial: false,
          ))
        tokenChan.close()
        joinThread(t)
        return accumulated
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
  return accumulated

# ── Name generation helper ─────────────────────────────────────────────────────

proc generateNames(completeFn: CompleteFn;
                   traits: PersonalityTraits): seq[string] {.gcsafe, raises: [].} =
  ## Asks LLM to suggest 5 names matching the given traits.
  ## Returns whatever names are parsed; empty seq on failure.
  var h = newHistory()
  h.addUser(buildNameGenPrompt(traits))
  let req  = buildPrompt(
    "You are a creative naming assistant. Output exactly 5 names, one per line, no numbering, no explanation.",
    h, "")
  let resp = safeComplete(completeFn, req)
  if resp.isErr: return @[]
  parseNameOptions(resp.value.text)

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
                     log: Logger): Future[string] {.async.} =
  let payload = $ %* {
    "name": tc.name, "id": tc.id, "inputJson": tc.inputJson
  }
  let taskId = msgId & "-" & $round & "-" & $callIndex
  await toolInbox.put(newTaskMsg(taskId, tkInvokeTool, "", payload))
  let toolReply = await awaitExpectedReply(toolOut, taskId, "ToolAgent")
  log.info("[tool] (" & tc.name & ") -> [" & providerLabel & "] |" &
           $toolReply.text.len & "|")
  toolReply.text

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

  let nr = await executeNativeTool(tc, nativeCtx, state, history)
  if nr.handled:
    return ToolCallResult(
      text: nr.text,
      checkpointNow: nr.checkpointNow,
      newHistory: nr.newHistory,
    )

  let toolResult = await invokeToolAgent(
    toolInbox, toolOut, msgId, round, callIndex, tc, providerLabel, log)
  if debugMode:
    await globalOutbox.put(OutboundMessage(
      userId: uid, channel: channel,
      text: buildToolDebugResultText(tc.name, toolResult)))
  ToolCallResult(text: toolResult)

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
    result =
      result |>->
      withToolResult(tc, toolResult.text, toolResult.newHistory)
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

  if not result.identityLoaded:
    {.cast(gcsafe).}:
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
        {.cast(gcsafe).}: typingFn(uid, channel)
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
                        loopResult: ToolLoopRunResult): Future[void] {.async.} =
  if loopResult.toolCallCount > 0:
    await globalOutbox.put(OutboundMessage(
      userId: uid,
      channel: channel,
      text: buildToolLoopDoneText(loopResult.toolCallCount),
      streamId: streamId & "-st",
      isPartial: false,
    ))

  if not loopResult.done:
    await globalOutbox.put(OutboundMessage(
      userId: uid,
      channel: channel,
      text: loopResult.finalText,
      replyTo: replyTo,
    ))
  elif streamFn == nil:
    await globalOutbox.put(OutboundMessage(
      userId: uid,
      channel: channel,
      text: loopResult.finalText,
      replyTo: replyTo,
    ))

proc buildNativeCtx*(uid: UserId;
                     channel: ChannelKind;
                     globalOutbox: AsyncQueue[OutboundMessage];
                     session: ptr SessionEntry;
                     memory: MemoryRuntimePort;
                     completeFn: CompleteFn;
                     http: HttpRuntimePort;
                     tools: seq[ToolDescription];
                     log: Logger;
                     paddockDir: string;
                     sandboxMode: SandboxMode;
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
    tools:        tools,
    log:          log,
    paddockDir:   paddockDir,
    sandboxMode:  sandboxMode,
    sandboxImage: sandboxImage,
  )

proc handleCancel(memory: MemoryRuntimePort;
                  memInbox: AsyncQueue[AgentMessage];
                  toolInbox: AsyncQueue[AgentMessage];
                  lastUserId: UserId;
                  sessionId: string;
                  history: ConversationHistory): Future[void] {.async.} =
  if $lastUserId != "":
    safeSaveSession(memory, lastUserId, sessionId, history)
  await memInbox.put(newCancelMsg())
  await toolInbox.put(newCancelMsg())

proc persistSessionSnapshot(memory: MemoryRuntimePort;
                            userId: UserId;
                            sessionId: string;
                            history: ConversationHistory) =
  if $userId == "":
    return
  safeSaveSession(memory, userId, sessionId, history)

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

  if guidedCtx.keyboard.len > 0:
    await sendReplyKeyboard(globalOutbox, uid, channel, replyTo, guidedCtx.replyText, guidedCtx.keyboard)
  elif guidedCtx.needsNames:
    await sendNameChoiceOrPrompt(
      globalOutbox, uid, channel, replyTo,
      guidedCtx.onboarding.names,
      "Aqui estão alguns nomes que combinam com essa personalidade. Qual prefere?")
  elif guidedCtx.replyText.len > 0:
    await sendReplyText(globalOutbox, uid, channel, replyTo, guidedCtx.replyText)

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
    await sendNameChoiceOrPrompt(
      globalOutbox, uid, channel, replyTo,
      freeCtx.onboarding.names,
      "Com base em quem você quer que eu seja, aqui estão alguns nomes:")

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
    await sendReplyText(globalOutbox, uid, channel, replyTo, profileCtx.replyText)

proc handleResetControlTask(globalOutbox: AsyncQueue[OutboundMessage];
                            memory: MemoryRuntimePort;
                            uid: UserId;
                            channel: ChannelKind;
                            replyTo: string;
                            sessionId: string;
                            history: ConversationHistory): Future[ConversationHistory] {.async.} =
  let pipelineResult = startResetControlContext(history, sessionId)
  let resetOpt = await unwrapOrReplyError(
    globalOutbox, uid, channel, replyTo, pipelineResult)
  if resetOpt.isNone:
    return history
  let resetCtx = resetOpt.get()
  if resetCtx.shouldPersist:
    safeSaveSession(memory, uid, resetCtx.sessionId, history)
  await sendReplyText(globalOutbox, uid, channel, replyTo, resetCtx.replyText)
  resetCtx.history

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
                          paddockDir: string;
                          typingFn: TypingFn;
                          log: Logger;
                          sandboxMode: SandboxMode;
                          sandboxImage: string;
                          msg: AgentMessage;
                          stateRuntime: OrchestratorState): UserTurnSetup =
  result.uid = UserId(msg.userId)
  result.streamId = stateRuntime.streamIdFor(msg.userId)
  (result.userText, _) = msg.payload |> decodeUserPayload
  result.isNewUser = not safeHasProfile(memory, result.uid)
  result.nativeCtx = buildNativeCtx(
    result.uid, msg.channel, globalOutbox, session, memory, completeFn, http, tools, log,
    paddockDir, sandboxMode, sandboxImage)
  {.cast(gcsafe).}: createDir(paddockDir)
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
                       sessionId: string): Future[ControlTaskResult] {.async.} =
  result.history = history
  result.onboarding = onboarding
  result.identity = identity
  result.debugMode = debugMode

  case msg.taskKind
  of tkReset:
    result.history = await handleResetControlTask(
      globalOutbox, memory, uid, channel, replyTo, sessionId, result.history)
    result.handled = true

  of tkDebugToggle:
    result.debugMode = await handleDebugToggleControlTask(
      globalOutbox, uid, channel, replyTo, result.debugMode)
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
    await sendReplyKeyboard(
      globalOutbox, uid, channel, replyTo,
      decision.replyText, decision.keyboard)

  of oekButtonOnly:
    await sendReplyText(globalOutbox, uid, channel, replyTo, decision.replyText)

  of oekFreeConvoText:
    (result.history, result.onboarding) = await handleFreeConvoOnboarding(
      globalOutbox, completeFn, uid, channel, replyTo,
      userText |> strutils.strip, result.history, result.onboarding)

  of oekUserProfileText:
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
                 log: Logger): Future[ToolLoopRunResult] {.async.} =
  var loopState = history |> newToolLoopState
  var round = 0
  var recentCalls: seq[(string, string)] = @[]
  let toolStatusId = streamId & "-st"

  while not loopState.done and round < MaxToolRoundsOrch:
    inc round

    let req = buildPrompt(systemBase, loopState.history, context, tools)

    if decideToolLoopStreaming(
      round = round,
      toolsCount = tools.len,
      streamingAvailable = streamFn != nil,
    ).useStreaming:
      let streamText = await streamToOutbox(
        streamFn, req, globalOutbox, uid, channel, replyTo, streamId)
      
      log.info($uid & " (" & $channel & ") <- [" & providerLabel &
               "] |" & $streamText.len & "| stream")
      loopState =
        loopState |>->
        withStreamFinalText(streamText)
      continue

    let resp = safeComplete(completeFn, req)
    if resp.isErr:
      await globalOutbox.put(OutboundMessage(
        userId: uid,
        channel: channel,
        text: buildProviderErrorText(resp.error),
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
                    http: HttpRuntimePort;
                    streamFn: StreamFn;
                    tools: seq[ToolDescription];
                    paddockDir: string;
                    typingFn: TypingFn;
                    log: Logger;
                    providerLabel: string;
                    sandboxMode: SandboxMode;
                    sandboxImage: string;
                    toolsSuffix: string;
                    state: SessionState;
                    msg: AgentMessage;
                    stateRuntime: OrchestratorState): Future[OrchestratorState] {.async.} =
  result = stateRuntime |> nextTurn
  let turnSetup = prepareUserTurnSetup(
    globalOutbox, session, memory, completeFn, http, tools, paddockDir, typingFn, log,
    sandboxMode, sandboxImage, msg, result)

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
    globalOutbox, toolInbox, toolOut, memory, completeFn, streamFn, turnSetup.nativeCtx,
    state, result.history, turnSetup.uid, msg.channel, msg.replyTo, msg.id, turnSetup.streamId,
    turnPrep.systemBase, turnPrep.context, tools, providerLabel,
    result.debugMode, log)
  result =
    result |>->
    withLoopResult(loopResult)

  stopTypingLoop(turnSetup.typingLoop)
  await finalizeNormalTurn(
    globalOutbox, turnSetup.uid, msg.channel, msg.replyTo, turnSetup.streamId, streamFn, loopResult)

proc handleActorCancel(memory: MemoryRuntimePort;
                       memInbox: AsyncQueue[AgentMessage];
                       toolInbox: AsyncQueue[AgentMessage];
                       sessionId: string;
                       stateRuntime: OrchestratorState): Future[void] {.async.} =
  await handleCancel(
    memory, memInbox, toolInbox,
    stateRuntime.lastUserId, sessionId, stateRuntime.history)

proc handleActorTask(globalOutbox: AsyncQueue[OutboundMessage];
                     session: ptr SessionEntry;
                     memInbox: AsyncQueue[AgentMessage];
                     toolInbox: AsyncQueue[AgentMessage];
                     memOut: AsyncQueue[AgentMessage];
                     toolOut: AsyncQueue[AgentMessage];
                     memory: MemoryRuntimePort;
                     completeFn: CompleteFn;
                     http: HttpRuntimePort;
                     streamFn: StreamFn;
                     tools: seq[ToolDescription];
                     paddockDir: string;
                     typingFn: TypingFn;
                     log: Logger;
                     providerLabel: string;
                     sandboxMode: SandboxMode;
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
    result.debugMode, sessionId)
  result =
    result |>->
    withControlResult(controlResult)
  if controlResult.handled and msg.taskKind == tkUserMsg:
    persistSessionSnapshot(memory, uid, sessionId, result.history)
  if controlResult.handled or msg.taskKind notin {tkUserMsg}:
    return

  result = await handleUserTurn(
    globalOutbox, memInbox, toolInbox, memOut, toolOut, session, memory,
    completeFn, http, streamFn, tools, paddockDir, typingFn, log,
    providerLabel, sandboxMode, sandboxImage, toolsSuffix,
    state, msg, result)
  persistSessionSnapshot(memory, uid, sessionId, result.history)

proc handleActorMessage(inbox: AsyncQueue[AgentMessage];
                        session: ptr SessionEntry;
                        globalOutbox: AsyncQueue[OutboundMessage];
                        memInbox: AsyncQueue[AgentMessage];
                        toolInbox: AsyncQueue[AgentMessage];
                        memOut: AsyncQueue[AgentMessage];
                        toolOut: AsyncQueue[AgentMessage];
                        memory: MemoryRuntimePort;
                        completeFn: CompleteFn;
                        http: HttpRuntimePort;
                        streamFn: StreamFn;
                        tools: seq[ToolDescription];
                        paddockDir: string;
                        typingFn: TypingFn;
                        log: Logger;
                        providerLabel: string;
                        sandboxMode: SandboxMode;
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
      completeFn, http, streamFn, tools, paddockDir, typingFn, log,
      providerLabel, sandboxMode, sandboxImage, sessionId,
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
                      typingFn:       TypingFn    = nil;
                      searchFn:       SearchFn    = nil;
                      log:            Logger      = newLogger("orch");
                      providerLabel:  string      = "?";
                      skillPrompt:    string      = "";
                      sandboxMode:    SandboxMode = smNone;
                      sandboxImage:   string      = "alpine"): Future[void] {.async.} =
  ## Persistent actor. Loops: debounce → memory → LLM → reply → repeat.
  let memInbox  = newAsyncQueue[AgentMessage]()
  let toolInbox = newAsyncQueue[AgentMessage]()
  let memOut    = newAsyncQueue[AgentMessage]()
  let toolOut   = newAsyncQueue[AgentMessage]()

  asyncSpawn(runMemoryAgent(memInbox, memOut, memory, searchFn))
  asyncSpawn(runToolAgent(toolInbox, toolOut, clients))
  sandboxLogLevel(sandboxMode, sandboxImage, log)

  var stateRuntime = newOrchestratorState()
  let state = newSessionState()
  let sessionId   = $nowMs()
  let toolsSuffix =
    (tools |> orchToolsSuffix) &
    (if skillPrompt.len > 0: "\n\n" & skillPrompt else: "")

  while true:
    let msg = await collectWithDebounce(inbox, DebounceWindowMs)
    let actorResult = await handleActorMessage(
      inbox, session, globalOutbox, memInbox, toolInbox, memOut, toolOut, memory,
      completeFn, http, streamFn, tools, paddockDir, typingFn, log,
      providerLabel, sandboxMode, sandboxImage, sessionId,
      toolsSuffix, state, msg, stateRuntime)
    stateRuntime = actorResult.stateRuntime
    if actorResult.shouldStop:
      break
