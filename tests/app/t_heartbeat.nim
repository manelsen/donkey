## Heartbeat unit tests — pure logic only, no real timers.
## Tests: task registration, tick counting, reminder delivery logic.

import std/[json, os, strutils, times, unittest]
import donkey/app/heartbeat
import donkey/core/types
import donkey/adapters/memory/md_file

suite "heartbeat task registry":

  test "empty task list is valid":
    let reg = newHeartbeatRegistry()
    check reg.taskCount == 0

  test "registerTask increments count":
    var reg = newHeartbeatRegistry()
    reg.registerTask("ping", proc() {.gcsafe.} = discard)
    check reg.taskCount == 1

  test "multiple tasks registered":
    var reg = newHeartbeatRegistry()
    reg.registerTask("a", proc() {.gcsafe.} = discard)
    reg.registerTask("b", proc() {.gcsafe.} = discard)
    check reg.taskCount == 2

  test "runAllTasks calls each registered task":
    var called: seq[string] = @[]
    var reg = newHeartbeatRegistry()
    reg.registerTask("x", proc() {.gcsafe.} = {.cast(gcsafe).}: called.add("x"))
    reg.registerTask("y", proc() {.gcsafe.} = {.cast(gcsafe).}: called.add("y"))
    reg.runAllTasks()
    check "x" in called
    check "y" in called

suite "heartbeat reminder delivery":

  test "deliverDueReminders calls outbox for each due reminder":
    let tmp = getTempDir() / "donkey_hb_test1"
    defer: removeDir(tmp)
    let mem = MdFileAdapter(paddocksDir: tmp)
    let uid = UserId("user-hb")
    mem.ensurePaddock(uid)
    let past = getTime().toUnix() - 60
    discard mem.scheduleReminder(uid, "ckTelegram", past, "standup!")

    var delivered: seq[string] = @[]
    let outboxFn: ReminderOutboxFn = proc(userId, channel, message: string) {.gcsafe.} =
      {.cast(gcsafe).}: delivered.add(userId & "|" & channel & "|" & message)

    deliverDueReminders(mem.toRuntimePort(), outboxFn)
    check delivered.len == 1
    check "standup!" in delivered[0]
    ## Reminder must be deleted after delivery.
    check mem.loadDueReminders().len == 0

  test "deliverDueReminders skips future reminders":
    let tmp = getTempDir() / "donkey_hb_test2"
    defer: removeDir(tmp)
    let mem = MdFileAdapter(paddocksDir: tmp)
    let uid = UserId("user-hb2")
    mem.ensurePaddock(uid)
    discard mem.scheduleReminder(uid, "ckTelegram", getTime().toUnix() + 3600, "future")

    var delivered: seq[string] = @[]
    let outboxFn: ReminderOutboxFn = proc(userId, channel, message: string) {.gcsafe.} =
      {.cast(gcsafe).}: delivered.add(message)

    deliverDueReminders(mem.toRuntimePort(), outboxFn)
    check delivered.len == 0
