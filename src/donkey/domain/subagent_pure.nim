## subagent_pure — pure policy, budgets and result shapes for subagents.
##
## No filesystem, ports, chronos or adapters here. The runtime creates and
## tears down children; this module decides what a child may do and whether it
## still has budget. Default policy is intentionally read-only.

import std/[json, strutils]
import results

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
                           Result[seq[string], string] =
  ## Empty request means the read-only default. Explicit requests may only
  ## narrow or select from the safe union; denied/unknown names fail closed.
  if requested.len == 0:
    return ok(defaultSubagentTools())
  if requested.len > SubagentMaxRequestedTools:
    return err("too many requested subagent tools (max " &
               $SubagentMaxRequestedTools & ")")
  var selected: seq[string]
  var denied, unknown: seq[string]
  for raw in requested:
    let name = raw.strip()
    if name.len == 0:
      continue
    if name in SubagentHardDeniedTools:
      if name notin denied:
        denied.add(name)
    elif not subagentToolAllowed(name):
      if name notin unknown:
        unknown.add(name)
    elif name notin selected:
      selected.add(name)
  if denied.len > 0:
    return err("tools not allowed for subagents: " & denied.join(", "))
  if unknown.len > 0:
    return err("unknown subagent tools: " & unknown.join(", "))
  if selected.len == 0:
    return err("no valid tools requested")
  ok(selected)

func validateSpawnDepth*(parentDepth: int): Result[void, string] =
  if parentDepth != 0:
    return err("subagents cannot spawn subagents (maximum depth is 1)")
  ok()

func validateSubagentRequest*(request: SubagentRequest;
                              parentDepth: int): Result[void, string] =
  ?validateSpawnDepth(parentDepth)
  if request.task.strip().len == 0:
    return err("'task' is required")
  if request.task.len > SubagentMaxTaskChars:
    return err("task exceeds " & $SubagentMaxTaskChars & " characters")
  if request.context.len > SubagentMaxContextChars:
    return err("context exceeds " & $SubagentMaxContextChars & " characters")
  let tools = ?resolveSubagentTools(request.tools)
  if tools.len == 0:
    return err("no tools available for subagent")
  ok()

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
