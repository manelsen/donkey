## Automation runtime tests — US-003 slice: persisted watermark, at-most-once
## ticks, restart resume, clock rollback and fail-closed persistence.
##
## No real clock and no file system: the store is an in-memory fake and every
## instant is injected. The daemon loop is deliberately not started here.

import std/[options, tables, unittest]
import results
import donkey/domain/automation/schedule_pure
import donkey/app/automation_runtime

const
  MinuteMs = 60_000'i64
  HourMs = 3_600_000'i64
  DayMs = 24 * HourMs

func at(hour, minute: int): int64 =
  ## Epoch milliseconds on 1970-01-01 UTC (fixed test clock).
  int64(hour) * HourMs + int64(minute) * MinuteMs

func makeSpec(
  cron: string;
  catchUp = scOnce;
  createdAt = 0'i64;
  enabled = true;
  id = "sched-1";
): ScheduleSpec =
  ScheduleSpec(
    id: id,
    cronExpr: cron,
    tzOffsetMinutes: 0,
    userId: "user-1",
    channel: "telegram",
    payload: "payload",
    catchUp: catchUp,
    enabled: enabled,
    createdAtMs: createdAt,
  )

type
  FakeStore = ref object
    records: Table[string, ScheduleWatermark]
    loadError: string
    saveError: string
    loadCount: int
    saveCount: int

  Recorder = ref object
    instants: seq[int64]
    ids: seq[string]
    failWith: string

proc newFakeStore(): FakeStore =
  FakeStore(records: initTable[string, ScheduleWatermark]())

proc seed(store: FakeStore; state: ScheduleWatermark) =
  store.records[state.id] = state

proc stored(
  store: FakeStore; id: string
): Option[ScheduleWatermark] {.gcsafe, raises: [].} =
  if store.records.hasKey(id):
    some(store.records.getOrDefault(id))
  else:
    none(ScheduleWatermark)

proc makePort(store: FakeStore): ScheduleStorePort =
  ## A persistence boundary with the same load/save shape the real JSON
  ## adapter will expose. Failures are injected, never raised.
  ScheduleStorePort(
    load: proc(
      scheduleId: string
    ): Result[Option[ScheduleWatermark], string] {.gcsafe, raises: [].} =
      inc store.loadCount
      if store.loadError.len > 0:
        return err(store.loadError)
      ok(store.stored(scheduleId)),
    save: proc(
      state: ScheduleWatermark
    ): Result[void, string] {.gcsafe, raises: [].} =
      inc store.saveCount
      if store.saveError.len > 0:
        return err(store.saveError)
      store.records[state.id] = state
      ok(),
  )

proc makeEnqueue(rec: Recorder): ScheduleEnqueueFn =
  result = proc(
    spec: ScheduleSpec; instantMs: int64
  ): Result[void, string] {.gcsafe, raises: [].} =
    rec.instants.add(instantMs)
    rec.ids.add(spec.id)
    if rec.failWith.len > 0:
      return err(rec.failWith)
    ok()

proc seedCreated(
  store: FakeStore; createdAt: int64; id = "sched-1"
) =
  store.seed(ScheduleWatermark(
    id: id, lastRunAtMs: createdAt, createdAtMs: createdAt
  ))

proc runTests*() =
  suite "automation runtime — tick state machine":

    test "first tick after creation does not fire; the first matching tick fires once":
      let createdAt = at(12, 0)
      let spec = makeSpec("* * * * *", createdAt = createdAt)
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(createdAt)

      # Tick in the creation minute: the window (createdAt, createdAt] is empty.
      let first = tickSchedule(store.makePort, spec, createdAt, rec.makeEnqueue)
      check first.isOk
      check first.get().firedAtMs.isNone
      check rec.instants.len == 0
      check store.stored("sched-1").get().lastRunAtMs == createdAt

      # Still inside the creation minute: the next occurrence is 12:01.
      let second = tickSchedule(
        store.makePort, spec, createdAt + 30_000, rec.makeEnqueue
      )
      check second.isOk
      check second.get().firedAtMs.isNone
      check rec.instants.len == 0

      # First matching tick fires exactly once.
      let third = tickSchedule(
        store.makePort, spec, createdAt + MinuteMs, rec.makeEnqueue
      )
      check third.isOk
      check third.get().firedAtMs == some(createdAt + MinuteMs)
      check rec.instants == @[createdAt + MinuteMs]
      ## `ctl schedule list/show` reads `last_run` from the fire instant, not the
      ## watermark; without this write it always said "never".
      check store.stored("sched-1").get().lastFireAtMs == createdAt + MinuteMs

    test "a restart resumes from the persisted watermark without replaying a 30-day backlog":
      let createdAt = 0'i64
      let spec = makeSpec("0 9 * * *", createdAt = createdAt)
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(createdAt)

      # 30 days later, 3 h after the most recent 09:00 occurrence.
      let now = 30 * DayMs + at(12, 0)
      let first = tickSchedule(store.makePort, spec, now, rec.makeEnqueue)
      check first.isOk
      check first.get().firedAtMs == some(now - 3 * HourMs)
      check first.get().watermarkMs == now
      check rec.instants.len == 1

      # Restart: a new port/closures over the same durable records. The window
      # (now, now] is empty, so nothing is replayed.
      let restarted = Recorder()
      let second = tickSchedule(store.makePort, spec, now, restarted.makeEnqueue)
      check second.isOk
      check second.get().firedAtMs.isNone
      check restarted.instants.len == 0
      check rec.instants.len == 1
      check store.stored("sched-1").get().lastRunAtMs == now

    test "two ticks at the same instant cannot fire twice":
      let now = at(12, 0)
      let spec = makeSpec("* * * * *")
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(at(11, 59))

      let first = tickSchedule(store.makePort, spec, now, rec.makeEnqueue)
      check first.isOk
      check first.get().firedAtMs == some(now)
      let second = tickSchedule(store.makePort, spec, now, rec.makeEnqueue)
      check second.isOk
      check second.get().firedAtMs.isNone
      check rec.instants == @[now]

    test "a failed enqueue consumes the occurrence and is never retried":
      let now = at(12, 0)
      let spec = makeSpec("* * * * *")
      let store = newFakeStore()
      let rec = Recorder()
      rec.failWith = "scheduled task dropped: denied or revoked"
      store.seedCreated(at(11, 59))

      let first = tickSchedule(store.makePort, spec, now, rec.makeEnqueue)
      check first.isOk
      check first.get().firedAtMs == some(now)
      check first.get().enqueueError ==
        "scheduled task dropped: denied or revoked"
      ## The failure is saved for `ctl schedule` and the TUI to show.
      check store.stored("sched-1").get().lastStatus == "failed"
      check store.stored("sched-1").get().lastError ==
        "scheduled task dropped: denied or revoked"
      check store.stored("sched-1").get().lastFireAtMs == 0  ## it did not run

      let second = tickSchedule(store.makePort, spec, now, rec.makeEnqueue)
      check second.isOk
      check second.get().firedAtMs.isNone
      check rec.instants.len == 1
      check store.stored("sched-1").get().lastRunAtMs == now

    test "clock rollback does not fire and does not move the watermark backwards":
      let spec = makeSpec("* * * * *")
      let store = newFakeStore()
      let rec = Recorder()
      let lastRun = at(12, 10)
      store.seedCreated(at(12, 0))
      store.seed(ScheduleWatermark(
        id: "sched-1", lastRunAtMs: lastRun, createdAtMs: at(12, 0)
      ))

      let rolledBack = tickSchedule(
        store.makePort, spec, at(12, 5), rec.makeEnqueue
      )
      check rolledBack.isOk
      check rolledBack.get().firedAtMs.isNone
      check rolledBack.get().rolledBack
      check rolledBack.get().watermarkMs == lastRun
      check store.stored("sched-1").get().lastRunAtMs == lastRun
      check rec.instants.len == 0
      # The tick still upserts the unchanged watermark, per the US-004 contract.
      check store.saveCount == 1

      # Once the clock passes the old watermark again, the schedule resumes.
      let resumed = tickSchedule(
        store.makePort, spec, at(12, 11), rec.makeEnqueue
      )
      check resumed.isOk
      check resumed.get().firedAtMs == some(at(12, 11))
      check rec.instants == @[at(12, 11)]

    test "enabled=false advances the watermark without firing":
      let spec = makeSpec("* * * * *", enabled = false)
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(at(11, 59))

      let tick = tickSchedule(
        store.makePort, spec, at(12, 30), rec.makeEnqueue
      )
      check tick.isOk
      check tick.get().firedAtMs.isNone
      check rec.instants.len == 0
      check store.stored("sched-1").get().lastRunAtMs == at(12, 30)

  suite "automation runtime — scSkip has no backlog":

    test "scSkip fires on an exact tick":
      let now = at(12, 0)
      let spec = makeSpec("* * * * *", catchUp = scSkip)
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(at(11, 59))

      let tick = tickSchedule(store.makePort, spec, now, rec.makeEnqueue)
      check tick.isOk
      check tick.get().firedAtMs == some(now)
      check tick.get().missedOccurrenceMs.isNone
      check rec.instants == @[now]

    test "scSkip fires a 30 s late tick inside the grace":
      let now = at(12, 0) + 30_000
      let spec = makeSpec("* * * * *", catchUp = scSkip)
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(at(11, 59))

      let tick = tickSchedule(store.makePort, spec, now, rec.makeEnqueue)
      check tick.isOk
      check tick.get().firedAtMs == some(at(12, 0))
      check tick.get().missedOccurrenceMs.isNone
      check rec.instants == @[at(12, 0)]

    test "scSkip drops a 30-day-stale occurrence and never revisits it":
      let spec = makeSpec("0 9 * * *", catchUp = scSkip)
      let store = newFakeStore()
      let rec = Recorder()
      let now = 30 * DayMs + at(12, 0)
      store.seedCreated(0'i64)

      let dropped = tickSchedule(store.makePort, spec, now, rec.makeEnqueue)
      check dropped.isOk
      check dropped.get().firedAtMs.isNone
      check dropped.get().missedOccurrenceMs == some(at(9, 0))
      check dropped.get().watermarkMs == now
      check rec.instants.len == 0
      check store.stored("sched-1").get().lastRunAtMs == now

      # Next tick starts from `now`: no firing and no repeated drop.
      let next = tickSchedule(
        store.makePort, spec, now + MinuteMs, rec.makeEnqueue
      )
      check next.isOk
      check next.get().firedAtMs.isNone
      check next.get().missedOccurrenceMs.isNone
      check rec.instants.len == 0

    test "graceMs=0 drops a 30 s late tick":
      let now = at(12, 0) + 30_000
      let spec = makeSpec("* * * * *", catchUp = scSkip)
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(at(11, 59))

      let tick = tickSchedule(
        store.makePort, spec, now, rec.makeEnqueue, graceMs = 0
      )
      check tick.isOk
      check tick.get().firedAtMs.isNone
      check tick.get().missedOccurrenceMs == some(at(12, 0))
      check tick.get().watermarkMs == now
      check rec.instants.len == 0

    test "scSkip rollback fires nothing and keeps the watermark":
      let spec = makeSpec("* * * * *", catchUp = scSkip)
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(at(12, 0))
      store.seed(ScheduleWatermark(
        id: "sched-1", lastRunAtMs: at(12, 10), createdAtMs: at(12, 0)
      ))

      let tick = tickSchedule(
        store.makePort, spec, at(12, 5), rec.makeEnqueue
      )
      check tick.isOk
      check tick.get().firedAtMs.isNone
      check tick.get().missedOccurrenceMs.isNone
      check tick.get().watermarkMs == at(12, 10)
      check tick.get().rolledBack
      check store.stored("sched-1").get().lastRunAtMs == at(12, 10)
      check rec.instants.len == 0

  suite "automation runtime — persistence boundary":

    test "watermark round-trips through the store port":
      let store = newFakeStore()
      let port = store.makePort
      let state = ScheduleWatermark(
        id: "sched-1", lastRunAtMs: at(12, 30), createdAtMs: at(9, 0)
      )

      check port.save(state).isOk
      let loaded = port.load("sched-1")
      check loaded.isOk
      check loaded.get().isSome
      check loaded.get().get().id == "sched-1"
      check loaded.get().get().lastRunAtMs == at(12, 30)
      check loaded.get().get().createdAtMs == at(9, 0)

      # Overwrite is an upsert, not a second row.
      check port.save(ScheduleWatermark(
        id: "sched-1", lastRunAtMs: at(12, 45), createdAtMs: at(9, 0)
      )).isOk
      check port.load("sched-1").get().get().lastRunAtMs == at(12, 45)
      check port.load("absent").get().isNone

    test "a corrupt record fails closed without firing":
      let spec = makeSpec("* * * * *")
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(at(11, 59))
      store.loadError = "state/schedules.json: invalid JSON"

      let tick = tickSchedule(
        store.makePort, spec, at(12, 0), rec.makeEnqueue
      )
      check tick.isErr
      check tick.error ==
        "cannot load schedule 'sched-1': state/schedules.json: invalid JSON"
      check rec.instants.len == 0
      check store.saveCount == 0

    test "a missing record is not resurrected, and nothing fires":
      let createdAt = at(12, 0)
      let spec = makeSpec("* * * * *", createdAt = createdAt)
      let store = newFakeStore()
      let rec = Recorder()

      ## A row that is absent means the schedule was removed between the tick's
      ## snapshot and this load. The tick reports the recovery and writes
      ## nothing: recreating the row produced a phantom, spec-less schedule.
      let recovered = tickSchedule(
        store.makePort, spec, createdAt + MinuteMs, rec.makeEnqueue
      )
      check recovered.isOk
      check recovered.get().recovered
      check recovered.get().firedAtMs.isNone
      check recovered.get().watermarkMs == createdAt
      check rec.instants.len == 0
      check store.stored("sched-1").isNone

      ## Still absent: it does not fire later either.
      let next = tickSchedule(
        store.makePort, spec, createdAt + 2 * MinuteMs, rec.makeEnqueue
      )
      check next.isOk
      check next.get().recovered
      check next.get().firedAtMs.isNone
      check rec.instants.len == 0

    test "a failed watermark save does not enqueue":
      let spec = makeSpec("* * * * *")
      let store = newFakeStore()
      let rec = Recorder()
      store.seedCreated(at(11, 59))
      store.saveError = "read-only state dir"

      let tick = tickSchedule(
        store.makePort, spec, at(12, 0), rec.makeEnqueue
      )
      check tick.isErr
      check tick.error ==
        "cannot persist watermark for schedule 'sched-1': read-only state dir"
      check rec.instants.len == 0

when isMainModule:
  runTests()
