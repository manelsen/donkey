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

import std/[json, options, os, sequtils, strutils, times]
import chronos
import ../core/pipeops
import ../core/cron as core_cron
import ../ports/memory
import ../core/types
import ../domain/memory/commitment_pure

# ── Types ─────────────────────────────────────────────────────────────────────

type
  HeartbeatTask* = proc() {.gcsafe.}

  ReminderOutboxFn* = proc(userId, channel, message: string) {.gcsafe.}

  ## Heartbeat task outbox: enqueues a heartbeat task into a user's session inbox.
  HeartbeatOutboxFn* = proc(userId, channel, taskPayload: string) {.gcsafe.}

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

const
  HeartbeatFileName* = "HEARTBEAT.md"
  HeartbeatStateFile* = "memory/heartbeat-state.json"
  MaxHeartbeatTasksPerUser* = 3
  HeartbeatCooldownMs* = 30 * 60 * 1000  ## 30 minutes between heartbeat dispatches

type
  HeartbeatTaskEntry* = object
    title*:    string
    checked*:  bool

  HeartbeatState* = object
    lastDispatchMs*: int64

func buildHeartbeatPrompt*(entries: seq[HeartbeatTaskEntry]): string =
  result = "Heartbeat automático.\n" &
           "Você tem tarefas pendentes no HEARTBEAT.md deste usuário. " &
           "Execute agora o que for viável com as ferramentas disponíveis. " &
           "Se concluir algo, atualize o HEARTBEAT.md marcando [x]. " &
           "Se não der para concluir tudo, responda com progresso objetivo e próximos passos.\n\n" &
           "Tarefas pendentes:\n"
  for e in entries:
    result &= "- [ ] " & e.title & "\n"

func parseHeartbeatMd*(content: string): seq[HeartbeatTaskEntry] =
  result = @[]
  for line in content.splitLines:
    let trimmed = line.strip()
    if trimmed.len == 0: continue
    let isChecked = trimmed.startsWith("[x]") or trimmed.startsWith("- [x]")
    var title = trimmed
    if title.len > 0 and title[0] in {'-', '*'}:
      title = title[1..^1].strip
    if title.len >= 4 and title[0] == '[' and title[2] == ']' and title[1] in {'x', ' '}:
      title = title[3..^1].strip
    if title.len > 0:
      result.add(HeartbeatTaskEntry(title: title, checked: isChecked))

proc loadHeartbeatState(paddockDir: string): HeartbeatState =
  let path = paddockDir / HeartbeatStateFile
  if fileExists(path):
    try:
      let parsed = parseJson(readFile(path))
      result.lastDispatchMs = parsed{"last_dispatch_ms"}.getBiggestInt(0)
    except CatchableError:
      discard

proc saveHeartbeatState(paddockDir: string; state: HeartbeatState) =
  try:
    createDir(paddockDir / "memory")
    writeFile(paddockDir / HeartbeatStateFile, $ %*{
      "last_dispatch_ms": state.lastDispatchMs,
    })
  except CatchableError:
    discard

proc deliverHeartbeats*(paddocksDir: string;
                        outboxFn: HeartbeatOutboxFn) =
  ## Scans all paddock directories for HEARTBEAT.md, selects unchecked tasks,
  ## and dispatches them as heartbeat task messages via outboxFn.
  if paddocksDir.len == 0 or not dirExists(paddocksDir):
    return
  let nowMs = nowMs()
  for kind, dir in walkDir(paddocksDir):
    if kind != pcDir: continue
    let hbPath = dir / HeartbeatFileName
    if not fileExists(hbPath): continue
    let userId = extractFilename(dir)
    let state = loadHeartbeatState(dir)
    if nowMs - state.lastDispatchMs < HeartbeatCooldownMs:
      continue
    let content = try: readFile(hbPath) except CatchableError: ""
    let entries = parseHeartbeatMd(content)
    let unchecked = entries.filterIt(not it.checked)
    if unchecked.len == 0: continue
    let selected = unchecked[0 ..< min(unchecked.len, MaxHeartbeatTasksPerUser)]
    outboxFn(userId, "telegram", buildHeartbeatPrompt(selected))
    var newState = state
    newState.lastDispatchMs = nowMs
    saveHeartbeatState(dir, newState)

# ── Async timer loop ──────────────────────────────────────────────────────────

proc millisUntilNextRun*(expr: core_cron.CronExpr;
                         current: DateTime): int64 {.gcsafe, raises: [].} =
  let nextDt = core_cron.nextRun(expr, current)
  let delta = nextDt.toTime - current.toTime
  max(0'i64, delta.inMilliseconds)

proc heartbeatLoop(reg: HeartbeatRegistry;
                   intervalMs: int) {.async: (raises: []).} =
  while true:
    try:
      await sleepAsync(chronos.milliseconds(intervalMs))
      reg.runAllTasks()
    except CancelledError:
      break
    except Exception:
      discard

proc heartbeatCronLoop(reg: HeartbeatRegistry;
                       expr: core_cron.CronExpr) {.async: (raises: []).} =
  while true:
    try:
      let waitMs = millisUntilNextRun(expr, now())
      await sleepAsync(chronos.milliseconds(waitMs.int))
      reg.runAllTasks()
    except CancelledError:
      break
    except Exception:
      discard

proc startHeartbeat*(reg: HeartbeatRegistry; intervalSec = 60) =
  ## Launches the heartbeat loop inside the Chronos event loop.
  ## Must be called after the Chronos event loop is running (i.e. inside waitFor).
  asyncSpawn heartbeatLoop(reg, intervalSec * 1000)

proc startHeartbeatCron*(reg: HeartbeatRegistry;
                         expr: string): Result[void, string] =
  let parsed = core_cron.parseCronExpr(expr).valueOr:
    return err(error)
  asyncSpawn heartbeatCronLoop(reg, parsed)
  ok()
