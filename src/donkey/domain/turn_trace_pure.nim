## turn_trace_pure — one line per agent turn, for export.
##
## The metrics (app/metrics) are totals; a trace is one turn's account: when,
## how long, whose (the internal user id), which channel and kind, which
## provider, whether it streamed, each tool call with its outcome, tokens,
## and how it ended. Never what was said: no message, tool input or output.
## The daemon appends the lines to `{home}/state/traces/YYYY-MM-DD.jsonl`
## (UTC days) when DONKEY_TRACES is on; `donkey ctl traces` exports them.
##
## `proc` where JSON is built or parsed (ADR-007 allows it).

import std/[json, strutils, tables]
import ./message

type
  ToolCallTrace* = object
    name*:    string
    outcome*: string   ## output, usage_error, operational_error, … or "none"

  TurnTrace* = object
    startedMs*:     int64
    durationMs*:    int64
    userId*:        string
    channel*:       string
    kind*:          string   ## user, schedule, heartbeat, …
    sessionId*:     string
    provider*:      string   ## the session's provider label
    agentProvider*: string   ## a named agent's own provider, when it had one
    streamed*:      bool
    tools*:         seq[ToolCallTrace]
    inputTokens*:   int
    outputTokens*:  int
    outcome*:       string   ## ok, provider_error, stopped

const DayMs = 86_400_000'i64

func statusOf(toolResultText: string): string =
  ## The status from a tool result's envelope (`[tool_result … status="…"]`).
  const marker = "status=\""
  let at = toolResultText.find(marker)
  if not toolResultText.startsWith("[tool_result") or at < 0:
    return "output"
  let start = at + marker.len
  let stop = toolResultText.find('"', start)
  if stop < 0: "output" else: toolResultText[start ..< stop]

func toolCallsOfTurn*(added: openArray[ChatMessage]): seq[ToolCallTrace] =
  ## The tool calls among the messages a turn added, in order, each with the
  ## outcome its result reported ("none" when no result came back).
  var outcomes = initTable[string, string]()
  for m in added:
    if m.toolCallId.len > 0:
      outcomes[m.toolCallId] = statusOf(m.text)
  for m in added:
    for call in m.toolCalls:
      result.add ToolCallTrace(name: call.name,
                               outcome: outcomes.getOrDefault(call.id, "none"))

proc traceLine*(t: TurnTrace): string =
  ## One JSON object, one line.
  var tools = newJArray()
  for call in t.tools:
    tools.add(%* {"name": call.name, "outcome": call.outcome})
  var j = %* {
    "ts": t.startedMs, "duration_ms": t.durationMs, "user": t.userId,
    "channel": t.channel, "kind": t.kind, "session": t.sessionId,
    "provider": t.provider, "streamed": t.streamed, "tools": tools,
    "tokens": {"input": t.inputTokens, "output": t.outputTokens},
    "outcome": t.outcome}
  if t.agentProvider.len > 0:
    j["agent_provider"] = %t.agentProvider
  $j

func civilFromDays(z: int64): (int64, int, int) =
  ## Howard Hinnant's days-to-civil, for UTC dates without a clock.
  let z = z + 719_468
  let era = (if z >= 0: z else: z - 146_096) div 146_097
  let doe = z - era * 146_097
  let yoe = (doe - doe div 1460 + doe div 36_524 - doe div 146_096) div 365
  let doy = doe - (365 * yoe + yoe div 4 - yoe div 100)
  let mp = (5 * doy + 2) div 153
  let day = int(doy - (153 * mp + 2) div 5 + 1)
  let month = int(if mp < 10: mp + 3 else: mp - 9)
  let year = yoe + era * 400 + (if month <= 2: 1 else: 0)
  (year, month, day)

func daysFromCivil(y: int64; m, d: int): int64 =
  let y = if m <= 2: y - 1 else: y
  let era = (if y >= 0: y else: y - 399) div 400
  let yoe = y - era * 400
  let mp = (if m > 2: m - 3 else: m + 9)
  let doy = (153 * mp + 2) div 5 + d - 1
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  era * 146_097 + doe - 719_468

func traceFileName*(ms: int64): string =
  ## `YYYY-MM-DD.jsonl` for the UTC day of `ms`.
  let (y, m, d) = civilFromDays(ms div DayMs)
  $y & "-" & ($m).align(2, '0') & "-" & ($d).align(2, '0') & ".jsonl"

func dayOfFileName(name: string): int64 =
  ## The day number of a trace file's name; -1 when it is not one.
  if name.len != "YYYY-MM-DD.jsonl".len or not name.endsWith(".jsonl"):
    return -1
  try:
    let y = parseInt(name[0 .. 3])
    let m = parseInt(name[5 .. 6])
    let d = parseInt(name[8 .. 9])
    if name[4] != '-' or name[7] != '-' or m notin 1 .. 12 or d notin 1 .. 31:
      return -1
    daysFromCivil(y, m, d)
  except ValueError:
    -1

func expiredTraceFiles*(names: openArray[string]; nowMs: int64; days: int): seq[string] =
  ## The trace files outside the last `days` days (today included). Other
  ## files in the directory are left alone.
  let cutoff = nowMs div DayMs - int64(days) + 1
  for name in names:
    let day = dayOfFileName(name)
    if day >= 0 and day < cutoff:
      result.add name

proc traceMatches*(line: string; sinceMs: int64; user: string): bool =
  ## For export: a trace line from `sinceMs` on, of `user` ("" = everyone).
  try:
    let j = parseJson(line)
    j{"ts"}.getBiggestInt(0) >= sinceMs and
      (user.len == 0 or j{"user"}.getStr == user)
  except CatchableError:
    false
