## Durability layer tests.
##
## Covers the file-backed session registry and outbound delivery ledger, plus
## the invariant that a broken persistence sink never blocks the hot path.

import std/[os, strutils, tables, unittest]
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
    let now = 1_700_000_000_000
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

    let now = 1_700_000_000_000
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

    let now = 1_700_000_000_000
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
