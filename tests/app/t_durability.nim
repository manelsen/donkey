## Durability layer tests.
##
## Covers the file-backed session registry and outbound delivery ledger, plus
## the invariant that a broken persistence sink never blocks the hot path.

import std/[json, os, strutils, tables, unittest]
import donkey/adapters/state/runtime_store
import donkey/app/outbound_runtime
import donkey/app/session_manager
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/channel
import donkey/ports/runtime_state

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_durability_" & tag & "_" & $getCurrentProcessId())
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

proc findRecord(records: seq[DeliveryRecord]; id: string): DeliveryRecord =
  for record in records:
    if record.id == id:
      return record
  DeliveryRecord()

suite "durability":

  test "session registry metadata survives a restart":
    let dir = freshDir("sessions")
    defer: cleanup(dir)

    let uid = UserId("user-restart")
    let signature = "provider=test|tools=a,b|dir=/tmp/paddock"

    var sm: SessionManager
    sm.init()
    sm.setRegistryStore(newRuntimeStateStore(dir).sessionRegistry())
    discard sm.getOrCreate(uid)
    sm.recordChannel(uid, ckTelegram, "12345")
    sm.recordChannel(uid, ckDiscord, "67890")
    let lease = sm.prepareEntry(uid, signature)
    let sessionId = lease.entry[].sessionId
    lease.entry[].lastInboundEpochMs = 1_700_000_000_000
    sm.persistSession(uid)
    check sessionId.len > 0

    check fileExists(dir / SessionsFileName)

    ## Simulate a daemon restart: a fresh manager reads the same state dir.
    var restarted: SessionManager
    restarted.init()
    restarted.setRegistryStore(newRuntimeStateStore(dir).sessionRegistry())
    let restored = restarted.restoreSessions()
    check restored.isOk
    check restored.value == 1
    check restarted.hasSession(uid)

    let entry = restarted.get(uid)
    check entry != nil
    check entry.sessionId == sessionId
    check entry.toolCatalogSignature == signature
    check entry.channels == @[(ckTelegram, "12345"), (ckDiscord, "67890")]
    check entry.lastInboundEpochMs == 1_700_000_000_000
    check entry.restored

    ## Restored metadata has no live orchestrator, so the first inbound turn
    ## must rebuild the runtime and keep the same session id.
    let rebuilt = restarted.prepareEntry(uid, signature)
    check rebuilt.rebuilt
    check not rebuilt.isNew
    check rebuilt.entry[].sessionId == sessionId
    check not rebuilt.entry[].restored
    check restarted.get(uid).channels == @[(ckTelegram, "12345"), (ckDiscord, "67890")]

  test "session registry failure never blocks session operations":
    let dir = freshDir("session-fail")
    defer: cleanup(dir)

    let failing = SessionRegistryPort(
      loadAll: proc(): Result[seq[SessionRegistryRecord], string] {.gcsafe, raises: [].} =
        err("registry read down"),
      upsert: proc(record: SessionRegistryRecord): Result[void, string] {.gcsafe, raises: [].} =
        err("registry write down"),
    )

    var sm: SessionManager
    sm.init()
    sm.setRegistryStore(failing)
    let uid = UserId("user-registry-down")
    let entry = sm.getOrCreate(uid)
    check entry != nil
    sm.recordChannel(uid, ckTelegram, "42")
    check sm.get(uid).channels == @[(ckTelegram, "42")]
    let lease = sm.prepareEntry(uid, "sig")
    check lease.isNew or lease.rebuilt or lease.entry != nil
    check sm.hasSession(uid)

    var restarted: SessionManager
    restarted.init()
    restarted.setRegistryStore(failing)
    let restored = restarted.restoreSessions()
    check restored.isErr
    check not restarted.hasSession(uid)

  test "delivery ledger records pending then sent":
    let dir = freshDir("ledger-sent")
    defer: cleanup(dir)

    let ledger = newRuntimeStateStore(dir).deliveryLedger()
    let now = epochMs()
    let pending = DeliveryRecord(
      id: "delivery-1",
      userId: "user-1",
      channel: ckTelegram,
      channelId: "chat-1",
      textHash: "abc123",
      state: dlsPending,
      attempts: 1,
      createdAtMs: now,
      updatedAtMs: now,
    )
    check ledger.recordPending(pending).isOk
    var loaded = ledger.loadAll()
    check loaded.isOk
    check loaded.value.len == 1
    check findRecord(loaded.value, "delivery-1").state == dlsPending

    check ledger.markSent("delivery-1", now + 50).isOk

    ## Re-read through a new store instance to prove the event log persists.
    let reopened = newRuntimeStateStore(dir).deliveryLedger()
    loaded = reopened.loadAll()
    check loaded.isOk
    check loaded.value.len == 1
    let sent = findRecord(loaded.value, "delivery-1")
    check sent.state == dlsSent
    check sent.updatedAtMs == now + 50
    check sent.error.len == 0

  test "delivery ledger records failed deliveries with the error":
    let dir = freshDir("ledger-failed")
    defer: cleanup(dir)

    let ledger = newRuntimeStateStore(dir).deliveryLedger()
    let pending = DeliveryRecord(
      id: "delivery-2",
      userId: "user-2",
      channel: ckDiscord,
      channelId: "chat-2",
      textHash: "def456",
      state: dlsPending,
      attempts: 1,
      createdAtMs: 10,
      updatedAtMs: 10,
    )
    check ledger.recordPending(pending).isOk
    check ledger.markFailed("delivery-2", 20, "network unreachable").isOk

    let loaded = ledger.loadAll()
    check loaded.isOk
    let failed = findRecord(loaded.value, "delivery-2")
    check failed.state == dlsFailed
    check failed.error == "network unreachable"
    check failed.updatedAtMs == 20

  test "state directory and ledger files are private on POSIX":
    let dir = freshDir("state-perms")
    defer: cleanup(dir)
    let ledger = newRuntimeStateStore(dir).deliveryLedger()
    let now = epochMs()
    check ledger.recordPending(DeliveryRecord(
      id: "perms", userId: "u", channel: ckTelegram, channelId: "c",
      textHash: "h", state: dlsPending,
      createdAtMs: now, updatedAtMs: now)).isOk

    when not defined(windows):
      let dirPerms = getFilePermissions(dir)
      check fpGroupRead notin dirPerms
      check fpGroupWrite notin dirPerms
      check fpOthersRead notin dirPerms
      check fpOthersWrite notin dirPerms
      let ledgerPerms = getFilePermissions(dir / DeliveryLedgerFileName)
      check fpUserRead in ledgerPerms
      check fpUserWrite in ledgerPerms
      check fpGroupRead notin ledgerPerms
      check fpGroupWrite notin ledgerPerms
      check fpOthersRead notin ledgerPerms
      check fpOthersWrite notin ledgerPerms

  test "ledger compaction keeps pending and drops expired terminal records":
    let dir = freshDir("ledger-compact")
    defer: cleanup(dir)

    let now = epochMs()
    let day = 86_400_000'i64
    let store = newRuntimeStateStore(
      dir,
      ledgerRetentionDays = 1.0,
      ledgerCompactIntervalSec = 0.0,
    )
    let ledger = store.deliveryLedger()

    ## Pending records are always kept, even when older than retention.
    check ledger.recordPending(DeliveryRecord(
      id: "pending-old", userId: "u-pending", channel: ckTelegram,
      channelId: "c-pending", textHash: "h-pending", state: dlsPending,
      createdAtMs: now - 10 * day, updatedAtMs: now - 10 * day)).isOk

    ## Old terminal record must be dropped.
    check ledger.recordPending(DeliveryRecord(
      id: "sent-old", userId: "u-old", channel: ckDiscord,
      channelId: "c-old", textHash: "h-old", state: dlsPending,
      createdAtMs: now - 2 * day, updatedAtMs: now - 2 * day)).isOk
    check ledger.markSent("sent-old", now - 2 * day).isOk

    ## Recent terminal record must survive.
    check ledger.recordPending(DeliveryRecord(
      id: "sent-recent", userId: "u-recent", channel: ckSlack,
      channelId: "c-recent", textHash: "h-recent", state: dlsPending,
      createdAtMs: now, updatedAtMs: now)).isOk
    check ledger.markSent("sent-recent", now).isOk

    check store.compactLedger(force = true, nowMs = now).isOk

    let loaded = store.deliveryLedger().loadAll()
    check loaded.isOk
    check findRecord(loaded.value, "pending-old").state == dlsPending
    check findRecord(loaded.value, "sent-recent").state == dlsSent
    check findRecord(loaded.value, "sent-old").id == ""

    ## The rewritten file no longer contains the dropped id.
    let raw = readFile(dir / DeliveryLedgerFileName)
    check "sent-old" notin raw
    check "pending-old" in raw
    check "sent-recent" in raw

  test "startup compaction drops expired terminal records":
    let dir = freshDir("ledger-startup-compact")
    defer: cleanup(dir)

    let now = epochMs()
    let day = 86_400_000'i64
    writeFile(dir / DeliveryLedgerFileName,
      "\n" & $(%* {
        "id": "expired",
        "state": "sent",
        "updated_at_ms": now - 2 * day,
      }) & "\n")

    let store = newRuntimeStateStore(
      dir,
      ledgerRetentionDays = 1.0,
      ledgerCompactIntervalSec = 3600.0,
    )
    let loaded = store.deliveryLedger().loadAll()
    check loaded.isOk
    check loaded.value.len == 0
    check readFile(dir / DeliveryLedgerFileName).strip.len == 0

  test "compaction keeps a disk terminal state over a stale pending entry":
    let dir = freshDir("ledger-terminal-wins")
    defer: cleanup(dir)

    let now = epochMs()
    let store = newRuntimeStateStore(
      dir,
      ledgerRetentionDays = 30.0,
      ledgerCompactIntervalSec = 3600.0,
    )
    let ledger = store.deliveryLedger()
    let pending = DeliveryRecord(
      id: "terminal-wins", userId: "u", channel: ckTelegram,
      channelId: "c", textHash: "h", state: dlsPending,
      attempts: 1, createdAtMs: now, updatedAtMs: now,
    )
    check ledger.recordPending(pending).isOk
    check ledger.markSent("terminal-wins", now + 10).isOk

    ## Simulate a failed terminal fsync that left the pending entry in memory.
    store.pending["terminal-wins"] = pending
    check store.compactLedger(force = true, nowMs = now + 20).isOk

    let loaded = ledger.loadAll()
    check loaded.isOk
    check findRecord(loaded.value, "terminal-wins").state == dlsSent

  test "compaction skips a ledger with unrecognized future events":
    let dir = freshDir("ledger-future")
    defer: cleanup(dir)

    let now = epochMs()
    writeFile(dir / DeliveryLedgerFileName,
      "\n" & $(%* {
        "id": "future",
        "channel": "future-channel",
        "state": "sent",
        "updated_at_ms": now,
      }) & "\n")

    let store = newRuntimeStateStore(
      dir,
      ledgerRetentionDays = 1.0,
      ledgerCompactIntervalSec = 3600.0,
    )
    check store.ledgerLastCompactError().len > 0
    check "future-channel" in readFile(dir / DeliveryLedgerFileName)

  test "compaction skips events with unknown fields":
    let dir = freshDir("ledger-future-field")
    defer: cleanup(dir)

    let now = epochMs()
    writeFile(dir / DeliveryLedgerFileName,
      "\n" & $(%* {
        "id": "future-field",
        "channel": "telegram",
        "state": "sent",
        "schema_version": 2,
        "updated_at_ms": now,
      }) & "\n")

    let store = newRuntimeStateStore(
      dir,
      ledgerRetentionDays = 1.0,
      ledgerCompactIntervalSec = 3600.0,
    )
    check store.ledgerLastCompactError().len > 0
    check "schema_version" in readFile(dir / DeliveryLedgerFileName)

  test "dedicated worker compacts outside the event loop":
    let dir = freshDir("ledger-worker")
    defer: cleanup(dir)

    let now = epochMs()
    let day = 86_400_000'i64
    var store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
    let ledger = store.deliveryLedger()
    check ledger.recordPending(DeliveryRecord(
      id: "worker-pending", userId: "u", channel: ckTelegram,
      channelId: "c", textHash: "h", state: dlsPending,
      createdAtMs: now - 10 * day, updatedAtMs: now - 10 * day)).isOk
    check ledger.recordPending(DeliveryRecord(
      id: "worker-expired", userId: "u", channel: ckSlack,
      channelId: "c", textHash: "h", state: dlsPending,
      createdAtMs: now - 2 * day, updatedAtMs: now - 2 * day)).isOk
    check ledger.markSent("worker-expired", now - 2 * day).isOk

    let before = store.ledgerLastCompactMs()
    let workerRes = startLedgerCompactionWorker(addr store, 1.0)
    check workerRes.isOk
    let worker = workerRes.get()
    check worker != nil
    defer: stopLedgerCompactionWorker(worker)

    sleep(2300)
    stopLedgerCompactionWorker(worker)
    check store.ledgerLastCompactMs() > before

    let loaded = store.deliveryLedger().loadAll()
    check loaded.isOk
    check findRecord(loaded.value, "worker-pending").state == dlsPending
    check findRecord(loaded.value, "worker-expired").id == ""
    let raw = readFile(dir / DeliveryLedgerFileName)
    check "worker-pending" in raw
    check "worker-expired" notin raw

  test "compaction on a missing ledger is a no-op":
    let dir = freshDir("ledger-none")
    defer: cleanup(dir)
    let store = newRuntimeStateStore(dir, ledgerCompactIntervalSec = 3600.0)
    check store.compactLedger(force = true).isOk
    check not fileExists(dir / DeliveryLedgerFileName)

  test "failing delivery ledger does not prevent sending":
    let dir = freshDir("ledger-blocked")
    defer: cleanup(dir)

    let brokenLedger = DeliveryLedgerPort(
      recordPending: proc(record: DeliveryRecord): Result[void, string] {.gcsafe, raises: [].} =
        err("ledger pending down"),
      markSent: proc(id: string; updatedAtMs: int64): Result[void, string] {.gcsafe, raises: [].} =
        err("ledger sent down"),
      markFailed: proc(id: string; updatedAtMs: int64; error: string): Result[void, string] {.gcsafe, raises: [].} =
        err("ledger failed down"),
      loadAll: proc(): Result[seq[DeliveryRecord], string] {.gcsafe, raises: [].} =
        err("ledger read down"),
    )

    var sentCount = 0
    let ports = OutboundChannelPorts(
      telegram: OutboundChannelPort(
        send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
          discard msg
          {.cast(gcsafe).}: inc sentCount
          ok(),
      )
    )

    sendImmediateOutbound(
      OutboundMessage(userId: UserId("user-3"), channel: ckTelegram, text: "still delivered"),
      ports,
      newLogger("test.durability"),
      brokenLedger,
    )
    check sentCount == 1

    ## Failure paths must also stay best-effort.
    let failingPorts = OutboundChannelPorts(
      telegram: OutboundChannelPort(
        send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
          discard msg
          err("channel down"),
      )
    )
    sendImmediateOutbound(
      OutboundMessage(userId: UserId("user-4"), channel: ckTelegram, text: "will fail"),
      failingPorts,
      newLogger("test.durability"),
      brokenLedger,
    )
    check sentCount == 1

  test "successful send is written to a working ledger":
    let dir = freshDir("ledger-live")
    defer: cleanup(dir)

    let ledger = newRuntimeStateStore(dir).deliveryLedger()
    var sentCount = 0
    let ports = OutboundChannelPorts(
      telegram: OutboundChannelPort(
        send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
          discard msg
          {.cast(gcsafe).}: inc sentCount
          ok(),
      )
    )
    sendImmediateOutbound(
      OutboundMessage(userId: UserId("user-5"), channel: ckTelegram, text: "hello ledger"),
      ports,
      newLogger("test.durability"),
      ledger,
    )
    check sentCount == 1
    let loaded = ledger.loadAll()
    check loaded.isOk
    check loaded.value.len == 1
    check loaded.value[0].state == dlsSent
    check loaded.value[0].userId == "user-5"
    check loaded.value[0].channel == ckTelegram
    check loaded.value[0].textHash.len > 0

  test "corrupt session registry is backed up and writes resume":
    let dir = freshDir("sessions-corrupt")
    defer: cleanup(dir)

    writeFile(dir / SessionsFileName, "{not valid json")

    let registry = newRuntimeStateStore(dir).sessionRegistry()
    let loaded = registry.loadAll()
    check loaded.isOk
    check loaded.value.len == 0

    var backups = 0
    for kind, path in walkDir(dir):
      if kind == pcFile and path.contains(".corrupt-"):
        inc backups
    check backups == 1
    check not fileExists(dir / SessionsFileName)

    let record = SessionRegistryRecord(
      userId: "user-corrupt",
      sessionId: "session-corrupt",
    )
    check registry.upsert(record).isOk
    check fileExists(dir / SessionsFileName)

    let reloaded = registry.loadAll()
    check reloaded.isOk
    check reloaded.value.len == 1
    check reloaded.value[0].userId == "user-corrupt"

  test "unsupported session registry version is preserved":
    let dir = freshDir("sessions-version")
    defer: cleanup(dir)

    let original = """{"version": 99, "sessions": []}"""
    writeFile(dir / SessionsFileName, original)

    let registry = newRuntimeStateStore(dir).sessionRegistry()
    let loaded = registry.loadAll()
    check loaded.isErr
    check "version" in loaded.error

    ## Unsupported versions are not corruption: keep the file untouched and
    ## refuse writes.
    check registry.upsert(SessionRegistryRecord(userId: "user-version")).isErr
    check readFile(dir / SessionsFileName) == original

    var backups = 0
    for kind, path in walkDir(dir):
      if kind == pcFile and path.contains(".corrupt-"):
        inc backups
    check backups == 0

  test "ledger torn line does not corrupt the next record":
    let dir = freshDir("ledger-torn")
    defer: cleanup(dir)

    ## A crash mid-write leaves a partial line without a trailing newline.
    writeFile(dir / DeliveryLedgerFileName, """{"id":"torn","state":"pen""")

    let ledger = newRuntimeStateStore(dir).deliveryLedger()
    let valid = DeliveryRecord(
      id: "delivery-valid",
      userId: "user-torn",
      channel: ckDiscord,
      channelId: "chat-torn",
      textHash: "torn123",
      state: dlsPending,
      attempts: 1,
      createdAtMs: 10,
      updatedAtMs: 10,
    )
    check ledger.recordPending(valid).isOk

    let loaded = ledger.loadAll()
    check loaded.isOk
    check loaded.value.len == 1
    let record = findRecord(loaded.value, "delivery-valid")
    check record.userId == "user-torn"
    check record.channel == ckDiscord
    check record.state == dlsPending

  test "pending table after reopen preserves metadata on markSent":
    let dir = freshDir("ledger-pending-reopen")
    defer: cleanup(dir)

    let now = epochMs()
    let pending = DeliveryRecord(
      id: "delivery-reopen",
      userId: "user-reopen",
      channel: ckDiscord,
      channelId: "chat-reopen",
      textHash: "hash-reopen",
      state: dlsPending,
      attempts: 1,
      createdAtMs: now,
      updatedAtMs: now,
    )
    check newRuntimeStateStore(dir).deliveryLedger().recordPending(pending).isOk

    ## Simulate a restart: the new store repopulates pending from the ledger.
    let reopened = newRuntimeStateStore(dir)
    check reopened.pending.len == 1
    check reopened.deliveryLedger().markSent("delivery-reopen", now + 10).isOk

    let loaded = newRuntimeStateStore(dir).deliveryLedger().loadAll()
    check loaded.isOk
    check loaded.value.len == 1
    let sent = findRecord(loaded.value, "delivery-reopen")
    check sent.state == dlsSent
    check sent.updatedAtMs == now + 10
    check sent.userId == "user-reopen"
    check sent.channel == ckDiscord
    check sent.channelId == "chat-reopen"
    check sent.textHash == "hash-reopen"
    check sent.createdAtMs == now
    check sent.attempts == 1

  test "minimal ledger event merges with full delivery metadata":
    let dir = freshDir("ledger-minimal")
    defer: cleanup(dir)

    let now = epochMs()
    let pending = DeliveryRecord(
      id: "delivery-minimal",
      userId: "user-minimal",
      channel: ckWeCom,
      channelId: "chat-minimal",
      textHash: "hash-minimal",
      state: dlsPending,
      attempts: 2,
      createdAtMs: now,
      updatedAtMs: now,
    )
    check newRuntimeStateStore(dir).deliveryLedger().recordPending(pending).isOk

    ## Simulate a pending-table miss (restart/failed pending write): clearing
    ## the cache forces markSent to append only the minimal event.
    let restarted = newRuntimeStateStore(dir)
    restarted.pending.clear()
    check restarted.deliveryLedger().markSent("delivery-minimal", now + 7).isOk

    let lines = (dir / DeliveryLedgerFileName).readFile.splitLines
    var lastRecord = ""
    for line in lines:
      if line.strip.len > 0:
        lastRecord = line
    check "user_id" notin lastRecord
    check "channel" notin lastRecord

    let loaded = newRuntimeStateStore(dir).deliveryLedger().loadAll()
    check loaded.isOk
    check loaded.value.len == 1
    let sent = findRecord(loaded.value, "delivery-minimal")
    check sent.state == dlsSent
    check sent.updatedAtMs == now + 7
    check sent.userId == "user-minimal"
    check sent.channel == ckWeCom
    check sent.channelId == "chat-minimal"
    check sent.textHash == "hash-minimal"
    check sent.createdAtMs == now
    check sent.attempts == 2

  test "registry cache keeps users written by successive upserts":
    let dir = freshDir("sessions-cache")
    defer: cleanup(dir)

    let store = newRuntimeStateStore(dir)
    let registry = store.sessionRegistry()
    check registry.upsert(SessionRegistryRecord(
      userId: "cache-a", channels: @[(ckTelegram, "1")],
      lastInboundAtMs: 10, sessionId: "s-a", runtimeSignature: "sig")).isOk
    check registry.upsert(SessionRegistryRecord(
      userId: "cache-b", channels: @[(ckDiscord, "2")],
      lastInboundAtMs: 20, sessionId: "s-b", runtimeSignature: "sig")).isOk

    ## A new store must see both records: the cached read-modify-write cannot
    ## overwrite the first user with the second.
    let reopened = newRuntimeStateStore(dir).sessionRegistry()
    let loaded = reopened.loadAll()
    check loaded.isOk
    check loaded.value.len == 2
    var sawA, sawB = false
    for record in loaded.value:
      if record.userId == "cache-a": sawA = true
      if record.userId == "cache-b": sawB = true
    check sawA
    check sawB

  test "timestamp-only updates coalesce and flush explicitly":
    let dir = freshDir("sessions-coalesce")
    defer: cleanup(dir)

    let store = newRuntimeStateStore(dir)
    let registry = store.sessionRegistry()
    var record = SessionRegistryRecord(
      userId: "coalesce", channels: @[(ckTelegram, "1")],
      lastInboundAtMs: 1, sessionId: "s", runtimeSignature: "sig")
    check registry.upsert(record).isOk

    record.lastInboundAtMs = 2
    check registry.upsert(record).isOk
    # The first write is structural; the timestamp-only update is deferred.
    check store.flushSessions().isOk

    let reopened = newRuntimeStateStore(dir).sessionRegistry()
    let loaded = reopened.loadAll()
    check loaded.isOk
    check loaded.value.len == 1
    check loaded.value[0].lastInboundAtMs == 2

    # A structural change (new channel) flushes immediately without an
    # explicit flush.
    record.channels.add((ckDiscord, "2"))
    record.lastInboundAtMs = 3
    check registry.upsert(record).isOk
    let reopened2 = newRuntimeStateStore(dir).sessionRegistry()
    let loaded2 = reopened2.loadAll()
    check loaded2.isOk
    check (ckDiscord, "2") in loaded2.value[0].channels
