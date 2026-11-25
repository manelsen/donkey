## subagent_pure — pure policy, budgets and result shapes for subagents.
##
## No filesystem, ports, chronos or adapters here. The runtime creates and
## tears down children; this module decides what a child may do and whether it
## still has budget. Default policy is intentionally read-only.

import std/[json, strutils]
import ../core/pipeops

type
  SubagentStatus* = enum
    ssQueued    = "queued"
    ssRunning   = "running"
    ssCompleted = "completed"
    ssFailed    = "failed"
    ssCancelled = "cancelled"
    ssTimedOut  = "timed_out"

  SubagentLimits* = object
    maxToolCalls*:  int
    maxTokens*:     int
    maxDurationMs*: int64

  SubagentUsage* = ref object
    toolCalls*:      int
    inputTokens*:    int
    outputTokens*:   int
    startedAtMs*:     int64  ## wall-clock creation time (display)
    startedAtMonoMs*: int64  ## monotonic start time (elapsed-budget logic)
    lastActivityMs*:  int64  ## wall-clock last activity (display)
    cancelled*:      bool
    budgetError*:    string

  SubagentRequest* = object
    task*:    string
    context*: string
    tools*:   seq[string]
    limits*:  SubagentLimits

  SubagentToolSelection* = object
    tools*:   seq[string]
    denied*:  seq[string]
    unknown*: seq[string]
    error*:   string

  SubagentResult* = object
    subagentId*:   string
    status*:       SubagentStatus
    text*:         string
    error*:        string
    toolCalls*:    int
    inputTokens*:  int
    outputTokens*: int
    durationMs*:   int64
    costUsd*:      float
    hasCost*:      bool

  SubagentSpawnResult* = object
    subagentId*: string
    status*:     SubagentStatus
    error*:      string

  SubagentInfo* = object
    subagentId*:    string
    status*:        SubagentStatus
    createdAtMs*:   int64
    lastActivityMs*: int64
    usage*:         SubagentUsage

  BudgetDecision* = enum
    bdOk
    bdCancelled
    bdToolCallsExceeded
    bdTokensExceeded
    bdTimeExceeded

  ## One child of a fan-out. The shape mirrors `SubagentRequest`; the plan
  ## keeps the effective (clamped) limits so the runtime spawns what was
  ## validated here, before any workspace exists.
  FanoutRequest* = object
    task*:    string
    context*: string
    tools*:   seq[string]
    limits*:  SubagentLimits

  FanoutTask* = FanoutRequest

  FanoutLimits* = object
    maxChildren*:            int
    maxAggregateTokens*:     int
    maxAggregateDurationMs*: int64

  FanoutPlan* = object
    tasks*:         seq[FanoutRequest]  ## deterministic: input order
    limits*:        FanoutLimits        ## normalized (maxChildren filled in)
    plannedTokens*: int                 ## sum of clamped per-child maxTokens

  FanoutOutcome* = object
    index*:              int
    subagentId*:         string
    status*:             SubagentStatus
    text*:               string
    error*:              string
    usage*:              SubagentUsage
    cancelledBySibling*: bool
    durationMs*:         int64

  FanoutChildOutcome* = FanoutOutcome

  FanoutPolicy* = enum
    fpFailFast
    fpCollectAll

  FanoutStopReason* = enum
    fsrNone
    fsrSpawnFailed
    fsrChildFailed
    fsrChildTimedOut
    fsrSessionStop
    fsrAggregateBudget

  FanoutSignal* = object
    spawnFailed*:    bool
    stopRequested*:  bool
    budgetExceeded*: bool

  FanoutAggregate* = object
    fanoutId*:        string
    policy*:          FanoutPolicy
    children*:        seq[FanoutOutcome]  ## ordered by plan index
    stopReason*:      FanoutStopReason
    ok*:              int
    failed*:          int
    timedOut*:        int
    cancelled*:       int
    totalTokens*:     int
    totalDurationMs*: int64

const
  SubagentDefaultMaxToolCalls*  = 24
  SubagentMinToolCalls*         = 1
  SubagentMaxToolCalls*         = 100
  SubagentDefaultMaxTokens*     = 32_000
  SubagentMinTokens*            = 1_000
  SubagentMaxTokens*            = 128_000
  SubagentDefaultMaxDurationMs* = 120_000'i64
  SubagentMinDurationMs*        = 1_000'i64
  SubagentMaxDurationMs*        = 600_000'i64

  SubagentMaxTaskChars*    = 8_000
  SubagentMaxContextChars* = 32_000
  SubagentMaxRequestedTools* = 32

  ## Fan-out ceilings. `FanoutAbsoluteMaxAggregateTokens` refuses absurd plans
  ## up front; `FanoutLimits.maxAggregateTokens` is the runtime ceiling that
  ## cancels a fan-out when real usage exceeds it. They are distinct knobs.
  FanoutMaxChildren* = 8
  FanoutAbsoluteMaxAggregateTokens* = 512_000
  FanoutDefaultAggregateTokens* = 256_000
  FanoutDefaultAggregateDurationMs* = 120_000'i64

  ## Read-only defaults. The runtime intersects this list with the tools the
  ## parent actually has, so a minimal parent does not advertise ghosts.
  SubagentReadTools* = [
    "read_file",
    "fs_list",
    "fs_read",
    "text_search",
    "text_read",
    "json_query",
    "table_query",
    "session_search",
    "calc",
    "current_time",
  ]

  ## Network reads are allowed only when explicitly requested and present in
  ## the parent; the child inherits the parent's URL/network policy.
  SubagentNetworkReadTools* = [
    "fetch",
    "http_fetch",
    "web_fetch",
    "web_search",
  ]

  ## Never available to a child, even if requested. This is the fail-closed
  ## part of the policy: parent tools cannot be escalated through spawn.
  SubagentHardDeniedTools* = [
    "manage_agents",
    "manage_schedules",
    "manage_tasks",
    "ask_agent",
    "convene_agents",
    "bash",
    "edit_file",
    "fs_write",
    "fs_mkdir",
    "fs_copy",
    "fs_move",
    "fs_remove",
    "text_replace",
    "cp",
    "mv",
    "rm",
    "mkdir",
    "archive_extract",
    "archive_create",
    "execute_code",
    "manage_skills",
    "task",
    "await",
    "cancel_job",
    "submit_result",
    "report_finding",
    "ask",
    "spawn_subagent",
    "await_subagent",
    "list_subagents",
    "cancel_subagent",
  ]

func defaultSubagentLimits*(): SubagentLimits =
  SubagentLimits(
    maxToolCalls:  SubagentDefaultMaxToolCalls,
    maxTokens:     SubagentDefaultMaxTokens,
    maxDurationMs: SubagentDefaultMaxDurationMs,
  )

func clampInt(value, fallback, minimum, maximum: int): int =
  if value <= 0:
    fallback
  else:
    min(max(value, minimum), maximum)

func clampSubagentLimits*(limits: SubagentLimits): SubagentLimits =
  result = SubagentLimits(
    maxToolCalls: clampInt(limits.maxToolCalls, SubagentDefaultMaxToolCalls,
                           SubagentMinToolCalls, SubagentMaxToolCalls),
    maxTokens: clampInt(limits.maxTokens, SubagentDefaultMaxTokens,
                        SubagentMinTokens, SubagentMaxTokens),
    maxDurationMs: int64(clampInt(int(limits.maxDurationMs),
                                  int(SubagentDefaultMaxDurationMs),
                                  int(SubagentMinDurationMs),
                                  int(SubagentMaxDurationMs))),
  )

func defaultSubagentTools*(): seq[string] =
  @SubagentReadTools

func subagentToolAllowed*(name: string): bool =
  name in SubagentReadTools or name in SubagentNetworkReadTools

func resolveSubagentTools*(requested: openArray[string]):
                           SubagentToolSelection =
  ## Empty request means the read-only default. Explicit requests may only
  ## narrow or select from the safe union; denied/unknown names fail closed.
  if requested.len == 0:
    return SubagentToolSelection(tools: defaultSubagentTools())
  if requested.len > SubagentMaxRequestedTools:
    return SubagentToolSelection(
      error: "too many requested subagent tools (max " &
             $SubagentMaxRequestedTools & ")")
  for raw in requested:
    let name = raw.strip()
    if name.len == 0:
      continue
    if name in SubagentHardDeniedTools:
      if name notin result.denied:
        result.denied.add(name)
    elif not subagentToolAllowed(name):
      if name notin result.unknown:
        result.unknown.add(name)
    elif name notin result.tools:
      result.tools.add(name)

func spawnDepthError*(parentDepth: int): string =
  if parentDepth != 0:
    "subagents cannot spawn subagents (maximum depth is 1)"
  else:
    ""

func subagentRequestError*(request: SubagentRequest;
                           parentDepth: int): string =
  let depthError = spawnDepthError(parentDepth)
  if depthError.len > 0:
    return depthError
  if request.task.strip().len == 0:
    return "'task' is required"
  if request.task.len > SubagentMaxTaskChars:
    return "task exceeds " & $SubagentMaxTaskChars & " characters"
  if request.context.len > SubagentMaxContextChars:
    return "context exceeds " & $SubagentMaxContextChars & " characters"
  let selection = resolveSubagentTools(request.tools)
  if selection.error.len > 0:
    return selection.error
  if selection.denied.len > 0:
    return "tools not allowed for subagents: " & selection.denied.join(", ")
  if selection.unknown.len > 0:
    return "unknown subagent tools: " & selection.unknown.join(", ")
  if selection.tools.len == 0:
    return "no valid tools requested"
  ""

func totalTokens*(usage: SubagentUsage): int =
  if usage == nil:
    return 0
  usage.inputTokens + usage.outputTokens

func checkBudget*(usage: SubagentUsage; limits: SubagentLimits;
                  nowMs: int64; checkToolCalls = true): BudgetDecision =
  if usage == nil:
    return bdOk
  if usage.cancelled:
    return bdCancelled
  let started = if usage.startedAtMonoMs > 0: usage.startedAtMonoMs
                else: usage.startedAtMs
  if started > 0 and nowMs - started > limits.maxDurationMs:
    return bdTimeExceeded
  if checkToolCalls and usage.toolCalls >= limits.maxToolCalls:
    return bdToolCallsExceeded
  if totalTokens(usage) >= limits.maxTokens:
    return bdTokensExceeded
  bdOk

proc recordToolCall*(usage: SubagentUsage; nowMs: int64) =
  if usage == nil:
    return
  inc usage.toolCalls
  usage.lastActivityMs = nowMs

proc recordTokens*(usage: SubagentUsage; inputTokens, outputTokens: int;
                   nowMs: int64) =
  if usage == nil:
    return
  usage.inputTokens += max(0, inputTokens)
  usage.outputTokens += max(0, outputTokens)
  usage.lastActivityMs = nowMs

func budgetDecisionText*(decision: BudgetDecision): string =
  case decision
  of bdOk: ""
  of bdCancelled: "subagent was cancelled"
  of bdToolCallsExceeded: "subagent tool-call budget exceeded"
  of bdTokensExceeded: "subagent token budget exceeded"
  of bdTimeExceeded: "subagent time budget exceeded"

func toJson*(spawn: SubagentSpawnResult): JsonNode =
  %*{
    "subagent_id": spawn.subagentId,
    "status": $spawn.status,
    "error": spawn.error,
  }

func toJson*(res: SubagentResult): JsonNode =
  result = %*{
    "subagent_id": res.subagentId,
    "status": $res.status,
    "text": res.text,
    "error": res.error,
    "tool_calls": res.toolCalls,
    "input_tokens": res.inputTokens,
    "output_tokens": res.outputTokens,
    "duration_ms": res.durationMs,
  }
  if res.hasCost:
    result["cost_usd"] = %res.costUsd

func toJson*(info: SubagentInfo; nowMs: int64): JsonNode =
  %*{
    "subagent_id": info.subagentId,
    "status": $info.status,
    "age_ms": max(0'i64, nowMs - info.createdAtMs),
    "last_activity_age_ms": max(0'i64, nowMs - info.lastActivityMs),
    "tool_calls": if info.usage == nil: 0 else: info.usage.toolCalls,
    "input_tokens": if info.usage == nil: 0 else: info.usage.inputTokens,
    "output_tokens": if info.usage == nil: 0 else: info.usage.outputTokens,
  }

# Fan-out: pure plan validation, aggregation and policy.
#
# The runtime creates workspaces, futures and cancellations; this module only
# decides whether a set of children may start and what their outcomes mean.

func defaultFanoutLimits*(): FanoutLimits =
  FanoutLimits(
    maxChildren:            FanoutMaxChildren,
    maxAggregateTokens:     FanoutDefaultAggregateTokens,
    maxAggregateDurationMs: FanoutDefaultAggregateDurationMs,
  )

func effectiveMaxChildren(limits: FanoutLimits): int =
  if limits.maxChildren > 0: limits.maxChildren else: FanoutMaxChildren

func len*(plan: FanoutPlan): int =
  plan.tasks.len

func planFanout*(tasks: openArray[FanoutRequest]; limits: FanoutLimits;
                 availableTools: openArray[string]):
                 Result[FanoutPlan, string] =
  ## Fail closed before the runtime creates any child. Shape, tools and the
  ## plan-time token ceiling are checked here; the runtime token ceiling is
  ## enforced later against real usage.
  if tasks.len == 0:
    return err("fanout requires at least 1 task")
  let maxChildren = effectiveMaxChildren(limits)
  if maxChildren > FanoutMaxChildren:
    return err("maxChildren exceeds absolute ceiling: " & $maxChildren &
               " > " & $FanoutMaxChildren)
  if tasks.len > maxChildren:
    return err("fanout supports at most " & $maxChildren & " children")
  if limits.maxAggregateTokens <= 0:
    return err("aggregate token budget must be positive")
  if limits.maxAggregateTokens > FanoutAbsoluteMaxAggregateTokens:
    return err("maxAggregateTokens exceeds absolute ceiling: " &
               $limits.maxAggregateTokens & " > " &
               $FanoutAbsoluteMaxAggregateTokens)
  if limits.maxAggregateDurationMs <= 0:
    return err("maxAggregateDurationMs must be positive")
  if limits.maxAggregateDurationMs > SubagentMaxDurationMs:
    return err("maxAggregateDurationMs exceeds " & $SubagentMaxDurationMs &
               " ms")

  var normalized: seq[FanoutRequest]
  normalized.setLen(tasks.len)
  var plannedTokens = 0
  for i, task in tasks:
    let requestError = subagentRequestError(SubagentRequest(
      task: task.task,
      context: task.context,
      tools: task.tools,
    ), 0)
    if requestError.len > 0:
      return err(requestError)
    for raw in task.tools:
      let name = raw.strip()
      if name.len == 0:
        continue
      if name notin availableTools:
        return err("tool '" & name & "' is not available in this session")
    let effective = clampSubagentLimits(task.limits)
    normalized[i] = FanoutRequest(
      task: task.task,
      context: task.context,
      tools: task.tools,
      limits: effective,
    )
    plannedTokens += effective.maxTokens

  if plannedTokens > FanoutAbsoluteMaxAggregateTokens:
    return err("aggregate token budget exceeded: " & $plannedTokens &
               " > " & $FanoutAbsoluteMaxAggregateTokens)

  ok(FanoutPlan(
    tasks: normalized,
    limits: FanoutLimits(
      maxChildren: maxChildren,
      maxAggregateTokens: limits.maxAggregateTokens,
      maxAggregateDurationMs: limits.maxAggregateDurationMs,
    ),
    plannedTokens: plannedTokens,
  ))

func aggregateFanout*(plan: FanoutPlan; outcomes: openArray[FanoutOutcome];
                      fanoutId: string; policy: FanoutPolicy;
                      signal: FanoutSignal): FanoutAggregate =
  ## Completion order must not matter: children are placed by plan index and
  ## missing indexes become queued placeholders so the sequence always has
  ## `plan.len` entries.
  result.fanoutId = fanoutId
  result.policy = policy
  result.children = newSeq[FanoutOutcome](plan.tasks.len)
  var seen = newSeq[bool](plan.tasks.len)
  for outcome in outcomes:
    if outcome.index >= 0 and outcome.index < result.children.len and
        not seen[outcome.index]:
      result.children[outcome.index] = outcome
      seen[outcome.index] = true
  for i in 0 ..< result.children.len:
    if not seen[i]:
      result.children[i] = FanoutOutcome(index: i, status: ssQueued)

  for child in result.children:
    result.totalTokens += totalTokens(child.usage)
    if child.durationMs > 0:
      result.totalDurationMs += child.durationMs
    case child.status
    of ssCompleted: inc result.ok
    of ssFailed: inc result.failed
    of ssTimedOut: inc result.timedOut
    of ssCancelled: inc result.cancelled
    else: discard

  # Precedence: spawn > stop > budget > first failure by index. A sibling
  # cancellation is never a failure and never becomes the stop reason.
  if signal.spawnFailed:
    result.stopReason = fsrSpawnFailed
  elif signal.stopRequested:
    result.stopReason = fsrSessionStop
  elif signal.budgetExceeded:
    result.stopReason = fsrAggregateBudget
  else:
    result.stopReason = fsrNone
    for child in result.children:
      if child.cancelledBySibling or child.status == ssCancelled:
        continue
      if child.status == ssFailed:
        result.stopReason = fsrChildFailed
        break
      if child.status == ssTimedOut:
        result.stopReason = fsrChildTimedOut
        break

func fanoutShouldCancelSiblings*(agg: FanoutAggregate;
                                 policy: FanoutPolicy): bool =
  ## Only a real failure triggers fail-fast cancellation. `ssCancelled` and
  ## `cancelledBySibling` are results of cancellation, never a reason to
  ## cancel again on every supervisor tick.
  if policy != fpFailFast:
    return false
  for child in agg.children:
    if child.cancelledBySibling or child.status == ssCancelled:
      continue
    if child.status == ssFailed or child.status == ssTimedOut:
      return true
  false

func fanoutBudgetDecision*(totalTokens: int;
                           limits: FanoutLimits): BudgetDecision =
  ## Runtime aggregate ceiling. Zero means the documented default, so a
  ## detached caller that does not configure a budget still has one.
  let ceiling =
    if limits.maxAggregateTokens > 0: limits.maxAggregateTokens
    else: FanoutDefaultAggregateTokens
  if totalTokens >= ceiling: bdTokensExceeded else: bdOk

func fanoutProgressDue*(lastMs, nowMs: int64;
                        intervalMs: int64 = 1_000): bool =
  if intervalMs <= 0:
    return true
  if nowMs < lastMs:
    return false
  nowMs - lastMs >= intervalMs
