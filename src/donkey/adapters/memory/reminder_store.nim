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

proc readText(path: string): Result[string, string] {.raises: [].} =
  try: ok(readFile(path))
  except CatchableError as e: err(e.msg)

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

proc reminderAt(path: string; owner: UserId): Result[Reminder, string] {.raises: [].} =
  ## The reminder in `path`, which must belong to the paddock it sits in and
  ## carry its file's name as id. The paddock is the user's own workspace and
  ## the file tools write there: a reminder naming another user would message
  ## them, and one whose id is not its file would never be removed.
  let reminder = ? parseReminder(? readText(path))
  if reminder.userId != owner:
    return err("belongs to " & $reminder.userId & ", not to the paddock owner")
  if reminder.id != path.splitFile.name:
    return err("id " & reminder.id & " is not the file name")
  ok(reminder)

proc due*(s: ReminderStore; now: int64): Result[seq[Reminder], string]
         {.raises: [].} =
  ## A file that cannot be read or does not hold a valid reminder is logged
  ## and skipped; only a paddocks directory that cannot be listed is an error.
  var found: seq[Reminder]
  try:
    if not dirExists(s.paddocksDir):
      return ok(found)
    for kind, paddock in walkDir(s.paddocksDir):
      if kind != pcDir: continue
      let owner = UserId(paddock.extractFilename)
      let dir = paddock / "reminders"
      if not dirExists(dir): continue
      for _, path in walkDir(dir):
        if not path.endsWith(".json"): continue
        let reminder = reminderAt(path, owner)
        if reminder.isErr:
          stderr.writeLine("WARN reminder: skipping " & path &
                           " reason=" & reminder.error)
          continue
        if reminder.get.scheduledAt <= now:
          found.add reminder.get
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
