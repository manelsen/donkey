## Turn journal adapter tests (US-002).
##
## The journal is an append-only, newline-framed JSONL file in the state dir.
## These tests exercise restart reload, torn tails, forward-compatible fields,
## commit idempotency, permissions, redaction and concurrent writers.

import std/[atomics, json, options, os, strutils, unittest]
import donkey/adapters/state/turn_journal_store
import donkey/core/pipeops
import donkey/domain/session/turn_journal_pure

const DayMs = 24 * 60 * 60 * 1000

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_turn_journal_" & tag & "_" &
                           $getCurrentProcessId())
  try:
    removeDir(result)
  except CatchableError:
    discard
  createDir(result)

proc cleanup(dir: string) =
  try:
    removeDir(dir)
  except CatchableError:
    discard

proc inbound(turnId, text: string; createdAtMs = 1_700_000_000_000'i64
            ): TurnEvent =
  TurnEvent(
    kind: tevInboundAccepted,
    turnId: turnId,
    userId: "user-1",
    channel: "telegram",
    chatId: "chat-1",
    channelMessageId: turnId,
    taskKind: "user_msg",
    inboundText: text,
    mediaUrls: @["https://example.test/a.png"],
    createdAtMs: createdAtMs,
  )

proc terminalEvents(store: TurnJournalStore; turnId: string;
                    stamp: int64) =
  ## Drive every branch to a terminal state so `commitIfTerminal` may close it.
  ## The final reply must exist first: delivery events are ignored before
  ## `tpsReplyReady`, and a turn without one is not committable.
  doAssert store.append(turnId, TurnEvent(kind: tevReplyReady,
    replyText: "resposta final", replyHash: turnId & "-reply-hash",
    replySource: rsBuffered, deliveryId: turnId & "-reply"), stamp).isOk
  doAssert store.append(turnId, TurnEvent(kind: tevDeliveryAttempted,
    ownerEpochMs: stamp, deliveryId: turnId & "-reply"), stamp).isOk
  doAssert store.append(turnId, TurnEvent(kind: tevDelivered), stamp).isOk
  doAssert store.append(turnId, TurnEvent(kind: tevMemoryPending), stamp).isOk
  doAssert store.append(turnId, TurnEvent(kind: tevMemoryWritten), stamp).isOk
  doAssert store.append(turnId, TurnEvent(kind: tevTranscriptPending), stamp).isOk
  doAssert store.append(turnId, TurnEvent(kind: tevTranscriptSaved), stamp).isOk

proc journalLines(store: TurnJournalStore): seq[string] =
  for line in readFile(store.path).splitLines():
    if line.strip().len > 0:
      result.add(line)

proc rawAppend(store: TurnJournalStore; line: string) =
  var f = open(store.path, fmAppend)
  defer: f.close()
  f.write(line)

type
  AppendArg = object
    stateDir: string
    worker: int

var gAppendErrors: Atomic[int]

proc appendWorker(arg: AppendArg) {.thread.} =
  {.cast(gcsafe).}:
    let store = newTurnJournalStore(arg.stateDir)
    for i in 0 ..< 20:
      let turnId = "turn-" & $arg.worker & "-" & $i
      let event = TurnEvent(
        kind: tevInboundAccepted,
        turnId: turnId,
        userId: "user-" & $arg.worker,
        channel: "telegram",
        chatId: "chat-" & $arg.worker,
        channelMessageId: turnId,
        taskKind: "user_msg",
        inboundText: "concorrente " & $i,
        createdAtMs: 1_000_000'i64,
      )
      if store.append(turnId, event, 1_000_000'i64).isErr:
        discard gAppendErrors.fetchAdd(1)

suite "turn journal store":

  test "append survives a restart and reloads by id, inbound and active":
    let dir = freshDir("restart")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    check store.path == dir / TurnJournalFileName
    check store.append("turn-1", inbound("turn-1", "oi")).isOk
    check store.append("turn-1", TurnEvent(
      kind: tevReplyReady,
      replyText: "resposta final",
      replyHash: "reply-hash",
      memoryHash: "memory-hash",
      replySource: rsBuffered,
      deliveryId: "turn-1-reply")).isOk

    ## A fresh store is the restart: it must rebuild the entry from disk.
    let restarted = newTurnJournalStore(dir)
    let loaded = restarted.loadById("turn-1")
    check loaded.isOk
    check loaded.get().isSome
    let entry = loaded.get().get()
    check entry.turnId == "turn-1"
    check entry.userId == "user-1"
    check entry.channel == "telegram"
    check entry.chatId == "chat-1"
    check entry.channelMessageId == "turn-1"
    check entry.inboundText == "oi"
    check entry.mediaUrls == @["https://example.test/a.png"]
    check entry.phase == tpsReplyReady
    check entry.replyText == "resposta final"
    check entry.replyHash == "reply-hash"
    check entry.memoryHash == "memory-hash"
    check entry.deliveryId == "turn-1-reply"

    let byInbound = restarted.loadByInbound(
      "user-1", "telegram", "turn-1", "chat-1", "oi")
    check byInbound.isOk
    check byInbound.get().isSome
    check byInbound.get().get().turnId == "turn-1"

    let active = restarted.loadActive()
    check active.isOk
    check active.get().len == 1
    check restarted.loadAll().get().len == 1

    check restarted.loadById("missing").get().isNone

  test "a torn trailing line is ignored and does not break the next append":
    let dir = freshDir("torn")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    check store.append("turn-1", inbound("turn-1", "oi")).isOk
    rawAppend(store, "\n{\"v\":1,\"kind\":\"tevDelivered\"")

    let restarted = newTurnJournalStore(dir)
    let loaded = restarted.loadAll()
    check loaded.isOk
    check loaded.get().len == 1
    check restarted.loadById("turn-1").get().get().phase == tpsAccepted

    ## The torn tail is not a frame; a later append must still be readable
    ## and must discard the partial frame instead of making it permanent.
    check restarted.append("turn-1", TurnEvent(kind: tevStreamStarted)).isOk
    check "tevDelivered" notin readFile(restarted.path)
    check readFile(restarted.path).endsWith("\n")
    let after = newTurnJournalStore(dir).loadById("turn-1").get().get()
    check after.replySource == rsStreamed

  test "unknown future fields are ignored on load and block compaction":
    let dir = freshDir("future")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    let old = 1_000_000'i64
    check store.append("turn-1", inbound("turn-1", "oi", old), old).isOk
    terminalEvents(store, "turn-1", old)
    check store.commitIfTerminal("turn-1", old).get()

    ## A future writer added a field this build does not know. The event's
    ## known fields still apply, but compaction must not drop the line.
    rawAppend(store, "\n" & $ %* {
      "v": 1,
      "kind": "tevRecoveryNotified",
      "turn_id": "turn-1",
      "ts_ms": old,
      "future_field": true,
    } & "\n")

    let restarted = newTurnJournalStore(dir)
    let entry = restarted.loadById("turn-1").get().get()
    check entry.notices == 0   # committed turns ignore later events
    check restarted.compact(old + 8 * DayMs).isOk
    check restarted.compact(old + 8 * DayMs).get() == false
    check "future_field" in readFile(restarted.path)

  test "unknown future event kinds are skipped and block compaction":
    let dir = freshDir("future_kind")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    check store.append("turn-1", inbound("turn-1", "oi")).isOk
    rawAppend(store, "\n" & $ %* {
      "v": 99,
      "kind": "tevFromTheFuture",
      "turn_id": "turn-1",
      "ts_ms": 1,
    } & "\n")

    let restarted = newTurnJournalStore(dir)
    check restarted.loadAll().get().len == 1
    check restarted.compact(2_000_000'i64).get() == false

  test "a second terminal commit is idempotent":
    let dir = freshDir("commit")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    let stamp = 1_000_000'i64
    check store.append("turn-1", inbound("turn-1", "oi", stamp), stamp).isOk

    ## Not terminal yet: committing must not close the turn.
    check store.commitIfTerminal("turn-1", stamp).get() == false
    check store.loadById("turn-1").get().get().phase == tpsAccepted

    terminalEvents(store, "turn-1", stamp)
    check store.commitIfTerminal("turn-1", stamp).get() == true
    check store.loadById("turn-1").get().get().phase == tpsCommitted

    ## The drainer and the actor may both reach the commit point; the second
    ## writer (even through another store instance) must not append again.
    let other = newTurnJournalStore(dir)
    check other.commitIfTerminal("turn-1", stamp).get() == false
    check store.commitIfTerminal("turn-1", stamp).get() == false
    check other.append("turn-1", TurnEvent(kind: tevCommitted), stamp).isOk

    var commits = 0
    for line in journalLines(store):
      if "\"tevCommitted\"" in line:
        inc commits
    check commits == 1
    check store.loadActive().get().len == 0

  test "a queued reply is resumable but not committable, streamed or buffered":
    let dir = freshDir("commit_queued")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    let stamp = 2_000_000'i64

    ## Streamed turn: the final reply only reached the outbox, the drainer has
    ## not sent it yet. Queued delivery is NOT terminal for commit: closing the
    ## turn here would hide it from `loadActive` and a crash would lose it.
    check store.append("stream-turn", inbound("stream-turn", "oi", stamp),
                       stamp).isOk
    check store.append("stream-turn", TurnEvent(kind: tevStreamStarted),
                       stamp).isOk
    check store.append("stream-turn", TurnEvent(kind: tevReplyReady,
      replyText: "final streamed", replyHash: "stream-hash",
      replySource: rsStreamed, deliveryId: "stream-turn-reply"), stamp).isOk
    check store.append("stream-turn", TurnEvent(kind: tevReplyQueued),
                       stamp).isOk
    check store.append("stream-turn", TurnEvent(kind: tevMemoryPending),
                       stamp).isOk
    check store.append("stream-turn", TurnEvent(kind: tevMemoryWritten),
                       stamp).isOk
    check store.append("stream-turn", TurnEvent(kind: tevTranscriptPending),
                       stamp).isOk
    check store.append("stream-turn", TurnEvent(kind: tevTranscriptSaved),
                       stamp).isOk

    let streamed = store.loadById("stream-turn").get().get()
    check streamed.phase == tpsReplyReady
    check streamed.replyDelivery == rdsQueued
    check streamed.replySource == rsStreamed
    check store.commitIfTerminal("stream-turn", stamp).get() == false
    ## Once the drainer attempts and delivers, the turn is committable.
    check store.append("stream-turn",
      TurnEvent(kind: tevDeliveryAttempted, ownerEpochMs: stamp), stamp).isOk
    check store.append("stream-turn", TurnEvent(kind: tevDelivered,
      deliveryId: "stream-turn-reply"), stamp).isOk
    check store.commitIfTerminal("stream-turn", stamp).get() == true
    check store.loadById("stream-turn").get().get().phase == tpsCommitted

    ## Buffered turn: same outbox ownership, no streaming involved.
    check store.append("buffer-turn", inbound("buffer-turn", "oi", stamp),
                       stamp).isOk
    check store.append("buffer-turn", TurnEvent(kind: tevReplyReady,
      replyText: "final buffered", replyHash: "buffer-hash",
      replySource: rsBuffered, deliveryId: "buffer-turn-reply"), stamp).isOk
    check store.append("buffer-turn", TurnEvent(kind: tevReplyQueued),
                       stamp).isOk
    check store.append("buffer-turn", TurnEvent(kind: tevMemoryPending),
                       stamp).isOk
    check store.append("buffer-turn", TurnEvent(kind: tevMemoryWritten),
                       stamp).isOk
    check store.append("buffer-turn", TurnEvent(kind: tevTranscriptPending),
                       stamp).isOk
    check store.append("buffer-turn", TurnEvent(kind: tevTranscriptSaved),
                       stamp).isOk

    let buffered = store.loadById("buffer-turn").get().get()
    check buffered.phase == tpsReplyReady
    check buffered.replyDelivery == rdsQueued
    check buffered.replySource == rsBuffered
    check store.commitIfTerminal("buffer-turn", stamp).get() == false
    check store.append("buffer-turn",
      TurnEvent(kind: tevDeliveryAttempted, ownerEpochMs: stamp), stamp).isOk
    check store.append("buffer-turn", TurnEvent(kind: tevDelivered,
      deliveryId: "buffer-turn-reply"), stamp).isOk
    check store.commitIfTerminal("buffer-turn", stamp).get() == true
    check store.loadById("buffer-turn").get().get().phase == tpsCommitted

    check store.loadActive().get().len == 0

  test "a replyReady turn with a pending transcript is not committable":
    let dir = freshDir("commit_pending_transcript")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    let stamp = 3_000_000'i64
    check store.append("turn-1", inbound("turn-1", "oi", stamp), stamp).isOk
    check store.append("turn-1", TurnEvent(kind: tevReplyReady,
      replyText: "resposta final", replyHash: "reply-hash",
      replySource: rsBuffered, deliveryId: "turn-1-reply"), stamp).isOk
    check store.append("turn-1", TurnEvent(kind: tevDeliveryAttempted,
      ownerEpochMs: stamp, deliveryId: "turn-1-reply"), stamp).isOk
    check store.append("turn-1", TurnEvent(kind: tevDelivered), stamp).isOk
    check store.append("turn-1", TurnEvent(kind: tevMemoryPending), stamp).isOk
    check store.append("turn-1", TurnEvent(kind: tevMemoryWritten), stamp).isOk
    check store.append("turn-1", TurnEvent(kind: tevTranscriptPending),
                       stamp).isOk

    ## Reply ready and delivery sent are not enough: the transcript branch is
    ## still in flight, so the commit must be refused.
    let entry = store.loadById("turn-1").get().get()
    check entry.phase == tpsReplyReady
    check entry.replyDelivery == rdsSent
    check entry.transcriptWrite == twsPending
    check store.commitIfTerminal("turn-1", stamp).get() == false
    check store.loadById("turn-1").get().get().phase == tpsReplyReady

    ## Once the transcript lands the same call closes the turn.
    check store.append("turn-1", TurnEvent(kind: tevTranscriptSaved),
                       stamp).isOk
    check store.commitIfTerminal("turn-1", stamp).get() == true
    check store.loadById("turn-1").get().get().phase == tpsCommitted

  test "journal file is 0600 and its directory is 0700":
    let dir = freshDir("perms")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    check store.append("turn-1", inbound("turn-1", "oi")).isOk

    let filePerms = getFilePermissions(store.path)
    check fpUserRead in filePerms
    check fpUserWrite in filePerms
    check fpGroupRead notin filePerms
    check fpGroupWrite notin filePerms
    check fpOthersRead notin filePerms
    check fpOthersWrite notin filePerms

    let dirPerms = getFilePermissions(dir)
    check fpUserRead in dirPerms
    check fpUserWrite in dirPerms
    check fpUserExec in dirPerms
    check fpGroupRead notin dirPerms
    check fpGroupWrite notin dirPerms
    check fpOthersRead notin dirPerms
    check fpOthersWrite notin dirPerms

  test "credentials are redacted before they reach the journal":
    let dir = freshDir("redaction")
    defer: cleanup(dir)

    check redactSecrets("Authorization: Bearer abc.def/ghi") ==
      "Authorization: Bearer [redacted]"
    check redactSecrets("key=RAWKEY&x=1") == "key=[redacted]&x=1"
    check redactSecrets("token=RAWTOK") == "token=[redacted]"
    check redactSecrets("sk-live-SECRET123") == "sk-[redacted]"

    let store = newTurnJournalStore(dir)
    check store.append("turn-1", inbound("turn-1",
      "call Bearer abc.def/ghi and sk-live-SECRET123 key=RAWKEY token=RAWTOK"
      )).isOk
    check store.append("turn-1", TurnEvent(
      kind: tevReplyReady,
      replyText: "use sk-live-REPLYSECRET",
      replySource: rsBuffered)).isOk

    let raw = readFile(store.path)
    check "abc.def/ghi" notin raw
    check "SECRET123" notin raw
    check "RAWKEY" notin raw
    check "RAWTOK" notin raw
    check "REPLYSECRET" notin raw
    check "[redacted]" in raw

    let entry = store.loadById("turn-1").get().get()
    check "[redacted]" in entry.inboundText
    check "[redacted]" in entry.replyText

  test "compaction keeps active turns and recent terminals, drops old ones":
    let dir = freshDir("retention")
    defer: cleanup(dir)

    let store = newTurnJournalStore(dir)
    let old = 1_000_000'i64
    let recent = old + 6 * DayMs
    let now = old + 8 * DayMs

    check store.append("old-turn", inbound("old-turn", "velho", old), old).isOk
    terminalEvents(store, "old-turn", old)
    check store.commitIfTerminal("old-turn", old).get() == true

    check store.append("recent-turn", inbound("recent-turn", "novo", recent),
                       recent).isOk
    terminalEvents(store, "recent-turn", recent)
    check store.commitIfTerminal("recent-turn", recent).get() == true

    check store.append("active-turn", inbound("active-turn", "ativo", recent),
                       recent).isOk

    let compacted = store.compact(now)
    check compacted.isOk
    check compacted.get() == true

    let restarted = newTurnJournalStore(dir)
    let all = restarted.loadAll().get()
    var ids: seq[string]
    for entry in all:
      ids.add(entry.turnId)
    check "old-turn" notin ids
    check "recent-turn" in ids
    check "active-turn" in ids
    check restarted.loadActive().get().len == 1

  test "concurrent appends from two store instances do not interleave":
    let dir = freshDir("concurrent")
    defer: cleanup(dir)

    var threads: array[2, Thread[AppendArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], appendWorker, AppendArg(stateDir: dir, worker: i))
    joinThread(threads[0])
    joinThread(threads[1])

    check gAppendErrors.load() == 0
    let store = newTurnJournalStore(dir)
    let all = store.loadAll()
    check all.isOk
    check all.get().len == 2 * 20

    ## Every frame must still be a complete JSON object.
    let lines = journalLines(store)
    check lines.len == 2 * 20
    for line in lines:
      check parseJson(line).kind == JObject

    ## And the journal is immediately readable (no torn frame at the tail).
    check store.loadById("turn-0-19").get().isSome
    check store.loadById("turn-1-19").get().isSome

  test "a complete frame without its trailing LF is not applied":
    let dir = freshDir("no_lf")
    defer: cleanup(dir)
    let store = newTurnJournalStore(dir)
    let stamp = 3_000_000'i64
    check store.append("t1", inbound("t1", "oi", stamp), stamp).isOk
    let path = dir / "turn_journal.jsonl"
    let frame = """{"v":1,"turn_id":"t1","ts_ms":3000000,"event":{"kind":"tevAbandoned"}}"""
    writeFile(path, readFile(path) & frame)   # no trailing LF
    let loaded = store.loadById("t1")
    check loaded.isOk
    let entry = loaded.get().get()
    check entry.phase != tpsAbandoned

  test "quoted key and token values are fully redacted":
    let text = "key=\"secret-value\" token='tok-9' safekey=public"
    let redacted = redactSecrets(text)
    check "secret-value" notin redacted
    check "tok-9" notin redacted
    check "public" in redacted

# ---------------------------------------------------------------------------
# Durability of the commit point (B1/B2/B3). The fsync seam lets a test fail
# one specific sync and assert that the store never reports a write it did not
# confirm, and that it retries the sync on the next append.
# ---------------------------------------------------------------------------

var
  gDataSyncFailures: int
  gDataSyncCalls: int
  gDirSyncFailures: int
  gDirSyncFailPath: string
  gDirSyncPaths: seq[string]

proc testSyncHook(path: string; kind: JournalSyncKind): bool
    {.gcsafe, raises: [].} =
  result = true
  {.cast(gcsafe).}:
    case kind
    of jskData:
      inc gDataSyncCalls
      if gDataSyncFailures > 0:
        dec gDataSyncFailures
        result = false
    of jskDirectory:
      gDirSyncPaths.add(path)
      if gDirSyncFailures > 0 and path == gDirSyncFailPath:
        dec gDirSyncFailures
        result = false

proc resetSyncHook() =
  gDataSyncFailures = 0
  gDataSyncCalls = 0
  gDirSyncFailures = 0
  gDirSyncFailPath = ""
  gDirSyncPaths = @[]

proc dirSyncsFor(path: string): int =
  for item in gDirSyncPaths:
    if item.normalizedPath == path.normalizedPath:
      inc result

suite "turn journal durability":

  test "a commit whose fsync failed is not reported as persisted":
    let dir = freshDir("commit_sync_failed")
    defer: cleanup(dir)
    resetSyncHook()
    setTurnJournalSyncHook(testSyncHook)
    defer: setTurnJournalSyncHook(nil)

    let store = newTurnJournalStore(dir)
    let stamp = 4_000_000'i64
    check store.append("turn-1", inbound("turn-1", "oi", stamp), stamp).isOk
    terminalEvents(store, "turn-1", stamp)

    ## The commit frame reaches the file, but its fsync fails: the frame is
    ## visible and still not durable.
    gDataSyncFailures = 3
    check store.commitIfTerminal("turn-1", stamp).isErr

    ## The daemon has two writers (actor and drainer) on the same file, so a
    ## second instance must not trust the visible frame either.
    let other = newTurnJournalStore(dir)
    check other.commitIfTerminal("turn-1", stamp).isErr

    ## A duplicate commit must not report success while the frame is
    ## unconfirmed, and no retry may append a second commit frame.
    check other.append("turn-1", TurnEvent(kind: tevCommitted), stamp).isErr
    var commits = 0
    for line in journalLines(store):
      if "\"tevCommitted\"" in line:
        inc commits
    check commits == 1

    ## No caller in this process may report the commit as settled: only the
    ## call that waits for the fsync may report it as persisted, and that call
    ## already failed. A retry resyncs the bytes, but it is still not the
    ## writer. Reporting `false` here would let the drainer close the turn
    ## believing a commit nobody confirmed.
    check store.commitIfTerminal("turn-1", stamp).isErr
    check other.commitIfTerminal("turn-1", stamp).isErr
    check other.append("turn-1", TurnEvent(kind: tevCommitted), stamp).isErr

    ## A restart is the honest resolution: the writer is gone and the frame is
    ## read back from disk, the same evidence every other frame rests on.
    let restarted = newTurnJournalStore(dir)
    check restarted.loadById("turn-1").get().get().phase == tpsCommitted

  test "the next append retries a tail whose fsync failed":
    let dir = freshDir("append_sync_retry")
    defer: cleanup(dir)
    resetSyncHook()
    setTurnJournalSyncHook(testSyncHook)
    defer: setTurnJournalSyncHook(nil)

    let store = newTurnJournalStore(dir)
    let stamp = 5_000_000'i64
    check store.append("turn-1", inbound("turn-1", "oi", stamp), stamp).isOk
    terminalEvents(store, "turn-1", stamp)

    gDataSyncFailures = 1
    check store.commitIfTerminal("turn-1", stamp).isErr

    ## A later append must first confirm the unsynced tail instead of writing
    ## on top of bytes whose durability was never established: one sync for
    ## the retry plus one for the new frame. Confirming the bytes is not the
    ## same as the commit being reported as persisted: that stays `err` (B1).
    let callsBefore = gDataSyncCalls
    check store.append("turn-1",
      TurnEvent(kind: tevDeliveryAttempted, ownerEpochMs: stamp), stamp).isOk
    check gDataSyncCalls == callsBefore + 2
    check store.commitIfTerminal("turn-1", stamp).isErr

  test "only the confirming writer reports a visible commit as persisted":
    let dir = freshDir("commit_writer")
    defer: cleanup(dir)
    resetSyncHook()
    setTurnJournalSyncHook(testSyncHook)
    defer: setTurnJournalSyncHook(nil)

    let actor = newTurnJournalStore(dir)
    let drainer = newTurnJournalStore(dir)
    let stamp = 7_000_000'i64
    check actor.append("turn-1", inbound("turn-1", "oi", stamp), stamp).isOk
    terminalEvents(actor, "turn-1", stamp)

    ## The drainer reaches the commit point first and fsyncs its frame itself.
    let callsBefore = gDataSyncCalls
    check drainer.commitIfTerminal("turn-1", stamp).get() == true
    check gDataSyncCalls == callsBefore + 1

    ## The actor's pending flags never saw that fsync, so it must not report the
    ## commit as persisted (`false` asserts a persistence it cannot see). The
    ## duplicate append is a no-op and appends nothing.
    check actor.commitIfTerminal("turn-1", stamp).isOk
    check actor.commitIfTerminal("turn-1", stamp).get() == false
    check actor.append("turn-1", TurnEvent(kind: tevCommitted), stamp).isOk

    ## No retry may append a second commit frame.
    var commits = 0
    for line in journalLines(actor):
      if "\"tevCommitted\"" in line:
        inc commits
    check commits == 1
    check newTurnJournalStore(dir).loadById("turn-1").get().get().phase ==
      tpsCommitted

  test "a failed directory fsync is retried on the next append":
    let dir = freshDir("dir_sync_retry")
    defer: cleanup(dir)
    resetSyncHook()
    setTurnJournalSyncHook(testSyncHook)
    defer: setTurnJournalSyncHook(nil)

    let store = newTurnJournalStore(dir)
    let stamp = 6_000_000'i64

    ## The journal file is written, but its directory entry is not confirmed.
    ## The append must fail: without the entry the whole file can disappear.
    gDirSyncFailPath = dir
    gDirSyncFailures = 2
    check store.append("t1", inbound("t1", "oi", stamp), stamp).isErr

    ## The file already exists now, so a store that only looked at `isNew`
    ## would skip the directory sync. The pending flag forces a retry.
    check store.append("t2", inbound("t2", "oi", stamp), stamp).isErr
    check dirSyncsFor(dir) == 2

    gDirSyncFailures = 0
    check store.append("t3", inbound("t3", "oi", stamp), stamp).isOk
    check dirSyncsFor(dir) == 3
    check store.loadById("t3").get().isSome

  test "creating the state directory fsyncs its parent":
    let root = freshDir("state_parent_sync")
    defer: cleanup(root)
    resetSyncHook()
    setTurnJournalSyncHook(testSyncHook)
    defer: setTurnJournalSyncHook(nil)

    let stateDir = root / "state"
    check not dirExists(stateDir)
    let store = newTurnJournalStore(stateDir)
    check store.append("t1", inbound("t1", "oi")).isOk
    check dirSyncsFor(root) == 1

    ## A failure to persist the new directory in its parent must fail the
    ## append, and the next append must retry it.
    let root2 = freshDir("state_parent_sync_fail")
    defer: cleanup(root2)
    let stateDir2 = root2 / "state"
    gDirSyncFailPath = root2
    gDirSyncFailures = 1
    check newTurnJournalStore(stateDir2).append(
      "t1", inbound("t1", "oi")).isErr
    check newTurnJournalStore(stateDir2).append(
      "t1", inbound("t1", "oi")).isOk
    check dirSyncsFor(root2) == 2

