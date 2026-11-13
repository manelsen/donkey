## Stress: ledger compaction worker racing with delivery appends.

import std/[atomics, monotimes, os, strutils, times, unittest]
import results
import donkey/adapters/state/runtime_store
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/ports/runtime_state

let stressDir = getTempDir() / ("donkey_stress_ledger_" & $getCurrentProcessId())

type
  AppendArg = object
    store:  RuntimeStateStore
    worker: int

var gAppendErrors: Atomic[int]

proc appendWorker(arg: AppendArg) {.thread.} =
  {.cast(gcsafe).}:
    let ledger = arg.store.deliveryLedger()
    for i in 0 ..< 100:
      let id = "w" & $arg.worker & "-" & $i
      let now = epochMs()
      let record = DeliveryRecord(
        id: id, userId: "u" & $arg.worker, channel: ckSlack,
        channelId: "c" & $arg.worker, textHash: "h", state: dlsPending,
        createdAtMs: now, updatedAtMs: now)
      let pending = ledger.recordPending(record)
      if pending.isErr:
        discard gAppendErrors.fetchAdd(1)
        continue
      if ledger.markSent(id, now).isErr:
        discard gAppendErrors.fetchAdd(1)
      sleep(10)

suite "ledger worker stress":

  test "concurrent appends stay valid while compaction runs":
    let dir = stressDir / "append"
    removeDir(dir)
    defer: removeDir(dir)

    gAppendErrors.store(0)
    let store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
    let beforeCompact = store.ledgerLastCompactMs()
    let logger = newLogger("stress.ledger", lvlError)
    let worker = startLedgerCompactionWorker(store, 1.0, logger)
    check worker != nil
    defer: stopLedgerCompactionWorker(worker)

    var threads: array[4, Thread[AppendArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], appendWorker,
                   AppendArg(store: store, worker: i))
    for i in 0 ..< threads.len:
      joinThread(threads[i])

    ## Wait for an observable compaction instead of a fixed sleep.
    var waited = 0
    while store.ledgerLastCompactMs() <= beforeCompact and waited < 5000:
      sleep(50)
      waited += 50
    check store.ledgerLastCompactMs() > beforeCompact

    let started = getMonoTime()
    stopLedgerCompactionWorker(worker)
    stopLedgerCompactionWorker(worker)  # idempotent
    check inMilliseconds(getMonoTime() - started) < 2000

    check gAppendErrors.load() == 0
    let loaded = store.deliveryLedger().loadAll()
    check loaded.isOk
    check loaded.get().len == 400
    for record in loaded.get():
      check record.state == dlsSent
      check record.id.startsWith("w")

  test "stop while the worker is running returns promptly":
    let dir = stressDir / "stop"
    removeDir(dir)
    defer: removeDir(dir)
    let store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)

    for _ in 0 ..< 10:
      let worker = startLedgerCompactionWorker(
        store, 1.0, newLogger("stress.ledger", lvlError))
      check worker != nil
      let started = getMonoTime()
      stopLedgerCompactionWorker(worker)
      check inMilliseconds(getMonoTime() - started) < 2000
