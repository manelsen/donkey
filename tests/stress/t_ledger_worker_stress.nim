## Stress: a ledger compaction job (on the blocking executor) racing with
## delivery appends.

import std/[atomics, monotimes, os, strutils, times, unittest]
import chronos
import donkey/adapters/state/runtime_store
import donkey/app/blocking_executor
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
  gReaderPort:     DeliveryLedgerPort
  gAppendCount:    array[4, Atomic[int]]
  gAppendErrors:   Atomic[int]
  gStopAppenders:  Atomic[bool]
  gHookEnabled:    Atomic[bool]
  gHookEntered:    Channel[bool]
  gHookRelease:    Channel[bool]
  gProbeStarted:   Channel[bool]
  gReaderErrors:   Atomic[int]
  gStopReader:     Atomic[bool]
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

proc readerWorker(_: int) {.thread.} =
  {.cast(gcsafe).}:
    while not gStopReader.load():
      if gReaderPort.loadAll().isErr:
        discard gReaderErrors.fetchAdd(1)
      sleep(1)



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
    gReaderPort = store.deliveryLedger()
    gProbeOk = false
    gAppendErrors.store(0)
    gReaderErrors.store(0)
    gStopReader.store(false)
    gStopAppenders.store(false)
    gHookEnabled.store(true)
    for i in 0 ..< gAppendCount.len:
      gAppendCount[i].store(0)

    store.onCompactStart = blockingHook
    store.onAppendStart = appendStartHook
    var reader: Thread[int]
    createThread(reader, readerWorker, 0)

    var threads: array[4, Thread[AppendArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], appendWorker, AppendArg(worker: i))

    ## Compaction of a missing ledger returns before the hook: start the job
    ## once the appenders have written it.
    var waitedForLedger = 0
    while gAppendCount[0].load() == 0 and waitedForLedger < 5000:
      sleep(5)
      waitedForLedger += 5
    let job = runOffLoop(compactLedgerJob,
                         LedgerCompactionJob(store: addr store, force: true))

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
    check (waitFor job).isOk
    check inMilliseconds(getMonoTime() - started) < 2000
    check store.ledgerLastCompactError().len == 0

    gStopReader.store(true)
    joinThread(reader)
    check gReaderErrors.load() == 0

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

  test "the job finishes only after its compaction (shutdown awaits it)":
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
    store.onCompactStart = blockingHook
    let job = runOffLoop(compactLedgerJob,
                         LedgerCompactionJob(store: addr store, force: true))

    discard gHookEntered.recv()
    waitFor sleepAsync(chronos.milliseconds(100))
    check not job.finished   ## the daemon's shutdown awaits this future

    gHookEnabled.store(false)
    gHookRelease.send(true)
    check (waitFor job).isOk
    check store.ledgerLastCompactError().len == 0

    let loaded = store.deliveryLedger().loadAll()
    check loaded.isOk
    var kept = false
    for record in loaded.get():
      if record.id == "keep":
        kept = true
        check record.state == dlsPending
    check kept
