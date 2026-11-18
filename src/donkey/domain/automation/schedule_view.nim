## schedule_view — pure rendering of persisted schedules (US-007).
##
## This module is the single source of truth for what an operator sees in
## `donkey ctl schedule list/show` (and, later, the read-only TUI panel). It is
## pure by contract: no clock, no disk, no environment. Callers inject `nowMs`.
##
## `ScheduleViewRecord` is intentionally not the adapter's `ScheduleRecord`:
## `domain/` may not import `adapters/`, so the ctl projects a record into this
## shape. The projection carries `lastRunAtMs` (the scheduler watermark) and
## `lastFireAtMs` (the last actual firing). **`last_run` is `lastFireAtMs`**:
## the watermark advances on every tick, including ticks that fire nothing, so
## showing it would claim a run that never happened. `lastFireAtMs = 0` means
## "never fired".
##
## `next_run` is derived from the cron expression with `nextRunAfterMs` at
## `nowMs`; it is never materialised on disk.
##
## `last_status`, `last_error` and `failures` are optional: the current store
## slice does not persist them, but the view renders them when the caller has
## them (the field names are stable so a future store can fill them in).
##
## Output contract (`list`):
##   - human: `No schedules.` when there is nothing, else a header plus one
##     `formatScheduleRow` line per record;
##   - `--json`: a JSON array with the same field names, and **no payload**.
##
## Output contract (`show`):
##   - human: `scheduleDetailLines`, one `name: value` line per field;
##   - `--json`: a single JSON object with the same field names plus `payload`.
##
## Documented field names (both formats agree):
##   id, cron, tz, user, channel, enabled, catch_up, last_run, next_run,
##   last_status, last_error, failures, created_at_ms, last_run_at_ms,
##   last_fire_at_ms. `payload` is show-only.

import std/[json, options, strutils, times]
import ./schedule_pure

const
  NeverText* = "never"
    ## Printed for `last_run` before the schedule ever fired.
  NoSchedulesText* = "No schedules."
    ## Printed by `list` when the store is empty.
  PanelHeader* = "id  last_run  next_run  enabled  catch_up  last_status"
    ## Documented header of the human list panel.
  InstantFormat* = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    ## Every instant is rendered in UTC so the offset in `tz` stays explicit.

type
  ScheduleViewRecord* = object
    ## Read-only projection of a persisted schedule row.
    spec*: ScheduleSpec
    lastRunAtMs*: int64
      ## Scheduler watermark; diagnostic only, never rendered as `last_run`.
    lastFireAtMs*: int64
      ## Last firing instant, or `0` for "never".
    lastStatus*: string
      ## Optional last run status (`sent`/`failed`/...); empty means unknown.
    lastError*: string
      ## Optional last run error; empty means none.
    failures*: int
      ## Retained failed runs since retention; `0` means none reported.

# ── formatting helpers ───────────────────────────────────────────────────────

func floorDiv(a, b: int64): int64 =
  ## Floor division so pre-1970 instants render consistently.
  if a >= 0:
    a div b
  else:
    -((-a + b - 1) div b)

func formatInstant*(ms: int64): string =
  ## UTC ISO-8601 instant with second precision (`2023-11-14T22:14:00Z`).
  {.cast(noSideEffect).}:
    result = fromUnix(floorDiv(ms, 1_000)).utc.format(InstantFormat)

func formatTzOffset*(offsetMinutes: int): string =
  ## Renders an offset in the persisted `UTC±HH:MM` spelling.
  let magnitude =
    if offsetMinutes < 0: -offsetMinutes else: offsetMinutes
  let sign = if offsetMinutes < 0: "-" else: "+"
  result = "UTC" & sign & align($(magnitude div 60), 2, '0') & ":" &
           align($(magnitude mod 60), 2, '0')

func catchUpName(catchUp: ScheduleCatchUp): string =
  case catchUp
  of scSkip: "skip"
  of scOnce: "once"

func lastRunText(record: ScheduleViewRecord): string =
  ## `last_run` comes from the firing instant, never the watermark.
  if record.lastFireAtMs == 0: NeverText
  else: formatInstant(record.lastFireAtMs)

func nextRunText(record: ScheduleViewRecord; nowMs: int64): string =
  let next = nextRunAfterMs(record.spec, nowMs)
  if next.isNone: "none"
  else: formatInstant(next.get())

func statusText(record: ScheduleViewRecord): string =
  if record.lastStatus.len == 0: "none"
  else: record.lastStatus

func failuresText(record: ScheduleViewRecord): string =
  if record.failures <= 0: ""
  else: "failures=" & $record.failures & " (since retention)"

# ── human output ─────────────────────────────────────────────────────────────

func formatScheduleRow*(record: ScheduleViewRecord; nowMs: int64): string =
  ## One compact `key=value` line for the list panel. The payload is never
  ## included: `list` is a visibility command, not a dump of what will run.
  var parts = @[
    "id=" & record.spec.id,
    "cron=" & record.spec.cronExpr,
    "tz=" & formatTzOffset(record.spec.tzOffsetMinutes),
    "user=" & record.spec.userId,
    "channel=" & record.spec.channel,
    "enabled=" & $record.spec.enabled,
    "catch_up=" & catchUpName(record.spec.catchUp),
    "last_run=" & lastRunText(record),
    "next_run=" & nextRunText(record, nowMs),
    "last_status=" & statusText(record),
  ]
  if record.lastError.len > 0:
    parts.add "last_error=" & record.lastError
  let failures = failuresText(record)
  if failures.len > 0:
    parts.add failures
  parts.join("  ")

func schedulePanelLines*(records: seq[ScheduleViewRecord];
                         nowMs: int64): seq[string] =
  ## The list panel: a header plus one row per record, or a single clear line
  ## when the store is empty.
  if records.len == 0:
    return @[NoSchedulesText]
  result = @[PanelHeader]
  for record in records:
    result.add formatScheduleRow(record, nowMs)

func scheduleDetailLines*(record: ScheduleViewRecord;
                          nowMs: int64): seq[string] =
  ## Multi-line `show` view. Field names match the JSON keys; `payload` is
  ## intentionally part of the detail view (and only here).
  result = @[
    "id: " & record.spec.id,
    "cron: " & record.spec.cronExpr,
    "tz: " & formatTzOffset(record.spec.tzOffsetMinutes),
    "user: " & record.spec.userId,
    "channel: " & record.spec.channel,
    "enabled: " & $record.spec.enabled,
    "catch_up: " & catchUpName(record.spec.catchUp),
    "created_at_ms: " & $record.spec.createdAtMs,
    "last_run_at_ms: " & $record.lastRunAtMs,
    "last_fire_at_ms: " & $record.lastFireAtMs,
    "last_run: " & lastRunText(record),
    "next_run: " & nextRunText(record, nowMs),
    "last_status: " & statusText(record),
  ]
  if record.lastError.len > 0:
    result.add "last_error: " & record.lastError
  if record.failures > 0:
    result.add "failures: " & $record.failures & " (since retention)"
  result.add "payload: " & record.spec.payload

# ── JSON output ──────────────────────────────────────────────────────────────

func scheduleJsonNode*(record: ScheduleViewRecord; nowMs: int64;
                       includePayload = false): JsonNode =
  ## One JSON object using the same field names as the human output. `payload`
  ## is only materialised for `show` (`includePayload = true`).
  result = newJObject()
  result["id"] = %record.spec.id
  result["cron"] = %record.spec.cronExpr
  result["tz"] = %formatTzOffset(record.spec.tzOffsetMinutes)
  result["user"] = %record.spec.userId
  result["channel"] = %record.spec.channel
  result["enabled"] = %record.spec.enabled
  result["catch_up"] = %catchUpName(record.spec.catchUp)
  result["last_run"] = %lastRunText(record)
  result["next_run"] = %nextRunText(record, nowMs)
  result["last_status"] = %statusText(record)
  result["last_error"] = %record.lastError
  result["failures"] = %record.failures
  result["created_at_ms"] = %record.spec.createdAtMs
  result["last_run_at_ms"] = %record.lastRunAtMs
  result["last_fire_at_ms"] = %record.lastFireAtMs
  if includePayload:
    result["payload"] = %record.spec.payload

func formatScheduleJson*(records: seq[ScheduleViewRecord]; nowMs: int64;
                         includePayload = false): string =
  ## `list --json`: a JSON array (an empty store is exactly `[]`).
  var list = newJArray()
  for record in records:
    list.add scheduleJsonNode(record, nowMs, includePayload)
  result = $list

func formatScheduleObjectJson*(record: ScheduleViewRecord; nowMs: int64;
                               includePayload = true): string =
  ## `show --json`: a single JSON object.
  result = $scheduleJsonNode(record, nowMs, includePayload)
