## tool_loop_runtime.nim — tool call dispatch, result handling, batch processing.
## Extracted from orchestrator.nim (issue #5).

import std/json
import std/options
import std/strutils
import ./blocking_executor
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
import ../domain/providers/descriptors
import ../domain/subagent_pure
import ../ports/memory
import ../ports/provider
import ../app/session_state
import ../app/native_tools
import ../app/approval_runtime
import ./session_manager
import ../app/prompt_building
import ../app/provider_executor
import ../infra/event_queue
import ../infra/thread_owner
import ./metrics
import ../domain/turn_journal_pure

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

# ── Streaming on the executor's stream pool ───────────────────────────────────
#
# The provider call blocks, so it runs as a job on the blocking executor's
# stream pool (app/blocking_executor, `opStream`): a fixed set of workers of
# its own, so streams never take the workers per-message calls need. Nothing
# GC-managed is shared: the job carries the request (copied), a `nimcall`
# factory and an event queue. The worker builds the provider closure itself,
# sends tokens and then one final event, and the event loop polls the queue.
#
# A stopped turn returns at once and leaves its stream to drain in the
# background. Every stream counts against `MaxLiveStreams` (the pool's size)
# until its final event is read; at the cap the tool loop falls back to the
# routed completion instead of streaming.

const
  StreamFlushMs* = 1_000
  StreamPollMs = 30
  StreamChannelDepth = 512
  MaxLiveStreams* = StreamWorkerCount

var gLiveStreams {.threadvar.}: int
  ## Started and not yet drained. Event loop state: another thread would see
  ## its own zero and slip past the cap, so gStreamsOwner refuses it.
var gStreamsOwner: ThreadOwner

proc liveStreams*(): int {.gcsafe.} =
  if gStreamsOwner.isOwner("live stream count"): gLiveStreams else: 0

proc streamSlotAvailable*(): bool {.gcsafe.} =
  ## False on any thread but the loop's: streaming is only counted there.
  gStreamsOwner.isOwner("live stream count") and
    gLiveStreams < min(MaxLiveStreams, poolCapacity(opStream))

proc streamStarted() {.gcsafe.} =
  if gStreamsOwner.isOwner("live stream count"): inc gLiveStreams

proc streamReaped() {.gcsafe.} =
  if gStreamsOwner.isOwner("live stream count"): dec gLiveStreams

type
  StreamEvent = object
    done:     bool              ## the last event: `response` or `error` is set
    token:    string
    response: CompletionResponse
    error:    string

  StreamJob = object
    factory: StreamFactory
    req:     CompletionRequest
    events:  EventQueue[StreamEvent]

proc runStreamJob(job: StreamJob): Result[bool, string] {.nimcall, gcsafe, raises: [].} =
  ## A job on the executor's stream pool: tokens and then one final event go
  ## through `events`; the provider closure is built here, on the worker.
  let events = job.events
  var final = StreamEvent(done: true)
  try:
    let fn =
      if job.factory.runtime != nil: job.factory.runtime(job.factory.spec).streamFn
      else: job.factory.build(job.factory.credential)
    if fn == nil:
      final.error = "streaming unavailable"
    else:
      let res = fn(job.req,
                   proc(tok: string) {.gcsafe.} =
                     events.waitPush(StreamEvent(token: tok)))
      if res.isOk: final.response = res.value
      else: final.error = res.error
  except Exception as e:  ## effect boundary: callee raises are unannotated
    final.error = e.msg
  events.waitPush(final)
  ok(true)

proc reapStream(events: EventQueue[StreamEvent]) {.async: (raises: []).} =
  ## Drains an abandoned stream (stopped or cancelled turn) until its final
  ## event, then frees the queue, without blocking the event loop meanwhile.
  ## The worker goes back to the pool when the provider call ends.
  var q = events
  while true:
    var ev: StreamEvent
    if q.tryPop(ev):
      if ev.done: break
    else:
      try: await sleepAsync(milliseconds(StreamPollMs))
      except CancelledError: return  ## shutting down: leave the worker be
  q.dispose()
  streamReaped()

proc streamToOutbox*(factory:   StreamFactory;
                    req:       CompletionRequest;
                    outbox:    AsyncQueue[OutboundMessage];
                    userId:    UserId;
                    ch:        ChannelKind;
                    replyTo:   string;
                    streamId:  string;
                    stopGeneration: uint64 = 0;
                    bridgeToken: uint64 = 0;
                    shown: ref bool = nil):
                    Future[Result[CompletionResponse, string]] {.async.} =
  ## Streams one completion into `outbox` as partial edits and a final
  ## message. The provider call runs on the executor's stream pool (its own
  ## workers, never the ones per-message calls use). A stop returns at once;
  ## the stream is drained in the background.
  ## `shown`, when given, turns true once a partial reached the outbox: a
  ## stream that failed before that can be retried without the user seeing
  ## two answers.
  if not streamSlotAvailable():
    return err("streaming saturated: " & $gLiveStreams &
               " stream(s) still running")
  var events = initEventQueue[StreamEvent]("stream", StreamChannelDepth)
  let running = runOffLoop(runStreamJob,
                           StreamJob(factory: factory, req: req, events: events),
                           pool = opStream)
  streamStarted()

  var accumulated = ""
  var lastFlush   = nowMs()
  var lastSent    = ""
  var joined      = false

  try:
    while true:
      if isSessionStopRequested(stopGeneration):
        return ok(CompletionResponse())
      while true:
        var ev: StreamEvent  ## fresh each time: see EventQueue.tryPop
        if not events.tryPop(ev): break
        if not ev.done:
          accumulated.add(ev.token)
          continue
        events.dispose()
        streamReaped()
        joined = true
        if ev.error.len > 0:
          return err(ev.error)
        let finalResponse = ev.response
        if finalResponse.toolCalls.len == 0 and
           not isSessionStopRequested(stopGeneration):
          if shown != nil:
            shown[] = true
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

      if accumulated.len > 0 and nowMs() - lastFlush >= StreamFlushMs:
        lastFlush = nowMs()
        let visible = cleanResponse(safeStreamPrefix(accumulated))
        if visible.strip.len > 0 and visible != lastSent:
          if isSessionStopRequested(stopGeneration):
            return ok(CompletionResponse())
          lastSent = visible
          if shown != nil:
            shown[] = true
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

      ## The job pushes its final event before it returns, so a finished job
      ## with an error and no final event never ran (pool full) or failed
      ## outside the provider call: nothing more will come. Disposing the
      ## queue here is safe because runOffLoop's future completes either
      ## before the handoff to a worker, or only after the worker finished
      ## the job and returned (it is never cancelled here), so no writer
      ## remains.
      if running.finished:
        let outcome =
          try: running.read()
          except CatchableError as e: err(Result[bool, string], e.msg)
        if outcome.isErr:
          events.dispose()
          streamReaped()
          joined = true
          return err("stream: " & outcome.error)
      await sleepAsync(milliseconds(StreamPollMs))
  finally:
    if not joined:
      asyncSpawn reapStream(events)

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
  except Exception as e: err(e.msg)  ## effect boundary: callee raises are unannotated

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
    except Exception as e:  ## effect boundary: callee raises are unannotated
      return completionErr(e.msg)
  if completeFn == nil:
    return completionErr("provider unavailable: no completion function")
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
                     userInterrupt: uint64;
                     providerLabel: string;
                     log: Logger;
                     channel = ""): Future[ToolCallResult] {.async.} =
  let payload = $ %* {
    "name": tc.name, "id": tc.id, "inputJson": tc.inputJson,
    "userInterrupt": userInterrupt.BiggestInt, "channel": channel
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

proc executeToolCallUntimed(globalOutbox: AsyncQueue[OutboundMessage];
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

  ## Write-ahead: the turn journal learns of an effect before it happens, so
  ## a crash in between never leads to running it twice.
  if nativeCtx.beforeEffect != nil and isEffectfulTool(tc.name):
    nativeCtx.beforeEffect(tc.name)

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
    toolInbox, toolOut, msgId, round, callIndex, tc, $uid, nativeCtx.userInterrupt,
    providerLabel, log, channel = $channel)
  if debugMode:
    await globalOutbox.put(OutboundMessage(
      userId: uid, channel: channel,
      text: buildToolDebugResultText(tc.name, toolResult.text),
      replyKind: rkDebug, bridgeToken: bridgeToken))
  toolResult

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
  ## Runs one tool call and records it: per tool, ok when it returned
  ## output, with its duration (approval waits included).
  let startedMs = nowMs()
  let res = await executeToolCallUntimed(
    globalOutbox, toolInbox, toolOut, nativeCtx, state, history, uid, channel,
    msgId, round, callIndex, tc, providerLabel, debugMode, log, bridgeToken)
  recordToolCall(tc.name, float(nowMs() - startedMs),
                 ok = res.resultKind == trkOutput)
  return res

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

proc recordStreamRound(factory: StreamFactory;
                       res: Result[CompletionResponse, string];
                       elapsedMs: int64) =
  ## A streamed round bypasses the provider executor, so it is measured here.
  let provider = (if factory.provider.len > 0: factory.provider else: "stream")
  recordLatency(provider, float(elapsedMs))
  if res.isErr:
    recordError(provider)
  else:
    recordTokens(provider, res.get.inputTokens, res.get.outputTokens,
                 res.get.cacheReadTokens, res.get.cacheWriteTokens)

proc runToolLoop*(globalOutbox: AsyncQueue[OutboundMessage];
                 toolInbox: AsyncQueue[AgentMessage];
                 toolOut: AsyncQueue[AgentMessage];
                 memory: MemoryRuntimePort;
                 completeFn: CompleteFn;
                 errorExplainFn: CompleteFn;
                 streamFactory: StreamFactory;
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
                 bridgeToken: uint64 = 0;
                 providerOverride = "";
                 modelOverride = "";
                 streamRoute: StreamRouteFn = nil;
                 providerRuntime: ProviderRuntimeBuilder = nil): Future[ToolLoopRunResult] {.async.} =
  ## `providerOverride`/`modelOverride`: a named agent's model, carried on
  ## every request of the turn so routing tries it first.
  ## `streamRoute` and `providerRuntime`: the turn streams through the
  ## provider its routing selects (a named agent's own included) when that
  ## provider's stream carries tool calls; without them, through
  ## `streamFactory` as before.
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
    req.providerOverride = providerOverride
    req.modelOverride = modelOverride

    ## With a route known, the stream goes through the provider routing
    ## selects, and only if its stream carries tool calls
    ## (descriptors.streamsToolCalls); otherwise the round is not streamed.
    ## It never falls back to the session's factory then: that would stream
    ## from a provider and model routing did not pick. Without a route (no
    ## provider runtime), the session's factory as before, which streams
    ## tool calls only through OpenRouter.
    var roundFactory = streamFactory
    var factoryStreamsTools = providerLabel.toLowerAscii().startsWith("openrouter")
    var routeKnown = false
    if streamRoute != nil and providerRuntime != nil:
      let route = streamRoute(req)
      if route.isSome:
        routeKnown = true
        factoryStreamsTools = streamsToolCalls(route.get.providerName)
        roundFactory =
          if factoryStreamsTools: routeStreamFactory(providerRuntime, route.get)
          else: StreamFactory()
    let canStreamToolCalls =
      roundFactory.available and streamSlotAvailable() and factoryStreamsTools
    ## Suppressing tool progress must not disable plain streaming on the
    ## first round; only the tool-call stream channel stays hidden.
    if decideToolLoopStreaming(
      round = round,
      toolsCount = tools.len,
      streamingAvailable = roundFactory.available and streamSlotAvailable(),
      streamingToolCalls = canStreamToolCalls and not suppressProgress,
    ).useStreaming:
      let streamStartedMs = nowMs()
      let shown = new bool
      var streamedRes = await streamToOutbox(
        roundFactory, req, globalOutbox, uid, channel, replyTo, streamId,
        nativeCtx.stopGeneration, bridgeToken = bridgeToken, shown = shown)
      recordStreamRound(roundFactory, streamedRes, nowMs() - streamStartedMs)
      ## The streaming branch goes through the same one-shot demotion: a
      ## vision-less model can refuse the inline image before the first token.
      if streamedRes.isErr and not loopState.imageRetryUsed and
         not sessionStopRequested(nativeCtx) and
         hasInlineImages(req) and isImageRejection(streamedRes.error):
        loopState.imageRetryUsed = true
        loopState.history = demoteInlineImagesForTurn(loopState.history)
        req = withoutInlineImages(req)
        streamedRes = await streamToOutbox(
          roundFactory, req, globalOutbox, uid, channel, replyTo, streamId,
          nativeCtx.stopGeneration, bridgeToken = bridgeToken, shown = shown)
      let fallBackToRouting =
        streamedRes.isErr and routeKnown and not shown[] and
        not sessionStopRequested(nativeCtx)
      if fallBackToRouting:
        ## Nothing reached the user: routing can try the next provider.
        nativeCtx.log.warn("stream failed before any text; routing instead: " &
                           clipProviderError(streamedRes.error))
      if streamedRes.isErr and not fallBackToRouting:
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
        loopState.providerFailed = true
        continue
      if not fallBackToRouting:
        let streamed = streamedRes.value
        loopState.usage = loopState.usage.addUsage(streamed)
        if sessionStopRequested(nativeCtx):
          loopState.done = true
          break

        log.info($uid & " (" & $channel & ") <- [" & providerLabel &
                 "] |" & $streamed.text.len & "| stream")
        if streamed.toolCalls.len > 0:
          loopState.history.addAssistantWithToolCalls(streamed.text, streamed.toolCalls,
                                                      reasoning = streamed.reasoning,
                                                      replayBlocks = streamed.replayBlocks)
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
          loopState = withStreamFinalText(streamed.text, streamed.reasoning, loopState,
                                          streamed.replayBlocks)
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
      loopState.providerFailed = true
      continue

    let r = resp.value
    loopState.usage = loopState.usage.addUsage(r)
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
      loopState.history.addAssistantWithToolCalls(r.text, r.toolCalls,
                                                  reasoning = r.reasoning,
                                                  replayBlocks = r.replayBlocks)
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
                        streamFactory: StreamFactory;
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
