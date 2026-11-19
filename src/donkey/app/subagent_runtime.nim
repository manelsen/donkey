## subagent_runtime — isolated child sessions with policy, budget and cleanup.
##
## The effectful shell around domain/subagent_pure. A child gets:
##   - its own paddock at {parentPaddock}/subagents/{id} (0700);
##   - a filtered, read-only tool set (no parent history);
##   - the same provider, approval service, URL/network policy and memory user;
##   - a hard token/time/tool-call budget and a dedicated output sink.
##
## The child never writes directly to the user channel: approval messages use
## the parent outbox, while progress/errors go to a drained child outbox.

import std/[algorithm, strutils, tables]
import chronos
import chronos/asyncsync
import ../core/log
import ../core/agent_events
import ../core/pipeops
import ../domain/agent_message
import ../domain/message
import ../domain/subagent_pure
import ../ports/provider
import ../ports/subagent_workspace
import ./native_tools
import ./prompt_building
import ./provider_executor
import ./session_manager
import ./session_state
import ./tool_agent
import ./tool_loop_runtime
import ./tools/fs_tools

const
  SubagentSystemPrompt* =
    "You are a focused subagent. Complete only the delegated task. " &
    "You cannot ask the user questions or spawn other subagents. " &
    "Use the available tools when needed, respect the workspace boundary, " &
    "and return a concise, self-contained result.\n\n" & LiveSourcesPrompt
  SubagentMaxConcurrent* = 16
  SubagentCompletedRetention* = 64

  ## Bound for completed fan-out states that nobody awaits (C3). The state
  ## holds the plan, the outcomes snapshot and the supervisor future, so it
  ## must not accumulate for the life of the process.
  SubagentFanoutRetention* = 64
  SubagentFanoutRetentionMs* = 600_000'i64

  FanoutTickMs = 100
  SubagentSettleBudgetMs = 2_000'i64

type
  ChildTools = object
    names:         seq[string]
    descriptions:  seq[ToolDescription]

  SubagentRuntime = ref object
    id:           string
    request:      SubagentRequest
    limits:       SubagentLimits
    usage:        SubagentUsage
    status:       SubagentStatus
    result:       SubagentResult
    createdAtMs:  int64
    lastActivityMs: int64
    paddockDir:   string
    parent:       NativeCtx
    childCtx:     NativeCtx
    childState:   SessionState
    completeFn:   CompleteFn
    asyncCompleteFn: AsyncCompleteFn
    history:      ConversationHistory
    systemBase:   string
    childOutbox:  AsyncQueue[OutboundMessage]
    toolInbox:    AsyncQueue[AgentMessage]
    toolOut:      AsyncQueue[AgentMessage]
    toolAgentFuture: Future[void]
    future:       Future[void]
    loopFuture:   Future[ToolLoopRunResult]
    lastError:    string
    fanoutId:     string
    fanoutIndex:  int
    cancelledBySibling: bool
    finalized:    bool

  ## Handle of a running fan-out: the id plus the children created, in plan
  ## order. Returned as soon as the children start (`wait=false` uses it).
  FanoutHandle* = object
    fanoutId*: string
    childIds*: seq[string]

  ## Result of `startFanout`. `failedIndex >= 0` means the plan aborted while
  ## spawning that child; `handle.childIds` still lists the children created
  ## and already cancelled/settled.
  FanoutStart* = object
    handle*:      FanoutHandle
    failedIndex*: int
    error*:       string

  ## Supervisor bookkeeping for one fan-out. Lives in `mgr.fanouts` in both
  ## modes (awaited and detached) so cancellation can always find it. Outcomes
  ## are captured at child completion, never rebuilt from `mgr.children`.
  FanoutState* = ref object
    fanoutId*:      string
    plan*:          FanoutPlan
    policy*:        FanoutPolicy
    childIds*:      seq[string]
    outcomes*:      seq[FanoutOutcome]
    captured*:      seq[bool]
    signal*:        FanoutSignal
    done*:          bool
    doneAtMs*:      int64  ## monotonic timestamp of `done` (retention, C3)
    deadlineMono*:  int64
    lastProgressMs*: int64
    future*:        Future[void]

  SubagentManager* = ref object
    children:      Table[string, SubagentRuntime]
    fanouts*:      Table[string, FanoutState]
    counter:       int
    fanoutCounter: int
    maxConcurrent: int
    closed:        bool
    workspace:     SubagentWorkspacePort

# ── Helpers ───────────────────────────────────────────────────────────────────

proc reapVoid(fut: Future[void]) {.async.} =
  try:
    await fut
  except CancelledError:
    discard
  except Exception:
    discard

proc reapLoop(fut: Future[ToolLoopRunResult]) {.async.} =
  try:
    discard await fut
  except CancelledError:
    discard
  except Exception:
    discard

proc awaitSettled*(future: Future[void]; budgetMs: int64):
                   Future[bool] {.async.} =
  ## Bounded wait on a monotonic deadline (C4). `finished()` is polled on a
  ## nap: the future is never awaited and never cancelled here, so a child that
  ## ignores cancellation cannot extend the budget or block the caller. Returns
  ## whether the future finished inside the budget.
  if future.isNil or future.finished():
    return true
  let deadline = nowMs() + max(0'i64, budgetMs)
  while not future.finished():
    let remaining = deadline - nowMs()
    if remaining <= 0:
      return false
    await sleepAsync(chronos.milliseconds(int(min(remaining, 20'i64))))
  true

proc markCancelled(rt: SubagentRuntime; bySibling: bool)
                  {.gcsafe, raises: [].} =
  ## Synchronous half of a cancellation: status and flags become visible before
  ## any settlement `await`, so a sibling cannot slip a completion into the
  ## cancel/settle window (C2). Settlement belongs to `settleChild`.
  ## `bySibling` is set only by the supervisor's fail-fast path (C5).
  if rt.isNil or rt.status notin {ssQueued, ssRunning}:
    return
  if bySibling:
    rt.cancelledBySibling = true
  rt.usage.cancelled = true
  rt.usage.budgetError = "subagent was cancelled"
  rt.status = ssCancelled
  rt.lastError = "subagent was cancelled"
  if not rt.future.isNil and not rt.future.finished():
    rt.future.cancelSoon()
  rt.result.subagentId = rt.id
  rt.result.status = ssCancelled
  rt.result.error = rt.lastError
  rt.result.toolCalls = max(rt.result.toolCalls, rt.usage.toolCalls)
  rt.result.inputTokens = rt.usage.inputTokens
  rt.result.outputTokens = rt.usage.outputTokens
  rt.result.durationMs = max(0'i64, epochMs() - rt.createdAtMs)
  rt.usage.lastActivityMs = epochMs()

# ── Fan-out decisions shared with the completion path ────────────────────────
# `captureOutcome` and `cancelSubagent` evaluate these at the exact moment of
# the event (completion or external cancel), not on the next supervisor tick.

func fanoutTokens(mgr: SubagentManager; st: FanoutState): int =
  ## Runtime ceiling input: captured (finished) children plus the live ones.
  ## A finished child must keep counting or 15 then 10 would evade a 20 cap.
  for i in 0 ..< st.plan.len:
    if st.captured[i]:
      result += totalTokens(st.outcomes[i].usage)
    elif i < st.childIds.len and st.childIds[i] in mgr.children:
      result += totalTokens(mgr.children[st.childIds[i]].usage)

func fanoutHasFailure(st: FanoutState): bool =
  for i in 0 ..< st.plan.len:
    if not st.captured[i]:
      continue
    let outcome = st.outcomes[i]
    if outcome.cancelledBySibling or outcome.status == ssCancelled:
      continue
    if outcome.status in {ssFailed, ssTimedOut}:
      return true
  false

proc timeOutFanoutChildren(mgr: SubagentManager; st: FanoutState) =
  for id in st.childIds:
    if id notin mgr.children:
      continue
    let rt = mgr.children[id]
    if rt.status notin {ssQueued, ssRunning}:
      continue
    rt.status = ssTimedOut
    rt.lastError = "fanout exceeded its aggregate duration"
    rt.usage.cancelled = true
    rt.usage.budgetError = rt.lastError
    rt.result.status = ssTimedOut
    rt.result.error = rt.lastError
    if not rt.future.isNil and not rt.future.finished():
      rt.future.cancelSoon()

proc signalFanoutBudgetStop(mgr: SubagentManager; st: FanoutState) =
  ## C6: the cap was crossed by a completion. The live siblings are stopped in
  ## that step (not on the next tick), so none of them starts another round.
  ## This is a budget stop, not a sibling failure: `cancelledBySibling` stays
  ## clear.
  for id in st.childIds:
    if id notin mgr.children:
      continue
    markCancelled(mgr.children[id], bySibling = false)

proc signalFanoutFailFast(mgr: SubagentManager; rt: SubagentRuntime) =
  ## US-004/C5: an external cancel of one child under `fpFailFast` is a
  ## fail-fast trigger, exactly like an internal failure. Only the *siblings*
  ## are marked `cancelledBySibling`; the externally cancelled child is not.
  ## The supervisor's own cancels never reach here: those children are marked
  ## before `settleChild`, so `cancelSubagent` returns early.
  if mgr.isNil or mgr.closed or rt.isNil or rt.fanoutId.len == 0:
    return
  if rt.fanoutId notin mgr.fanouts:
    return
  let st = mgr.fanouts[rt.fanoutId]
  if st.done or st.policy != fpFailFast:
    return
  if st.signal.stopRequested or st.signal.budgetExceeded:
    return
  for id in st.childIds:
    if id == rt.id or id notin mgr.children:
      continue
    markCancelled(mgr.children[id], bySibling = true)

func estimateTextTokens(text: string): int =
  if text.len == 0: 0 else: max(1, text.len div 4)

func estimateRequestTokens(req: CompletionRequest): int =
  result = estimateTextTokens(req.system)
  for msg in req.messages:
    result += estimateTextTokens(msg.text)
  for tool in req.tools:
    result += estimateTextTokens(tool.description)
    result += estimateTextTokens(tool.schemaJson)

proc buildChildTools(parent: NativeCtx; requested: seq[string]):
                    Result[ChildTools, string] =
  let selection = resolveSubagentTools(requested)
  if selection.error.len > 0:
    return err(selection.error)
  if selection.denied.len > 0:
    return err("tools not allowed for subagents: " &
               selection.denied.join(", "))
  if selection.unknown.len > 0:
    return err("unknown subagent tools: " & selection.unknown.join(", "))
  let explicitRequest = requested.len > 0
  var tools: ChildTools
  for name in selection.tools:
    for description in parent.tools:
      if description.name == name:
        tools.names.add(name)
        tools.descriptions.add(description)
        break
  if explicitRequest:
    for name in selection.tools:
      if name notin tools.names:
        return err("tool '" & name & "' is not available in the parent session")
  if tools.names.len == 0:
    return err("no allowed tools are available in the parent session")
  ok(tools)

func failedSpawn(message: string): SubagentSpawnResult =
  SubagentSpawnResult(status: ssFailed, error: message)

func terminalStatus(status: SubagentStatus): bool =
  status notin {ssQueued, ssRunning}

func rtSettled(rt: SubagentRuntime): bool =
  ## A child is settled only when its status is terminal **and** its future
  ## has finished. Inside `runChild`'s finally the future is still running,
  ## so cleanup scheduled there can never observe a settled child.
  rt != nil and terminalStatus(rt.status) and not rt.future.isNil and
    rt.future.finished()

proc childSettled*(mgr: SubagentManager; subagentId: string): bool =
  ## Terminal status and no pending future. Single predicate used by the
  ## removal path (and asserted by the spy workspace port in tests).
  if mgr.isNil:
    return false
  let rt = mgr.children.getOrDefault(subagentId)
  rtSettled(rt)

proc finalizeChild*(mgr: SubagentManager; rt: SubagentRuntime): bool =
  ## The single owner of `workspace.remove`. Idempotent: the completion
  ## watcher, `settleChild` and `cancelAll` may all reach the same child.
  ## A child that has not settled keeps its paddock and is logged instead.
  if rt == nil:
    return false
  if rt.finalized:
    return true
  if not rtSettled(rt):
    rt.parent.log.warn("subagent paddock kept until settlement id=" & rt.id)
    return false
  rt.finalized = true
  if rt.paddockDir.len == 0 or mgr.workspace.remove == nil:
    return true
  let removed = mgr.workspace.remove(rt.paddockDir)
  if removed.isErr:
    rt.parent.log.warn("subagent paddock cleanup failed id=" & rt.id &
                       " path=" & rt.paddockDir & " error=" & removed.error)
  true

func outcomeFor(rt: SubagentRuntime; index: int): FanoutOutcome =
  FanoutOutcome(
    index:              index,
    subagentId:         rt.id,
    status:             rt.status,
    text:               rt.result.text,
    error:              rt.lastError,
    usage:              rt.usage,
    cancelledBySibling: rt.cancelledBySibling,
    durationMs:         max(0'i64, rt.result.durationMs),
  )

proc captureOutcome(mgr: SubagentManager; rt: SubagentRuntime) =
  ## Called from `runChild`'s finally: the outcome is frozen exactly when the
  ## child finishes, before retention can prune it from `mgr.children`.
  if rt.fanoutId.len == 0 or mgr.fanouts.len == 0:
    return
  if rt.fanoutId notin mgr.fanouts:
    return
  let st = mgr.fanouts[rt.fanoutId]
  if rt.fanoutIndex < 0 or rt.fanoutIndex >= st.outcomes.len:
    return
  if st.captured[rt.fanoutIndex]:
    return
  ## C7: the aggregate deadline applies at completion time, not on the next
  ## 100 ms tick. A child that finished after it is not a success.
  if st.deadlineMono > 0 and nowMs() >= st.deadlineMono and
      rt.status == ssCompleted:
    rt.status = ssTimedOut
    rt.lastError = "fanout exceeded its aggregate duration"
    rt.result.status = ssTimedOut
    rt.result.error = rt.lastError
  st.outcomes[rt.fanoutIndex] = outcomeFor(rt, rt.fanoutIndex)
  st.captured[rt.fanoutIndex] = true
  ## C7: once the deadline is spent, the remaining children are timed out now
  ## instead of waiting for the tick to do it.
  if st.deadlineMono > 0 and nowMs() >= st.deadlineMono:
    timeOutFanoutChildren(mgr, st)
  ## C6: the runtime token ceiling is also checked on every completion, so a
  ## running sibling cannot start another provider round until the next tick.
  if not st.signal.budgetExceeded and
      fanoutBudgetDecision(fanoutTokens(mgr, st), st.plan.limits) ==
        bdTokensExceeded:
    st.signal.budgetExceeded = true
    signalFanoutBudgetStop(mgr, st)

proc makeBudgetedComplete(rt: SubagentRuntime;
                          parentComplete: CompleteFn): CompleteFn =
  result = proc(req: CompletionRequest):
               Result[CompletionResponse, string] {.gcsafe, raises: [].} =
    if rt.usage.cancelled:
      rt.usage.budgetError = "subagent was cancelled"
      rt.lastError = rt.usage.budgetError
      return err(rt.usage.budgetError)
    let decision = checkBudget(rt.usage, rt.limits, nowMs(),
                               checkToolCalls = false)
    if decision != bdOk:
      rt.usage.budgetError = budgetDecisionText(decision)
      rt.lastError = rt.usage.budgetError
      return err(rt.usage.budgetError)
    let response =
      try:
        parentComplete(req)
      except Exception as e:
        err("subagent provider error: " & e.msg)
    if response.isErr:
      rt.lastError = response.error
      return response
    var inputTokens = response.value.inputTokens
    var outputTokens = response.value.outputTokens
    if inputTokens <= 0:
      inputTokens = estimateRequestTokens(req)
    if outputTokens <= 0:
      outputTokens = estimateTextTokens(response.value.text)
    rt.usage.recordTokens(inputTokens, outputTokens, epochMs())
    rt.lastActivityMs = rt.usage.lastActivityMs
    if totalTokens(rt.usage) > rt.limits.maxTokens:
      rt.usage.budgetError = budgetDecisionText(bdTokensExceeded)
      rt.lastError = rt.usage.budgetError
      return err(rt.usage.budgetError)
    response

proc makeBudgetedAsyncComplete(rt: SubagentRuntime;
                               parentComplete: AsyncCompleteFn): AsyncCompleteFn =
  result = proc(req: CompletionRequest):
               Future[Result[CompletionResponse, string]] {.async, gcsafe.} =
    if rt.usage.cancelled:
      rt.usage.budgetError = "subagent was cancelled"
      rt.lastError = rt.usage.budgetError
      return err(rt.usage.budgetError)
    let decision = checkBudget(rt.usage, rt.limits, nowMs(),
                               checkToolCalls = false)
    if decision != bdOk:
      rt.usage.budgetError = budgetDecisionText(decision)
      rt.lastError = rt.usage.budgetError
      return err(rt.usage.budgetError)
    let response =
      try:
        await parentComplete(req)
      except CancelledError:
        raise
      except Exception as e:
        err("subagent provider error: " & e.msg)
    if response.isErr:
      rt.lastError = response.error
      return response
    var inputTokens = response.value.inputTokens
    var outputTokens = response.value.outputTokens
    if inputTokens <= 0:
      inputTokens = estimateRequestTokens(req)
    if outputTokens <= 0:
      outputTokens = estimateTextTokens(response.value.text)
    rt.usage.recordTokens(inputTokens, outputTokens, epochMs())
    rt.lastActivityMs = rt.usage.lastActivityMs
    if totalTokens(rt.usage) > rt.limits.maxTokens:
      rt.usage.budgetError = budgetDecisionText(bdTokensExceeded)
      rt.lastError = rt.usage.budgetError
      return err(rt.usage.budgetError)
    response

# ── Child lifecycle ───────────────────────────────────────────────────────────

proc pruneChildren(mgr: SubagentManager) {.gcsafe, raises: [].}

proc runChild(mgr: SubagentManager; rt: SubagentRuntime) {.async.} =
  try:
    await sleepAsync(chronos.milliseconds(1))
    rt.status = ssRunning
    rt.loopFuture = runToolLoop(
      globalOutbox = rt.childOutbox,
      toolInbox = rt.toolInbox,
      toolOut = rt.toolOut,
      memory = rt.parent.memory,
      completeFn = rt.completeFn,
      errorExplainFn = nil,
      asyncCompleteFn = rt.asyncCompleteFn,
      streamFn = nil,
      nativeCtx = rt.childCtx,
      state = rt.childState,
      history = rt.history,
      uid = rt.parent.uid,
      channel = rt.parent.channel,
      replyTo = "",
      msgId = "subagent-" & rt.id,
      streamId = "subagent-" & rt.id,
      systemBase = rt.systemBase,
      context = rt.request.context,
      tools = rt.childCtx.tools,
      providerLabel = "subagent",
      suppressProgress = true,
      debugMode = false,
      showReasoning = false,
      log = rt.childCtx.log,
    )
    let finished = await withTimeout(
      rt.loopFuture, milliseconds(int(rt.limits.maxDurationMs)))
    if not finished:
      rt.status = ssTimedOut
      rt.lastError = "subagent timed out after " & $rt.limits.maxDurationMs & "ms"
      rt.usage.budgetError = rt.lastError
      rt.loopFuture.cancelSoon()
      asyncSpawn reapLoop(rt.loopFuture)
    else:
      let loopResult = rt.loopFuture.read()
      rt.result.text = loopResult.finalText
      rt.result.toolCalls = loopResult.toolCallCount
      if rt.status == ssCancelled or rt.usage.cancelled:
        rt.status = ssCancelled
        if rt.lastError.len == 0:
          rt.lastError = "subagent was cancelled"
      elif rt.usage.budgetError.len > 0:
        rt.status = ssFailed
        rt.lastError = rt.usage.budgetError
      elif rt.lastError.len > 0:
        rt.status = ssFailed
      elif not loopResult.done:
        rt.status = ssFailed
        rt.lastError = "subagent exceeded the tool-round limit"
      else:
        rt.status = ssCompleted
  except CancelledError:
    if rt.status != ssTimedOut:
      rt.status = ssCancelled
      if rt.lastError.len == 0:
        rt.lastError = "subagent was cancelled"
  except Exception as e:
    rt.status = ssFailed
    rt.lastError = "subagent failed: " & e.msg
  finally:
    if not rt.loopFuture.isNil and not rt.loopFuture.finished():
      rt.loopFuture.cancelSoon()
      asyncSpawn reapLoop(rt.loopFuture)
    if not rt.toolInbox.isNil:
      discard rt.toolInbox.put(newCancelMsg())
    if rt.status in {ssQueued, ssRunning}:
      rt.status = ssFailed
      if rt.lastError.len == 0:
        rt.lastError = "subagent ended without a result"
    rt.result.subagentId = rt.id
    rt.result.status = rt.status
    rt.result.error = rt.lastError
    if rt.result.toolCalls == 0:
      rt.result.toolCalls = rt.usage.toolCalls
    rt.result.inputTokens = rt.usage.inputTokens
    rt.result.outputTokens = rt.usage.outputTokens
    rt.result.durationMs = max(0'i64, epochMs() - rt.createdAtMs)
    rt.lastActivityMs = epochMs()
    rt.usage.lastActivityMs = rt.lastActivityMs
    rt.childOutbox.clear()
    ## Removal does not happen here: the future is still running inside its
    ## own finally, so `childSettled` is false. `finalizeWhenSettled` (and the
    ## fan-out supervisor) remove after settlement through `finalizeChild`.
    captureOutcome(mgr, rt)
    pushAgentEvent(AgentEvent(
      kind: aekSessionEnd,
      userId: $rt.parent.uid,
      channel: $rt.parent.channel,
      summary: "subagent " & rt.id & " " & $rt.status,
    ))
    pruneChildren(mgr)

proc finalizeWhenSettled(mgr: SubagentManager; rt: SubagentRuntime) {.async.} =
  ## Completion watcher. It owns no I/O besides delegating to `finalizeChild`;
  ## every fan-out child also gets one, so an awaited or detached fan-out
  ## never leaks a paddock.
  if rt.future.isNil:
    return
  ## C1: `markCancelled` cancels the future to deliver the cancellation, and
  ## awaiting a cancelled future never resumes the awaiter. The watcher therefore
  ## waits on the finish, bounded, and removes only a settled child; otherwise
  ## a cancelled child kept its paddock for the life of the process.
  if not rt.future.finished():
    try:
      await rt.future
    except CancelledError:
      discard
    except Exception:
      discard
  if not await awaitSettled(rt.future, SubagentSettleBudgetMs):
    rt.parent.log.warn("subagent paddock orphaned: child did not settle id=" &
                       rt.id)
  discard finalizeChild(mgr, rt)

proc pruneChildren(mgr: SubagentManager) {.gcsafe, raises: [].} =
  if mgr.children.len <= SubagentCompletedRetention:
    return
  var finished: seq[SubagentRuntime]
  for _, child in mgr.children:
    if child.status notin {ssQueued, ssRunning}:
      finished.add(child)
  finished.sort(proc(a, b: SubagentRuntime): int =
    cmp(a.createdAtMs, b.createdAtMs))
  for child in finished:
    if mgr.children.len <= SubagentCompletedRetention:
      break
    mgr.children.del(child.id)

# ── Public manager API ────────────────────────────────────────────────────────

proc newSubagentManager*(workspace: SubagentWorkspacePort = SubagentWorkspacePort();
                         maxConcurrent = SubagentMaxConcurrent): SubagentManager =
  SubagentManager(
    children: initTable[string, SubagentRuntime](),
    fanouts: initTable[string, FanoutState](),
    maxConcurrent: max(1, maxConcurrent),
    workspace: workspace,
  )

proc spawn*(mgr: SubagentManager; parent: NativeCtx;
            request: SubagentRequest; fanoutId = "";
            fanoutIndex = -1): Future[SubagentSpawnResult] {.async.} =
  if mgr.closed:
    return failedSpawn("subagent manager is shutting down")
  let requestError = subagentRequestError(request, parent.subagentDepth)
  if requestError.len > 0:
    return failedSpawn(requestError)
  if parent.completeFn == nil:
    return failedSpawn("subagent provider is unavailable")
  if parent.asyncCompleteFn == nil:
    return failedSpawn("subagent provider must be asynchronous")
  if parent.paddockDir.len == 0:
    return failedSpawn("subagents require a paddock")
  let childTools = buildChildTools(parent, request.tools).valueOr:
    return failedSpawn(error)

  var running = 0
  for _, child in mgr.children:
    if child.status in {ssQueued, ssRunning}:
      inc running
  if running >= mgr.maxConcurrent:
    return failedSpawn("too many running subagents")

  inc mgr.counter
  let id = "sub-" & $epochMs() & "-" & $mgr.counter
  if not mgr.workspace.hasSubagentWorkspace:
    return failedSpawn("subagent workspace is unavailable")
  let childDirRes = mgr.workspace.create(parent.paddockDir, id)
  if childDirRes.isErr:
    return failedSpawn("could not create the subagent paddock: " &
                       childDirRes.error)
  let childDir = childDirRes.get()
  if not inPaddock(childDir, parent.paddockDir):
    let removed = mgr.workspace.remove(childDir)
    if removed.isErr:
      parent.log.warn("subagent paddock cleanup failed id=" & id &
                      " path=" & childDir & " error=" & removed.error)
    return failedSpawn("subagent paddock escaped the parent paddock")

  let limits = clampSubagentLimits(request.limits)
  let createdAt = epochMs()
  let usage = SubagentUsage(startedAtMs: createdAt, startedAtMonoMs: nowMs(),
                            lastActivityMs: createdAt)
  let toolInbox = newAsyncQueue[AgentMessage]()
  let toolOut = newAsyncQueue[AgentMessage]()
  let childOutbox = newAsyncQueue[OutboundMessage]()
  var history = newHistory()
  history.addUser(request.task)

  var childCtx = parent
  childCtx.session = nil
  childCtx.paddockDir = childDir
  childCtx.tools = childTools.descriptions
  childCtx.log = parent.log.child("subagent-" & id)
  childCtx.restrictTools = true
  childCtx.allowedTools = childTools.names
  childCtx.subagentId = id
  childCtx.subagentDepth = parent.subagentDepth + 1
  childCtx.budget = usage
  childCtx.budgetLimits = limits
  if "web_search" notin childTools.names:
    childCtx.braveApiKey = ""
  childCtx.spawnSubagent = nil
  childCtx.awaitSubagent = nil
  childCtx.listSubagents = nil
  childCtx.cancelSubagent = nil
  childCtx.completeFn = nil

  let rt = SubagentRuntime(
    id: id,
    request: request,
    limits: limits,
    usage: usage,
    status: ssQueued,
    createdAtMs: createdAt,
    lastActivityMs: createdAt,
    paddockDir: childDir,
    parent: parent,
    childCtx: childCtx,
    childState: newSessionState(),
    history: history,
    systemBase: SubagentSystemPrompt,
    childOutbox: childOutbox,
    toolInbox: toolInbox,
    toolOut: toolOut,
    fanoutId: fanoutId,
    fanoutIndex: fanoutIndex,
  )
  rt.completeFn = makeBudgetedComplete(rt, parent.completeFn)
  if parent.asyncCompleteFn != nil:
    rt.asyncCompleteFn = makeBudgetedAsyncComplete(rt, parent.asyncCompleteFn)
  rt.childCtx.completeFn = rt.completeFn
  rt.childCtx.asyncCompleteFn = rt.asyncCompleteFn
  rt.toolAgentFuture = runToolAgent(toolInbox, toolOut, @[])
  asyncSpawn reapVoid(rt.toolAgentFuture)
  mgr.children[id] = rt
  parent.log.info("subagent started id=" & id & " task_chars=" & $request.task.len &
                  " tools=" & $childTools.names.len)
  pushAgentEvent(AgentEvent(
    kind: aekSessionStart,
    userId: $parent.uid,
    channel: $parent.channel,
    summary: "subagent " & id & " started",
  ))
  rt.future = runChild(mgr, rt)
  asyncSpawn finalizeWhenSettled(mgr, rt)
  SubagentSpawnResult(subagentId: id, status: ssRunning)

proc cancelSubagent*(mgr: SubagentManager; subagentId: string;
                     signalSiblings = true): Future[bool] {.gcsafe.}

proc awaitSubagent*(mgr: SubagentManager; subagentId: string;
                    stopGeneration: uint64;
                    userId: string; userInterrupt: uint64):
                    Future[SubagentResult] {.async.} =
  if subagentId notin mgr.children:
    return SubagentResult(
      subagentId: subagentId,
      status: ssFailed,
      error: "unknown subagent: " & subagentId,
    )
  let rt = mgr.children[subagentId]
  if not rt.future.isNil and not rt.future.finished():
    let waitMs = max(1_000'i64, rt.limits.maxDurationMs + 5_000'i64)
    let deadline = nowMs() + waitMs
    while not rt.future.finished():
      if isSessionStopRequested(stopGeneration) or
         isUserStoppedSince(userId, userInterrupt):
        ## Both process shutdown and a per-user /stop must free the parent
        ## actor: cancel the child first, then return its partial result.
        try:
          discard await mgr.cancelSubagent(subagentId)
        except CancelledError:
          discard
        except Exception:
          discard
        return rt.result
      let remaining = deadline - nowMs()
      if remaining <= 0:
        rt.usage.cancelled = true
        rt.usage.budgetError = "subagent await timed out"
        rt.status = ssTimedOut
        rt.lastError = rt.usage.budgetError
        rt.result.subagentId = rt.id
        rt.result.status = ssTimedOut
        rt.result.error = rt.lastError
        rt.result.toolCalls = max(rt.result.toolCalls, rt.usage.toolCalls)
        rt.result.inputTokens = rt.usage.inputTokens
        rt.result.outputTokens = rt.usage.outputTokens
        rt.result.durationMs = max(0'i64, epochMs() - rt.createdAtMs)
        rt.usage.lastActivityMs = epochMs()
        rt.future.cancelSoon()
        asyncSpawn reapVoid(rt.future)
        return rt.result
      await sleepAsync(milliseconds(int(min(remaining, 100'i64))))
  discard finalizeChild(mgr, rt)
  rt.result

proc cancelSubagent*(mgr: SubagentManager;
                     subagentId: string;
                     signalSiblings = true): Future[bool] {.async, gcsafe.} =
  ## External cancellation. Under `fpFailFast` it is a fail-fast trigger just
  ## like an internal failure (US-004/C5): the live siblings are signalled in
  ## the same synchronous step, before any settlement. The supervisor's own
  ## cancels pass `signalSiblings = false`; `cancelledBySibling` therefore
  ## stays reserved for the siblings the supervisor cancels.
  if subagentId notin mgr.children:
    return false
  let rt = mgr.children[subagentId]
  if rt.status notin {ssQueued, ssRunning}:
    return true
  markCancelled(rt, bySibling = false)
  if signalSiblings:
    signalFanoutFailFast(mgr, rt)
  ## Behaviour change (US-003): cancelling no longer removes the paddock.
  ## Removal belongs to `finalizeChild`, after `childSettled`.
  true

proc settleChild*(mgr: SubagentManager;
                  subagentId: string): Future[bool] {.async.} =
  ## Cancel (when live), wait at most 2 s on a monotonic deadline, then let
  ## `finalizeChild` remove the paddock. A timeout logs the orphan and does
  ## not remove: a paddock is never deleted under a running child.
  if mgr.isNil or subagentId notin mgr.children:
    return false
  let rt = mgr.children[subagentId]
  if rt.status in {ssQueued, ssRunning}:
    discard await mgr.cancelSubagent(subagentId)
  if not rt.future.isNil and not rt.future.finished():
    ## C4: an expired deadline abandons the future instead of cancelling and
    ## waiting for it, so the 2 s bound is real.
    if not await awaitSettled(rt.future, SubagentSettleBudgetMs):
      rt.parent.log.warn("subagent paddock orphaned: child did not settle in 2s id=" &
                         rt.id)
      return false
  finalizeChild(mgr, rt)

proc listSubagents*(mgr: SubagentManager): seq[SubagentInfo] =
  for _, rt in mgr.children:
    result.add(SubagentInfo(
      subagentId: rt.id,
      status: rt.status,
      createdAtMs: rt.createdAtMs,
      lastActivityMs: rt.usage.lastActivityMs,
      usage: rt.usage,
    ))

proc cancelAll*(mgr: SubagentManager): Future[void] {.async.} =
  ## Shutdown walks both registries: detached supervisors first (so they stop
  ## re-spawning/settling), then every child. Removal is delegated to
  ## `finalizeChild` only after settlement, inside a single 2 s window.
  if mgr == nil:
    return
  mgr.closed = true

  var fanoutIds: seq[string]
  for id in mgr.fanouts.keys:
    fanoutIds.add(id)
  for id in fanoutIds:
    let st = mgr.fanouts[id]
    st.signal.stopRequested = true
    st.done = true
    st.doneAtMs = nowMs()
    if not st.future.isNil and not st.future.finished():
      st.future.cancelSoon()
      asyncSpawn reapVoid(st.future)

  var ids: seq[string]
  for id in mgr.children.keys:
    ids.add(id)
  for id in ids:
    if id notin mgr.children:
      continue
    let rt = mgr.children[id]
    if rt.status in {ssQueued, ssRunning}:
      ## Shutdown is not a fail-fast trigger: `mgr.closed` keeps
      ## `signalFanoutFailFast` out of this path.
      discard await mgr.cancelSubagent(id)

  let deadline = nowMs() + SubagentSettleBudgetMs
  for id in ids:
    if id notin mgr.children:
      continue
    let rt = mgr.children[id]
    if rt.future.isNil or rt.future.finished():
      continue
    let remaining = deadline - nowMs()
    if remaining <= 0:
      rt.parent.log.warn("subagent paddock orphaned on shutdown id=" & rt.id)
      continue
    ## C4: bounded on a monotonic deadline; abandoned, never awaited.
    var settled = false
    try:
      settled = await awaitSettled(rt.future, remaining)
    except CancelledError:
      settled = rt.future.finished()
    except Exception:
      settled = rt.future.finished()
    if not settled:
      rt.parent.log.warn("subagent paddock orphaned on shutdown id=" & rt.id)

  for id in ids:
    if id notin mgr.children:
      continue
    discard finalizeChild(mgr, mgr.children[id])

# ── Fan-out supervisor (US-003) ───────────────────────────────────────────────

proc newFanoutId(mgr: SubagentManager): string =
  "fan-" & $epochMs() & "-" & $mgr.fanoutCounter

func fanoutSettleBudget(st: FanoutState): int64 =
  SubagentSettleBudgetMs * int64(max(1, st.childIds.len))

proc cancelFanoutChildren(mgr: SubagentManager; st: FanoutState;
                          bySibling: bool) {.async.} =
  ## C2: signal every live child in one synchronous phase *before* awaiting any
  ## settlement, so no sibling can finish inside the cancel/settle window.
  for id in st.childIds:
    if id notin mgr.children:
      continue
    markCancelled(mgr.children[id], bySibling)
  ## C1: the signal cancels the child future, and awaiting a cancelled future
  ## never resumes the caller. The settlement is observed on the future itself,
  ## on a bounded deadline, until every child of the signal phase is settled.
  let deadline = nowMs() + fanoutSettleBudget(st)
  for id in st.childIds:
    if id notin mgr.children:
      continue
    let rt = mgr.children[id]
    if not await awaitSettled(rt.future, deadline - nowMs()):
      rt.parent.log.warn("subagent paddock orphaned: child did not settle id=" &
                         id)
    discard finalizeChild(mgr, rt)

proc pruneFanouts*(mgr: SubagentManager; retain = SubagentFanoutRetention;
                   atMs: int64 = 0) =
  ## C3: drops completed fan-out states — oldest first — beyond `retain`, and
  ## any completed state older than `SubagentFanoutRetentionMs`. Live states
  ## are never dropped: their supervisor and cancellation hooks need them.
  ## Called automatically when a fan-out starts; `atMs` lets tests age the
  ## registry without a clock.
  if mgr.isNil or mgr.fanouts.len == 0:
    return
  let now = if atMs > 0: atMs else: nowMs()
  var completed: seq[FanoutState]
  for _, st in mgr.fanouts:
    if st.done:
      completed.add(st)
  if completed.len == 0:
    return
  completed.sort(proc(a, b: FanoutState): int = cmp(a.doneAtMs, b.doneAtMs))
  var remaining = completed.len
  for st in completed:
    let expired = st.doneAtMs > 0 and now - st.doneAtMs >=
                  SubagentFanoutRetentionMs
    if expired or remaining > retain:
      mgr.fanouts.del(st.fanoutId)
      dec remaining

proc superviseFanout(mgr: SubagentManager; st: FanoutState;
                     parent: NativeCtx) {.async.} =
  ## 100 ms tick: stop, deadline, aggregate token ceiling and fail-fast. The
  ## aggregate's stop reason stays in `aggregateFanout` (spawn > stop >
  ## budget > failure); here we only raise the signal and cancel. The same
  ## checks also run at each child completion (`captureOutcome`), so the tick
  ## is the fallback for a fan-out with no completion (C6/C7).
  try:
    while not st.done:
      await sleepAsync(chronos.milliseconds(FanoutTickMs))
      if st.done:
        break
      if isSessionStopRequested(parent.stopGeneration) or
         isUserStoppedSince($parent.uid, parent.userInterrupt):
        st.signal.stopRequested = true
        await cancelFanoutChildren(mgr, st, bySibling = false)
        break
      if nowMs() >= st.deadlineMono:
        timeOutFanoutChildren(mgr, st)
        await cancelFanoutChildren(mgr, st, bySibling = false)
        break
      if st.signal.budgetExceeded or
          fanoutBudgetDecision(fanoutTokens(mgr, st), st.plan.limits) ==
            bdTokensExceeded:
        st.signal.budgetExceeded = true
        await cancelFanoutChildren(mgr, st, bySibling = false)
        break
      if st.policy == fpFailFast and fanoutHasFailure(st):
        await cancelFanoutChildren(mgr, st, bySibling = true)
        break
      var allCaptured = true
      for captured in st.captured:
        if not captured:
          allCaptured = false
          break
      if allCaptured:
        break
  finally:
    st.done = true
    st.doneAtMs = nowMs()

proc startFanout*(mgr: SubagentManager; parent: NativeCtx;
                  plan: FanoutPlan; policy: FanoutPolicy):
                  Future[FanoutStart] {.async.} =
  ## Sequential `await mgr.spawn` per task. `spawn` is async without an
  ## internal await, so no child is blocked behind another; there is no
  ## per-child `awaitSubagent` here. On a partial spawn failure the plan
  ## aborts: created children are settled/removed and their ids returned.
  if mgr == nil:
    return FanoutStart(failedIndex: -1, error: "subagent manager is unavailable")
  var running = 0
  for _, child in mgr.children:
    if child.status in {ssQueued, ssRunning}:
      inc running
  if running + plan.len > mgr.maxConcurrent:
    return FanoutStart(
      failedIndex: -1,
      error: "too many running subagents: " & $running & " + " & $plan.len &
             " > " & $mgr.maxConcurrent,
    )

  inc mgr.fanoutCounter
  let fanoutId = newFanoutId(mgr)
  var childIds: seq[string]
  for i, task in plan.tasks:
    let request = SubagentRequest(
      task: task.task,
      context: task.context,
      tools: task.tools,
      limits: task.limits,
    )
    let spawned = await mgr.spawn(parent, request, fanoutId, i)
    if spawned.error.len > 0 or spawned.subagentId.len == 0:
      for id in childIds:
        discard await mgr.settleChild(id)
      var message = "fanout child " & $i & " failed to start: " &
                    (if spawned.error.len > 0: spawned.error
                     else: "unknown spawn error")
      if childIds.len > 0:
        message.add("; cancelled children: " & childIds.join(","))
      return FanoutStart(
        handle: FanoutHandle(fanoutId: fanoutId, childIds: childIds),
        failedIndex: i,
        error: message,
      )
    childIds.add(spawned.subagentId)

  var st = FanoutState(
    fanoutId: fanoutId,
    plan: plan,
    policy: policy,
    childIds: childIds,
    outcomes: newSeq[FanoutOutcome](plan.len),
    captured: newSeq[bool](plan.len),
    deadlineMono: nowMs() + plan.limits.maxAggregateDurationMs,
    lastProgressMs: nowMs(),
  )
  for i in 0 ..< st.outcomes.len:
    st.outcomes[i] = FanoutOutcome(index: i, status: ssQueued)
  ## C3: bound the registry before adding another state.
  mgr.pruneFanouts()
  mgr.fanouts[fanoutId] = st
  parent.log.info("fanout started id=" & fanoutId & " children=" & $plan.len &
                  " policy=" & $policy)
  st.future = superviseFanout(mgr, st, parent)
  asyncSpawn reapVoid(st.future)
  FanoutStart(handle: FanoutHandle(fanoutId: fanoutId, childIds: childIds),
              failedIndex: -1)

proc awaitFanout*(mgr: SubagentManager; fanoutId: string;
                  stopGeneration: uint64; userId: string;
                  userInterrupt: uint64): Future[FanoutAggregate] {.async.} =
  ## Aggregates the supervisor snapshot captured at each child completion —
  ## never `mgr.children`, which retention 64 may have pruned. Stop/shutdown
  ## flags from the caller are checked while waiting so a detached supervisor
  ## cannot outlive the turn that started it.
  ##
  ## C1: nothing is published while a settlement is in flight. The supervisor
  ## is never cancelled in the middle of its own cancellation work; after it
  ## finishes (or the bounded wait expires) every child is settled here before
  ## the aggregate is built. C3: the state is dropped afterwards.
  if mgr.isNil or fanoutId notin mgr.fanouts:
    return FanoutAggregate(fanoutId: fanoutId, children: @[])
  let st = mgr.fanouts[fanoutId]
  let budget = fanoutSettleBudget(st)
  var settleDeadline = 0'i64
  while true:
    if isSessionStopRequested(stopGeneration) or
       isUserStoppedSince(userId, userInterrupt):
      st.signal.stopRequested = true
      settleDeadline = nowMs() + budget
      st.done = true
      st.doneAtMs = nowMs()
      break
    if st.done or (not st.future.isNil and st.future.finished()):
      break
    await sleepAsync(chronos.milliseconds(FanoutTickMs))
  if settleDeadline == 0:
    settleDeadline = nowMs() + budget
  if not st.future.isNil and not st.future.finished():
    ## The supervisor may be mid-settlement (it was cancelled by shutdown or is
    ## cancelling children itself). Wait for that work, bounded from before
    ## `done` was observed, so the wait covers the settlement it announced (C1).
    discard await awaitSettled(st.future, settleDeadline - nowMs())
  if not st.future.isNil and st.future.finished():
    try:
      await st.future
    except CancelledError:
      discard
    except Exception:
      discard
  ## C1: `done` only says the supervisor stopped. A child it cancelled keeps
  ## running until its own finally publishes the result, so the aggregate is
  ## built only once every child of the fan-out is settled; each pending one is
  ## awaited on the shared budget and reported if it never arrives.
  if st.signal.stopRequested:
    for id in st.childIds:
      if id in mgr.children:
        markCancelled(mgr.children[id], bySibling = false)
  for id in st.childIds:
    if id notin mgr.children or mgr.childSettled(id):
      continue
    let rt = mgr.children[id]
    if rt.status in {ssQueued, ssRunning}:
      ## A live child is cancelled here; one already marked cancelled is only
      ## awaited, since a second cancel could misfire its fail-fast.
      discard await mgr.cancelSubagent(id, signalSiblings = false)
    if not await awaitSettled(rt.future, settleDeadline - nowMs()):
      rt.parent.log.warn("subagent paddock orphaned: child did not settle id=" &
                         id)
    discard finalizeChild(mgr, rt)
  var outcomes: seq[FanoutOutcome]
  for i in 0 ..< st.outcomes.len:
    if st.captured[i]:
      outcomes.add(st.outcomes[i])
  result = aggregateFanout(st.plan, outcomes, st.fanoutId, st.policy, st.signal)
  ## C3: the aggregate is a value; plan, outcomes and future are not retained.
  mgr.fanouts.del(fanoutId)
  mgr.pruneFanouts()

proc spawnFanout*(mgr: SubagentManager; parent: NativeCtx; plan: FanoutPlan;
                  policy: FanoutPolicy): Future[FanoutAggregate] {.async.} =
  ## `startFanout` + `awaitFanout`. A spawn failure still becomes a
  ## deterministic aggregate (`fsrSpawnFailed`) built from the created ids.
  let started = await mgr.startFanout(parent, plan, policy)
  if started.error.len > 0:
    var outcomes: seq[FanoutOutcome]
    for id in started.handle.childIds:
      if mgr.children.hasKey(id):
        let rt = mgr.children[id]
        outcomes.add(outcomeFor(rt, max(0, rt.fanoutIndex)))
    return aggregateFanout(plan, outcomes, started.handle.fanoutId, policy,
                           FanoutSignal(spawnFailed: true))
  await mgr.awaitFanout(started.handle.fanoutId, parent.stopGeneration,
                        $parent.uid, parent.userInterrupt)

# ── Wiring helpers ────────────────────────────────────────────────────────────

proc attachSubagentRuntime*(ctx: var NativeCtx; mgr: SubagentManager) =
  if mgr == nil:
    return
  var parentTemplate = ctx
  parentTemplate.spawnSubagent = nil
  parentTemplate.awaitSubagent = nil
  parentTemplate.listSubagents = nil
  parentTemplate.cancelSubagent = nil
  let parentCtx = parentTemplate
  ctx.spawnSubagent = proc(request: SubagentRequest):
      Future[SubagentSpawnResult] {.gcsafe, raises: [].} =
    mgr.spawn(parentCtx, request)
  ctx.awaitSubagent = proc(subagentId: string; stopGeneration: uint64;
                           userId: string; userInterrupt: uint64):
      Future[SubagentResult] {.gcsafe, raises: [].} =
    mgr.awaitSubagent(subagentId, stopGeneration, userId, userInterrupt)
  ctx.listSubagents = proc(): seq[SubagentInfo] {.gcsafe, raises: [].} =
    mgr.listSubagents()
  ctx.cancelSubagent = proc(subagentId: string):
      Future[bool] {.gcsafe, raises: [].} =
    mgr.cancelSubagent(subagentId)

func paddockDirFor*(mgr: SubagentManager; subagentId: string): string =
  if mgr != nil and subagentId in mgr.children:
    mgr.children[subagentId].paddockDir
  else:
    ""
