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
    "and return a concise, self-contained result."
  SubagentMaxConcurrent* = 16
  SubagentCompletedRetention* = 64

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

  SubagentManager* = ref object
    children:      Table[string, SubagentRuntime]
    counter:       int
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

proc cleanupPaddock(mgr: SubagentManager; rt: SubagentRuntime) =
  if rt.paddockDir.len == 0 or mgr.workspace.remove == nil:
    return
  let removed = mgr.workspace.remove(rt.paddockDir)
  if removed.isErr:
    rt.parent.log.warn("subagent paddock cleanup failed id=" & rt.id &
                       " path=" & rt.paddockDir & " error=" & removed.error)

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
    cleanupPaddock(mgr, rt)
    pushAgentEvent(AgentEvent(
      kind: aekSessionEnd,
      userId: $rt.parent.uid,
      channel: $rt.parent.channel,
      summary: "subagent " & rt.id & " " & $rt.status,
    ))
    pruneChildren(mgr)

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
    maxConcurrent: max(1, maxConcurrent),
    workspace: workspace,
  )

proc spawn*(mgr: SubagentManager; parent: NativeCtx;
            request: SubagentRequest): Future[SubagentSpawnResult] {.async.} =
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
  SubagentSpawnResult(subagentId: id, status: ssRunning)

proc cancelSubagent*(mgr: SubagentManager;
                     subagentId: string): Future[bool] {.gcsafe.}

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
  rt.result

proc cancelSubagent*(mgr: SubagentManager;
                     subagentId: string): Future[bool] {.async, gcsafe.} =
  if subagentId notin mgr.children:
    return false
  let rt = mgr.children[subagentId]
  if rt.status notin {ssQueued, ssRunning}:
    return true
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
  cleanupPaddock(mgr, rt)
  true

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
  if mgr == nil:
    return
  mgr.closed = true
  var ids: seq[string]
  for id in mgr.children.keys:
    ids.add(id)
  var futures: seq[Future[void]]
  for id in ids:
    if id notin mgr.children:
      continue
    let rt = mgr.children[id]
    if rt.status in {ssQueued, ssRunning}:
      discard await mgr.cancelSubagent(id)
    if not rt.future.isNil and not rt.future.finished():
      futures.add(rt.future)
  for fut in futures:
    if not fut.finished():
      let finished = await withTimeout(fut, milliseconds(2_000))
      if not finished:
        fut.cancelSoon()
  ## Final sweep: a future stuck in a synchronous provider/tool call may not
  ## reach its own cleanup, but shutdown must not leave paddocks behind.
  for id in ids:
    if id notin mgr.children:
      continue
    let rt = mgr.children[id]
    cleanupPaddock(mgr, rt)

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
