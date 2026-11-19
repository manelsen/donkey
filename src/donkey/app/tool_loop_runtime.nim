## tool_loop_runtime.nim — tool call dispatch, result handling, batch processing.
## Extracted from orchestrator.nim (issue #5).

import std/json
import std/options
import std/strutils
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../core/log
import ../core/output_sanitizer
import ../core/utf8
import ../core/security/approval
import ../core/tooling/tool_loop
import ../core/tooling/native_tool_dispatch
import ../core/agent_events
import ../domain/agent_message
import ../domain/message
import ../domain/more_tools
import ../domain/providers/media_pure
import ../domain/subagent_pure
import ../ports/memory
import ../ports/provider
import ../app/session_state
import ../app/native_tools
import ../app/approval_runtime
import ./session_manager
import ../app/prompt_building
import ../app/provider_executor

export tool_loop

type TypingFn* = proc(userId: UserId; channel: ChannelKind) {.gcsafe, raises: [].}

const RepeatAbortThreshold* = 2    ## abort if same (tool, args) seen ≥ this many times

const
  AskInterruptedReply* = "A pergunta pendente foi cancelada porque chegou " &
    "uma nova mensagem antes da resposta."
    ## Terminal reply for a turn whose open `ask` the ingress cancelled. It
    ## closes the turn's bridge instead of leaving the caller to time out.

func clipProviderError(err: string; maxChars = 500): string =
  clipUtf8(err, maxChars)
    .replace("\r\n", "\\n")
    .replace("\n", "\\n")
    .replace("\r", "\\r")

type ToolCallResult* = object
  text*:          string
  resultKind*:    ToolResultKind
  checkpointNow*: bool
  newHistory*:    Option[ConversationHistory]

type ToolBatchResult* = ToolBatchState

# ── Thread-based streaming ─────────────────────────────────────────────────────

const
  doneSentinel* = "\x00DONE"
  StreamFlushMs* = 1_000

type StreamJob* = object
  fn*:  StreamFn
  req*: CompletionRequest
  ch*:  ptr Channel[string]
  res*: ptr CompletionResponse # Output
  errOut*: ptr string

proc doStreamJob*(job: StreamJob) {.thread, gcsafe.} =
  let res = job.fn(job.req,
                   proc(tok: string) {.gcsafe.} = job.ch[].send(tok))
  if res.isOk:
    job.res[] = res.value
  else:
    job.errOut[] = res.error
  job.ch[].send(doneSentinel)

proc streamToOutbox*(fn:        StreamFn;
                    req:       CompletionRequest;
                    outbox:    AsyncQueue[OutboundMessage];
                    userId:    UserId;
                    ch:        ChannelKind;
                    replyTo:   string;
                    streamId:  string;
                    stopGeneration: uint64 = 0;
                    bridgeToken: uint64 = 0):
                    Future[Result[CompletionResponse, string]] {.async.} =
  var tokenChan: Channel[string]
  var finalResponse: CompletionResponse
  var streamErr = ""
  tokenChan.open(512)

  var t: Thread[StreamJob]
  createThread(t, doStreamJob,
               StreamJob(fn: fn, req: req, ch: addr tokenChan,
                         res: addr finalResponse, errOut: addr streamErr))

  var accumulated = ""
  var lastFlush   = nowMs()
  var lastSent    = ""
  var stopSeen    = false

  while true:
    if isSessionStopRequested(stopGeneration):
      stopSeen = true
      break
    var (has, tok) = tokenChan.tryRecv()
    while has:
      if tok == doneSentinel:
        tokenChan.close()
        joinThread(t)
        if streamErr.len > 0:
          return err(streamErr)
        if finalResponse.toolCalls.len == 0 and
           not isSessionStopRequested(stopGeneration):
          let visible = cleanResponse(finalResponse.text)
          await outbox.put(OutboundMessage(
            userId:    userId,
            channel:   ch,
            text:      if visible.strip.len > 0: visible else: "...",
            replyTo:   replyTo,
            streamId:  streamId,
            isPartial: false,
            replyKind: rkFinalAnswer,
            bridgeToken: bridgeToken,
            # This terminal bypasses `finalizeNormalTurn`, so clamp here too:
            # a provider reporting negative usage must not reach the API body.
            inputTokens:  max(0, finalResponse.inputTokens),
            outputTokens: max(0, finalResponse.outputTokens),
          ))
        return ok(finalResponse)
      accumulated.add(tok)
      (has, tok) = tokenChan.tryRecv()

    if accumulated.len > 0 and nowMs() - lastFlush >= StreamFlushMs:
      lastFlush = nowMs()
      let visible = cleanResponse(safeStreamPrefix(accumulated))
      if visible.strip.len > 0 and visible != lastSent:
        if isSessionStopRequested(stopGeneration):
          stopSeen = true
          break
        lastSent = visible
        await outbox.put(OutboundMessage(
          userId:    userId,
          channel:   ch,
          text:      visible,
          replyTo:   replyTo,
          streamId:  streamId,
          isPartial: true,
          replyKind: rkFinalAnswer,
          bridgeToken: bridgeToken,
        ))

    await sleepAsync(milliseconds(30))

  tokenChan.close()
  joinThread(t)
  if stopSeen:
    return ok(finalResponse)
  if streamErr.len > 0: err(streamErr) else: ok(finalResponse)

# ── Typing loop ───────────────────────────────────────────────────────────────

type TypingFlag* = ref bool

proc startTypingLoop*(typingFn: TypingFn;
                      uid: UserId;
                      channel: ChannelKind;
                      intervalMs = 4_000): TypingFlag =
  ## Behavior derived from hermes-agent (MIT) fix 5948ab52e2; see
  ## docs/hermes-mining/telegram/CASES.md#tg-010
  ##
  ## The typing action expires after about 5 s, so it is re-armed while the
  ## turn is active instead of being sent once.
  var flag: TypingFlag
  new(flag)
  flag[] = true
  proc typingLoopProc() {.async.} =
    while flag[]:
      if typingFn != nil:
        typingFn(uid, channel)
      await sleepAsync(milliseconds(intervalMs))
  asyncSpawn typingLoopProc()
  flag

proc stopTypingLoop*(flag: TypingFlag) =
  if flag != nil:
    flag[] = false

# ── Tool execution ────────────────────────────────────────────────────────────

proc safeComplete(fn: CompleteFn; req: CompletionRequest
                 ): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try: fn(req)
  except Exception as e: err(e.msg)

func completionErr(msg: string): Result[CompletionResponse, string] {.gcsafe.} =
  err(msg)

proc completeOnce(req: CompletionRequest;
                  completeFn: CompleteFn;
                  asyncCompleteFn: AsyncCompleteFn):
                  Future[Result[CompletionResponse, string]] {.async.} =
  ## One provider round, through the async twin when the caller has one.
  if asyncCompleteFn != nil:
    try:
      return await asyncCompleteFn(req)
    except CancelledError:
      raise
    except Exception as e:
      return completionErr(e.msg)
  safeComplete(completeFn, req)

proc awaitExpectedReply*(outbox: AsyncQueue[AgentMessage];
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
                     userId: string;
                     providerLabel: string;
                     log: Logger): Future[ToolCallResult] {.async.} =
  let payload = $ %* {
    "name": tc.name, "id": tc.id, "inputJson": tc.inputJson
  }
  let taskId = msgId & "-" & $round & "-" & $callIndex
  await toolInbox.put(newTaskMsg(taskId, tkInvokeTool, userId, payload))
  let toolReply = await awaitExpectedReply(toolOut, taskId, "ToolAgent")
  log.info("[tool] (" & tc.name & ") -> [" & providerLabel & "] |" &
           $toolReply.text.len & "|")
  ToolCallResult(
    text: toolReply.text,
    resultKind: if toolReply.kind == amkError: trkOperationalError else: trkOutput,
  )

proc executeToolCall*(globalOutbox: AsyncQueue[OutboundMessage];
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
                     log: Logger;
                     bridgeToken: uint64 = 0): Future[ToolCallResult] {.async.} =
  if debugMode:
    await globalOutbox.put(OutboundMessage(
      userId: uid, channel: channel, text: buildToolDebugCallText(tc),
      replyKind: rkDebug, bridgeToken: bridgeToken))

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

  ## Defense in depth: a restricted child must not reach MCP/skill clients,
  ## even if a future native-tool category forgets to handle a name.
  if nativeCtx.restrictTools and
     (tc.name notin nativeCtx.allowedTools or tc.name in SubagentHardDeniedTools):
    return ToolCallResult(
      text: "Error: tool '" & tc.name & "' is not allowed for subagent '" &
            (if nativeCtx.subagentId.len > 0: nativeCtx.subagentId else: "?") & "'.",
      resultKind: trkOperationalError,
    )
  if nativeCtx.budget != nil and not isKnownNativeTool(tc.name):
    let budgetDecision = checkBudget(nativeCtx.budget, nativeCtx.budgetLimits,
                                     nowMs())
    if budgetDecision != bdOk:
      nativeCtx.budget.budgetError = budgetDecisionText(budgetDecision)
      return ToolCallResult(
        text: "Error: " & nativeCtx.budget.budgetError & ".",
        resultKind: trkOperationalError,
      )
    nativeCtx.budget.recordToolCall(epochMs())

  ## Native tools are gated inside executeNativeTool. Non-native tools (MCP,
  ## skills) can be included through DONKEY_APPROVAL_TOOLS names or "*".
  if requiresApproval(nativeCtx.approval, tc.name):
    var summary = approvalInputSummary(tc.inputJson)
    if summary.len > 0 and nativeCtx.subagentId.len > 0:
      summary = "[subagent " & nativeCtx.subagentId & "] " & summary
    if summary.len == 0:
      return ToolCallResult(
        text: "Error: tool '" & tc.name &
              "' is too large to display for approval; split the action.",
        resultKind: trkOperationalError,
      )
    let decision = await requestAndWait(
      nativeCtx.approval, uid, channel, nativeCtx.outbox, tc.name, summary, log,
      shouldStop = proc(): bool {.gcsafe, raises: [].} = sessionStopRequested(nativeCtx))
    case decision
    of adApproved:
      discard
    of adDenied:
      return ToolCallResult(
        text: "Error: tool '" & tc.name & "' was denied by the user.",
        resultKind: trkOperationalError,
      )
    of adTimeout:
      return ToolCallResult(
        text: "Error: approval for tool '" & tc.name & "' timed out.",
        resultKind: trkOperationalError,
      )

  let toolResult = await invokeToolAgent(
    toolInbox, toolOut, msgId, round, callIndex, tc, $uid, providerLabel, log)
  if debugMode:
    await globalOutbox.put(OutboundMessage(
      userId: uid, channel: channel,
      text: buildToolDebugResultText(tc.name, toolResult.text),
      replyKind: rkDebug, bridgeToken: bridgeToken))
  toolResult

proc processToolCalls*(globalOutbox: AsyncQueue[OutboundMessage];
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
                      suppressProgress: bool;
                      debugMode: bool;
                      toolCallCount: int;
                      recentCalls: seq[(string, string)];
                      log: Logger;
                      bridgeToken: uint64 = 0): Future[ToolBatchResult] {.async.} =
  result = newToolBatchState(history, toolCallCount, recentCalls)
  for i, tc in toolCalls:
    if sessionStopRequested(nativeCtx):
      for j in i ..< toolCalls.len:
        result = result |>->
          withToolResult(toolCalls[j], "Error: session is stopping.",
                         trkOperationalError, none(ConversationHistory))
      break
    let prePlan = planToolBatchItem(
      result.recentCalls, tc, RepeatAbortThreshold, result.toolCallCount + 1, "")
    if prePlan.shouldAbort:
      await globalOutbox.put(OutboundMessage(
        userId: uid,
        channel: channel,
        text: prePlan.abortText,
        replyTo: replyTo,
        bridgeToken: bridgeToken,
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
      uid, channel, msgId, round, i, tc, providerLabel, debugMode, log,
      bridgeToken = bridgeToken)
    if toolResult.checkpointNow:
      ## Number before the snapshot: a rewind restores these messages, and the
      ## transcript must recognise them as already stored.
      numberMessages(result.history, state.messageSeq)
      state.checkpoints.add(result.history)
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
    if tc.name == AskToolName and toolResult.text == AskInterruptedText and
       toolResult.resultKind == trkOperationalError:
      ## The ingress cancelled the open ask for a new API turn. Stop the batch
      ## and the turn: the next round could ask again and block the new turn.
      result.askInterrupted = true
      if not suppressProgress:
        ## The turn ends without a final text, so close its bridge with a
        ## terminal error; otherwise the caller waits until the deadline.
        await globalOutbox.put(OutboundMessage(
          userId: uid,
          channel: channel,
          text: AskInterruptedReply,
          replyTo: replyTo,
          replyKind: rkTurnError,
          bridgeToken: bridgeToken,
        ))
      for j in i + 1 ..< toolCalls.len:
        result = result |>->
          withToolResult(toolCalls[j], AskInterruptedText,
                         trkOperationalError, none(ConversationHistory))
      break
    let postPlan = planToolBatchItem(
      @[], tc, RepeatAbortThreshold, result.toolCallCount, toolResult.text)
    if not suppressProgress:
      await globalOutbox.put(OutboundMessage(
        userId: uid,
        channel: channel,
        text: postPlan.progressText,
        streamId: toolStatusId,
        isPartial: true,
        replyKind: rkToolNotice,
        toolCall: ToolCallNotice(phase: "done", name: tc.name, id: tc.id),
        bridgeToken: bridgeToken,
      ))

# ── Tool loop runner ──────────────────────────────────────────────────────────

const MaxToolRoundsOrch* = 250  ## hard safety cap; loop ends earlier on repeated calls

proc runToolLoop*(globalOutbox: AsyncQueue[OutboundMessage];
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
                 suppressProgress: bool;
                 debugMode: bool;
                 showReasoning: bool;
                 log: Logger;
                 asyncCompleteFn: AsyncCompleteFn = nil;
                 bridgeToken: uint64 = 0): Future[ToolLoopRunResult] {.async.} =
  var loopState = history |> newToolLoopState
  var round = 0
  var recentCalls: seq[(string, string)] = @[]
  let toolStatusId = streamId & "-st"

  while not loopState.done and round < MaxToolRoundsOrch:
    if sessionStopRequested(nativeCtx):
      loopState.done = true
      break
    inc round

    var req = buildPrompt(systemBase, loopState.history, context, tools, reasoning = showReasoning)

    let canStreamToolCalls =
      streamFn != nil and providerLabel.toLowerAscii().startsWith("openrouter")
    ## Suppressing tool progress must not disable plain streaming on the
    ## first round; only the tool-call stream channel stays hidden.
    if decideToolLoopStreaming(
      round = round,
      toolsCount = tools.len,
      streamingAvailable = streamFn != nil,
      streamingToolCalls = canStreamToolCalls and not suppressProgress,
    ).useStreaming:
      var streamedRes = await streamToOutbox(
        streamFn, req, globalOutbox, uid, channel, replyTo, streamId,
        nativeCtx.stopGeneration, bridgeToken = bridgeToken)
      ## The streaming branch goes through the same one-shot demotion: a
      ## vision-less model can refuse the inline image before the first token.
      if streamedRes.isErr and not loopState.imageRetryUsed and
         not sessionStopRequested(nativeCtx) and
         hasInlineImages(req) and isImageRejection(streamedRes.error):
        loopState.imageRetryUsed = true
        loopState.history = demoteInlineImagesForTurn(loopState.history)
        req = withoutInlineImages(req)
        streamedRes = await streamToOutbox(
          streamFn, req, globalOutbox, uid, channel, replyTo, streamId,
          nativeCtx.stopGeneration, bridgeToken = bridgeToken)
      if streamedRes.isErr:
        nativeCtx.log.warn("provider error: " & clipProviderError(streamedRes.error))
        pushAgentEvent(AgentEvent(
          kind:    aekError,
          userId:  $uid,
          channel: $channel,
          summary: "stream provider: " & streamedRes.error[0 ..< min(streamedRes.error.len, 80)],
        ))
        await globalOutbox.put(OutboundMessage(
          userId: uid,
          channel: channel,
          text: explainProviderError(errorExplainFn, streamedRes.error),
          replyTo: replyTo,
          replyKind: rkTurnError,
          bridgeToken: bridgeToken,
        ))
        loopState.done = true
        continue
      let streamed = streamedRes.value
      loopState.usage = loopState.usage.addUsage(
        streamed.inputTokens, streamed.outputTokens)
      if sessionStopRequested(nativeCtx):
        loopState.done = true
        break

      log.info($uid & " (" & $channel & ") <- [" & providerLabel &
               "] |" & $streamed.text.len & "| stream")
      if streamed.toolCalls.len > 0:
        loopState.history.addAssistantWithToolCalls(streamed.text, streamed.toolCalls)
        let batchResult = await processToolCalls(
          globalOutbox, toolInbox, toolOut, nativeCtx, state, loopState.history,
          uid, channel, replyTo, msgId, round, toolStatusId, streamed.toolCalls,
          providerLabel, suppressProgress, debugMode, loopState.toolCallCount,
          recentCalls, log, bridgeToken = bridgeToken)
        loopState =
          loopState |>->
          withToolBatchState(batchResult)
        recentCalls = batchResult.recentCalls
      else:
        loopState =
          loopState |>->
          withStreamFinalText(streamed.text, streamed.reasoning)
      continue
    var resp = await completeOnce(req, completeFn, asyncCompleteFn)
    ## One retry per turn: the flag lives in `loopState`, which survives every
    ## tool round, instead of in the completion closure.
    if resp.isErr and not loopState.imageRetryUsed and
       not sessionStopRequested(nativeCtx) and
       hasInlineImages(req) and isImageRejection(resp.error):
      loopState.imageRetryUsed = true
      ## The persistent history drops the image and its inline promise, so
      ## later rounds rebuild a text-only request. Only this retry request
      ## carries the removal note.
      loopState.history = demoteInlineImagesForTurn(loopState.history)
      req = withoutInlineImages(req)
      resp = await completeOnce(req, completeFn, asyncCompleteFn)
    if resp.isErr:
      nativeCtx.log.warn("provider error: " & clipProviderError(resp.error))
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
        replyKind: rkTurnError,
        bridgeToken: bridgeToken,
      ))
      loopState.done = true
      continue

    let r = resp.value
    loopState.usage = loopState.usage.addUsage(r.inputTokens, r.outputTokens)
    if sessionStopRequested(nativeCtx):
      loopState.done = true
      break
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
          userId: uid, channel: channel, text: completionResult.debugText,
          replyKind: rkDebug, bridgeToken: bridgeToken))
      continue

    of tlrkHandleToolBatch:
      loopState.history.addAssistantWithToolCalls(r.text, r.toolCalls)
      let batchResult = await processToolCalls(
        globalOutbox, toolInbox, toolOut, nativeCtx, state, loopState.history,
        uid, channel, replyTo, msgId, round, toolStatusId, r.toolCalls,
        providerLabel, suppressProgress, debugMode, loopState.toolCallCount, recentCalls, log,
        bridgeToken = bridgeToken)
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

func isQuietHeartbeatText*(text: string): bool =
  let lowered = text.toLowerAscii().strip()
  if lowered.len == 0 or lowered in ["— 🫡", "- 🫡", "🫡"]:
    return true
  (lowered.contains("tudo quiet") or
   lowered.contains("sem ação necessária") or
   lowered.contains("sem alterações") or
   lowered.contains("sem tarefas pendentes") or
   lowered.contains("sem demandas pendentes") or
   lowered.contains("checklist limpo") or
   lowered.contains("checklist vazio") or
   lowered.contains("checklist em dia") or
   lowered.contains("checklist completo") or
   lowered.contains("tudo em ordem") or
   lowered.contains("tudo em dia") or
   lowered.contains("tudo completo") or
   lowered.contains("tudo limpo") or
   lowered.contains("nada pendente") or
   lowered.contains("nada a fazer") or
   lowered.contains("sem ação")) and
  not lowered.contains("há tarefa pendente") and
  not lowered.contains("ha tarefa pendente") and
  not lowered.contains("tarefa pendente no") and
  not lowered.contains("tarefas pendentes:") and
  not lowered.contains("próximos passos") and
  not lowered.contains("falh") and
  not lowered.contains("erro")

proc finalizeNormalTurn*(globalOutbox: AsyncQueue[OutboundMessage];
                        uid: UserId;
                        channel: ChannelKind;
                        replyTo: string;
                        streamId: string;
                        streamFn: StreamFn;
                        suppressProgress: bool;
                        suppressQuietFinal: bool;
                        showReasoning: bool;
                        loopResult: ToolLoopRunResult;
                        bridgeToken: uint64 = 0): Future[void] {.async.} =
  if not suppressProgress and loopResult.toolCallCount > 0:
    await globalOutbox.put(OutboundMessage(
      userId: uid,
      channel: channel,
      text: buildToolLoopDoneText(loopResult.toolCallCount),
      streamId: streamId & "-st",
      isPartial: false,
      replyKind: rkToolNotice,
      toolCall: ToolCallNotice(phase: "done"),
      bridgeToken: bridgeToken,
    ))

  if not loopResult.done or not loopResult.wasStreamed:
    if loopResult.finalText.len > 0:
      let cleanFinal = cleanResponse(loopResult.finalText).strip()
      if suppressQuietFinal and isQuietHeartbeatText(cleanFinal):
        return
      var fullText = ""
      if showReasoning and loopResult.reasoning.len > 0:
        let cleanReasoning = cleanResponse(loopResult.reasoning).strip()
        if cleanReasoning.len > 0:
          fullText = "> " & cleanReasoning.replace("\n", "\n> ") & "\n\n"
      fullText &= cleanFinal
      if fullText.strip.len == 0:
        fullText = "..."

      await globalOutbox.put(OutboundMessage(
        userId: uid,
        channel: channel,
        text: fullText,
        replyTo: replyTo,
        replyKind: rkFinalAnswer,
        inputTokens: loopResult.usage.inputTokens,
        outputTokens: loopResult.usage.outputTokens,
        bridgeToken: bridgeToken,
      ))
