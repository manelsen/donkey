## Schedule watermark store adapter tests.
##
## The store is a single JSON document in the state dir
## (`{stateDir}/schedules.json`) holding one record per schedule id:
##
##   {"v": 1, "schedules": [
##     {"id": "...", "last_run_at_ms": 0, "created_at_ms": 0}
##   ]}
##
## These tests exercise the port contract used by `tickSchedule`, restart
## reload (two instances), overwrite semantics, corruption, forward-compatible
## fields, `loadAll` and on-disk permissions.

import std/[atomics, json, options, os, sets, unittest]
import results
import donkey/adapters/state/schedule_store
import donkey/app/automation_runtime

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_schedule_store_" & tag & "_" &
                           $getCurrentProcessId())
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

proc watermark(id: string; lastRunAtMs, createdAtMs: int64): ScheduleWatermark =
  ScheduleWatermark(id: id, lastRunAtMs: lastRunAtMs, createdAtMs: createdAtMs)

proc recordIds(path: string; wanted: string): int =
  ## Counts raw records for `wanted`, independent of the adapter's reader.
  let doc = parseFile(path)
  for node in doc["schedules"]:
    if node["id"].getStr == wanted:
      inc result

type
  SaveArg = object
    stateDir: string
    worker: int
    count: int

var gSaveErrors: Atomic[int]

proc saveWorker(arg: SaveArg) {.thread.} =
  {.cast(gcsafe).}:
    let store = newScheduleStoreRef(arg.stateDir)
    for i in 0 ..< arg.count:
      let id = "schedule-" & $arg.worker & "-" & $i
      let saved = store.save(watermark(id, 1_000'i64 + i, 1_000'i64))
      if saved.isErr:
        discard gSaveErrors.fetchAdd(1)

suite "schedule watermark store":

  test "saves and reloads all three fields; unknown id is none":
    let dir = freshDir("roundtrip")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    check store.path == dir / ScheduleFileName
    check store.save(watermark("daily", 1_700_000_000_123'i64,
                               1_600_000_000_000'i64)).isOk

    let loaded = store.load("daily")
    check loaded.isOk
    check loaded.get().isSome
    let state = loaded.get().get()
    check state.id == "daily"
    check state.lastRunAtMs == 1_700_000_000_123'i64
    check state.createdAtMs == 1_600_000_000_000'i64
    check state == watermark("daily", 1_700_000_000_123'i64,
                             1_600_000_000_000'i64)

    let missing = store.load("not-a-schedule")
    check missing.isOk
    check missing.get().isNone

  test "the port returned by newScheduleStore is wired and reads the file":
    let dir = freshDir("port")
    defer: cleanup(dir)

    let port = newScheduleStore(dir)
    check port.hasScheduleStore
    check port.save(watermark("every-minute", 42'i64, 7'i64)).isOk

    let loaded = port.load("every-minute")
    check loaded.isOk
    check loaded.get().isSome
    check loaded.get().get().lastRunAtMs == 42'i64
    check port.load("absent").get().isNone

  test "two instances see each other's writes":
    let dir = freshDir("instances")
    defer: cleanup(dir)

    let first = newScheduleStoreRef(dir)
    let second = newScheduleStoreRef(dir)
    check first.save(watermark("from-first", 100'i64, 10'i64)).isOk
    check second.save(watermark("from-second", 200'i64, 20'i64)).isOk

    check first.load("from-second").get().get() ==
      watermark("from-second", 200'i64, 20'i64)
    check second.load("from-first").get().get() ==
      watermark("from-first", 100'i64, 10'i64)

  test "concurrent saves of different ids keep every record":
    let dir = freshDir("concurrent")
    defer: cleanup(dir)

    const Workers = 4
    const PerWorker = 10
    gSaveErrors.store(0)
    var threads: array[Workers, Thread[SaveArg]]
    for i in 0 ..< Workers:
      createThread(threads[i], saveWorker, SaveArg(stateDir: dir, worker: i,
                                                   count: PerWorker))
    joinThreads(threads)

    check gSaveErrors.load() == 0
    let all = newScheduleStoreRef(dir).loadAll()
    check all.isOk
    check all.get().len == Workers * PerWorker
    var ids = initHashSet[string]()
    for state in all.get():
      ids.incl(state.id)
    check ids.len == Workers * PerWorker

  test "saving the same id twice overwrites instead of duplicating":
    let dir = freshDir("overwrite")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    check store.save(watermark("job", 10'i64, 5'i64)).isOk
    check store.save(watermark("job", 20'i64, 5'i64)).isOk

    check recordIds(store.path, "job") == 1
    let loaded = store.load("job")
    check loaded.get().isSome
    check loaded.get().get().lastRunAtMs == 20'i64
    check loaded.get().get().createdAtMs == 5'i64
    check store.loadAll().get().len == 1

  test "corrupt JSON is an err and leaves the file untouched":
    let dir = freshDir("corrupt")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    writeFile(store.path, "{\"v\":1,\"schedules\":[{\"id\":\"job\"")
    let before = readFile(store.path)

    let loaded = store.load("job")
    check loaded.isErr
    check readFile(store.path) == before

    let all = store.loadAll()
    check all.isErr
    check readFile(store.path) == before

    ## A write must fail closed on a corrupt document: silently replacing it
    ## would erase every watermark the operator might still recover.
    check store.save(watermark("job", 1'i64, 1'i64)).isErr
    check readFile(store.path) == before

  test "unknown future fields and a record without id are tolerated":
    let dir = freshDir("future")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    writeFile(store.path, """{"v": 1, "future_top_level": true, "schedules": [
      {"id": "known", "last_run_at_ms": 30, "created_at_ms": 10,
       "future_field": {"nested": [1, 2, 3]}},
      {"last_run_at_ms": 99, "created_at_ms": 99},
      {"id": "", "last_run_at_ms": 98, "created_at_ms": 98}
    ]}""")

    let loaded = store.load("known")
    check loaded.isOk
    check loaded.get().isSome
    check loaded.get().get() == watermark("known", 30'i64, 10'i64)
    check store.loadAll().get().len == 1

    ## The tolerated document is still writable; the skipped records stay
    ## skipped and the known record keeps working.
    check store.save(watermark("second", 50'i64, 40'i64)).isOk
    check store.load("known").get().get().lastRunAtMs == 30'i64
    check store.load("second").get().get().createdAtMs == 40'i64
    check store.loadAll().get().len == 2

  test "loadAll returns every recorded id":
    let dir = freshDir("loadall")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    for i in 0 ..< 3:
      check store.save(watermark("id-" & $i, int64(i), int64(i * 10))).isOk

    let all = store.loadAll()
    check all.isOk
    var ids = initHashSet[string]()
    for state in all.get():
      ids.incl(state.id)
    check ids == toHashSet(["id-0", "id-1", "id-2"])

  test "file is 0600 and its directory is 0700":
    let dir = freshDir("perms")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    check store.save(watermark("job", 1'i64, 1'i64)).isOk

    when defined(posix):
      let filePerms = getFilePermissions(store.path)
      check fpUserRead in filePerms
      check fpUserWrite in filePerms
      check fpGroupRead notin filePerms
      check fpGroupWrite notin filePerms
      check fpOthersRead notin filePerms
      check fpOthersWrite notin filePerms

      let dirPerms = getFilePermissions(dir)
      check fpUserRead in dirPerms
      check fpUserWrite in dirPerms
      check fpUserExec in dirPerms
      check fpGroupRead notin dirPerms
      check fpGroupWrite notin dirPerms
      check fpGroupExec notin dirPerms
      check fpOthersRead notin dirPerms
      check fpOthersWrite notin dirPerms
      check fpOthersExec notin dirPerms
