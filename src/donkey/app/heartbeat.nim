## Heartbeat — periodic maintenance runtime.
##
## Runs a set of registered tasks on a fixed interval using Chronos.
## Each task is a fire-and-forget gcsafe proc.
##
## Usage:
##   var reg = newHeartbeatRegistry()
##   reg.registerTask("reminders", myReminderTask)
##   startHeartbeat(reg, intervalSec = 60)
##
## Concrete tasks shipped here:
##   deliverDueReminders — polls MemoryRuntimePort for due reminders, delivers via outbox fn.

import std/[json, strutils]
import chronos
import ../ports/memory
import ../core/types

# ── Types ─────────────────────────────────────────────────────────────────────

type
  HeartbeatTask* = proc() {.gcsafe.}

  ReminderOutboxFn* = proc(userId, channel, message: string) {.gcsafe.}

  HeartbeatEntry = object
    name: string
    task: HeartbeatTask

  HeartbeatRegistry* = object
    entries: seq[HeartbeatEntry]

# ── Registry ──────────────────────────────────────────────────────────────────

func newHeartbeatRegistry*(): HeartbeatRegistry =
  HeartbeatRegistry()

func taskCount*(reg: HeartbeatRegistry): int =
  reg.entries.len

proc registerTask*(reg: var HeartbeatRegistry; name: string; task: HeartbeatTask) =
  reg.entries.add HeartbeatEntry(name: name, task: task)

proc runAllTasks*(reg: HeartbeatRegistry) =
  for e in reg.entries:
    try: e.task()
    except: discard

# ── Concrete task: reminder delivery ─────────────────────────────────────────

proc deliverDueReminders*(memory: MemoryRuntimePort;
                          outboxFn: ReminderOutboxFn) =
  ## Fetches due reminders from memory, delivers them via outboxFn,
  ## and deletes them so they are not delivered twice.
  if memory.loadDueReminders == nil: return
  let due = memory.loadDueReminders()
  for j in due:
    let userId  = j{"userId"}.getStr("")
    let channel = j{"channel"}.getStr("")
    let message = j{"message"}.getStr("")
    let remId   = j{"id"}.getStr("")
    if userId.len == 0 or message.len == 0: continue
    try: outboxFn(userId, channel, message) except: discard
    if remId.len > 0 and memory.deleteReminder != nil:
      memory.deleteReminder(UserId(userId), remId)

# ── Async timer loop ──────────────────────────────────────────────────────────

proc heartbeatLoop(reg: HeartbeatRegistry;
                   intervalMs: int) {.async: (raises: []).} =
  while true:
    try:
      await sleepAsync(intervalMs.milliseconds)
      reg.runAllTasks()
    except CancelledError:
      break
    except Exception:
      discard

proc startHeartbeat*(reg: HeartbeatRegistry; intervalSec = 60) =
  ## Launches the heartbeat loop inside the Chronos event loop.
  ## Must be called after the Chronos event loop is running (i.e. inside waitFor).
  asyncSpawn heartbeatLoop(reg, intervalSec * 1000)
