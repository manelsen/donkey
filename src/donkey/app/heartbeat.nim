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

import std/[json, options]
import chronos
import ../ports/memory
import ../core/types
import ../domain/memory/commitment_pure

# ── Types ─────────────────────────────────────────────────────────────────────

type
  HeartbeatTask* = proc() {.gcsafe.}

  ReminderOutboxFn* = proc(userId, channel, message: string) {.gcsafe.}

  CommitmentSnapshot* = object
    userId*:      UserId
    commitment*:  Commitment

  CommitmentReview* = object
    userId*:       UserId
    commitmentId*: string
    status*:       CommitmentStatus
    score*:        float32
    overdue*:      bool
    sourceText*:   string

  CommitmentSnapshotLoader* = proc(): seq[CommitmentSnapshot] {.gcsafe.}
  CommitmentReviewSink* = proc(review: CommitmentReview) {.gcsafe.}
  NowSecFn* = proc(): int64 {.gcsafe.}

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
    except CatchableError: discard

proc reviewCommitments*(snapshots: seq[CommitmentSnapshot];
                        nowSec: int64): seq[CommitmentReview] =
  for snapshot in snapshots:
    let commitment = snapshot.commitment
    result.add(CommitmentReview(
      userId: snapshot.userId,
      commitmentId: commitment.id,
      status: commitment.status,
      score: commitmentScore(commitment, nowSec),
      overdue: commitment.status == csOpen and commitment.dueAt.isSome and
               commitment.dueAt.get() < nowSec,
      sourceText: commitment.sourceText,
    ))

proc runCommitmentReview*(loadSnapshots: CommitmentSnapshotLoader;
                          sink: CommitmentReviewSink;
                          nowSec: int64) =
  if loadSnapshots == nil or sink == nil:
    return
  for review in reviewCommitments(loadSnapshots(), nowSec):
    try: sink(review)
    except CatchableError: discard

proc registerCommitmentReviewTask*(reg: var HeartbeatRegistry;
                                   loadSnapshots: CommitmentSnapshotLoader;
                                   sink: CommitmentReviewSink;
                                   nowSecFn: NowSecFn) =
  reg.registerTask("commitments", proc() {.gcsafe.} =
    runCommitmentReview(
      loadSnapshots,
      sink,
      if nowSecFn != nil: nowSecFn() else: 0'i64,
    )
  )

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
    try: outboxFn(userId, channel, message) except CatchableError: discard
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
