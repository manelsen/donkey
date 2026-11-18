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

import std/[monotimes, os, strutils]
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../core/debounce
import ../core/log
import ../core/onboarding/onboarding
import ../core/agent_events
import ../core/memory/blackboard
import ../core/tooling/tool_loop
import ../domain/agent_message
import ../domain/gateway/identity_pure
import ../domain/memory/capture_pure
import ../domain/memory/provenance_pure
import ../domain/message
import ../domain/personality
import ../domain/providers/media_pure
import ../config/types as cfgTypes
import ./memory_consolidation
import ./session_manager
import ./sandbox
import ../ports/provider
import ../ports/subagent_workspace
import ../ports/memory
import ../ports/http
import ../ports/fs
import ../ports/tool
import ./memory_agent
import ./tool_agent
import ./session_state
import ./channel_prefs_parse
import ./native_tools
import ./approval_runtime
import ./onboarding_runtime
import ./tool_loop_runtime
import ./subagent_runtime
import ./prompt_building
import ./provider_executor
import ./review_runtime
import ../core/security/dm_policy
import ../infra/queue/nonblocking

# Re-export public API from extracted modules
export onboarding
export onboarding_runtime
export tool_loop_runtime
export prompt_building

const DebounceWindowMs* = MinWindowMs
  ## Base window kept for callers that do not pass a `DebounceConfig`.

proc nowMonoMs*(): int64 =
  ## Monotonic milliseconds, immune to wall-clock adjustments. Kept in the app
  ## layer so `core/debounce` stays effect-free.
  getMonoTime().ticks div 1_000_000

proc debounceConfigFromEnv*(): DebounceConfig =
  ## Reads DONKEY_DEBOUNCE_* overrides. Invalid or non-positive values fall
  ## back to the compiled policy, so a bad env cannot disable debouncing.
  proc posInt(name: string; fallback: int64): int64 =
    let raw = getEnv(name).strip
    if raw.len == 0:
      return fallback
    let parsed = try:
      raw.parseInt
    except ValueError:
      return fallback
    if parsed <= 0: fallback else: parsed

  result = defaultDebounceConfig()
  result.minWindowMs = posInt("DONKEY_DEBOUNCE_MIN_MS", result.minWindowMs)
  result.maxWindowMs = posInt("DONKEY_DEBOUNCE_MAX_MS", result.maxWindowMs)
  result.perPartExtMs = posInt("DONKEY_DEBOUNCE_PER_PART_MS", result.perPartExtMs)
  result.shortMsgThreshold = posInt(
    "DONKEY_DEBOUNCE_SHORT_MSG_CHARS", result.shortMsgThreshold.int64).int
  result.shortExtMs = posInt("DONKEY_DEBOUNCE_SHORT_EXT_MS", result.shortExtMs)
  if result.maxWindowMs < result.minWindowMs:
    result.maxWindowMs = result.minWindowMs

func suppressToolProgressFromEnv*(): bool =
  ## Hides the `🔧 tool [n]` progress messages for deployments that only want
  ## the final answer and approval prompts. Set DONKEY_SUPPRESS_TOOL_PROGRESS=1.
  getEnv("DONKEY_SUPPRESS_TOOL_PROGRESS").strip.toLowerAscii() in
    ["1", "true", "yes", "on"]

# ── Orchestrator state and pipe ops ────────────────────────────────────────────

type OrchestratorState = object
  history*:       ConversationHistory
  debugMode*:     bool
  showReasoning*: bool
  lastUserId*:    UserId
  onboarding*:    OnboardingRuntime
  identity*:      IdentityRuntime
  completedBootstrapTargets*: seq[string]
  turnSeq*:       int
  blackboard*:    Blackboard
  lastConsolidatedFingerprint*: string
  subagents*:     SubagentManager
  stopGeneration*: uint64
  sessionId*:     string

func newOrchestratorState*(): OrchestratorState =
  OrchestratorState(
    history: newHistory(),
    debugMode: false,
    showReasoning: true,
    onboarding: OnboardingRuntime(phase: opWakeUp),
    identity: IdentityRuntime(),
    completedBootstrapTargets: @[],
    blackboard: newBlackboard(12),
  )

func nextTurn*(state: OrchestratorState): OrchestratorState =
  result = state
  inc result.turnSeq

func streamIdFor*(state: OrchestratorState; userId: string): string =
  userId & "-" & $state.turnSeq

func withLastUser*(uid: UserId; state: OrchestratorState): OrchestratorState =
  result = state
  result.lastUserId = uid

func withControlResult*(controlResult: onboarding_runtime.ControlTaskResult;
                        state: OrchestratorState): OrchestratorState =
  result = state
  result.history = controlResult.history
  result.onboarding = controlResult.onboarding
  result.identity = controlResult.identity
  result.debugMode = controlResult.debugMode
  result.showReasoning = controlResult.showReasoning

func withOnboardingResult*(onboardingResult: onboarding_runtime.OnboardingTurnResult;
                           state: OrchestratorState): OrchestratorState =
  result = state
  result.history = onboardingResult.history
  result.onboarding = onboardingResult.onboarding
  result.identity = onboardingResult.identity

func bootstrapTargetKey(channel: ChannelKind; replyTo: string): string =
  $channel & ":" & (if replyTo.len > 0: replyTo else: "_default")

func withCompletedBootstrapTarget*(channel: ChannelKind;
                                   replyTo: string;
                                   state: OrchestratorState): OrchestratorState =
  result = state
  let key = bootstrapTargetKey(channel, replyTo)
  if key notin result.completedBootstrapTargets:
    result.completedBootstrapTargets.add(key)

func withoutCompletedBootstrapTarget*(channel: ChannelKind;
                                      replyTo: string;
                                      state: OrchestratorState): OrchestratorState =
  result = state
  let key = bootstrapTargetKey(channel, replyTo)
  result.completedBootstrapTargets = result.completedBootstrapTargets.filterIt(it != key)

func hasCompletedBootstrapTarget*(state: OrchestratorState;
                                  channel: ChannelKind;
                                  replyTo: string): bool =
  bootstrapTargetKey(channel, replyTo) in state.completedBootstrapTargets

func withTurnPrep*(turnPrep: prompt_building.NormalTurnPrep;
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

# ── Native context builder ─────────────────────────────────────────────────────

proc buildNativeCtx*(uid: UserId;
                     channel: ChannelKind;
                     globalOutbox: AsyncQueue[OutboundMessage];
                     session: ptr SessionEntry;
                     memory: MemoryRuntimePort;
                     completeFn: CompleteFn;
                     http: HttpRuntimePort;
                     fs: FsRuntimePort;
                     cfg: cfgTypes.DonkeyConfig;
                     tools: seq[ToolDescription];
                     log: Logger;
                     paddockDir: string;
                     sandboxMode: SandboxMode;
                     sandboxRuntimeCmd: string;
                     sandboxImage: string): NativeCtx =
  result = NativeCtx(
    uid:          uid,
    channel:      channel,
    outbox:       globalOutbox,
    session:      session,
    memory:       memory,
    completeFn:   completeFn,
    http:         http,
    fs:           fs,
    braveApiKey:  getEnv("BRAVE_API_KEY", ""),
    webAllowlist: cfg.webAllowlist,
    toolWebPolicy: cfg.toolWebPolicy,
    tools:        tools,
    approval:     currentApprovalService(),
    log:          log,
    paddockDir:   paddockDir,
    sandboxMode:  sandboxMode,
    sandboxRuntimeCmd: sandboxRuntimeCmd,
    sandboxImage: sandboxImage,
    sandboxAllowHostFallback: cfg.sandboxAllowHostFallback,
    sandboxAllowNetwork: cfg.sandboxAllowNetwork,
    sandboxReadOnlyRootfs: cfg.sandboxReadOnlyRootfs,
  )

# ── User turn setup ───────────────────────────────────────────────────────────

type UserTurnSetup = object
  uid:         UserId
  streamId:    string
  userText:    string
  isNewUser:   bool
  nativeCtx:   NativeCtx
  typingLoop:  TypingFlag

proc prepareUserTurnSetup(globalOutbox: AsyncQueue[OutboundMessage];
                          session: ptr SessionEntry;
                          memory: MemoryRuntimePort;
                          completeFn: CompleteFn;
                          http: HttpRuntimePort;
                          fs: FsRuntimePort;
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
  let payload = msg.payload |> decodeUserPayload
  result.userText = payload.text
  result.isNewUser =
    not isApiUserId(result.uid) and
    not onboarding_runtime.safeHasProfile(memory, result.uid) and
    not stateRuntime.hasCompletedBootstrapTarget(msg.channel, msg.replyTo)
  result.nativeCtx = buildNativeCtx(
    result.uid, msg.channel, globalOutbox, session, memory, completeFn, http, fs,
    cfgTypes.DonkeyConfig(
      home: "", paddocks: "", logLevel: log.minLevel, logFile: "",
      defaultProvider: "", defaultModel: "",
      webAllowlist: webAllowlist, toolWebPolicy: toolWebPolicy,
      skillNetPolicy: @[], sandboxMode: sandboxMode,
      sandboxRuntimeCmd: sandboxRuntimeCmd, sandboxImage: sandboxImage,
      sandboxAllowHostFallback: false, sandboxAllowNetwork: false,
      sandboxReadOnlyRootfs: true, wasmShellPath: "",
      dmPolicy: DmPolicyOpen, wiring: false),
    tools, log,
    paddockDir, sandboxMode, sandboxRuntimeCmd, sandboxImage)
  result.nativeCtx.replyTo = msg.replyTo
  result.nativeCtx.stopGeneration = stateRuntime.stopGeneration
  ## Recorded per turn: a `/stop` that arrives after this point aborts the
  ## turn; one that arrived before it belongs to an earlier turn.
  result.nativeCtx.userInterrupt = currentUserInterrupt($result.uid)
  result.nativeCtx.scopeSessionId = stateRuntime.sessionId
  createDir(paddockDir)
  result.typingLoop = startTypingLoop(typingFn, result.uid, msg.channel)

# ── Control task dispatcher ───────────────────────────────────────────────────

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
                       sessionId: string): Future[onboarding_runtime.ControlTaskResult] {.async.} =
  var currentOnboarding = onboarding
  var currentIdentity = identity
  if msg.taskKind in {tkPersonalityChoice, tkNameChoice} and
     currentOnboarding.phase == opWakeUp and
     not onboarding_runtime.safeHasCompletedBootstrap(memory, uid):
    (currentOnboarding, currentIdentity) =
      onboarding_runtime.safeRestoreOnboardingState(memory, uid)
  result.history = history
  result.onboarding = currentOnboarding
  result.identity = currentIdentity
  result.debugMode = debugMode
  result.showReasoning = showReasoning

  case msg.taskKind
  of tkReset:
    let (nextHistory, nextOnboarding, resetApplied) = await onboarding_runtime.handleResetControlTask(
      globalOutbox, memory, uid, channel, replyTo, log, sessionId, result.history)
    result.history = nextHistory
    if resetApplied:
      result.onboarding = nextOnboarding
      result.identity = IdentityRuntime()
    result.resetApplied = resetApplied
    result.handled = true

  of tkDebugToggle:
    result.debugMode = await onboarding_runtime.handleDebugToggleControlTask(
      globalOutbox, uid, channel, replyTo, result.debugMode)
    result.handled = true

  of tkCompact:
    result.history = await onboarding_runtime.handleCompactControlTask(
      globalOutbox, uid, channel, replyTo, result.history)
    result.handled = true

  of tkNew:
    result.history = await onboarding_runtime.handleNewSessionTask(
      globalOutbox, memory, uid, channel, replyTo, sessionId, result.history)
    result.handled = true

  of tkStop:
    await onboarding_runtime.sendReplyText(globalOutbox, uid, channel, replyTo, "🛑 Parado.")
    result.handled = true

  of tkRestart:
    result.history = await onboarding_runtime.handleNewSessionTask(
      globalOutbox, memory, uid, channel, replyTo, sessionId, result.history)
    result.handled = true

  of tkBind:
    await onboarding_runtime.sendReplyText(globalOutbox, uid, channel, replyTo, "🔗 Bind: funcionalidade em implementação.")
    result.handled = true

  of tkPersonalityChoice, tkNameChoice:
    (result.onboarding, result.identity, result.handled) = await onboarding_runtime.handleOnboardingControlTask(
      globalOutbox, memory, completeFn, uid, channel, replyTo,
      msg, result.onboarding, result.identity)

  else:
    discard

# ── User turn handler ─────────────────────────────────────────────────────────

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
                    fs: FsRuntimePort;
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
                    stateRuntime: OrchestratorState;
                    asyncCompleteFn: AsyncCompleteFn = nil;
                    reviewRt: ReviewRuntime = nil): Future[OrchestratorState] {.async.} =
  result = stateRuntime |> nextTurn
  var turnSetup = prepareUserTurnSetup(
    globalOutbox, session, memory, completeFn, http, fs, tools, webAllowlist, toolWebPolicy,
    paddockDir, typingFn, log,
    sandboxMode, sandboxRuntimeCmd, sandboxImage, msg, result)
  turnSetup.nativeCtx.asyncCompleteFn = asyncCompleteFn
  attachSubagentRuntime(turnSetup.nativeCtx, result.subagents)

  if turnSetup.isNewUser and not isApiUserId(turnSetup.uid):
    if result.onboarding.phase == opWakeUp and not result.identity.identityLoaded:
      (result.onboarding, result.identity) =
        onboarding_runtime.safeRestoreOnboardingState(memory, turnSetup.uid)
    let onboardingResult = await onboarding_runtime.handleOnboardingTurn(
      globalOutbox, memory, completeFn, turnSetup.uid, msg.channel, msg.replyTo, turnSetup.userText,
      result.history, result.onboarding, result.identity)
    result =
      result |>->
      withOnboardingResult(onboardingResult)
    if onboardingResult.handled:
      return

  let prefs = try: memory.loadContext(turnSetup.uid).preferencesMd |> parseChannelPrefs
              except: defaultChannelPrefs()
  let showReasoning = prefs.reasoning == "on"

  var identityLoaded = result.identity.identityLoaded
  var agentName = result.identity.name
  var agentTraits = result.identity.traits
  var obPhase = result.onboarding.phase

  if not identityLoaded:
    (agentName, agentTraits) = onboarding_runtime.safeLoadIdentity(memory, turnSetup.uid)
    identityLoaded = true
    obPhase = opDone

  let systemBase = buildSystemBase(agentTraits, agentName, toolsSuffix)

  let userPayload = decodeUserPayload(msg.payload)
  await memInbox.put(newTaskMsg(msg.id, tkLoadCtx, msg.userId, userPayload.text))
  let ctxReply = await awaitExpectedReply(memOut, msg.id, "MemoryAgent")
  var context = if ctxReply.kind == amkResult: ctxReply.text else: ""
  if userPayload.recentContext.len > 0:
    let recentBlock =
      "## Recent Context\n" &
      "These messages happened immediately before the current message and may be missing from live session memory due to restart, rebuild, or long idle time.\n\n" &
      userPayload.recentContext
    context =
      if context.len > 0: context & "\n\n" & recentBlock
      else: recentBlock

  discard rememberCommitments(
    result.blackboard, userPayload.text, "", epochMs())
  let blackboardText = result.blackboard.renderForUser()
  if blackboardText.len > 0:
    let blackboardBlock = "## Session commitments\n" & blackboardText
    context =
      if context.len > 0: context & "\n\n" & blackboardBlock
      else: blackboardBlock

  const MaxAttachmentsPerTurn = 10
  var attachmentUrls = userPayload.mediaUrls
  if attachmentUrls.len == 0 and userPayload.mediaUrl.len > 0:
    attachmentUrls = @[userPayload.mediaUrl]
  let attachmentPaths =
    if userPayload.mediaPaths.len == attachmentUrls.len:
      userPayload.mediaPaths
    else:
      @[]
  if attachmentUrls.len > MaxAttachmentsPerTurn:
    log.warn("turn with " & $attachmentUrls.len & " attachments; keeping " &
             $MaxAttachmentsPerTurn)
  let history =
    if attachmentUrls.len > 0:
      addUserTurnWithImages(result.history, userPayload.text, attachmentUrls,
                            attachmentPaths)
    else:
      addUserTurn(result.history, userPayload.text, "")

  result =
    result |>->
    withTurnPrep(prompt_building.NormalTurnPrep(
      history: history,
      context: context,
      systemBase: systemBase,
      agentName: agentName,
      agentTraits: agentTraits,
      identityLoaded: identityLoaded,
      obPhase: obPhase,
      showReasoning: showReasoning,
    ))

  log.info($turnSetup.uid & " (" & $msg.channel & ") -> [" & providerLabel & "] |" &
           $turnSetup.userText.len & "|")
  let suppressHeartbeatProgress = msg.taskKind == tkHeartbeat
  let suppressQuietHeartbeatFinal = msg.taskKind == tkHeartbeat
  let suppressProgress = suppressHeartbeatProgress or suppressToolProgressFromEnv()
  let loopResult = await runToolLoop(
    globalOutbox, toolInbox, toolOut, memory, completeFn, errorExplainFn, streamFn, turnSetup.nativeCtx,
    state, history, turnSetup.uid, msg.channel, msg.replyTo, msg.id, turnSetup.streamId,
    systemBase, context, tools, providerLabel,
    suppressProgress, result.debugMode, result.showReasoning, log,
    asyncCompleteFn)
  result =
    result |>->
    withLoopResult(loopResult)

  ## The inline photo belonged to this turn only. Demote it before
  ## `finalizeNormalTurn` and `saveNumberedSession` so the next request — and
  ## the transcript — carry the text marker instead of the base64 payload.
  result.history = demoteInlineImages(result.history)

  stopTypingLoop(turnSetup.typingLoop)
  await finalizeNormalTurn(
    globalOutbox, turnSetup.uid, msg.channel, msg.replyTo, turnSetup.streamId, streamFn,
    suppressProgress, suppressQuietHeartbeatFinal, result.showReasoning, loopResult)

  # Capture the turn into long-term memory. The policy (what counts as
  # substantive, how each side is clipped) lives in domain/memory/capture_pure.
  if not shouldSkipAutoMemoryCapture(turnSetup.userText, loopResult.finalText):
    onboarding_runtime.safeAppendMemory(
      memory, turnSetup.uid,
      formatAutoMemoryEntry(turnSetup.userText, loopResult.finalText),
      turnOrigin(result.sessionId)).isOkOr:
        log.warn("auto memory capture: " & error)

  if loopResult.finalText.len > 0:
    discard rememberCommitments(
      result.blackboard, "", loopResult.finalText, epochMs())

  # Post-turn self-improvement review. It is curation, not capture: the turn
  # itself is already in MEMORY.md above. Skip heartbeat and control turns, a
  # turn with no final answer, and a turn the user interrupted — there is
  # nothing to learn from an answer that was cut off.
  if reviewRt != nil and msg.taskKind == tkUserMsg and
     loopResult.finalText.len > 0 and
     not isUserStoppedSince($turnSetup.uid, turnSetup.nativeCtx.userInterrupt):
    discard reviewRt.afterTurn(turnSetup.uid, result.sessionId, result.history,
                               loopResult.toolCallCount)

# ── Actor message handling ────────────────────────────────────────────────────

type ActorMessageResult = object
  stateRuntime: OrchestratorState
  shouldStop:   bool

proc saveNumberedSession(memory: MemoryRuntimePort; uid: UserId;
                         sessionId: string; state: SessionState;
                         history: var ConversationHistory) {.gcsafe, raises: [].} =
  ## Numbers the messages that have no number yet and saves the transcript.
  ## The numbers stay in `history`, so later saves recognise what is stored.
  numberMessages(history, state.messageSeq)
  onboarding_runtime.safeSaveSession(memory, uid, sessionId, history)

proc handleActorCancel(memory:          MemoryRuntimePort;
                       memInbox:         AsyncQueue[AgentMessage];
                       toolInbox:        AsyncQueue[AgentMessage];
                       sessionId:        string;
                       state:            SessionState;
                       stateRuntime:     OrchestratorState): Future[void] {.async.} =
  ## Save history on cancel so mid-turn rebuilds don't lose context.
  var history = stateRuntime.history
  saveNumberedSession(memory, stateRuntime.lastUserId, sessionId, state, history)
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
                     fs: FsRuntimePort;
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
                     stateRuntime: OrchestratorState;
                     asyncCompleteFn: AsyncCompleteFn = nil;
                     reviewRt: ReviewRuntime = nil): Future[OrchestratorState] {.async.} =
  result = stateRuntime
  let uid = UserId(msg.userId)
  result =
    result |>->
    withLastUser(uid)

  if msg.taskKind in {tkCompact, tkReset, tkNew, tkRestart}:
    let fingerprint = historyFingerprint(result.history)
    if fingerprint != result.lastConsolidatedFingerprint:
      let consolidation = await consolidateSessionAsync(
        memory, completeFn, asyncCompleteFn, uid, sessionId, result.history, log)
      if consolidation.completed:
        result.lastConsolidatedFingerprint = fingerprint

  ## /reset and /new save the transcript inside the control task.
  numberMessages(result.history, state.messageSeq)
  let controlResult = await handleControlTask(
    globalOutbox, memory, completeFn, uid, msg.channel, msg.replyTo, msg,
    result.history, result.onboarding, result.identity,
    result.debugMode, result.showReasoning, log, sessionId)
  result =
    result |>->
    withControlResult(controlResult)
  if controlResult.handled and
     (msg.taskKind in {tkNew, tkRestart} or
      (msg.taskKind == tkReset and controlResult.resetApplied)):
    result.blackboard.clear()
    result.lastConsolidatedFingerprint = ""
  if controlResult.handled and msg.taskKind == tkReset:
    result =
      result |>->
      withoutCompletedBootstrapTarget(msg.channel, msg.replyTo)
  if controlResult.handled and msg.taskKind == tkUserMsg:
    saveNumberedSession(memory, uid, sessionId, state, result.history)
  if controlResult.handled or msg.taskKind notin {tkUserMsg, tkHeartbeat}:
    return
  if msg.taskKind == tkHeartbeat and not onboarding_runtime.safeHasCompletedBootstrap(memory, uid):
    return

  result = await handleUserTurn(
    globalOutbox, memInbox, toolInbox, memOut, toolOut, session, memory,
    completeFn, errorExplainFn, http, fs, streamFn, tools, webAllowlist, toolWebPolicy, paddockDir, typingFn, log,
    providerLabel, sandboxMode, sandboxRuntimeCmd, sandboxImage, toolsSuffix,
    state, msg, result, asyncCompleteFn, reviewRt = reviewRt)
  if result.onboarding.phase == opDone:
    result =
      result |>->
      withCompletedBootstrapTarget(msg.channel, msg.replyTo)
  saveNumberedSession(memory, uid, sessionId, state, result.history)

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
                        fs: FsRuntimePort;
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
                        stateRuntime: OrchestratorState;
                        asyncCompleteFn: AsyncCompleteFn = nil;
                        reviewRt: ReviewRuntime = nil): Future[ActorMessageResult] {.async.} =
  result.stateRuntime = stateRuntime
  case msg.kind
  of amkCancel:
    if stateRuntime.subagents != nil:
      await stateRuntime.subagents.cancelAll()
    await handleActorCancel(memory, memInbox, toolInbox, sessionId, state, stateRuntime)
    result.shouldStop = true

  of amkTask:
    result.stateRuntime = await handleActorTask(
      globalOutbox, session, memInbox, toolInbox, memOut, toolOut, memory,
      completeFn, errorExplainFn, http, fs, streamFn, tools, webAllowlist, toolWebPolicy, paddockDir, typingFn, log,
      providerLabel, sandboxMode, sandboxRuntimeCmd, sandboxImage, sessionId,
      toolsSuffix, state, msg, stateRuntime, asyncCompleteFn, reviewRt = reviewRt)

  else:
    discard

# ── Debounce collector ─────────────────────────────────────────────────────────

proc collectWithDebounce*(inbox: AsyncQueue[AgentMessage];
                          cfg: DebounceConfig = debounceConfigFromEnv()):
                          Future[AgentMessage] {.async.} =
  ## Waits for the first amkTask, then accumulates fragments while they keep
  ## arriving inside the adaptive window: more parts (or a short last part)
  ## hold the window open longer, up to `maxWindowMs`. Returns one AgentMessage
  ## with all payloads joined by `mergeUserPayloads`. `amkCancel` always wins.
  let first = await inbox.get()
  if first.kind != amkTask or first.taskKind != tkUserMsg:
    return first   ## cancel / control task / stray — pass through untouched

  var texts = @[first.payload]
  var latest = first
  var state = initDebounce(first.payload, nowMonoMs())

  while true:
    ## Recompute the remaining wait after every part: the adaptive window can
    ## grow mid-burst, so a fixed timeout would close too early.
    let lastTextLen = decodeUserPayload(state.parts[^1]).text.len
    let win = windowMs(state.parts.len, lastTextLen, cfg)
    let elapsed = nowMonoMs() - state.lastMs
    let waitMs = max(1'i64, win - elapsed)
    let nextFut = inbox.get()
    if not (await withTimeout(nextFut, milliseconds(waitMs.int))):
      break   ## adaptive window closed
    let next = nextFut.read()
    case next.kind
    of amkCancel: return next          ## cancel wins
    of amkTask:
      if next.taskKind != tkUserMsg:
        ## A control task must stay its own turn. Put it back at the front and
        ## close the burst; the actor loop picks it up on the next iteration.
        discard tryAddFirstNoWait(inbox, next)
        break
      state = appendFragment(next.payload, nowMonoMs(), state)
      texts.add(next.payload)
      latest = next
    else: discard

  ## A cancel already sitting in the queue must win over the burst: starting
  ## the user turn would run a request the user aborted. Drain, look for it,
  ## and put everything else back in the original order.
  var pending: seq[AgentMessage] = @[]
  var cancelMsg: AgentMessage
  var sawCancel = false
  while true:
    let item =
      try:
        inbox.popFirstNoWait()
      except AsyncQueueEmptyError:
        break
    if item.kind == amkCancel and not sawCancel:
      sawCancel = true
      cancelMsg = item
    else:
      pending.add(item)
  for item in pending:
    discard tryAddLastNoWait(inbox, item)
  if sawCancel:
    return cancelMsg

  result         = latest
  result.payload = mergeUserPayloads(texts)

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
                      errorExplainFn: CompleteFn = nil;
                      asyncCompleteFn: AsyncCompleteFn = nil;
                      subagentWorkspace: SubagentWorkspacePort = SubagentWorkspacePort();
                      fs:             FsRuntimePort = unavailableFs();
                      reviewRuntime:  ReviewRuntime = nil): Future[void] {.async.} =
  ## Persistent actor. Loops: debounce → memory → LLM → reply → repeat.
  if daemonShuttingDown():
    return
  let memInbox  = newAsyncQueue[AgentMessage]()
  let toolInbox = newAsyncQueue[AgentMessage]()
  let memOut    = newAsyncQueue[AgentMessage]()
  let toolOut   = newAsyncQueue[AgentMessage]()

  let memAgentFut = runMemoryAgent(memInbox, memOut, memory, searchFn)
  let toolAgentFut = runToolAgent(toolInbox, toolOut, clients)
  sandboxLogLevel(sandboxMode, sandboxImage, sandboxRuntimeCmd, log)
  if paddockDir.len > 0:
    logSandboxWorkspaceProbe(
      sandboxMode, paddockDir, sandboxImage, sandboxRuntimeCmd,
      false, true, log)

  var stateRuntime = newOrchestratorState()
  stateRuntime.subagents = newSubagentManager(subagentWorkspace)
  stateRuntime.stopGeneration = currentSessionStopGeneration()
  let sessionId   = $nowMs()
  stateRuntime.sessionId = sessionId
  registerActor()
  pushAgentEvent(AgentEvent(kind: aekSessionStart, summary: "session " & sessionId))
  let toolsSuffix =
    (tools |> orchToolsSuffix) &
    (if skillPrompt.len > 0: "\n\n" & skillPrompt else: "")

  # One review runtime per actor: the cadence counters must survive turns.
  # The paddock is {home}/paddocks/{user}, so its grandparent is the home that
  # holds the installed skills.
  let review =
    if reviewRuntime != nil:
      reviewRuntime
    else:
      newReviewRuntime(
        reviewConfigFromEnv(), asyncCompleteFn, memory,
        homeDir = (if paddockDir.len > 0: parentDir(parentDir(paddockDir)) else: ""),
        log = log.child("review"))

  try:
    while true:
      let msg = await collectWithDebounce(inbox)
      let actorResult = await handleActorMessage(
        inbox, session, globalOutbox, memInbox, toolInbox, memOut, toolOut, memory,
        completeFn, errorExplainFn, http, fs, streamFn, tools, webAllowlist, toolWebPolicy, paddockDir, typingFn, log,
        providerLabel, sandboxMode, sandboxRuntimeCmd, sandboxImage, sessionId,
        toolsSuffix, state, msg, stateRuntime, asyncCompleteFn, reviewRt = review)
      stateRuntime = actorResult.stateRuntime
      if actorResult.shouldStop:
        break
  finally:
    if stateRuntime.subagents != nil:
      await stateRuntime.subagents.cancelAll()
    ## The stop path may interrupt a turn before handleActorCancel runs, so the
    ## helper actors always receive their stop signal here.
    memInbox.addLastNoWait(newCancelMsg())
    toolInbox.addLastNoWait(newCancelMsg())
    await memAgentFut
    await toolAgentFut
    unregisterActor()
