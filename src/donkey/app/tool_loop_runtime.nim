## tool_loop_runtime.nim — tool call dispatch, result handling, batch processing.
## Extracted from orchestrator.nim (issue #5).

import std/json
import std/options
import std/strutils
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../core/log
import ../core/tooling/tool_loop
import ../core/agent_events
import ../core/security/secret_scan
import ../domain/agent_message
import ../domain/message
import ../ports/memory
import ../ports/provider
import ../app/session_state
import ../app/native_tools
import ../app/prompt_building

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

proc doStreamJob*(job: StreamJob) {.thread, gcsafe.} =
  let res = job.fn(job.req,
                   proc(tok: string) {.gcsafe.} = job.ch[].send(tok))
  if res.isOk:
    job.res[] = res.value
  job.ch[].send(doneSentinel)

proc streamToOutbox*(fn:        StreamFn;
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
    toolInbox, toolOut, msgId, round, callIndex, tc, providerLabel, log)
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

# ── Tool loop runner ──────────────────────────────────────────────────────────

const MaxToolRoundsOrch* = 50   ## hard safety cap; loop ends earlier on repeated calls

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

proc finalizeNormalTurn*(globalOutbox: AsyncQueue[OutboundMessage];
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
