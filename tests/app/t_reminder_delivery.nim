## Delivering due reminders through `ReminderPort`: each one goes to the
## outbox, then out of the store; a failed delivery keeps it for the next pass.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/core/log
import donkey/ports/reminders
import donkey/app/reminders as reminder_delivery

type LogCapture = ref object
  entries: seq[LogEntry]

proc newLogCapture(): LogCapture = LogCapture()

proc makeSink(cap: LogCapture): LogSink =
  proc(entry: LogEntry) {.gcsafe, closure.} = cap.entries.add entry

type Store = ref object
  items: seq[Reminder]
  removed: seq[string]
  failRemove: bool

proc port(s: Store): ReminderPort =
  ReminderPort(
    due: proc(now: int64): Result[seq[Reminder], string] {.gcsafe, raises: [].} =
      var res: seq[Reminder]
      for r in s.items:
        if r.scheduledAt <= now: res.add r
      ok(res),
    remove: proc(userId: UserId; id: string): Result[void, string] {.gcsafe, raises: [].} =
      if s.failRemove: return err("disk full")
      s.removed.add id
      ok())

func reminderAt(id: string; at: int64): Reminder =
  Reminder(id: id, userId: UserId("u-" & id), channel: "ckTelegram",
           scheduledAt: at, message: "msg " & id)

proc runTests*() =
  suite "reminder delivery":
    test "a due reminder is delivered and removed; a future one stays":
      let store = Store(items: @[reminderAt("a", 90), reminderAt("b", 200)])
      var sent: seq[Reminder]
      let delivered = deliverDueReminders(store.port, 100,
        proc(r: Reminder): Result[void, string] {.gcsafe, raises: [].} =
          sent.add r
          ok())
      check delivered == 1
      check sent.len == 1
      check sent[0].message == "msg a"
      check store.removed == @["a"]

    test "a reminder the outbox refused is kept for the next pass":
      let cap = newLogCapture()
      let store = Store(items: @[reminderAt("a", 1)])
      let delivered = deliverDueReminders(store.port, 100,
        proc(r: Reminder): Result[void, string] {.gcsafe, raises: [].} =
          err("outbox closed"),
        newLogger("t", lvlDebug, makeSink(cap)))
      check delivered == 0
      check store.removed.len == 0
      check cap.entries.len == 1
      check "outbox closed" in cap.entries[0].message

    test "a reminder that could not be removed is logged":
      let cap = newLogCapture()
      let store = Store(items: @[reminderAt("a", 1)], failRemove: true)
      let delivered = deliverDueReminders(store.port, 100,
        proc(r: Reminder): Result[void, string] {.gcsafe, raises: [].} = ok(),
        newLogger("t", lvlDebug, makeSink(cap)))
      check delivered == 1
      check cap.entries.len == 1
      check "disk full" in cap.entries[0].message

    test "the message names the reminder and keeps its channel":
      let msg = reminderMessage(Reminder(userId: UserId("u1"), channel: "ckDiscord",
                                         message: "standup"))
      check msg.userId == UserId("u1")
      check msg.channel == ckDiscord
      check msg.text == "⏰ standup"
      check reminderMessage(Reminder(channel: "ckNowhere")).channel == ckTelegram

    test "a port without a store delivers nothing":
      check deliverDueReminders(ReminderPort(), 100,
        proc(r: Reminder): Result[void, string] {.gcsafe, raises: [].} = ok()) == 0

when isMainModule:
  runTests()
