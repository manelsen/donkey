## Stress: ledger compaction worker racing with delivery appends.

import std/[atomics, json, monotimes, os, strutils, times, unittest]
import results
import donkey/adapters/state/runtime_store
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/ports/runtime_state

let stressDir = getTempDir() / ("donkey_stress_ledger_" & $getCurrentProcessId())

type
  AppendArg = object
    worker: int

var
  gLedgerPorts:    array[4, DeliveryLedgerPort]
  gAppendCount:    array[4, int]
  gAppendErrors:   Atomic[int]
  gStopAppenders:  Atomic[bool]
  gCompactionStarted: Atomic[bool]
  gWritesAfterStart: Atomic[int]

proc appendWorker(arg: AppendArg) {.thread.} =
  {.cast(gcsafe).}:
    var i = 0
    while not gStopAppenders.load():
      let id = "w" & $arg.worker & "-" & $i
      let now = epochMs()
      let record = DeliveryRecord(
        id: id, userId: "u" & $arg.worker, channel: ckSlack,
        channelId: "c" & $arg.worker, textHash: "h", state: dlsPending,
        createdAtMs: now, updatedAtMs: now)
      let pending = gLedgerPorts[arg.worker].recordPending(record)
      if pending.isErr:
        discard gAppendErrors.fetchAdd(1)
      else:
        inc gAppendCount[arg.worker]
        if gLedgerPorts[arg.worker].markSent(id, now).isErr:
          discard gAppendErrors.fetchAdd(1)
        elif gCompactionStarted.load():
          discard gWritesAfterStart.fetchAdd(1)
      inc i
      sleep(10)

suite "ledger worker stress":

  test "concurrent appends overlap a real compaction":
    let dir = stressDir / "append"
    removeDir(dir)
    defer: removeDir(dir)

    let store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
    for i in 0 ..< gLedgerPorts.len:
      gLedgerPorts[i] = store.deliveryLedger()
    gAppendErrors.store(0)
    gStopAppenders.store(false)
    gCompactionStarted.store(false)
    gWritesAfterStart.store(0)
    let beforeLastCompact = store.ledgerLastCompactMs()
    for i in 0 ..< gAppendCount.len:
      gAppendCount[i] = 0

    let beforeCompact = store.ledgerCompactStarts()
    let logger = newLogger("stress.ledger", lvlError)
    let worker = startLedgerCompactionWorker(store, 1.0, logger)
    check worker != nil
    defer: stopLedgerCompactionWorker(worker)

    var threads: array[4, Thread[AppendArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], appendWorker, AppendArg(worker: i))

    ## Keep writers active until the worker has actually started a compaction.
    var waited = 0
    while store.ledgerCompactStarts() <= beforeCompact and waited < 5000:
      sleep(10)
      waited += 10
    check store.ledgerCompactStarts() > beforeCompact
    gCompactionStarted.store(true)

    ## Confirm a write after the start signal and wait for compaction to finish.
    waited = 0
    while gWritesAfterStart.load() == 0 and waited < 5000:
      sleep(10)
      waited += 10
    check gWritesAfterStart.load() > 0

    waited = 0
    while store.ledgerLastCompactMs() <= beforeLastCompact and waited < 5000:
      sleep(10)
      waited += 10
    check store.ledgerLastCompactMs() > beforeLastCompact
    gStopAppenders.store(true)

    for i in 0 ..< threads.len:
      joinThread(threads[i])

    let started = getMonoTime()
    stopLedgerCompactionWorker(worker)
    stopLedgerCompactionWorker(worker)  # idempotent
    check inMilliseconds(getMonoTime() - started) < 2000
    check store.ledgerLastCompactError().len == 0

    check gAppendErrors.load() == 0
    var expected = 0
    for i in 0 ..< gAppendCount.len:
      expected += gAppendCount[i]
    check expected > 0

    let loaded = store.deliveryLedger().loadAll()
    check loaded.isOk
    check loaded.get().len == expected
    for record in loaded.get():
      check record.state == dlsSent
      check record.id.startsWith("w")

  test "stop after a compaction started returns promptly":
    let dir = stressDir / "stop"
    removeDir(dir)
    defer: removeDir(dir)
    createDir(dir)

    let now = epochMs()
    var content = ""
    for i in 0 ..< 2000:
      content.add("\n" & $(%* {
        "id": "stop-" & $i,
        "state": "sent",
        "updated_at_ms": now,
      }) & "\n")
    writeFile(dir / DeliveryLedgerFileName, content)

    let store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
    let beforeCompact = store.ledgerCompactStarts()
    let worker = startLedgerCompactionWorker(
      store, 1.0, newLogger("stress.ledger", lvlError))
    check worker != nil

    var waited = 0
    while store.ledgerCompactStarts() <= beforeCompact and waited < 5000:
      sleep(10)
      waited += 10
    check store.ledgerCompactStarts() > beforeCompact

    let started = getMonoTime()
    stopLedgerCompactionWorker(worker)
    check inMilliseconds(getMonoTime() - started) < 2000
