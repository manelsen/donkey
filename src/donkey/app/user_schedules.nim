## user_schedules.nim — the `manage_schedules` tool: a user's own recurring
## jobs, through the schedule port.
##
## Rules (id, cap, spacing) are in `domain/automation/user_schedule_pure`;
## this module only reads and writes the store and checks ownership: a user
## sees and touches only the schedules whose `userId` is theirs.

import std/[algorithm, options, strutils]
import ../core/pipeops
import ../core/tooling/native_tool_args
import ../domain/automation/user_schedule_pure
import ../ports/schedules

const SchedulesUnavailable* =
  "Error: scheduled jobs are not available on this server."

proc ownedRows(port: SchedulePort; userId: string): Result[seq[ScheduleViewRecord], string] =
  var rows: seq[ScheduleViewRecord]
  for row in ? port.all():
    if ownsSchedule(row.spec, userId):
      rows.add(row)
  rows.sort(proc(a, b: ScheduleViewRecord): int = cmp(a.spec.id, b.spec.id))
  ok(rows)

proc ownedRow(port: SchedulePort; userId, name: string): Result[ScheduleViewRecord, string] =
  let id = userScheduleId(userId, name)
  for row in ? ownedRows(port, userId):
    if row.spec.id == id:
      return ok(row)
  err("Error: no schedule named '" & name & "'")

func catchUpOf(raw: string): Result[ScheduleCatchUp, string] =
  case raw.strip.toLowerAscii
  of "", "skip": ok(scSkip)
  of "once": ok(scOnce)
  else: err("Error: catch_up must be skip or once")

proc performManageSchedules*(port: SchedulePort; userId, channel: string;
                             ctx: ManageSchedulesContext;
                             nowMs: int64): Result[string, string] =
  if not port.schedulesAvailable:
    return err(SchedulesUnavailable)
  case ctx.action
  of "list":
    let rows = ? ownedRows(port, userId)
    return ok(formatUserSchedules(rows, nowMs))
  of "create":
    if not validScheduleName(ctx.name):
      return err("Error: a job name is 1-32 of a-z, 0-9 and '-'")
    let tz = (if ctx.timezone.strip.len == 0: "UTC+00:00" else: ctx.timezone)
    let offset = parseTzOffset(tz).valueOr:
      return err("Error: " & error)
    let spec = ScheduleSpec(
      id: userScheduleId(userId, ctx.name), cronExpr: ctx.schedule.strip,
      tzOffsetMinutes: offset, userId: userId, channel: channel,
      payload: ctx.prompt.strip, catchUp: ? catchUpOf(ctx.catchUp),
      enabled: true, createdAtMs: nowMs)
    let owned = ? ownedRows(port, userId)
    checkNewUserSchedule(spec, owned.len, nowMs).isOkOr:
      return err("Error: " & error)
    if not ? port.insert(spec):
      return err("Error: a job named '" & ctx.name &
                 "' already exists; delete it first")
    let next = nextRunAfterMs(spec, nowMs)
    return ok("Scheduled '" & ctx.name & "' (" & spec.cronExpr & "). " &
              (if next.isSome: "First run " & formatInstant(next.get()) & ". "
               else: "") &
              "At each run the prompt comes to you as a task in this channel.")
  of "delete":
    let row = ? ownedRow(port, userId, ctx.name)
    ? port.remove(row.spec.id)
    return ok("Deleted '" & ctx.name & "'.")
  of "pause", "resume":
    let row = ? ownedRow(port, userId, ctx.name)
    let enable = ctx.action == "resume"
    if not ? port.setEnabled(row.spec.id, enable, nowMs):
      return err("Error: no schedule named '" & ctx.name & "'")
    return ok((if enable: "Resumed '" else: "Paused '") & ctx.name & "'.")
  else:
    err("Error: unknown action " & ctx.action)
