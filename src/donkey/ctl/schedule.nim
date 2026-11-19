## ctl/schedule.nim — `donkey ctl schedule` handlers and helpers.
##
## `schedule list/show` are read-only and work with the daemon stopped: they
## open `{home}/state/schedules.json` through the same store the daemon uses.
##
## The handlers below return the rendered stdout text as the `Result` value
## (instead of echoing it) so the output is testable without capturing stdout;
## `dispatchSchedule` is the only caller and prints it. That is a deliberate
## small deviation from the `Result[void, string]` + echo convention used by
## the older ctl groups.

import std/[options, strutils]
import ../core/pipeops
import ../domain/automation/schedule_pure
import ../domain/automation/schedule_view
import ../adapters/state/schedule_store

# ── ctl schedule commands ──────────────────────────────────────────────────────

const
  ScheduleDefaultChannel* = "telegram"
  ScheduleDefaultTz* = "UTC+00:00"
  ScheduleDefaultCatchUp* = "skip"

proc scheduleNow(nowMs: int64): int64 =
  ## `-1` means "use the wall clock"; tests always inject an instant.
  if nowMs >= 0: nowMs else: epochMs()

func scheduleViewOf(record: ScheduleRecord): ScheduleViewRecord =
  ## Adapter row → pure view projection. `last_status`/`last_error`/`failures`
  ## stay empty: this store slice does not persist them, and the view never
  ## invents a status.
  ScheduleViewRecord(
    spec: record.spec,
    lastRunAtMs: record.lastRunAtMs,
    lastFireAtMs: record.lastFireAtMs,
  )

func parseCatchUpArg(raw: string): Result[ScheduleCatchUp, string] =
  case raw.strip().toLowerAscii()
  of "", "skip": ok(scSkip)
  of "once": ok(scOnce)
  else:
    err("invalid catch-up policy '" & raw & "': expected skip or once")

proc ctlScheduleList*(stateDir: string; asJson = false;
                      nowMs = -1'i64): Result[string, string] =
  ## `list`: every schedule, never the payload. Empty store prints
  ## `No schedules.` (human) or `[]` (`--json`) and is a success.
  let loaded = newScheduleStoreRef(stateDir).loadAllRecords()
  if loaded.isErr:
    return err(loaded.error)
  var rows: seq[ScheduleViewRecord]
  for record in loaded.get():
    rows.add scheduleViewOf(record)
  let at = scheduleNow(nowMs)
  if asJson:
    return ok(formatScheduleJson(rows, at))
  ok(schedulePanelLines(rows, at).join("\n"))

proc ctlScheduleShow*(stateDir, scheduleId: string; asJson = false;
                      nowMs = -1'i64): Result[string, string] =
  ## `show <id>`: detail for one schedule, including the payload. Unknown id
  ## is an error (the caller exits non-zero).
  let loaded = newScheduleStoreRef(stateDir).loadRecord(scheduleId)
  if loaded.isErr:
    return err(loaded.error)
  if loaded.get().isNone:
    return err("schedule not found: " & scheduleId)
  let record = loaded.get().get()
  let row = scheduleViewOf(record)
  let at = scheduleNow(nowMs)
  if asJson:
    return ok(formatScheduleObjectJson(row, at))
  var lines = scheduleDetailLines(row, at)
  if record.loadWarning.len > 0:
    lines.insert("warning: " & record.loadWarning, 0)
  ok(lines.join("\n"))

proc ctlScheduleAdd*(stateDir, scheduleId, cronExpr, userId, payload: string;
                     nowMs: int64; channel = ScheduleDefaultChannel;
                     tz = ScheduleDefaultTz;
                     catchUp = ScheduleDefaultCatchUp): Result[string, string] =
  ## `add <id> ...`: validate, refuse a duplicate id before touching the file,
  ## then persist `createdAtMs = now`, `lastRunAtMs = createdAtMs` (creation
  ## never fires) and `lastFireAtMs = 0`.
  let id = scheduleId.strip()
  let offset = parseTzOffset(tz)
  if offset.isErr:
    return err(offset.error)
  let policy = parseCatchUpArg(catchUp)
  if policy.isErr:
    return err(policy.error)

  let spec = ScheduleSpec(
    id: id,
    cronExpr: cronExpr,
    tzOffsetMinutes: offset.get(),
    userId: userId,
    channel: channel,
    payload: payload,
    catchUp: policy.get(),
    enabled: true,
    createdAtMs: nowMs,
  )
  let valid = validateScheduleSpec(spec)
  if valid.isErr:
    return err(valid.error)

  let store = newScheduleStoreRef(stateDir)
  let record = ScheduleRecord(
    spec: spec,
    lastRunAtMs: spec.createdAtMs,
    lastFireAtMs: 0,
  )
  ## Check-and-insert in one store transaction: `loadRecord` + `upsert` in two
  ## lock acquisitions let two concurrent `add`s both pass the duplicate check.
  let inserted = store.insertIfAbsent(record)
  if inserted.isErr:
    return err(inserted.error)
  if not inserted.get():
    return err("schedule '" & spec.id & "' already exists; remove it first " &
               "with `donkey ctl schedule remove " & spec.id & "`")
  ok("Added schedule '" & spec.id & "' (" & spec.cronExpr & ", " &
     formatTzOffset(spec.tzOffsetMinutes) & ", " & spec.channel & ")")

proc ctlScheduleRemove*(stateDir, scheduleId: string
                       ): Result[string, string] =
  ## `remove <id>`: unknown id is an error.
  let store = newScheduleStoreRef(stateDir)
  let existing = store.loadRecord(scheduleId)
  if existing.isErr:
    return err(existing.error)
  if existing.get().isNone:
    return err("schedule not found: " & scheduleId)
  let removed = store.remove(scheduleId)
  if removed.isErr:
    return err(removed.error)
  ok("Removed schedule '" & scheduleId & "'.")

proc ctlScheduleSetEnabled*(stateDir, scheduleId: string; enabled: bool;
                            nowMs = -1'i64): Result[string, string] =
  ## `enable`/`disable <id>`: one store transaction flips `spec.enabled`.
  ##
  ## A real re-enable (disabled → enabled) also writes `lastRunAtMs = now`:
  ## if the daemon was stopped for the whole disabled period, no tick advanced
  ## the watermark, and the first tick after enabling would catch up on that
  ## window. `lastFireAtMs` is historical and stays untouched. Unknown id is
  ## an error.
  let toggled = newScheduleStoreRef(stateDir).setEnabled(
    scheduleId, enabled, scheduleNow(nowMs))
  if toggled.isErr:
    return err(toggled.error)
  if not toggled.get():
    return err("schedule not found: " & scheduleId)
  ok((if enabled: "Enabled schedule '" else: "Disabled schedule '") &
     scheduleId & "'.")

proc scheduleFlagValue*(args: seq[string]; name: string): Option[string] =
  var i = 0
  while i < args.len:
    if args[i] == name:
      if i + 1 < args.len:
        return some(args[i + 1])
      return none(string)
    if args[i].startsWith(name & "="):
      return some(args[i][name.len + 1 .. ^1])
    inc i
  none(string)

const ScheduleValueFlags = ["--cron", "--user", "--payload", "--channel",
                            "--tz", "--catchup", "--catch-up"]

func scheduleAddId*(raw: openArray[string]; fallback: seq[string]): string =
  ## The schedule id is the first positional after `add`. `main()` parses with
  ## `std/parseopt`, whose `cmdArgument` also yields the *value* of a long
  ## option, so `args[3]` can be the cron expression when flags come first —
  ## and `add --cron "0 9 * * *" ... daily` would create a schedule whose id is
  ## the cron. Walk the raw argv instead, skipping flags and their values.
  var i = 0
  while i < raw.len and raw[i] != "add":
    inc i
  if i >= raw.len:
    if fallback.len >= 4 and not fallback[3].startsWith("--"):
      return fallback[3]
    return ""
  inc i
  while i < raw.len:
    let token = raw[i]
    if token.startsWith("--"):
      inc i
      if '=' notin token and token in ScheduleValueFlags and i < raw.len:
        inc i
      continue
    return token
  ""

func scheduleHasFlag*(args: seq[string]; name: string): bool =
  for arg in args:
    if arg == name:
      return true
  false

proc scheduleUsage*() =
  echo "Usage: donkey ctl schedule <list|show|add|remove|enable|disable> [args]"
  echo ""
  echo "  list [--json]"
  echo "  show <id> [--json]"
  echo "  add <id> --cron <expr> --user <id> --payload <text>"
  echo "           [--channel " & ScheduleDefaultChannel & "] [--tz UTC+00:00] [--catchup skip|once]"
  echo "  remove <id>"
  echo "  enable <id>"
  echo "  disable <id>"
