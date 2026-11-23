## user_schedule_pure.nim — the schedules a user makes from chat, the pure part.
##
## The operator's schedules (`ctl schedule add`) take any id and any spacing.
## A user's own, made through the `manage_schedules` tool, live in the same
## store under the id `<userId>:<name>`, so two users can both have a `daily`
## and one cannot reach the other's. Each firing is a full agent turn, so a
## user may keep at most `MaxUserSchedules` and none may fire more often than
## every `MinUserScheduleGapMs`.

import std/[options, strutils]
import ../../core/pipeops
import ./schedule_pure
import ./schedule_view

const
  MaxScheduleNameLen* = 32
  MaxUserSchedules* = 20
  MinUserScheduleGapMs* = 5 * MinuteMs

func validScheduleName*(name: string): bool =
  name.len in 1 .. MaxScheduleNameLen and
    name.allCharsInSet({'a' .. 'z', '0' .. '9', '-'})

func userScheduleId*(userId, name: string): string =
  userId & ":" & name

func scheduleNameOf*(id: string): string =
  ## The name part of a user's schedule id; an operator's id as it is.
  let colon = id.rfind(':')
  if colon < 0: id else: id[colon + 1 .. ^1]

func ownsSchedule*(spec: ScheduleSpec; userId: string): bool =
  spec.userId == userId

func firesMoreOftenThan*(spec: ScheduleSpec; nowMs, gapMs: int64): bool =
  let gap = closestGapMs(spec, nowMs, gapMs)
  gap.isSome and gap.get() < gapMs

func checkNewUserSchedule*(spec: ScheduleSpec; existingCount: int;
                           nowMs: int64): Result[void, string] =
  ? validateScheduleSpec(spec)
  if existingCount >= MaxUserSchedules:
    return err("you already have " & $MaxUserSchedules &
      " schedules, the most one user may keep; delete one first")
  if firesMoreOftenThan(spec, nowMs, MinUserScheduleGapMs):
    return err("a schedule may fire at most every " &
      $(MinUserScheduleGapMs div MinuteMs) & " minutes")
  ok()

func isInterval(spec: ScheduleSpec): bool =
  let trigger = parseTrigger(spec.cronExpr)
  trigger.isOk and trigger.get().kind == tkInterval

func formatUserSchedules*(rows: seq[ScheduleViewRecord]; nowMs: int64): string =
  ## What the model reads back from `action=list`. Instants are UTC; the
  ## model converts them for the user.
  if rows.len == 0:
    return "No schedules yet. Make one with manage_schedules " &
      "(action=create, name, schedule, prompt)."
  var lines = @["Scheduled jobs (times in UTC):"]
  for r in rows:
    var line = "- " & scheduleNameOf(r.spec.id) & ": " & r.spec.cronExpr
    if not isInterval(r.spec):
      line.add(" (" & formatTzOffset(r.spec.tzOffsetMinutes) & ")")
    if not r.spec.enabled:
      line.add(", paused")
    else:
      let next = nextRunAfterMs(r.spec, nowMs)
      if next.isSome:
        line.add(", next " & formatInstant(next.get()))
    if r.lastFireAtMs > 0:
      line.add(", last " & formatInstant(r.lastFireAtMs) &
               (if r.lastStatus.len > 0: " " & r.lastStatus else: ""))
    if r.lastError.len > 0:
      line.add(" (" & r.lastError & ")")
    if r.missed > 0:
      line.add(", missed " & $r.missed & " (last noticed " &
               formatInstant(r.lastMissedAtMs) & ")")
    line.add("\n  prompt: " & r.spec.payload.replace("\n", " "))
    lines.add(line)
  lines.join("\n")
