## Durability layer tests.
##
## Covers the file-backed session registry and outbound delivery ledger, plus
## the invariant that a broken persistence sink never blocks the hot path.

import std/[os, unittest]
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
      loadAll: proc(): Result[seq[SessionRegistryRecord], string] {.gcsafe.} =
        err("registry read down"),
      upsert: proc(record: SessionRegistryRecord): Result[void, string] {.gcsafe.} =
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
      recordPending: proc(record: DeliveryRecord): Result[void, string] {.gcsafe.} =
        err("ledger pending down"),
      markSent: proc(id: string; updatedAtMs: int64): Result[void, string] {.gcsafe.} =
        err("ledger sent down"),
      markFailed: proc(id: string; updatedAtMs: int64; error: string): Result[void, string] {.gcsafe.} =
        err("ledger failed down"),
      loadAll: proc(): Result[seq[DeliveryRecord], string] {.gcsafe.} =
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
