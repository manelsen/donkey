## Heartbeat unit tests — pure logic only, no real timers.
## Tests: task registration, tick counting, reminder delivery logic.

import std/[os, strutils, times, unittest, options, sequtils]
import donkey/core/pipeops
import donkey/core/log
import donkey/app/heartbeat
import donkey/app/contemplation
import donkey/core/types
import donkey/core/cron
import donkey/adapters/memory/md_file
import donkey/domain/memory/commitment_pure
import donkey/domain/memory/episode_pure

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

  test "runAllTasks logs error when a task fails instead of silently discarding":
    var logEntries: seq[LogEntry] = @[]
    let testSink: LogSink = proc(entry: LogEntry) {.gcsafe.} =
      {.cast(gcsafe).}: logEntries.add(entry)
    let log = newLogger("test.heartbeat", sink = testSink)
    var reg = newHeartbeatRegistry()
    reg.registerTask("good", proc() {.gcsafe.} = discard)
    reg.registerTask("bad", proc() {.gcsafe.} = raise newException(CatchableError, "simulated failure"))
    reg.runAllTasks(log = log)
    ## The good task should have run, the bad task should have logged an error.
    check logEntries.len == 1
    check logEntries[0].level == lvlError
    check "bad" in logEntries[0].message
    check "simulated failure" in logEntries[0].message

  test "runCommitmentReview logs error when sink fails instead of silently discarding":
    var logEntries: seq[LogEntry] = @[]
    let testSink: LogSink = proc(entry: LogEntry) {.gcsafe.} =
      {.cast(gcsafe).}: logEntries.add(entry)
    let log = newLogger("test.commitment", sink = testSink)
    var callCount = 0
    var capturedUserId = ""
    let failingSink: CommitmentReviewSink = proc(review: CommitmentReview) {.gcsafe.} =
      {.cast(gcsafe).}:
        inc callCount
        capturedUserId = $review.userId
        if callCount == 1:
          raise newException(CatchableError, "sink failure")
    let loadSnapshots: CommitmentSnapshotLoader = proc(): seq[CommitmentSnapshot] {.gcsafe.} =
      let c = newCommitment(coAgent, "test commitment", nowSec = 100'i64, dueAt = some(200'i64))
      @[CommitmentSnapshot(userId: UserId("u-fail"), commitment: c)]
    runCommitmentReview(loadSnapshots, failingSink, 200'i64, log = log)
    check callCount == 1
    check logEntries.len == 1
    check logEntries[0].level == lvlError
    check "u-fail" in logEntries[0].message
    check "sink failure" in logEntries[0].message

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

suite "heartbeat commitment accountability":

  test "reviewCommitments scores overdue open commitments without changing status":
    let c = newCommitment(
      coAgent,
      "I'll send the report tomorrow.",
      nowSec = 100'i64,
      dueAt = some(110'i64),
    )
    let reviews = reviewCommitments(@[
      CommitmentSnapshot(userId: UserId("u1"), commitment: c)
    ], nowSec = 200'i64)
    check reviews.len == 1
    check reviews[0].userId == UserId("u1")
    check reviews[0].status == csOpen
    check reviews[0].overdue
    check reviews[0].score < 0.5'f32

  test "reviewCommitments keeps fulfilled commitments at full score":
    let c = markCompleted(newCommitment(
      coAgent,
      "I'll send the report tomorrow.",
      nowSec = 100'i64,
    ), nowSec = 150'i64)
    let reviews = reviewCommitments(@[
      CommitmentSnapshot(userId: UserId("u1"), commitment: c)
    ], nowSec = 200'i64)
    check reviews.len == 1
    check reviews[0].status == csDone
    check not reviews[0].overdue
    check reviews[0].score == 1.0'f32

  test "registerCommitmentReviewTask runs alongside reminders":
    var reg = newHeartbeatRegistry()
    var reviews: seq[CommitmentReview] = @[]
    reg.registerTask("reminders", proc() {.gcsafe.} = discard)
    reg.registerCommitmentReviewTask(
      proc(): seq[CommitmentSnapshot] {.gcsafe.} =
        @[
          CommitmentSnapshot(
            userId: UserId("u1"),
            commitment: newCommitment(
              coUser,
              "Remind me tomorrow about the invoice.",
              nowSec = 1_000'i64,
              dueAt = some(2_000'i64),
            ),
          )
        ],
      proc(review: CommitmentReview) {.gcsafe.} =
        {.cast(gcsafe).}: reviews.add(review),
      proc(): int64 {.gcsafe.} = 1_500'i64,
    )
    reg.runAllTasks()
    check reg.taskCount == 2
    check reviews.len == 1
    check reviews[0].status == csOpen
    check not reviews[0].overdue
    check reviews[0].score > 0.5'f32

suite "heartbeat parseHeartbeatMd":

  test "parses unchecked task items":
    let entries = parseHeartbeatMd("- [ ] Fix the bug\n- [ ] Review PR")
    check entries.len == 2
    check entries[0].title == "Fix the bug"
    check not entries[0].checked
    check entries[1].title == "Review PR"
    check not entries[1].checked

  test "parses checked task items":
    let entries = parseHeartbeatMd("- [x] Done task\n- [x] Another done")
    check entries.len == 2
    check entries[0].checked
    check entries[1].checked

  test "parses mixed checked/unchecked":
    let entries = parseHeartbeatMd("- [ ] Active task\n- [x] Completed\n- [ ] Another active")
    check entries.len == 3
    check not entries[0].checked
    check entries[1].checked
    check not entries[2].checked

  test "skips empty lines":
    let entries = parseHeartbeatMd("\n\n- [ ] Task\n\n\n")
    check entries.len == 1
    check entries[0].title == "Task"

  test "ignores bullet points without checkbox":
    let entries = parseHeartbeatMd("- Regular bullet without checkbox")
    check entries.len == 0

suite "heartbeat prompt helpers":

  test "buildHeartbeatPrompt instructs the agent to act and update the file":
    let prompt = buildHeartbeatPrompt(@[
      HeartbeatTaskEntry(title: "Review the logs", checked: false),
      HeartbeatTaskEntry(title: "Fix the retry loop", checked: false),
    ])
    check prompt.contains("Execute agora o que for viável")
    check prompt.contains("HEARTBEAT.md")
    check prompt.contains("Review the logs")
    check prompt.contains("Fix the retry loop")

  test "millisUntilNextRun returns a positive delay":
    let current = dateTime(2026, mApr, 7, 10, 3, 15, 0, local())
    let waitMs = millisUntilNextRun(everyMinute(), current)
    check waitMs > 0
    check waitMs <= 60_000

suite "heartbeat deliverHeartbeats":

  test "delivers heartbeat tasks from HEARTBEAT.md in paddock":
    let tmp = getTempDir() / "donkey_hb_dispatch"
    try: removeDir(tmp) except: discard
    createDir(tmp / "user-uuid")
    writeFile(tmp / "user-uuid" / "HEARTBEAT.md",
      "- [ ] Review the logs\n- [ ] Check email\n- [x] Done already")
    var dispatched: seq[string] = @[]
    let outboxFn: HeartbeatOutboxFn = proc(userId, channel, taskPayload: string) {.gcsafe.} =
      {.cast(gcsafe).}: dispatched.add(userId & "|" & channel & "|" & taskPayload)
    deliverHeartbeats(tmp, outboxFn)
    check dispatched.len == 1
    check "user-uuid" in dispatched[0]
    check "||" in dispatched[0]
    check "Review the logs" in dispatched[0]
    check "Check email" in dispatched[0]

  test "skips already dispatched users within cooldown":
    let tmp = getTempDir() / "donkey_hb_cooldown"
    try: removeDir(tmp) except: discard
    createDir(tmp / "user-cool" / "memory")
    writeFile(tmp / "user-cool" / "HEARTBEAT.md", "- [ ] Do this")
    writeFile(tmp / "user-cool" / "memory" / "heartbeat-state.json",
      $ %* {"last_dispatch_ms": nowMs()})
    var dispatched: seq[string] = @[]
    let outboxFn: HeartbeatOutboxFn = proc(userId, channel, taskPayload: string) {.gcsafe.} =
      {.cast(gcsafe).}: dispatched.add(userId)
    deliverHeartbeats(tmp, outboxFn)
    check dispatched.len == 0
    try: removeDir(tmp) except: discard

  test "skips users with no HEARTBEAT.md":
    let tmp = getTempDir() / "donkey_hb_no_hb"
    try: removeDir(tmp) except: discard
    createDir(tmp / "user-no-hb")
    var dispatched2: seq[string] = @[]
    let outboxFn2: HeartbeatOutboxFn = proc(userId, channel, taskPayload: string) {.gcsafe.} =
      {.cast(gcsafe).}: dispatched2.add(userId)
    deliverHeartbeats(tmp, outboxFn2)
    check dispatched2.len == 0
    try: removeDir(tmp) except: discard

  test "skips empty heartbeat checklists":
    let tmp = getTempDir() / "donkey_hb_empty_checklist"
    try: removeDir(tmp) except: discard
    createDir(tmp / "user-empty")
    writeFile(tmp / "user-empty" / "HEARTBEAT.md",
      "- [x] Done already\n- [X] Also done\n\nPlain note, not a task")
    var dispatched: seq[string] = @[]
    let outboxFn: HeartbeatOutboxFn = proc(userId, channel, taskPayload: string) {.gcsafe.} =
      {.cast(gcsafe).}: dispatched.add(userId)
    deliverHeartbeats(tmp, outboxFn)
    check dispatched.len == 0
    try: removeDir(tmp) except: discard

suite "contemplation runtime":

  test "registerContemplationTask skips when disabled":
    var reg = newHeartbeatRegistry()
    var writes = 0
    let loadMemories = proc(): seq[ContemplationMemory] {.gcsafe.} =
      @[ContemplationMemory(id: "u1_m0", content: "Reviewed logs.", timestamp: 100'i64)]
    let buildEpisode = proc(memories: seq[ContemplationMemory]): EpisodeJournal {.gcsafe.} =
      newEpisodeJournal("Should not run", "disabled", 100'i64, 100'i64, @["u1_m0"])
    let writeEpisode = proc(userId: UserId; episode: EpisodeJournal) {.gcsafe.} =
      {.cast(gcsafe).}: inc writes
    let loadUserId = proc(): UserId {.gcsafe.} = UserId("u1")
    reg.registerContemplationTask(
      ContemplationConfig(enabled: false, provider: "ollama", model: "qwen2.5:3b"),
      loadMemories,
      buildEpisode,
      writeEpisode,
      loadUserId,
    )
    reg.runAllTasks()
    check writes == 0

  test "registerContemplationTask writes episode journals for local-capable config":
    var reg = newHeartbeatRegistry()
    var written: seq[EpisodeJournal] = @[]
    let loadMemories = proc(): seq[ContemplationMemory] {.gcsafe.} =
      @[
        ContemplationMemory(id: "u1_m0", content: "Reviewed logs.", timestamp: 100'i64),
        ContemplationMemory(id: "u1_m1", content: "Fixed the retry loop.", timestamp: 200'i64),
      ]
    let buildEpisode = proc(memories: seq[ContemplationMemory]): EpisodeJournal {.gcsafe.} =
      newEpisodeJournal(
        "Retry fix reflection",
        "A short contemplation condensed the recent debugging session.",
        100'i64,
        200'i64,
        memories.mapIt(it.id),
      )
    let writeEpisode = proc(userId: UserId; episode: EpisodeJournal) {.gcsafe.} =
      {.cast(gcsafe).}: written.add(episode)
    let loadUserId = proc(): UserId {.gcsafe.} = UserId("u1")
    reg.registerContemplationTask(
      ContemplationConfig(enabled: true, provider: "ollama", model: "qwen2.5:3b"),
      loadMemories,
      buildEpisode,
      writeEpisode,
      loadUserId,
    )
    reg.runAllTasks()
    check written.len == 1
    check written[0].title == "Retry fix reflection"
    check written[0].sourceMemoryIds == @["u1_m0", "u1_m1"]
