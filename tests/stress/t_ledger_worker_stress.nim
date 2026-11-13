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
    worker: int

var
  gLedgerPorts:    array[4, DeliveryLedgerPort]
  gProbePort:      DeliveryLedgerPort
  gAppendCount:    array[4, int]
  gAppendErrors:   Atomic[int]
  gStopAppenders:  Atomic[bool]
  gHookEntered:    Atomic[bool]
  gHookRelease:    Atomic[bool]
  gWriteAttemptsAfterHook: Atomic[int]
  gStopReturned:   Atomic[bool]
  gProbeOk:        bool

proc blockingHook() {.gcsafe, raises: [].} =
  gHookEntered.store(true)
  while not gHookRelease.load():
    sleep(1)

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
      inc i
      sleep(10)

proc probeWorker(_: int) {.thread.} =
  {.cast(gcsafe).}:
    while not gHookEntered.load():
      sleep(1)
    discard gWriteAttemptsAfterHook.fetchAdd(1)
    let now = epochMs()
    let record = DeliveryRecord(
      id: "probe", userId: "probe", channel: ckSlack, channelId: "probe",
      textHash: "h", state: dlsPending, createdAtMs: now, updatedAtMs: now)
    let pending = gProbePort.recordPending(record)
    if pending.isOk:
      gProbeOk = gProbePort.markSent("probe", epochMs()).isOk
    else:
      gProbeOk = false

proc stopWorker(worker: LedgerCompactionWorker) {.thread.} =
  {.cast(gcsafe).}:
    stopLedgerCompactionWorker(worker)
    gStopReturned.store(true)

suite "ledger worker stress":

  test "writes submitted during active compaction complete safely":
    let dir = stressDir / "append"
    removeDir(dir)
    defer: removeDir(dir)

    let store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
    for i in 0 ..< gLedgerPorts.len:
      gLedgerPorts[i] = store.deliveryLedger()
    gProbePort = store.deliveryLedger()
    gProbeOk = false
    gAppendErrors.store(0)
    gStopAppenders.store(false)
    gHookEntered.store(false)
    gHookRelease.store(false)
    gWriteAttemptsAfterHook.store(0)
    for i in 0 ..< gAppendCount.len:
      gAppendCount[i] = 0

    store.onCompactStart = blockingHook
    let worker = startLedgerCompactionWorker(
      store, 1.0, newLogger("stress.ledger", lvlError))
    check worker != nil
    defer: stopLedgerCompactionWorker(worker)

    var threads: array[4, Thread[AppendArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], appendWorker, AppendArg(worker: i))

    var waited = 0
    while not gHookEntered.load() and waited < 5000:
      sleep(10)
      waited += 10
    check gHookEntered.load()

    var probe: Thread[int]
    createThread(probe, probeWorker, 0)
    waited = 0
    while gWriteAttemptsAfterHook.load() == 0 and waited < 5000:
      sleep(10)
      waited += 10
    check gWriteAttemptsAfterHook.load() > 0

    gHookRelease.store(true)
    joinThread(probe)
    check gProbeOk
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
    inc expected  ## the probe record

    let loaded = store.deliveryLedger().loadAll()
    check loaded.isOk
    check loaded.get().len == expected
    for record in loaded.get():
      check record.state == dlsSent
      check record.id == "probe" or record.id.startsWith("w")

  test "stop waits for an actively running compaction":
    let dir = stressDir / "stop"
    removeDir(dir)
    defer: removeDir(dir)

    let store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
    let ledger = store.deliveryLedger()
    check ledger.recordPending(DeliveryRecord(
      id: "keep", userId: "u", channel: ckSlack, channelId: "c",
      textHash: "h", state: dlsPending,
      createdAtMs: epochMs(), updatedAtMs: epochMs())).isOk

    gHookEntered.store(false)
    gHookRelease.store(false)
    gStopReturned.store(false)
    store.onCompactStart = blockingHook

    let worker = startLedgerCompactionWorker(
      store, 1.0, newLogger("stress.ledger", lvlError))
    check worker != nil

    var waited = 0
    while not gHookEntered.load() and waited < 5000:
      sleep(10)
      waited += 10
    check gHookEntered.load()

    var stopper: Thread[LedgerCompactionWorker]
    createThread(stopper, stopWorker, worker)
    sleep(20)
    check not gStopReturned.load()

    gHookRelease.store(true)
    joinThread(stopper)
    check gStopReturned.load()
    check store.ledgerLastCompactError().len == 0
