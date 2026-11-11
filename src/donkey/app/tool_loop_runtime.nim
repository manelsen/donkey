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
import ../core/tooling/tool_loop
import ../core/agent_events
import ../domain/agent_message
import ../domain/message
import ../ports/memory
import ../ports/provider
import ../app/session_state
import ../app/native_tools
import ../app/prompt_building
import ../app/provider_executor

export tool_loop

type TypingFn* = proc(userId: UserId; channel: ChannelKind) {.gcsafe, raises: [].}

const RepeatAbortThreshold* = 2    ## abort if same (tool, args) seen ≥ this many times

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
                    streamId:  string): Future[Result[CompletionResponse, string]] {.async.} =
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

  while true:
    var (has, tok) = tokenChan.tryRecv()
    while has:
      if tok == doneSentinel:
        tokenChan.close()
        joinThread(t)
        if streamErr.len > 0:
          return err(streamErr)
        if finalResponse.toolCalls.len == 0:
          let visible = cleanResponse(finalResponse.text)
          await outbox.put(OutboundMessage(
            userId:    userId,
            channel:   ch,
            text:      if visible.strip.len > 0: visible else: "...",
            replyTo:   replyTo,
            streamId:  streamId,
            isPartial: false,
          ))
        return ok(finalResponse)
      accumulated.add(tok)
      (has, tok) = tokenChan.tryRecv()

    if accumulated.len > 0 and nowMs() - lastFlush >= StreamFlushMs:
      lastFlush = nowMs()
      let visible = cleanResponse(safeStreamPrefix(accumulated))
      if visible.strip.len > 0 and visible != lastSent:
        lastSent = visible
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
  if streamErr.len > 0: err(streamErr) else: ok(finalResponse)

# ── Typing loop ───────────────────────────────────────────────────────────────

type TypingFlag* = ref bool

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

# ── Tool execution ────────────────────────────────────────────────────────────

proc safeComplete(fn: CompleteFn; req: CompletionRequest
                 ): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try: fn(req)
  except Exception as e: err(e.msg)

func completionErr(msg: string): Result[CompletionResponse, string] {.gcsafe.} =
  err(msg)

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
    toolInbox, toolOut, msgId, round, callIndex, tc, $uid, providerLabel, log)
  if debugMode:
    await globalOutbox.put(OutboundMessage(
      userId: uid, channel: channel,
      text: buildToolDebugResultText(tc.name, toolResult.text)))
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
    if not suppressProgress:
      await globalOutbox.put(OutboundMessage(
        userId: uid,
        channel: channel,
        text: postPlan.progressText,
        streamId: toolStatusId,
        isPartial: true,
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
                 asyncCompleteFn: AsyncCompleteFn = nil): Future[ToolLoopRunResult] {.async.} =
  var loopState = history |> newToolLoopState
  var round = 0
  var recentCalls: seq[(string, string)] = @[]
  let toolStatusId = streamId & "-st"

  while not loopState.done and round < MaxToolRoundsOrch:
    inc round

    let req = buildPrompt(systemBase, loopState.history, context, tools, reasoning = showReasoning)

    let canStreamToolCalls =
      streamFn != nil and providerLabel.toLowerAscii().startsWith("openrouter")
    if decideToolLoopStreaming(
      round = round,
      toolsCount = tools.len,
      streamingAvailable = streamFn != nil and not suppressProgress,
      streamingToolCalls = canStreamToolCalls and not suppressProgress,
    ).useStreaming:
      let streamedRes = await streamToOutbox(
        streamFn, req, globalOutbox, uid, channel, replyTo, streamId)
      if streamedRes.isErr:
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
        ))
        loopState.done = true
        continue
      let streamed = streamedRes.value

      log.info($uid & " (" & $channel & ") <- [" & providerLabel &
               "] |" & $streamed.text.len & "| stream")
      if streamed.toolCalls.len > 0:
        loopState.history.addAssistantWithToolCalls(streamed.text, streamed.toolCalls)
        let batchResult = await processToolCalls(
          globalOutbox, toolInbox, toolOut, nativeCtx, state, loopState.history,
          uid, channel, replyTo, msgId, round, toolStatusId, streamed.toolCalls,
          providerLabel, suppressProgress, debugMode, loopState.toolCallCount,
          recentCalls, log)
        loopState =
          loopState |>->
          withToolBatchState(batchResult)
        recentCalls = batchResult.recentCalls
      else:
        loopState =
          loopState |>->
          withStreamFinalText(streamed.text, streamed.reasoning)
      continue
    let resp =
      if asyncCompleteFn != nil:
        try:
          await asyncCompleteFn(req)
        except Exception as e:
          completionErr(e.msg)
      else:
        safeComplete(completeFn, req)
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
        providerLabel, suppressProgress, debugMode, loopState.toolCallCount, recentCalls, log)
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
                        loopResult: ToolLoopRunResult): Future[void] {.async.} =
  if not suppressProgress and loopResult.toolCallCount > 0:
    await globalOutbox.put(OutboundMessage(
      userId: uid,
      channel: channel,
      text: buildToolLoopDoneText(loopResult.toolCallCount),
      streamId: streamId & "-st",
      isPartial: false,
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
      ))
