## Automation runtime — one tick of a persisted schedule (US-003 slice).
##
## This is the runtime core only: it loads a watermark through
## `ScheduleStorePort`, asks the pure `decideTick` what to do, persists the
## advanced watermark and then dispatches at most one occurrence through an
## injected `ScheduleEnqueueFn`. It owns no clock, no file I/O and no daemon
## loop; those are supplied by the caller/wiring.
##
## Ordering matters: the watermark is saved **before** the enqueue. A crash
## between the two loses one occurrence (at-most-once) instead of firing it
## twice on the next tick. An enqueue failure is also a consumed attempt: the
## caller sees it in `enqueueError` and the occurrence is never retried.
##
## `scSkip` means "no backlog", not "never fire" (see `schedule_runtime`):
## a due occurrence inside the grace fires normally; a stale one is dropped,
## surfaced in `missedOccurrenceMs` and consumed by advancing the watermark.

import std/[options, strutils]
import ../core/pipeops
import ../domain/automation/schedule_pure
import ../domain/automation/schedule_runtime

type
  ScheduleWatermark* = object
    ## Persisted row owned by the scheduler store. `createdAtMs` is kept so a
    ## lost/recovered record can reinitialise the watermark from creation.
    id*: string
    lastRunAtMs*: int64
    createdAtMs*: int64
    lastFireAtMs*: int64   ## when the schedule last actually fired (0 = never)

  ScheduleStorePort* = object
    ## Persistence boundary. Implementations live in the state adapter (or an
    ## in-memory fake in tests); the runtime never touches files.
    load*: proc(
      scheduleId: string
    ): Result[Option[ScheduleWatermark], string] {.gcsafe, raises: [].}
    save*: proc(
      state: ScheduleWatermark
    ): Result[void, string] {.gcsafe, raises: [].}

  ScheduleEnqueueFn* = proc(
    spec: ScheduleSpec; instantMs: int64
  ): Result[void, string] {.gcsafe, raises: [].}
    ## Dispatches one firing. `Err` is terminal (failed attempt), never retried.

  ScheduleTickResult* = object
    scheduleId*: string
    firedAtMs*: Option[int64]
      ## The occurrence handed to `enqueue`, or `none` when nothing fired.
    watermarkMs*: int64
      ## Watermark after the tick (`max(lastRun, now)`, unchanged on rollback).
    recovered*: bool
      ## The persisted row was missing; the watermark was reinitialised from
      ## `createdAtMs` and this tick deliberately did not fire.
    rolledBack*: bool
      ## `nowMs < lastRunMs`: no firing and no watermark movement.
    missedOccurrenceMs*: Option[int64]
      ## `scSkip` only: a due occurrence older than the grace was dropped.
      ## The watermark already advanced to `nowMs`; this is for logging.
    enqueueError*: string
      ## Non-empty when the firing was consumed but the enqueue failed.

func hasScheduleStore*(store: ScheduleStorePort): bool =
  ## True when both halves of the persistence boundary are wired.
  store.load != nil and store.save != nil

func initialWatermark*(spec: ScheduleSpec): ScheduleWatermark =
  ## The row written when a schedule is created: `lastRunAtMs = createdAtMs`,
  ## so creation itself can never fire.
  ScheduleWatermark(
    id: spec.id,
    lastRunAtMs: spec.createdAtMs,
    createdAtMs: spec.createdAtMs,
  )

proc tickSchedule*(
  store: ScheduleStorePort;
  spec: ScheduleSpec;
  nowMs: int64;
  enqueue: ScheduleEnqueueFn;
  maxLookbackMinutes = CatchUpMaxMinutesDefault;
  graceMs = SkipGraceMsDefault,
): Result[ScheduleTickResult, string] =
  ## Runs one tick for one schedule.
  ##
  ## The watermark is advanced and saved even when nothing fires (disabled,
  ## no due occurrence, rollback, or a dropped `scSkip` occurrence), so the
  ## next tick does not rescan a closed window. For `scSkip`, `graceMs` is how
  ## late an occurrence may be and still fire; a staler one is reported in
  ## `missedOccurrenceMs` and consumed. Store failures are `Err` and fail
  ## closed: no enqueue.
  if not store.hasScheduleStore:
    return err("schedule store unavailable")
  if enqueue == nil:
    return err("schedule enqueue callback unavailable")

  let id = spec.id.strip()
  if id.len == 0:
    return err("schedule id must not be empty")

  var state: ScheduleWatermark
  var recovered = false
  let loaded = store.load(id)
  if loaded.isErr:
    return err("cannot load schedule '" & id & "': " & loaded.error)

  if loaded.get().isNone:
    # Fail closed on a missing row: recreate it from creation and do not fire
    # on the recovery tick. A later tick can resume normally.
    recovered = true
    state = initialWatermark(spec)
    ## Do not write: the row is gone, which means the schedule was removed
    ## between the tick's snapshot and this load. Recreating it would resurrect
    ## a phantom, spec-less row in `ctl schedule list`.
    return ok(ScheduleTickResult(
      scheduleId: id,
      firedAtMs: none(int64),
      watermarkMs: state.lastRunAtMs,
      recovered: true,
    ))

  state = loaded.get().get()
  if state.id != id:
    return err("schedule store returned '" & state.id & "' for '" & id & "'")
  if state.lastRunAtMs < 0 or state.createdAtMs < 0:
    return err("schedule '" & id & "' has a corrupt watermark")

  let decision = decideTick(
    spec, state.lastRunAtMs, nowMs, maxLookbackMinutes, graceMs
  )
  var tick = ScheduleTickResult(
    scheduleId: id,
    firedAtMs: none(int64),
    watermarkMs: decision.watermarkMs,
    rolledBack: decision.rolledBack,
    missedOccurrenceMs: decision.missedOccurrenceMs,
  )

  ## The schedule may have been removed since the load (`ctl remove` is a
  ## separate process). Do not save or fire a row that no longer exists: the
  ## save would recreate a spec-less phantom and queue an obsolete payload.
  if store.load(id).get(none(ScheduleWatermark)).isNone:
    tick.recovered = true
    return ok(tick)

  # Upsert on every tick, even when the watermark is unchanged (rollback, two
  # ticks in the same instant). The contract is "persist at the end of each
  # tick"; the adapter may skip an identical write internally.
  let next = ScheduleWatermark(
    id: id,
    lastRunAtMs: decision.watermarkMs,
    createdAtMs: state.createdAtMs,
    lastFireAtMs: state.lastFireAtMs,
  )
  let saved = store.save(next)
  if saved.isErr:
    return err("cannot persist watermark for schedule '" & id & "': " &
      saved.error)

  if decision.fireAtMs.isNone:
    return ok(tick)

  let instant = decision.fireAtMs.get()
  tick.firedAtMs = some(instant)
  let enqueued = enqueue(spec, instant)
  if enqueued.isErr:
    tick.enqueueError = enqueued.error
    return ok(tick)
  ## Record the firing only after the task reached the inbox: `last_run` in
  ## `ctl schedule list/show` reads this, and it must not claim a run that was
  ## dropped. The watermark is already persisted, so a crash here loses the
  ## display value, not the at-most-once guarantee. Re-check first: `save`
  ## recreates a missing row, and the schedule may have been removed during the
  ## enqueue.
  if store.load(id).get(none(ScheduleWatermark)).isNone:
    return ok(tick)
  discard store.save(ScheduleWatermark(
    id: id,
    lastRunAtMs: decision.watermarkMs,
    createdAtMs: state.createdAtMs,
    lastFireAtMs: instant,
  ))
  ok(tick)
