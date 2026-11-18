## scheduler_wiring — the daemon edge of the persisted schedule (US-006).
##
## Two testable units live here and one thin runner:
##
##   - `parseSchedulerConfig` reads every `DONKEY_SCHEDULE*` variable through an
##     injected lookup, so the process environment is only touched in
##     `src/donkey.nim`. Invalid values fall back to the documented default and
##     are reported in `warnings`; the domain never reads env.
##   - `runSchedulerTick` runs exactly one tick over every persisted record: it
##     loads the snapshot, skips `enabled = false` for firing, calls
##     `tickSchedule` with the injected `nowMs` and reports what happened. It
##     owns no clock, no timer and no file I/O; the adapter supplies the store
##     and the snapshot loader.
##   - `startSchedulerTask`/`stopSchedulerTask` own the periodic task. It is a
##     dedicated loop, **not** the heartbeat registry, so
##     `DONKEY_HEARTBEAT_CRON` cannot silence `DONKEY_SCHEDULES_TICK_SEC`.
##
## Boundary note: this module lives under `app/` and therefore may not import
## `adapters/`. The daemon composes the concrete `ScheduleStore` with the
## `ScheduleSnapshot` projection below; everything here only sees the app-level
## `ScheduleStorePort` from `automation_runtime`.
##
## Failure policy: a tick is best effort. A load error aborts the pass, a
## per-schedule error or enqueue error is counted and logged, and the loop
## keeps running. A crashed tick never kills the daemon or the other tasks.
##
## `DONKEY_SCHEDULE_CATCHUP` is the **creation-time** default: it is parsed and
## carried here, but the record's own `catchUp` always wins at tick time (the
## `scSkip` grace still applies to both). `DONKEY_SCHEDULE_RETENTION_DAYS` is
## owned by the store adapter/ctl, not by this edge.

import std/[options, strutils]
import chronos
import results
import ../core/log
import ../domain/automation/schedule_pure
import ../domain/automation/schedule_runtime
import ./automation_runtime

const
  EnvSchedulesEnabled* = "DONKEY_SCHEDULES_ENABLED"
  EnvSchedulesTickSec* = "DONKEY_SCHEDULES_TICK_SEC"
  EnvScheduleCatchUp* = "DONKEY_SCHEDULE_CATCHUP"
  EnvScheduleCatchUpMaxH* = "DONKEY_SCHEDULE_CATCHUP_MAX_H"

  SchedulerTickSecDefault* = 60
    ## `DONKEY_SCHEDULES_TICK_SEC` default, independent of the heartbeat.
  SchedulerTickSecMin* = 1
  SchedulerTickSecMax* = 86_400
    ## One day is the widest meaningful tick; anything above is a typo.
  MaxTickSecDigits = 6
    ## Parsing bound: wider input is rejected before it can overflow an `int`.

type
  EnvLookup* = proc(name: string): string {.
    gcsafe, raises: [], noSideEffect.}
    ## `func`-compatible env accessor. The daemon passes `getEnv`; tests pass a
    ## table so no process environment is touched.

  SchedulerConfig* = object
    enabled*: bool
      ## `DONKEY_SCHEDULES_ENABLED`, default `false`. The daemon starts no
      ## periodic task when this is false.
    tickSec*: int
      ## `DONKEY_SCHEDULES_TICK_SEC`, default 60, clamped to `1..86_400`.
    catchUp*: ScheduleCatchUp
      ## `DONKEY_SCHEDULE_CATCHUP`: creation-time default only. The record's
      ## own `catchUp` wins during a tick.
    catchUpMaxHours*: int
      ## `DONKEY_SCHEDULE_CATCHUP_MAX_H` (`validateCatchUpHours`), default 24.
    warnings*: seq[string]
      ## Invalid values that fell back to a default, for the startup log.

  ScheduleSnapshot* = object
    ## App-level view of one persisted row. The adapter maps its
    ## `ScheduleRecord` onto this; `loadWarning` is the v1 upgrade notice.
    spec*: ScheduleSpec
    loadWarning*: string

  ScheduleSnapshotLoader* = proc(): Result[seq[ScheduleSnapshot], string] {.
    gcsafe, raises: [].}
    ## Loads every persisted schedule. `Err` means the store is unreadable.

  SchedulerTickSummary* = object
    loaded*: int
      ## Records returned by the loader.
    legacyWarnings*: int
      ## Rows loaded from the v1 watermark-only schema.
    disabled*: int
      ## `enabled = false` rows skipped for firing.
    fired*: int
      ## Enqueue attempts (Ok or Err); at most one per schedule per tick.
    missed*: int
      ## `scSkip` occurrences dropped as too stale to fire.
    enqueueErrors*: int
      ## Fired occurrences whose enqueue failed.
    loadError*: string
      ## Non-empty when the loader failed; the tick did nothing else.
    errors*: seq[string]
      ## Per-schedule runtime errors; the tick continued past each one.

  SchedulerClock* = proc(): int64 {.gcsafe, raises: [].}
    ## Injected wall clock (epoch ms). Code under test always takes `nowMs`.

  SchedulerTask* = ref object
    ## Handle for the periodic loop, so shutdown can stop it explicitly.
    stopRequested: bool
    tickSec: int
    future: Future[void]

# ── Environment parsing ──────────────────────────────────────────────────────

func parseEnabled*(raw: string): bool =
  ## `DONKEY_SCHEDULES_ENABLED`: only an explicit enable turns the task on.
  case raw.strip().toLowerAscii()
  of "1", "true", "yes", "on": true
  else: false

func parseTickSecValue(raw: string): Result[int, string] =
  ## Strict parse behind `parseTickSec`. A blank value means "default"; a
  ## non-numeric, non-positive or absurd value is an error the caller turns
  ## into a fallback plus a warning.
  let text = raw.strip()
  if text.len == 0:
    return ok(SchedulerTickSecDefault)
  if text.len > MaxTickSecDigits:
    return err("DONKEY_SCHEDULES_TICK_SEC is absurdly large: '" & raw & "'")

  var i = 0
  if text[0] == '+':
    inc i
  elif text[0] == '-':
    return err("DONKEY_SCHEDULES_TICK_SEC must be between " &
      $SchedulerTickSecMin & " and " & $SchedulerTickSecMax &
      " seconds (got " & raw & ")")
  if i >= text.len:
    return err("invalid DONKEY_SCHEDULES_TICK_SEC '" & raw &
      "': expected a whole number of seconds")

  var value = 0
  while i < text.len:
    let c = text[i]
    if c < '0' or c > '9':
      return err("invalid DONKEY_SCHEDULES_TICK_SEC '" & raw &
        "': expected a whole number of seconds")
    value = value * 10 + (ord(c) - ord('0'))
    inc i

  if value < SchedulerTickSecMin or value > SchedulerTickSecMax:
    return err("DONKEY_SCHEDULES_TICK_SEC must be between " &
      $SchedulerTickSecMin & " and " & $SchedulerTickSecMax &
      " seconds (got " & $value & ")")
  ok(value)

func parseTickSec*(raw: string): int =
  ## `DONKEY_SCHEDULES_TICK_SEC` with the documented fallback to 60.
  parseTickSecValue(raw).valueOr(SchedulerTickSecDefault)

func parseCatchUpPolicyValue(raw: string): Result[ScheduleCatchUp, string] =
  case raw.strip().toLowerAscii()
  of "", "skip":
    ok(scSkip)
  of "once":
    ok(scOnce)
  else:
    err("DONKEY_SCHEDULE_CATCHUP '" & raw & "' is not skip|once")

func parseCatchUpPolicy*(raw: string): ScheduleCatchUp =
  ## `DONKEY_SCHEDULE_CATCHUP`, default `scSkip`.
  parseCatchUpPolicyValue(raw).valueOr(scSkip)

func parseSchedulerConfig*(lookup: EnvLookup): SchedulerConfig =
  ## Reads the scheduler knobs at the edge. Never fails: invalid values fall
  ## back to the defaults and land in `warnings` for the startup log.
  ##
  ## `DONKEY_SCHEDULES_TICK_SEC` is read here and nowhere else, so a cron
  ## configured for `DONKEY_HEARTBEAT_CRON` cannot change the scheduler
  ## interval.
  if lookup == nil:
    return SchedulerConfig(
      enabled: false,
      tickSec: SchedulerTickSecDefault,
      catchUp: scSkip,
      catchUpMaxHours: CatchUpHoursDefault,
    )

  result.enabled = parseEnabled(lookup(EnvSchedulesEnabled))

  let tick = parseTickSecValue(lookup(EnvSchedulesTickSec))
  if tick.isErr:
    result.tickSec = SchedulerTickSecDefault
    result.warnings.add(tick.error)
  else:
    result.tickSec = tick.get()

  let catchUp = parseCatchUpPolicyValue(lookup(EnvScheduleCatchUp))
  if catchUp.isErr:
    result.catchUp = scSkip
    result.warnings.add(catchUp.error)
  else:
    result.catchUp = catchUp.get()

  let hours = validateCatchUpHours(lookup(EnvScheduleCatchUpMaxH))
  if hours.isErr:
    result.catchUpMaxHours = CatchUpHoursDefault
    result.warnings.add(hours.error)
  else:
    result.catchUpMaxHours = hours.get()

# ── One tick ─────────────────────────────────────────────────────────────────

proc runSchedulerTick*(store: ScheduleStorePort;
                       load: ScheduleSnapshotLoader;
                       enqueue: ScheduleEnqueueFn;
                       cfg: SchedulerConfig;
                       nowMs: int64;
                       log: Logger = newLogger("scheduler")
                      ): SchedulerTickSummary =
  ## Runs one pass over every persisted schedule at `nowMs`.
  ##
  ## Disabled schedules are skipped for firing; a far-future cron has no due
  ## occurrence and fires nothing. Each enabled schedule goes through
  ## `tickSchedule`, which persists the watermark before enqueueing and returns
  ## at most one occurrence. Anything that goes wrong is recorded in the
  ## summary and logged; this proc does not raise.
  result = SchedulerTickSummary()

  if load == nil:
    result.loadError = "schedule snapshot loader unavailable"
    log.error("scheduler: " & result.loadError)
    return

  let snapshot = load()
  if snapshot.isErr:
    result.loadError = snapshot.error
    log.error("scheduler: cannot load schedules: " & result.loadError)
    return

  let schedules = snapshot.get()
  result.loaded = schedules.len
  let maxLookbackMinutes = max(cfg.catchUpMaxHours, 1) * 60

  for entry in schedules:
    if entry.loadWarning.len > 0:
      inc result.legacyWarnings

    let id = entry.spec.id
    if not entry.spec.enabled:
      inc result.disabled
      ## FR-5: still run the tick so the watermark advances. Skipping would
      ## freeze it and replay the disabled period on re-enable.
      log.debug("scheduler: id=" & id & " disabled; advancing the watermark")

    let ticked = tickSchedule(
      store, entry.spec, nowMs, enqueue,
      maxLookbackMinutes = maxLookbackMinutes)
    if ticked.isErr:
      result.errors.add(id & ": " & ticked.error)
      log.error("scheduler: tick failed id=" & id & " error=" & ticked.error)
      continue

    let tick = ticked.get()
    if tick.firedAtMs.isSome:
      inc result.fired
      log.info("scheduler: fired id=" & id & " at=" & $tick.firedAtMs.get())
    if tick.missedOccurrenceMs.isSome:
      inc result.missed
      let missedAt = tick.missedOccurrenceMs.get()
      log.warn("scheduler: missed occurrence id=" & id &
        " missedOccurrenceMs=" & $missedAt &
        " lateMs=" & $(nowMs - missedAt))
    if tick.enqueueError.len > 0:
      inc result.enqueueErrors
      log.error("scheduler: enqueue failed id=" & id &
        " instant=" & $tick.firedAtMs.get() &
        " enqueueError=" & tick.enqueueError)

# ── Periodic task ────────────────────────────────────────────────────────────

proc schedulerLoop(task: SchedulerTask;
                   store: ScheduleStorePort;
                   load: ScheduleSnapshotLoader;
                   enqueue: ScheduleEnqueueFn;
                   cfg: SchedulerConfig;
                   clock: SchedulerClock;
                   log: Logger) {.async: (raises: []).} =
  ## First tick immediately (so startup logs the loaded schedules), then one
  ## pass per `cfg.tickSec`. Every iteration is guarded: a failure is logged
  ## and the loop sleeps and tries again.
  var firstTick = true
  while not task.stopRequested:
    var summary = SchedulerTickSummary()
    try:
      summary = runSchedulerTick(store, load, enqueue, cfg, clock(), log)
    except CatchableError as e:
      summary.loadError = "tick crashed: " & e.msg
      log.error("scheduler: " & summary.loadError)

    if firstTick:
      firstTick = false
      if summary.loadError.len > 0:
        log.error("scheduler: startup load failed: " & summary.loadError)
      else:
        var line = "scheduler: " & $summary.loaded & " schedule" &
          (if summary.loaded == 1: "" else: "s") & " loaded"
        if summary.legacyWarnings > 0:
          line.add(" (" & $summary.legacyWarnings & " legacy v1 row" &
            (if summary.legacyWarnings == 1: "" else: "s") & ")")
        line.add(", tick every " & $cfg.tickSec & "s")
        log.info(line)

    if task.stopRequested:
      break
    try:
      await sleepAsync(chronos.milliseconds(task.tickSec * 1000))
    except CancelledError:
      break

proc startSchedulerTask*(store: ScheduleStorePort;
                         load: ScheduleSnapshotLoader;
                         enqueue: ScheduleEnqueueFn;
                         cfg: SchedulerConfig;
                         clock: SchedulerClock;
                         log: Logger = newLogger("scheduler")): SchedulerTask =
  ## Starts the dedicated scheduler task. The caller must have checked
  ## `cfg.enabled`; this proc schedules the loop and returns its handle.
  result = SchedulerTask(tickSec: max(cfg.tickSec, SchedulerTickSecMin))
  result.future = schedulerLoop(result, store, load, enqueue, cfg, clock, log)
  asyncSpawn result.future

proc stopSchedulerTask*(task: SchedulerTask) =
  ## Stops the loop on shutdown: the flag ends the iteration and the cancel
  ## aborts a pending `sleepAsync` instead of waiting out the interval.
  if task == nil:
    return
  task.stopRequested = true
  if not task.future.isNil and not task.future.finished():
    task.future.cancelSoon()
