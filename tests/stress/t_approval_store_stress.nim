## Stress: approval store concurrency and cap enforcement.

import std/[atomics, os, sets, strutils, unittest]
import results
import donkey/adapters/state/approval_store
import donkey/core/pipeops
import donkey/core/security/approval

let stressDir = getTempDir() / ("donkey_stress_approval_" & $getCurrentProcessId())

type
  CreateArg = object
    path:   string
    userId: string
    index:  int

  DecideArg = object
    path:   string
    id:     string
    userId: string
    index:  int

var
  gCreateIds:   array[32, string]
  gCreateOk:    array[32, bool]
  gDecideOk:    array[32, bool]
  gReadErrors:  Atomic[int]
  gReaderReady: Atomic[int]
  gWritersDone: Atomic[bool]

proc createWorker(arg: CreateArg) {.thread.} =
  {.cast(gcsafe).}:
    let store = newApprovalStore(arg.path)
    let res = store.create(arg.userId, "telegram", "bash", "stress", 60_000)
    gCreateOk[arg.index] = res.isOk
    if res.isOk:
      gCreateIds[arg.index] = res.get().id

proc readerWorker(path: string) {.thread.} =
  {.cast(gcsafe).}:
    discard gReaderReady.fetchAdd(1)
    while not gWritersDone.load():
      if newApprovalStore(path).listPending().isErr:
        discard gReadErrors.fetchAdd(1)
      sleep(1)

proc decideWorker(arg: DecideArg) {.thread.} =
  {.cast(gcsafe).}:
    let store = newApprovalStore(arg.path)
    gDecideOk[arg.index] = store.decide(arg.id, arg.userId, true).isOk

suite "approval store stress":

  test "concurrent creates use unique ids and are all listable":
    let dir = stressDir / "create"
    removeDir(dir)
    defer: removeDir(dir)
    let path = dir / "approvals.json"

    gReadErrors.store(0)
    gReaderReady.store(0)
    gWritersDone.store(false)
    var reader: Thread[string]
    createThread(reader, readerWorker, path)
    while gReaderReady.load() == 0:
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
