## Stress: approval store concurrency and cap enforcement.

import std/[atomics, os, sets, strutils, unittest]
import results
import donkey/adapters/state/approval_store
import donkey/core/pipeops
import donkey/core/security/approval

let stressDir = getTempDir() / ("donkey_stress_approval_" & $getCurrentProcessId())

type
  CreateArg = object
    path:       string
    userId:     string
    index:      int
    signalLock: bool

  DecideArg = object
    path:   string
    id:     string
    userId: string
    index:  int

var
  gCreateIds: array[32, string]
  gCreateOk:  array[32, bool]
  gDecideOk:  array[32, bool]
  gBlockedOk:      Atomic[bool]
  gBlockedCompleted: Atomic[bool]
  gReadErrors:     Atomic[int]
  gReadCount:      Atomic[int]
  gReaderReady:    Atomic[bool]
  gWritersDone:    Atomic[bool]
  gLockWait:       Channel[bool]
  gBlockedWriter:  Thread[CreateArg]
  gReaderOk:       bool

proc createWorker(arg: CreateArg) {.thread.} =
  {.cast(gcsafe).}:
    let store = newApprovalStore(arg.path)
    let res = store.create(arg.userId, "telegram", "bash", "stress", 60_000)
    gCreateOk[arg.index] = res.isOk
    if res.isOk:
      gCreateIds[arg.index] = res.get().id

proc blockedCreateWorker(arg: CreateArg) {.thread.} =
  {.cast(gcsafe).}:
    let store = newApprovalStore(arg.path)
    if arg.signalLock:
      store.onLockWait = proc() {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          {.cast(raises: []).}:
            gLockWait.send(true)
    gBlockedOk.store(
      store.create(arg.userId, "telegram", "bash", "blocked", 60_000).isOk)
    gBlockedCompleted.store(true)

proc readerWorker(path: string) {.thread.} =
  {.cast(gcsafe).}:
    let first = newApprovalStore(path).listPending()
    if first.isErr:
      discard gReadErrors.fetchAdd(1)
    else:
      discard gReadCount.fetchAdd(1)
    gReaderReady.store(true)
    while not gWritersDone.load():
      let pending = newApprovalStore(path).listPending()
      if pending.isErr:
        discard gReadErrors.fetchAdd(1)
      else:
        discard gReadCount.fetchAdd(1)
      sleep(1)

proc decideWorker(arg: DecideArg) {.thread.} =
  {.cast(gcsafe).}:
    gDecideOk[arg.index] =
      newApprovalStore(arg.path).decide(arg.id, arg.userId, true).isOk

suite "approval store stress":

  test "concurrent creates use unique ids and are all listable":
    let dir = stressDir / "create"
    removeDir(dir)
    defer: removeDir(dir)
    let path = dir / "approvals.json"

    gReadErrors.store(0)
    gReadCount.store(0)
    gReaderReady.store(false)
    gWritersDone.store(false)
    var reader: Thread[string]
    createThread(reader, readerWorker, path)
    while not gReaderReady.load():
      sleep(1)

    var threads: array[16, Thread[CreateArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], createWorker,
                   CreateArg(path: path, userId: "u" & $i, index: i))
    for i in 0 ..< threads.len:
      joinThread(threads[i])
    gWritersDone.store(true)
    joinThread(reader)
    check gReadErrors.load() == 0
    check gReadCount.load() > 0

    var ids = initHashSet[string]()
    for i in 0 ..< threads.len:
      check gCreateOk[i]
      check gCreateIds[i].len == ApprovalIdLength
      ids.incl(gCreateIds[i])
    check ids.len == threads.len

    let pending = newApprovalStore(path).listPending()
    check pending.isOk
    check pending.get().len == threads.len

  test "concurrent creates respect the per-user cap":
    let dir = stressDir / "cap"
    removeDir(dir)
    defer: removeDir(dir)
    let path = dir / "approvals.json"

    var threads: array[16, Thread[CreateArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], createWorker,
                   CreateArg(path: path, userId: "same-user", index: i))
    for i in 0 ..< threads.len:
      joinThread(threads[i])

    var successes = 0
    for i in 0 ..< threads.len:
      if gCreateOk[i]:
        inc successes
    check successes == MaxPendingPerUser

    let pending = newApprovalStore(path).listPending("same-user")
    check pending.isOk
    check pending.get().len == MaxPendingPerUser

  test "concurrent decisions allow exactly one winner":
    let dir = stressDir / "decide"
    removeDir(dir)
    defer: removeDir(dir)
    let path = dir / "approvals.json"
    let created = newApprovalStore(path).create(
      "owner", "slack", "bash", "stress", 60_000)
    check created.isOk
    let request = created.get()

    var threads: array[12, Thread[DecideArg]]
    for i in 0 ..< threads.len:
      createThread(threads[i], decideWorker,
                   DecideArg(path: path, id: request.id,
                             userId: "owner", index: i))
    for i in 0 ..< threads.len:
      joinThread(threads[i])

    var winners = 0
    for i in 0 ..< threads.len:
      if gDecideOk[i]:
        inc winners
    check winners == 1
    check newApprovalStore(path).status(request.id).get() == apsApproved

  test "reader sees a stable store while a create waits for the lock":
    let dir = stressDir / "locked"
    removeDir(dir)
    defer: removeDir(dir)
    let path = dir / "approvals.json"
    let store = newApprovalStore(path)
    check store.create("owner", "telegram", "bash", "first", 60_000).isOk

    gBlockedOk.store(false)
    gBlockedCompleted.store(false)
    gReaderOk = false
    gLockWait.open(1)

    let held = store.withApprovalLock(
      proc(): Result[void, string] {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          {.cast(raises: []).}:
            createThread(gBlockedWriter, blockedCreateWorker,
                         CreateArg(path: path, userId: "blocked", index: 0,
                                   signalLock: true))
          {.cast(raises: []).}:
            discard gLockWait.recv()
          if gBlockedCompleted.load():
            return err("blocked writer completed while the lock was held")
          gReaderOk = store.listPending().isOk
          ok())

    check held.isOk
    joinThread(gBlockedWriter)
    gLockWait.close()
    check gBlockedOk.load()
    check gReaderOk
    check store.listPending().get().len == 2
