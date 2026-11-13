## Stress: ledger compaction worker racing with delivery appends.

import std/[atomics, monotimes, os, strutils, times, unittest]
import donkey/adapters/state/runtime_store
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
  gAppendCount:    array[4, Atomic[int]]
  gAppendErrors:   Atomic[int]
  gStopAppenders:  Atomic[bool]
  gHookEnabled:    Atomic[bool]
  gHookEntered:    Channel[bool]
  gHookRelease:    Channel[bool]
  gProbeStarted:   Channel[bool]
  gStopReturned:   Atomic[bool]
  gProbeOk:        bool
  gWorkerToStop:   LedgerCompactionWorker

proc blockingHook() {.gcsafe, raises: [].} =
  if not gHookEnabled.load():
    return
  {.cast(gcsafe).}:
    {.cast(raises: []).}:
      gHookEntered.send(true)
      discard gHookRelease.recv()

proc appendStartHook(record: DeliveryRecord) {.gcsafe, raises: [].} =
  if record.id == "probe":
    {.cast(gcsafe).}:
      {.cast(raises: []).}:
        gProbeStarted.send(true)

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
        discard gAppendCount[arg.worker].fetchAdd(1)
        if gLedgerPorts[arg.worker].markSent(id, now).isErr:
          discard gAppendErrors.fetchAdd(1)
      inc i
      sleep(10)

proc probeWorker(_: int) {.thread.} =
  {.cast(gcsafe).}:
    let now = epochMs()
    let record = DeliveryRecord(
      id: "probe", userId: "probe", channel: ckSlack, channelId: "probe",
      textHash: "h", state: dlsPending, createdAtMs: now, updatedAtMs: now)
    let pending = gProbePort.recordPending(record)
    if pending.isOk:
      gProbeOk = gProbePort.markSent("probe", epochMs()).isOk
    else:
      gProbeOk = false

proc stopWorker(_: int) {.thread.} =
  {.cast(gcsafe).}:
    stopLedgerCompactionWorker(gWorkerToStop)
    gStopReturned.store(true)


gHookEntered.open(1)
gHookRelease.open(1)
gProbeStarted.open(1)

suite "ledger worker stress":

  test "writes submitted during active compaction complete safely":
    let dir = stressDir / "append"
    removeDir(dir)
    defer: removeDir(dir)

    var store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
    for i in 0 ..< gLedgerPorts.len:
      gLedgerPorts[i] = store.deliveryLedger()
    gProbePort = store.deliveryLedger()
    gProbeOk = false
    gAppendErrors.store(0)
    gStopAppenders.store(false)
    gHookEnabled.store(true)
    for i in 0 ..< gAppendCount.len:
      gAppendCount[i].store(0)

    store.onCompactStart = blockingHook
    store.onAppendStart = appendStartHook
    let workerRes = startLedgerCompactionWorker(addr store, 1.0)
    check workerRes.isOk
    let worker = workerRes.get()
    check worker != nil
    defer: stopLedgerCompactionWorker(worker)

    var threads: array[4, Thread[AppendArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], appendWorker, AppendArg(worker: i))

    discard gHookEntered.recv()
    check gHookEnabled.load()

    var probe: Thread[int]
    createThread(probe, probeWorker, 0)
    discard gProbeStarted.recv()

    gHookEnabled.store(false)
    gHookRelease.send(true)
    joinThread(probe)
    check gProbeOk

    var waited = 0
    while waited < 5000:
      var allReady = true
      for i in 0 ..< gAppendCount.len:
        if gAppendCount[i].load() < 20:
          allReady = false
      if allReady:
        break
      sleep(10)
      waited += 10
    for i in 0 ..< gAppendCount.len:
      check gAppendCount[i].load() >= 20

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
      expected += gAppendCount[i].load()
    check expected >= 80
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

    var store = newRuntimeStateStore(
      dir, ledgerRetentionDays = 1.0, ledgerCompactIntervalSec = 1.0)
    let ledger = store.deliveryLedger()
    let old = epochMs() - 10 * 86_400_000'i64
    check ledger.recordPending(DeliveryRecord(
      id: "keep", userId: "u", channel: ckSlack, channelId: "c",
      textHash: "h", state: dlsPending,
      createdAtMs: old, updatedAtMs: old)).isOk

    gHookEnabled.store(true)
    gStopReturned.store(false)
    store.onCompactStart = blockingHook
    let workerRes = startLedgerCompactionWorker(addr store, 1.0)
    check workerRes.isOk
    let worker = workerRes.get()
    check worker != nil

    discard gHookEntered.recv()

    gWorkerToStop = worker
    var stopper: Thread[int]
    createThread(stopper, stopWorker, 0)
    var waited = 0
    while not worker.stopping.load() and waited < 2000:
      sleep(1)
      waited += 1
    check worker.stopping.load()
    check not gStopReturned.load()

    gHookEnabled.store(false)
    gHookRelease.send(true)
    joinThread(stopper)
    gWorkerToStop = nil
    check gStopReturned.load()
    check store.ledgerLastCompactError().len == 0

    let loaded = store.deliveryLedger().loadAll()
    check loaded.isOk
    var kept = false
    for record in loaded.get():
      if record.id == "keep":
        kept = true
        check record.state == dlsPending
    check kept
