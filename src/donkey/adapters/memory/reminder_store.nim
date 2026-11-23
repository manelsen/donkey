## ReminderStore — `ReminderPort` on files: one JSON file per reminder in
## `{paddocksDir}/{userId}/reminders/`, private to the service user.

import std/[json, os, strutils, times]
import ../../core/pipeops
import ../../core/types
import ../../ports/reminders
import ../filesystem/paths

export reminders

type
  ReminderStore* = object
    paddocksDir*: string

func newReminderStore*(paddocksDir: string): ReminderStore =
  ReminderStore(paddocksDir: paddocksDir)

func reminderDir*(s: ReminderStore; userId: UserId): string =
  s.paddocksDir / $userId / "reminders"

func validReminderId(id: string): bool =
  ## Ids are generated here, but `remove` builds a path from one.
  id.len > 0 and '/' notin id and '\\' notin id and '\0' notin id and
    not id.startsWith(".")

proc newReminderId(dir: string): string =
  ## Seconds and nanoseconds, then a counter for a clock that did not move.
  let t = getTime()
  let base = $t.toUnix() & "_" & align($t.nanosecond, 9, '0')
  result = base
  var n = 1
  while fileExists(dir / result & ".json"):
    result = base & "_" & $n
    inc n

proc schedule*(s: ReminderStore; userId: UserId; channel: string;
               scheduledAt: int64; message: string): Result[string, string]
              {.raises: [].} =
  try:
    let dir = s.reminderDir(userId)
    ? secureDir(s.paddocksDir / $userId)
    ? secureDir(dir)
    let id = newReminderId(dir)
    let data = %* {
      "id":          id,
      "userId":      $userId,
      "channel":     channel,
      "scheduledAt": scheduledAt,
      "message":     message,
    }
    let path = dir / id & ".json"
    writeFile(path, $data)
    discard secureFile(path)
    ok(id)
  except CatchableError as e:
    err("schedule reminder: " & e.msg)

proc parseReminder(text: string): Result[Reminder, string] {.raises: [].} =
  try:
    let j = parseJson(text)
    let r = Reminder(
      id:          j{"id"}.getStr(""),
      userId:      UserId(j{"userId"}.getStr("")),
      channel:     j{"channel"}.getStr(""),
      scheduledAt: j{"scheduledAt"}.getBiggestInt(high(int64)),
      message:     j{"message"}.getStr(""),
    )
    if r.id.len == 0 or ($r.userId).len == 0:
      return err("no id or user")
    ok(r)
  except CatchableError as e:
    err(e.msg)

proc due*(s: ReminderStore; now: int64): Result[seq[Reminder], string]
         {.raises: [].} =
  var found: seq[Reminder]
  try:
    if not dirExists(s.paddocksDir):
      return ok(found)
    for _, paddock in walkDir(s.paddocksDir):
      let dir = paddock / "reminders"
      if not dirExists(dir): continue
      for _, path in walkDir(dir):
        if not path.endsWith(".json"): continue
        let parsed = parseReminder(readFile(path))
        if parsed.isErr:
          stderr.writeLine("WARN reminder.parse: skipping " & path &
                           " reason=" & parsed.error)
          continue
        if parsed.get.scheduledAt <= now:
          found.add parsed.get
    ok(found)
  except CatchableError as e:
    err("load reminders: " & e.msg)

proc remove*(s: ReminderStore; userId: UserId; id: string): Result[void, string]
            {.raises: [].} =
  if not validReminderId(id):
    return err("invalid reminder id: " & id)
  try:
    let path = s.reminderDir(userId) / id & ".json"
    if fileExists(path): removeFile(path)
    ok()
  except CatchableError as e:
    err("remove reminder: " & e.msg)

proc toReminderPort*(s: ReminderStore): ReminderPort =
  ReminderPort(
    schedule: proc(userId: UserId; channel: string; scheduledAt: int64;
                   message: string): Result[string, string] {.gcsafe, raises: [].} =
      s.schedule(userId, channel, scheduledAt, message),
    due: proc(now: int64): Result[seq[Reminder], string] {.gcsafe, raises: [].} =
      s.due(now),
    remove: proc(userId: UserId; id: string): Result[void, string] {.gcsafe, raises: [].} =
      s.remove(userId, id),
  )
