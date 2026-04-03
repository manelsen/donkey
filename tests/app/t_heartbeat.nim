## Heartbeat unit tests — pure logic only, no real timers.
## Tests: task registration, tick counting, reminder delivery logic.

import std/[os, strutils, times, unittest, options, sequtils]
import donkey/app/heartbeat
import donkey/app/contemplation
import donkey/core/types
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
