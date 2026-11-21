## Scheduler wiring (automation US-006) — env parsing at the edge and the one
## tick the daemon runs.
##
## The timer itself is deliberately not under test: every unit here is called
## with an injected `nowMs` and an injected enqueue callback, and the store is
## a real `schedules.json` in a temp dir. No daemon process, no `sleep`, no
## real clock, no provider.
##
## The two behaviours this file pins beyond the happy path:
##   - `DONKEY_HEARTBEAT_CRON` is irrelevant: the tick interval comes from
##     `DONKEY_SCHEDULES_TICK_SEC` alone;
##   - the record's own `catchUp` wins over the env default, so an env of
##     `once` never turns a `skip` record into a catch-up firing.

import std/[options, os, strutils, tables, unittest]
import results
import donkey/adapters/state/schedule_store
import donkey/app/automation_runtime
import donkey/app/scheduler_wiring
import donkey/domain/automation/schedule_pure
import donkey/domain/automation/schedule_runtime

const
  MinuteMs = 60_000'i64
  HourMs = 3_600_000'i64

func at(day, hour, minute: int): int64 =
  ## Epoch milliseconds on 1970-01-<day+1> UTC (fixed test clock).
  (int64(day) * 24 + int64(hour)) * HourMs + int64(minute) * MinuteMs

func makeSpec(
  id: string;
  cron = "* * * * *";
  catchUp = scSkip;
  enabled = true;
  userId = "user-1";
  payload = "payload";
  createdAt = 0'i64;
): ScheduleSpec =
  ScheduleSpec(
    id: id,
    cronExpr: cron,
    tzOffsetMinutes: 0,
    userId: userId,
    channel: "telegram",
    payload: payload,
    catchUp: catchUp,
    enabled: enabled,
    createdAtMs: createdAt,
  )

func testConfig(
  catchUp = scSkip; catchUpMaxHours = CatchUpHoursDefault
): SchedulerConfig =
  SchedulerConfig(
    enabled: true,
    tickSec: SchedulerTickSecDefault,
    catchUp: catchUp,
    catchUpMaxHours: catchUpMaxHours,
  )

type
  FakeEnv = ref object
    values: Table[string, string]

  Recorder = ref object
    ids: seq[string]
    users: seq[string]
    payloads: seq[string]
    instants: seq[int64]
    failWith: string

proc newEnv(pairs: openArray[(string, string)] = []): FakeEnv =
  result = FakeEnv(values: initTable[string, string]())
  for (key, value) in pairs:
    result.values[key] = value

proc lookup(env: FakeEnv): EnvLookup =
  ## Stand-in for `getEnv`: the parser never reaches the process environment.
  result = proc(name: string): string {.gcsafe, raises: [], noSideEffect.} =
    env.values.getOrDefault(name)

proc makeEnqueue(rec: Recorder): ScheduleEnqueueFn =
  result = proc(
    spec: ScheduleSpec; instantMs: int64
  ): Result[void, string] {.gcsafe, raises: [].} =
    rec.ids.add(spec.id)
    rec.users.add(spec.userId)
    rec.payloads.add(spec.payload)
    rec.instants.add(instantMs)
    if rec.failWith.len > 0:
      return err(rec.failWith)
    ok()

proc tempStateDir(tag: string): string =
  ## Unique per process and per test; never derived from a clock.
  result = getTempDir() / ("donkey_sched_wiring_" & $getCurrentProcessId() &
                           "_" & tag)
  removeDir(result)

proc seed(store: ScheduleStore; spec: ScheduleSpec; lastRunAtMs: int64) =
  let saved = store.upsert(
    ScheduleRecord(spec: spec, lastRunAtMs: lastRunAtMs))
  doAssert saved.isOk, saved.error

proc loadFrom(store: ScheduleStore): ScheduleSnapshotLoader =
  ## The same adapter -> app projection the daemon composes.
  result = proc(): Result[seq[ScheduleSnapshot], string] {.
      gcsafe, raises: [].} =
    let records = store.loadAllRecords()
    if records.isErr:
      return err(records.error)
    var snapshot: seq[ScheduleSnapshot]
    for record in records.get():
      snapshot.add(ScheduleSnapshot(
        spec: record.spec,
        loadWarning: record.loadWarning,
      ))
    ok(snapshot)

proc runTests*() =
  suite "scheduler wiring — environment parsing":

    test "defaults keep the scheduler off":
      let cfg = parseSchedulerConfig(newEnv().lookup)

      check cfg.enabled == false
      check cfg.tickSec == 60
      check cfg.catchUp == scSkip
      check cfg.catchUpMaxHours == 24
      check cfg.warnings.len == 0

    test "the env names are the documented ones":
      check EnvSchedulesEnabled == "DONKEY_SCHEDULES_ENABLED"
      check EnvSchedulesTickSec == "DONKEY_SCHEDULES_TICK_SEC"
      check EnvScheduleCatchUp == "DONKEY_SCHEDULE_CATCHUP"
      check EnvScheduleCatchUpMaxH == "DONKEY_SCHEDULE_CATCHUP_MAX_H"

    test "ENABLED=0 keeps the periodic task off, ENABLED=1 turns it on":
      let off = parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULES_ENABLED": "0"}).lookup)
      check off.enabled == false

      let on = parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULES_ENABLED": "1"}).lookup)
      check on.enabled == true

      # Anything else is off, never a silent enable.
      let junk = parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULES_ENABLED": "maybe"}).lookup)
      check junk.enabled == false

    test "the tick interval ignores DONKEY_HEARTBEAT_CRON":
      let cfg = parseSchedulerConfig(newEnv({
        "DONKEY_SCHEDULES_TICK_SEC": "5",
        "DONKEY_HEARTBEAT_CRON": "0 9 * * *",
      }).lookup)
      check cfg.tickSec == 5

    test "invalid tick seconds fall back to 60":
      for raw in ["0", "-5", "abc", "999999999", "1.5"]:
        let cfg = parseSchedulerConfig(
          newEnv({"DONKEY_SCHEDULES_TICK_SEC": raw}).lookup)
        check cfg.tickSec == 60
        check cfg.warnings.len == 1

      let blank = parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULES_TICK_SEC": "  "}).lookup)
      check blank.tickSec == 60
      check blank.warnings.len == 0

    test "catch-up policy is skip|once, default skip":
      check parseSchedulerConfig(newEnv().lookup).catchUp == scSkip
      check parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULE_CATCHUP": "skip"}).lookup).catchUp == scSkip
      check parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULE_CATCHUP": "once"}).lookup).catchUp == scOnce
      check parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULE_CATCHUP": "ONCE"}).lookup).catchUp == scOnce

      let junk = parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULE_CATCHUP": "sometimes"}).lookup)
      check junk.catchUp == scSkip
      check junk.warnings.len == 1

    test "CATCHUP_MAX_H rejects 25 h and accepts 24 h":
      let accepted = parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULE_CATCHUP_MAX_H": "24"}).lookup)
      check accepted.catchUpMaxHours == 24
      check accepted.warnings.len == 0

      let rejected = parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULE_CATCHUP_MAX_H": "25"}).lookup)
      check rejected.catchUpMaxHours == CatchUpHoursDefault
      check rejected.warnings.len == 1
      check "24-hour ceiling" in rejected.warnings[0]

      let nonsense = parseSchedulerConfig(
        newEnv({"DONKEY_SCHEDULE_CATCHUP_MAX_H": "abc"}).lookup)
      check nonsense.catchUpMaxHours == CatchUpHoursDefault
      check nonsense.warnings.len == 1

  suite "scheduler wiring — one tick":

    test "a due enabled schedule fires once; disabled and far-future do not":
      let dir = tempStateDir("due")
      defer: removeDir(dir)
      let store = newScheduleStoreRef(dir)
      store.seed(makeSpec("due", userId = "u-due", payload = "ship it"), at(0, 11, 59))
      store.seed(makeSpec("off", enabled = false), at(0, 11, 59))
      store.seed(makeSpec("later", cron = "0 9 * * *"), at(0, 11, 59))

      let rec = Recorder()
      let summary = runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(), at(0, 12, 0))

      check summary.loaded == 3
      check summary.disabled == 1
      check summary.fired == 1
      check summary.missed == 0
      check summary.enqueueErrors == 0
      check summary.loadError.len == 0
      check summary.errors.len == 0

      check rec.instants == @[at(0, 12, 0)]
      check rec.ids == @["due"]
      check rec.users == @["u-due"]
      check rec.payloads == @["ship it"]

    test "re-enabling does not replay the disabled period":
      ## FR-5: a disabled schedule advances its watermark, so an occurrence that
      ## passed while it was off is not fired when it is enabled again.
      let dir = tempStateDir("reenable")
      defer: removeDir(dir)
      let store = newScheduleStoreRef(dir)
      let spec = makeSpec("off", enabled = false, cron = "0 12 * * *",
                          catchUp = scOnce, userId = "u-off", payload = "x")
      store.seed(spec, at(0, 11, 0))

      let rec = Recorder()
      discard runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(), at(0, 12, 0))
      check rec.instants.len == 0

      var enabledSpec = spec
      enabledSpec.enabled = true
      check store.upsert(ScheduleRecord(spec: enabledSpec)).isOk
      discard runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(), at(0, 12, 30))
      check rec.instants.len == 0

    test "a second tick at the same instant does not fire again":
      let dir = tempStateDir("watermark")
      defer: removeDir(dir)
      let store = newScheduleStoreRef(dir)
      store.seed(makeSpec("due"), at(0, 11, 59))

      let rec = Recorder()
      let first = runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(), at(0, 12, 0))
      check first.fired == 1
      check rec.instants.len == 1

      let second = runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(), at(0, 12, 0))
      check second.fired == 0
      check rec.instants.len == 1
      check store.loadRecord("due").get().get().lastRunAtMs == at(0, 12, 0)

    test "an enqueue failure is reported and the tick continues":
      let dir = tempStateDir("enqueue-error")
      defer: removeDir(dir)
      let store = newScheduleStoreRef(dir)
      store.seed(makeSpec("broken", userId = "u-revoked"), at(0, 11, 59))
      store.seed(makeSpec("healthy"), at(0, 11, 59))

      let rec = Recorder()
      rec.failWith = "scheduled task dropped: denied or revoked"
      let summary = runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(), at(0, 12, 0))

      # Both schedules were attempted; the failed enqueue is counted, not fatal.
      check summary.loaded == 2
      check summary.fired == 2
      check summary.enqueueErrors == 2
      check summary.errors.len == 0
      check rec.instants.len == 2

    test "a store error is reported and the tick returns without throwing":
      let dir = tempStateDir("broken-store")
      defer: removeDir(dir)
      createDir(dir)
      writeFile(dir / ScheduleFileName, "{ this is not json")

      let store = newScheduleStoreRef(dir)
      let rec = Recorder()
      let summary = runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(), at(0, 12, 0))

      check summary.loadError.len > 0
      check summary.fired == 0
      check rec.instants.len == 0

    test "v1 watermark-only rows are counted for the startup log":
      let dir = tempStateDir("legacy-v1")
      defer: removeDir(dir)
      createDir(dir)
      writeFile(dir / ScheduleFileName, """{"schedules": [
      {"id": "legacy", "last_run_at_ms": 0, "created_at_ms": 0}
    ]}""")

      let store = newScheduleStoreRef(dir)
      let rec = Recorder()
      let summary = runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(), at(0, 12, 0))

      check summary.loaded == 1
      check summary.legacyWarnings == 1
      check summary.disabled == 1
      check summary.fired == 0
      check rec.instants.len == 0

    test "DONKEY_SCHEDULE_CATCHUP_MAX_H reaches the runtime lookback":
      let spec = makeSpec("daily", cron = "0 9 * * *", catchUp = scOnce)
      # Watermark at the epoch; the most recent 09:00 is 23 h old at 08:00.
      let now = at(1, 8, 0)
      let expected = at(0, 9, 0)

      let narrowDir = tempStateDir("lookback-narrow")
      defer: removeDir(narrowDir)
      let narrowStore = newScheduleStoreRef(narrowDir)
      narrowStore.seed(spec, 0)
      let narrow = Recorder()
      let narrowTick = runSchedulerTick(
        narrowStore.scheduleStorePort, narrowStore.loadFrom, narrow.makeEnqueue,
        testConfig(catchUpMaxHours = 1), now)
      check narrowTick.fired == 0
      check narrow.instants.len == 0

      let wideDir = tempStateDir("lookback-wide")
      defer: removeDir(wideDir)
      let wideStore = newScheduleStoreRef(wideDir)
      wideStore.seed(spec, 0)
      let wide = Recorder()
      let wideTick = runSchedulerTick(
        wideStore.scheduleStorePort, wideStore.loadFrom, wide.makeEnqueue,
        testConfig(catchUpMaxHours = 24), now)
      check wideTick.fired == 1
      check wide.instants == @[expected]

    test "the spec's catchUp wins over the env default":
      let dir = tempStateDir("spec-catchup")
      defer: removeDir(dir)
      let store = newScheduleStoreRef(dir)
      # Record says skip, the env default says once. The 09:00 occurrence is
      # 3 h stale, so `skip` must drop it instead of catching up.
      store.seed(makeSpec("stale", cron = "0 9 * * *", catchUp = scSkip), 0)

      let rec = Recorder()
      let summary = runSchedulerTick(
        store.scheduleStorePort, store.loadFrom, rec.makeEnqueue,
        testConfig(catchUp = scOnce), at(0, 12, 0))

      check summary.fired == 0
      check summary.missed == 1
      check rec.instants.len == 0

when isMainModule:
  runTests()
