## The reminder store: one JSON file per reminder under the user's paddock,
## behind `ReminderPort`.

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/adapters/memory/reminder_store

const Now = 1_700_000_000'i64

proc freshStore(name: string): ReminderPort =
  let dir = getTempDir() / name
  removeDir(dir)
  newReminderStore(dir).toReminderPort()

proc runTests*() =
  suite "reminder store":
    test "a reminder that is due comes back typed":
      let port = freshStore("donkey_rem_due")
      let id = port.schedule(UserId("user-a"), "ckTelegram", Now - 60, "standup!").get
      check id.len > 0
      let due = port.due(Now).get
      check due.len == 1
      check due[0].id == id
      check due[0].userId == UserId("user-a")
      check due[0].channel == "ckTelegram"
      check due[0].scheduledAt == Now - 60
      check due[0].message == "standup!"

    test "a future reminder is not due yet":
      let port = freshStore("donkey_rem_future")
      discard port.schedule(UserId("user-b"), "ckTelegram", Now + 3_600, "later").get
      check port.due(Now).get.len == 0
      check port.due(Now + 3_600).get.len == 1

    test "two reminders scheduled at once both survive":
      ## The id was the second and the user: the second write replaced the first.
      let port = freshStore("donkey_rem_twice")
      let uid = UserId("user-c")
      let first = port.schedule(uid, "ckTelegram", Now - 1, "one").get
      let second = port.schedule(uid, "ckTelegram", Now - 1, "two").get
      check first != second
      check port.due(Now).get.len == 2

    test "remove takes the reminder out; removing it again is fine":
      let port = freshStore("donkey_rem_remove")
      let uid = UserId("user-d")
      let id = port.schedule(uid, "ckTelegram", Now - 10, "deleteme").get
      check port.remove(uid, id).isOk
      check port.due(Now).get.len == 0
      check port.remove(uid, id).isOk

    test "only the due reminders of every user come back":
      let port = freshStore("donkey_rem_users")
      discard port.schedule(UserId("user-x"), "ckTelegram", Now - 5, "due").get
      discard port.schedule(UserId("user-y"), "ckTelegram", Now + 999, "future").get
      let due = port.due(Now).get
      check due.len == 1
      check due[0].message == "due"

    test "a corrupt file is skipped, not fatal":
      let dir = getTempDir() / "donkey_rem_corrupt"
      removeDir(dir)
      let port = newReminderStore(dir).toReminderPort()
      discard port.schedule(UserId("user-z"), "ckTelegram", Now - 5, "ok").get
      writeFile(dir / "user-z" / "reminders" / "broken.json", "{not json")
      let due = port.due(Now).get
      check due.len == 1
      check due[0].message == "ok"

    test "a reminder naming another user, or not named after its id, is skipped":
      ## A user's file tools write in their own paddock, reminders/ included.
      let dir = getTempDir() / "donkey_rem_forged"
      removeDir(dir)
      let port = newReminderStore(dir).toReminderPort()
      discard port.schedule(UserId("mallory"), "ckTelegram", Now - 5, "mine").get
      let remDir = dir / "mallory" / "reminders"
      writeFile(remDir / "forged.json",
        """{"id":"forged","userId":"alice","channel":"ckTelegram","scheduledAt":1,"message":"hi"}""")
      writeFile(remDir / "renamed.json",
        """{"id":"other","userId":"mallory","channel":"ckTelegram","scheduledAt":1,"message":"again"}""")
      let due = port.due(Now).get
      check due.len == 1
      check due[0].message == "mine"

    when defined(posix):
      test "a file that cannot be read does not stop the others":
        let dir = getTempDir() / "donkey_rem_unreadable"
        removeDir(dir)
        let port = newReminderStore(dir).toReminderPort()
        discard port.schedule(UserId("user-a"), "ckTelegram", Now - 5, "ok").get
        createDir(dir / "user-b" / "reminders" / "dir.json")  ## not a file
        let due = port.due(Now).get
        check due.len == 1
        check due[0].message == "ok"

    test "a reminder id cannot leave the reminders directory":
      let port = freshStore("donkey_rem_escape")
      check port.remove(UserId("user-e"), "../USER").isErr
      check "invalid" in port.remove(UserId("user-e"), "a/b").error

    test "no paddocks directory means nothing is due":
      let port = newReminderStore(getTempDir() / "donkey_rem_none_here").toReminderPort()
      check port.due(Now).get.len == 0

when isMainModule:
  runTests()
