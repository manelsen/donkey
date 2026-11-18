## `donkey ctl schedule` tests — US-007 management slice.
##
## The handlers are called directly (no daemon, no socket, no process) against
## a temporary state dir. `ctlSchedule*` returns the rendered stdout text as
## the `Result` value, so the tests can assert what the operator sees without
## capturing stdout.
##
## Covered: empty list (human + `--json`), add round-trip through the real
## store, duplicate/invalid/concurrent add, show of a known/unknown id, remove,
## and the disable/enable round-trip: disabling preserves both watermarks, while
## re-enabling advances `lastRunAtMs` so a daemon that was stopped for the whole
## disabled period cannot catch up on it.

import std/[atomics, json, options, os, strutils, unittest]
import results
import donkey/adapters/state/schedule_store
import donkey/app/automation_runtime
import donkey/domain/automation/schedule_pure
import donkey/ctl_handler

const
  FixedNow = 1_700_000_040_000'i64
    ## 2023-11-14T22:14:00Z: fixed creation clock for every test.
  HourMs = 3_600_000'i64

type
  Recorder = ref object
    instants: seq[int64]

  AddArg = object
    stateDir: string
    id: string

var gAddWins: Atomic[int]
var gAddLosers: Atomic[int]

proc makeEnqueue(rec: Recorder): ScheduleEnqueueFn =
  result = proc(
    spec: ScheduleSpec; instantMs: int64
  ): Result[void, string] {.gcsafe, raises: [].} =
    rec.instants.add(instantMs)
    ok()

proc addWorker(arg: AddArg) {.thread.} =
  ## Both workers add the same id; the store must accept exactly one.
  {.cast(gcsafe).}:
    let added = ctlScheduleAdd(arg.stateDir, arg.id, "*/5 * * * *", "alice",
                               "payload", FixedNow)
    if added.isOk:
      discard gAddWins.fetchAdd(1)
    else:
      discard gAddLosers.fetchAdd(1)

proc freshDir(tag: string): string =
  result = getTempDir() / ("donkey_ctl_schedule_" & tag & "_" &
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

proc storePath(dir: string): string =
  dir / "schedules.json"

proc addDaily(dir: string): Result[string, string] =
  ctlScheduleAdd(dir, "daily", "0 9 * * *", "alice", "run the report",
                 FixedNow, channel = "telegram", tz = "UTC-03:00",
                 catchUp = "once")

suite "ctl schedule — list":

  test "empty store is ok and prints a clear line":
    let dir = freshDir("list_empty")
    try:
      let listed = ctlScheduleList(dir, nowMs = FixedNow)
      check listed.isOk
      check listed.get().strip() == "No schedules."
      # Read-only: listing must not create the document.
      check not fileExists(storePath(dir))
    finally:
      cleanup(dir)

  test "empty store --json is []":
    let dir = freshDir("list_empty_json")
    try:
      let listed = ctlScheduleList(dir, asJson = true, nowMs = FixedNow)
      check listed.isOk
      check listed.get().strip() == "[]"
      check parseJson(listed.get()).kind == JArray
    finally:
      cleanup(dir)

  test "--json parses and has the documented keys without the payload":
    let dir = freshDir("list_json")
    try:
      check addDaily(dir).isOk
      let listed = ctlScheduleList(dir, asJson = true, nowMs = FixedNow)
      check listed.isOk
      let parsed = parseJson(listed.get())
      check parsed.kind == JArray
      check parsed.len == 1
      let node = parsed[0]
      for key in [
        "id", "cron", "tz", "user", "channel", "enabled", "catch_up",
        "last_run", "next_run", "last_status", "last_error", "failures",
        "created_at_ms", "last_run_at_ms", "last_fire_at_ms",
      ]:
        check node.hasKey(key)
      check not node.hasKey("payload")
      check node["id"].getStr == "daily"
      check node["cron"].getStr == "0 9 * * *"
      check node["tz"].getStr == "UTC-03:00"
      check node["user"].getStr == "alice"
      check node["channel"].getStr == "telegram"
      check node["catch_up"].getStr == "once"
      check node["enabled"].getBool
      check node["last_run"].getStr == "never"
      check node["last_fire_at_ms"].getInt == 0
    finally:
      cleanup(dir)

  test "human list does not print the payload":
    let dir = freshDir("list_human")
    try:
      check addDaily(dir).isOk
      let listed = ctlScheduleList(dir, nowMs = FixedNow)
      check listed.isOk
      check "daily" in listed.get()
      check "last_run=never" in listed.get()
      check "run the report" notin listed.get()
    finally:
      cleanup(dir)

suite "ctl schedule — add":

  test "writes a record the store can reload":
    let dir = freshDir("add_roundtrip")
    try:
      let added = addDaily(dir)
      check added.isOk
      let store = newScheduleStoreRef(dir)
      let loaded = store.loadRecord("daily")
      check loaded.isOk
      check loaded.get().isSome
      let record = loaded.get().get()
      check record.spec.cronExpr == "0 9 * * *"
      check record.spec.tzOffsetMinutes == -180
      check record.spec.userId == "alice"
      check record.spec.channel == "telegram"
      check record.spec.payload == "run the report"
      check record.spec.catchUp == scOnce
      check record.spec.enabled
      check record.spec.createdAtMs == FixedNow
      check record.lastRunAtMs == FixedNow
      check record.lastFireAtMs == 0
    finally:
      cleanup(dir)

  test "duplicate id fails without touching the file":
    let dir = freshDir("add_duplicate")
    try:
      check addDaily(dir).isOk
      let before = readFile(storePath(dir))
      let duplicate = addDaily(dir)
      check duplicate.isErr
      check "already exists" in duplicate.error
      check readFile(storePath(dir)) == before
      # The original record survives unchanged.
      let record = newScheduleStoreRef(dir).loadRecord("daily").get().get()
      check record.spec.payload == "run the report"
    finally:
      cleanup(dir)

  test "concurrent adds of the same id accept exactly one":
    let dir = freshDir("add_race")
    try:
      const Workers = 8
      gAddWins.store(0)
      gAddLosers.store(0)
      var threads: array[Workers, Thread[AddArg]]
      for i in 0 ..< Workers:
        createThread(threads[i], addWorker,
                     AddArg(stateDir: dir, id: "race"))
      joinThreads(threads)

      check gAddWins.load() == 1
      check gAddLosers.load() == Workers - 1
      let all = newScheduleStoreRef(dir).loadAllRecords()
      check all.isOk
      check all.get().len == 1
      check all.get()[0].spec.id == "race"
    finally:
      cleanup(dir)

  test "invalid cron fails with the validator message":
    let dir = freshDir("add_bad_cron")
    try:
      let added = ctlScheduleAdd(dir, "bad", "not a cron", "alice", "payload",
                                 FixedNow)
      check added.isErr
      check "invalid cron expression" in added.error
      check not fileExists(storePath(dir))
    finally:
      cleanup(dir)

  test "empty user fails with the validator message":
    let dir = freshDir("add_bad_user")
    try:
      let added = ctlScheduleAdd(dir, "bad", "0 9 * * *", "", "payload",
                                 FixedNow)
      check added.isErr
      check "userId must not be empty" in added.error
      check not fileExists(storePath(dir))
    finally:
      cleanup(dir)

  test "empty payload fails with the validator message":
    let dir = freshDir("add_bad_payload")
    try:
      let added = ctlScheduleAdd(dir, "bad", "0 9 * * *", "alice", "",
                                 FixedNow)
      check added.isErr
      check "payload must not be empty" in added.error
    finally:
      cleanup(dir)

  test "oversized payload fails with the validator message":
    let dir = freshDir("add_big_payload")
    try:
      let added = ctlScheduleAdd(dir, "bad", "0 9 * * *", "alice",
                                 repeat("x", MaxPayloadBytes + 1), FixedNow)
      check added.isErr
      check "exceeds 4096 bytes" in added.error
    finally:
      cleanup(dir)

  test "IANA timezone is refused":
    let dir = freshDir("add_bad_tz")
    try:
      let added = ctlScheduleAdd(dir, "bad", "0 9 * * *", "alice", "payload",
                                 FixedNow, tz = "America/Sao_Paulo")
      check added.isErr
      check "IANA names are not supported" in added.error
    finally:
      cleanup(dir)

  test "unknown channel is refused":
    let dir = freshDir("add_bad_channel")
    try:
      let added = ctlScheduleAdd(dir, "bad", "0 9 * * *", "alice", "payload",
                                 FixedNow, channel = "pager")
      check added.isErr
      check "unknown channel kind" in added.error
    finally:
      cleanup(dir)

  test "unknown catch-up policy is refused":
    let dir = freshDir("add_bad_catchup")
    try:
      let added = ctlScheduleAdd(dir, "bad", "0 9 * * *", "alice", "payload",
                                 FixedNow, catchUp = "maybe")
      check added.isErr
      check "catch-up" in added.error
    finally:
      cleanup(dir)

suite "ctl schedule — show":

  test "unknown id fails":
    let dir = freshDir("show_unknown")
    try:
      let shown = ctlScheduleShow(dir, "ghost", nowMs = FixedNow)
      check shown.isErr
      check "not found" in shown.error
    finally:
      cleanup(dir)

  test "known id prints last/next/status":
    let dir = freshDir("show_known")
    try:
      check addDaily(dir).isOk
      let shown = ctlScheduleShow(dir, "daily", nowMs = FixedNow)
      check shown.isOk
      let text = shown.get()
      check "last_run: never" in text
      check "next_run: 2023-11-15T12:00:00Z" in text
      check "last_status: none" in text
      check "payload: run the report" in text
      check "enabled: true" in text
      check "catch_up: once" in text
    finally:
      cleanup(dir)

  test "known id --json includes the payload":
    let dir = freshDir("show_json")
    try:
      check addDaily(dir).isOk
      let shown = ctlScheduleShow(dir, "daily", asJson = true, nowMs = FixedNow)
      check shown.isOk
      let node = parseJson(shown.get())
      check node.kind == JObject
      check node["id"].getStr == "daily"
      check node["payload"].getStr == "run the report"
      check node["last_run"].getStr == "never"
    finally:
      cleanup(dir)

suite "ctl schedule — remove/enable/disable":

  test "remove unknown id fails":
    let dir = freshDir("remove_unknown")
    try:
      let removed = ctlScheduleRemove(dir, "ghost")
      check removed.isErr
      check "not found" in removed.error
    finally:
      cleanup(dir)

  test "enable/disable unknown id fails":
    let dir = freshDir("toggle_unknown")
    try:
      let disabled = ctlScheduleSetEnabled(dir, "ghost", false)
      check disabled.isErr
      check "not found" in disabled.error
      let enabled = ctlScheduleSetEnabled(dir, "ghost", true)
      check enabled.isErr
      check "not found" in enabled.error
    finally:
      cleanup(dir)

  test "remove deletes the record":
    let dir = freshDir("remove_ok")
    try:
      check addDaily(dir).isOk
      let removed = ctlScheduleRemove(dir, "daily")
      check removed.isOk
      check newScheduleStoreRef(dir).loadRecord("daily").get().isNone
    finally:
      cleanup(dir)

  test "disable preserves the watermark and enable advances it":
    let dir = freshDir("toggle_roundtrip")
    try:
      check addDaily(dir).isOk
      # Simulate a firing so we can prove the toggle never rewrites timings.
      let store = newScheduleStoreRef(dir)
      var record = store.loadRecord("daily").get().get()
      record.lastRunAtMs = FixedNow + 60_000
      record.lastFireAtMs = FixedNow + 60_000
      check store.upsert(record).isOk

      check ctlScheduleSetEnabled(dir, "daily", false,
                                  nowMs = FixedNow + 120_000).isOk
      var toggled = store.loadRecord("daily").get().get()
      check not toggled.spec.enabled
      ## Disabling never moves either watermark.
      check toggled.lastRunAtMs == FixedNow + 60_000
      check toggled.lastFireAtMs == FixedNow + 60_000

      check ctlScheduleSetEnabled(dir, "daily", true,
                                  nowMs = FixedNow + 3_600_000).isOk
      toggled = store.loadRecord("daily").get().get()
      check toggled.spec.enabled
      ## Re-enabling closes the disabled window: the watermark becomes "now",
      ## while the last actual firing stays historical.
      check toggled.lastRunAtMs == FixedNow + 3_600_000
      check toggled.lastFireAtMs == FixedNow + 60_000
      check toggled.spec.createdAtMs == FixedNow
    finally:
      cleanup(dir)

  test "re-enabling after a stopped daemon does not fire the stale occurrence":
    let dir = freshDir("enable_catchup")
    try:
      check addDaily(dir).isOk
      let store = newScheduleStoreRef(dir)
      # One firing at FixedNow, then disabled. The daemon was down for the
      # whole disabled period, so no tick advanced the watermark itself.
      var record = store.loadRecord("daily").get().get()
      record.lastRunAtMs = FixedNow
      record.lastFireAtMs = FixedNow
      check store.upsert(record).isOk
      check ctlScheduleSetEnabled(dir, "daily", false,
                                  nowMs = FixedNow + 1_000).isOk

      # 2023-11-15T12:00Z (the next 09:00 at UTC-03:00) falls inside the
      # disabled window: a catch-up tick would fire it without the fix.
      let enableNow = FixedNow + 14 * HourMs
      check ctlScheduleSetEnabled(dir, "daily", true, nowMs = enableNow).isOk

      let enabled = store.loadRecord("daily").get().get()
      check enabled.spec.enabled
      check enabled.lastRunAtMs == enableNow
      check enabled.lastFireAtMs == FixedNow

      let rec = Recorder()
      let tick = tickSchedule(newScheduleStore(dir), enabled.spec, enableNow,
                              rec.makeEnqueue)
      check tick.isOk
      check tick.get().firedAtMs.isNone
      check tick.get().missedOccurrenceMs.isNone
      check rec.instants.len == 0
    finally:
      cleanup(dir)

suite "ctl schedule — argument parsing":

  test "the id wins when flags come before it":
    ## `add --cron "0 9 * * *" ... daily` used to create a schedule whose id
    ## was the cron expression, because parseopt yields the flag value as an
    ## argument.
    check scheduleAddId(@["donkey", "ctl", "schedule", "add", "--cron",
                          "0 9 * * *", "--user", "alice", "--payload", "p",
                          "daily"], @[]) == "daily"

  test "the documented order still works":
    check scheduleAddId(@["donkey", "ctl", "schedule", "add", "daily",
                          "--cron", "0 9 * * *"], @[]) == "daily"

  test "a boolean flag does not swallow the id":
    check scheduleAddId(@["donkey", "ctl", "schedule", "add", "--json",
                          "daily"], @[]) == "daily"

  test "--flag=value is understood":
    check scheduleFlagValue(@["--cron=0 9 * * *"], "--cron") ==
      some("0 9 * * *")
    check scheduleFlagValue(@["--catch-up=once"], "--catch-up") == some("once")

  test "a missing id is empty, not a flag value":
    check scheduleAddId(@["donkey", "ctl", "schedule", "add", "--cron",
                          "0 9 * * *"], @[]) == ""
