## Schedule store adapter tests.
##
## The store is a single JSON document in the state dir
## (`{stateDir}/schedules.json`) holding one record per schedule id. Since the
## schema version bump, a row carries the full spec plus the runtime watermark:
##
##   {"v": 2, "schedules": [
##     {"id": "...", "cron_expr": "*/5 * * * *", "tz_offset_minutes": 0,
##      "user_id": "...", "channel": "telegram", "payload": "...",
##      "catch_up": "once", "enabled": true,
##      "created_at_ms": 0, "last_run_at_ms": 0, "last_fire_at_ms": 0}
##   ]}
##
## A v1 document (watermarks only) is still accepted: each row loads with empty
## spec fields, keeps its watermark, and is flagged through `loadWarning`. The
## next save upgrades the document to v2 without losing the watermark.
##
## These tests exercise both APIs: the `ScheduleStorePort` contract used by
## `tickSchedule` (load/save watermark) and the record API used by the ctl and
## the daemon tick (`loadAllRecords`/`upsert`/`insertIfAbsent`/`setEnabled`/
## `remove`). Restart reload (two instances), overwrite semantics, atomic
## "insert unless the id exists" under thread contention, corruption,
## forward-compatible fields, `loadAll` and on-disk permissions are covered as
## well.

import std/[atomics, json, options, os, sets, strutils, unittest]
import results
import donkey/adapters/state/schedule_store
import donkey/app/automation_runtime
import donkey/domain/automation/schedule_pure

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

proc watermark(id: string; lastRunAtMs, createdAtMs: int64;
               lastFireAtMs = 0'i64): ScheduleWatermark =
  ScheduleWatermark(id: id, lastRunAtMs: lastRunAtMs, createdAtMs: createdAtMs,
                    lastFireAtMs: lastFireAtMs)

proc fullRecord(
  id = "daily";
  payload = "run the report";
  cron = "*/5 * * * *";
  catchUp = scOnce;
  enabled = true;
): ScheduleRecord =
  ## A row with every persisted field set to a distinct, recognisable value.
  ScheduleRecord(
    spec: ScheduleSpec(
      id: id,
      cronExpr: cron,
      tzOffsetMinutes: -180,
      userId: "user-42",
      channel: "telegram",
      payload: payload,
      catchUp: catchUp,
      enabled: enabled,
      createdAtMs: 1_600_000_000_000'i64,
    ),
    lastRunAtMs: 1_700_000_000_123'i64,
    lastFireAtMs: 1_700_000_000_000'i64,
  )

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

  InsertArg = object
    stateDir: string
    id: string
    payload: string

var gSaveErrors: Atomic[int]
var gInsertWins: Atomic[int]
var gInsertErrors: Atomic[int]

proc saveWorker(arg: SaveArg) {.thread.} =
  {.cast(gcsafe).}:
    let store = newScheduleStoreRef(arg.stateDir)
    for i in 0 ..< arg.count:
      let id = "schedule-" & $arg.worker & "-" & $i
      let saved = store.save(watermark(id, 1_000'i64 + i, 1_000'i64))
      if saved.isErr:
        discard gSaveErrors.fetchAdd(1)

proc insertWorker(arg: InsertArg) {.thread.} =
  ## Every worker races for the *same* id: only one may be told it inserted.
  {.cast(gcsafe).}:
    let store = newScheduleStoreRef(arg.stateDir)
    let inserted = store.insertIfAbsent(ScheduleRecord(
      spec: ScheduleSpec(
        id: arg.id,
        cronExpr: "*/5 * * * *",
        tzOffsetMinutes: 0,
        userId: "user-1",
        channel: "telegram",
        payload: arg.payload,
        catchUp: scSkip,
        enabled: true,
        createdAtMs: 1_000'i64,
      ),
      lastRunAtMs: 1_000'i64,
    ))
    if inserted.isErr:
      discard gInsertErrors.fetchAdd(1)
    elif inserted.get():
      discard gInsertWins.fetchAdd(1)

suite "schedule watermark store (port)":
  ## Fixtures in this suite exercise the runtime-facing port: load/save only
  ## know about the watermark, and must keep leaving the spec of an existing
  ## row untouched.

  test "saves and reloads all three fields; unknown id is none":
    let dir = freshDir("roundtrip")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    check store.path == dir / ScheduleFileName
    ## `save` is update-only now: the row is the schedule definition, so a
    ## watermark for an unknown id must not create a phantom.
    check store.upsert(fullRecord()).isOk
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
                             1_600_000_000_000'i64,
                             lastFireAtMs = 1_700_000_000_000'i64)

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
    writeFile(store.path, "{\"v\":2,\"schedules\":[{\"id\":\"job\"")
    let before = readFile(store.path)

    let loaded = store.load("job")
    check loaded.isErr
    check readFile(store.path) == before

    let all = store.loadAll()
    check all.isErr
    check readFile(store.path) == before

    let records = store.loadAllRecords()
    check records.isErr
    check readFile(store.path) == before

    ## A write must fail closed on a corrupt document: silently replacing it
    ## would erase every watermark the operator might still recover.
    check store.save(watermark("job", 1'i64, 1'i64)).isErr
    check store.upsert(fullRecord("job")).isErr
    check store.remove("job").isErr
    check readFile(store.path) == before

  test "unknown future fields and a record without id are tolerated":
    let dir = freshDir("future")
    defer: cleanup(dir)

    ## Declared v2 fixture: the spec fields are present, plus a field this
    ## version does not know and a spec-less row that must be skipped.
    let store = newScheduleStoreRef(dir)
    writeFile(store.path, """{"v": 2, "future_top_level": true, "schedules": [
      {"id": "known", "cron_expr": "* * * * *", "tz_offset_minutes": 0,
       "user_id": "u", "channel": "telegram", "payload": "p",
       "catch_up": "once", "enabled": true,
       "last_run_at_ms": 30, "created_at_ms": 10,
       "future_field": {"nested": [1, 2, 3]}},
      {"last_run_at_ms": 99, "created_at_ms": 99},
      {"id": "", "last_run_at_ms": 98, "created_at_ms": 98}
    ]}""")

    let loaded = store.load("known")
    check loaded.isOk
    check loaded.get().isSome
    check loaded.get().get() == watermark("known", 30'i64, 10'i64)
    check store.loadAll().get().len == 1

    let records = store.loadAllRecords()
    check records.isOk
    check records.get().len == 1
    check records.get()[0].spec.catchUp == scOnce
    check records.get()[0].spec.enabled
    check records.get()[0].loadWarning.len == 0

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

suite "schedule record store (spec + watermark)":

  test "full record round-trips including channel, catchUp and enabled":
    let dir = freshDir("record-roundtrip")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    let expected = fullRecord()
    check expected.spec.createdAtMs > 0
    check store.upsert(expected).isOk

    let all = store.loadAllRecords()
    check all.isOk
    check all.get().len == 1
    let got = all.get()[0]
    check got.spec.id == "daily"
    check got.spec.cronExpr == "*/5 * * * *"
    check got.spec.tzOffsetMinutes == -180
    check got.spec.userId == "user-42"
    check got.spec.channel == "telegram"
    check got.spec.payload == "run the report"
    check got.spec.catchUp == scOnce
    check got.spec.enabled
    check got.spec.createdAtMs == 1_600_000_000_000'i64
    check got.lastRunAtMs == 1_700_000_000_123'i64
    check got.lastFireAtMs == 1_700_000_000_000'i64
    check got.loadWarning.len == 0

    ## The document is written in the current schema version.
    let doc = parseFile(store.path)
    check doc["v"].getInt == 2
    check doc["schedules"][0]["channel"].getStr == "telegram"
    check doc["schedules"][0]["catch_up"].getStr == "once"
    check doc["schedules"][0]["enabled"].getBool

    ## A second instance reloads the same record: restart-safe.
    let reopened = newScheduleStoreRef(dir).loadAllRecords()
    check reopened.isOk
    check reopened.get()[0].spec.payload == "run the report"
    check reopened.get()[0].lastFireAtMs == 1_700_000_000_000'i64

    ## The runtime port still reads the watermark out of the full record.
    check store.load("daily").get().get() ==
      watermark("daily", 1_700_000_000_123'i64, 1_600_000_000_000'i64,
                lastFireAtMs = 1_700_000_000_000'i64)

  test "upsert then edit the payload: watermark and createdAtMs preserved":
    let dir = freshDir("record-edit")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    let original = fullRecord()
    check store.upsert(original).isOk

    ## A spec edit arrives without the read-modify-write watermark: all three
    ## timing fields are zero (omitted) and must keep their stored values.
    var edited = original
    edited.spec.payload = "run it twice"
    edited.spec.cronExpr = "0 * * * *"
    edited.spec.catchUp = scSkip
    edited.spec.enabled = false
    edited.spec.createdAtMs = 0
    edited.lastRunAtMs = 0
    edited.lastFireAtMs = 0
    check store.upsert(edited).isOk

    let all = store.loadAllRecords()
    check all.isOk
    check all.get().len == 1
    let got = all.get()[0]
    check got.spec.payload == "run it twice"
    check got.spec.cronExpr == "0 * * * *"
    check got.spec.catchUp == scSkip
    check not got.spec.enabled
    check got.spec.createdAtMs == original.spec.createdAtMs
    check got.lastRunAtMs == original.lastRunAtMs
    check got.lastFireAtMs == original.lastFireAtMs

    ## An explicit non-zero watermark from a tick is still accepted.
    var lastRunAtMs = original.lastRunAtMs + 60_000'i64
    var ticked = got
    ticked.lastRunAtMs = lastRunAtMs
    check store.upsert(ticked).isOk
    check store.loadAllRecords().get()[0].lastRunAtMs == lastRunAtMs

  test "remove then loadAllRecords does not contain it":
    let dir = freshDir("record-remove")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    check store.upsert(fullRecord("keep-me")).isOk
    check store.upsert(fullRecord("delete-me")).isOk
    check store.loadAllRecords().get().len == 2

    check store.remove("delete-me").isOk
    let all = store.loadAllRecords()
    check all.isOk
    check all.get().len == 1
    check all.get()[0].spec.id == "keep-me"
    check store.load("delete-me").get().isNone

    ## Removal is idempotent: a second remove is still ok.
    check store.remove("delete-me").isOk
    check store.remove("never-existed").isOk

  test "v1 watermarks-only file loads with a warning and keeps the watermark":
    let dir = freshDir("v1")
    defer: cleanup(dir)

    let store = newScheduleStoreRef(dir)
    writeFile(store.path, """{"v": 1, "schedules": [
      {"id": "legacy", "last_run_at_ms": 123, "created_at_ms": 100}
    ]}""")

    ## Chosen behaviour: accept, do not drop the watermark, flag the row.
    let all = store.loadAllRecords()
    check all.isOk
    check all.get().len == 1
    let legacy = all.get()[0]
    check legacy.spec.id == "legacy"
    check legacy.spec.cronExpr == ""
    check legacy.spec.userId == ""
    check legacy.spec.channel == ""
    check legacy.spec.payload == ""
    check not legacy.spec.enabled
    check legacy.spec.createdAtMs == 100'i64
    check legacy.lastRunAtMs == 123'i64
    check legacy.lastFireAtMs == 0'i64
    check legacy.loadWarning.len > 0

    ## The port keeps working on the same row.
    check store.load("legacy").get().get() == watermark("legacy", 123'i64, 100'i64)

    ## A later upsert fills the spec, keeps the watermark and rewrites v2.
    var upgraded = fullRecord("legacy")
    upgraded.spec.createdAtMs = 0
    upgraded.lastRunAtMs = 0
    upgraded.lastFireAtMs = 0
    check store.upsert(upgraded).isOk

    let reloaded = store.loadAllRecords()
    check reloaded.isOk
    check reloaded.get()[0].spec.payload == "run the report"
    check reloaded.get()[0].lastRunAtMs == 123'i64
    check reloaded.get()[0].spec.createdAtMs == 100'i64
    check reloaded.get()[0].loadWarning.len == 0
    check parseFile(store.path)["v"].getInt == 2

  test "a document without a schedules array is an error, not an empty store":
    let dir = freshDir("no-schedules")
    defer: cleanup(dir)
    let path = dir / ScheduleFileName
    writeFile(path, """{"v":2}""")
    let store = newScheduleStoreRef(dir)
    check store.loadAllRecords().isErr
    check store.load("daily").isErr

  test "an empty object is an empty store":
    let dir = freshDir("empty-object")
    defer: cleanup(dir)
    writeFile(dir / ScheduleFileName, """{}""")
    let store = newScheduleStoreRef(dir)
    check store.loadAllRecords().isOk
    check store.loadAllRecords().get().len == 0

  test "a cross-process lock file guards the document":
    let dir = freshDir("lockfile")
    defer: cleanup(dir)
    let store = newScheduleStoreRef(dir)
    check store.upsert(fullRecord()).isOk
    check fileExists(dir / (ScheduleFileName & ".lock"))

suite "schedule store — atomic insertIfAbsent":

  test "insertIfAbsent persists a new id and reports true":
    let dir = freshDir("insert_new")
    defer: cleanup(dir)
    let store = newScheduleStoreRef(dir)

    let inserted = store.insertIfAbsent(fullRecord())
    check inserted.isOk
    check inserted.get()

    let loaded = store.loadRecord("daily")
    check loaded.isOk
    check loaded.get().isSome
    check loaded.get().get().spec.payload == "run the report"
    check loaded.get().get().spec.createdAtMs == 1_600_000_000_000'i64
    check loaded.get().get().lastRunAtMs == 1_700_000_000_123'i64

  test "insertIfAbsent refuses an existing id without touching the file":
    let dir = freshDir("insert_dup")
    defer: cleanup(dir)
    let store = newScheduleStoreRef(dir)

    check store.insertIfAbsent(fullRecord(payload = "first")).isOk
    let before = readFile(store.path)

    let duplicate = store.insertIfAbsent(fullRecord(payload = "second"))
    check duplicate.isOk
    check not duplicate.get()
    ## The losing insert must not rewrite the row (nor its watermark).
    check readFile(store.path) == before
    check store.loadRecord("daily").get().get().spec.payload == "first"
    check recordIds(store.path, "daily") == 1

  test "insertIfAbsent trims the id and refuses an empty one":
    let dir = freshDir("insert_id")
    defer: cleanup(dir)
    let store = newScheduleStoreRef(dir)

    check store.insertIfAbsent(fullRecord(id = "  daily  ")).get()
    check store.loadRecord("daily").get().isSome
    let blank = store.insertIfAbsent(fullRecord(id = "   "))
    check blank.isErr
    check "empty schedule id" in blank.error

  test "insertIfAbsent fails closed on a corrupt document":
    let dir = freshDir("insert_corrupt")
    defer: cleanup(dir)
    let store = newScheduleStoreRef(dir)
    writeFile(store.path, """{"v":2,"schedules":[""")
    let before = readFile(store.path)

    let inserted = store.insertIfAbsent(fullRecord())
    check inserted.isErr
    check "cannot parse schedule store" in inserted.error
    check readFile(store.path) == before

  test "concurrent insertIfAbsent of the same id lets exactly one win":
    let dir = freshDir("insert_race")
    defer: cleanup(dir)

    const Workers = 8
    gInsertWins.store(0)
    gInsertErrors.store(0)
    var threads: array[Workers, Thread[InsertArg]]
    for i in 0 ..< Workers:
      createThread(threads[i], insertWorker,
                   InsertArg(stateDir: dir, id: "race",
                             payload: "worker-" & $i))
    joinThreads(threads)

    check gInsertErrors.load() == 0
    check gInsertWins.load() == 1
    check recordIds(dir / ScheduleFileName, "race") == 1

    let all = newScheduleStoreRef(dir).loadAllRecords()
    check all.isOk
    check all.get().len == 1
    check all.get()[0].spec.id == "race"

