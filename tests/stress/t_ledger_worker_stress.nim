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
  gHookEnabled:    Atomic[bool]
  gHookEntered:    Channel[bool]
  gHookRelease:    Channel[bool]
  gProbeStarted:   Channel[bool]
  gStopStarted:    Channel[bool]
  gStopReturned:   Atomic[bool]
  gProbeOk:        bool

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
        inc gAppendCount[arg.worker]
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

proc stopWorker(worker: LedgerCompactionWorker) {.thread.} =
  {.cast(gcsafe).}:
    gStopStarted.send(true)
    stopLedgerCompactionWorker(worker)
    gStopReturned.store(true)

proc openChannels() =
  gHookEntered.open(1)
  gHookRelease.open(1)
  gProbeStarted.open(1)
  gStopStarted.open(1)

proc closeChannels() =
  gHookEntered.close()
  gHookRelease.close()
  gProbeStarted.close()
  gStopStarted.close()

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
    gHookEnabled.store(true)
    for i in 0 ..< gAppendCount.len:
      gAppendCount[i] = 0
    openChannels()

    store.onCompactStart = blockingHook
    store.onAppendStart = appendStartHook
    let worker = startLedgerCompactionWorker(
      store, 1.0, newLogger("stress.ledger", lvlError))
    check worker != nil
    defer:
      stopLedgerCompactionWorker(worker)
      closeChannels()

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

    gHookEnabled.store(true)
    gStopReturned.store(false)
    openChannels()
    store.onCompactStart = blockingHook
    let worker = startLedgerCompactionWorker(
      store, 1.0, newLogger("stress.ledger", lvlError))
    check worker != nil
    defer: closeChannels()

    discard gHookEntered.recv()

    var stopper: Thread[LedgerCompactionWorker]
    createThread(stopper, stopWorker, worker)
    discard gStopStarted.recv()
    check not gStopReturned.load()

    gHookEnabled.store(false)
    gHookRelease.send(true)
    joinThread(stopper)
    check gStopReturned.load()
    check store.ledgerLastCompactError().len == 0
