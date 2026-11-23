## Pure runtime decisions for the automation scheduler.
##
## This module holds the parts of US-003 that must stay free of clocks, disk
## and environment: what a single tick should do with a persisted watermark,
## and the guard for `DONKEY_SCHEDULE_CATCHUP_MAX_H`.
##
## The app layer is responsible for loading the watermark, calling
## `decideTick`, persisting `watermarkMs` and only then dispatching
## `fireAtMs`. Persisting first is what keeps the contract at-most-once.
##
## Resolution of the PRD contradiction around `scSkip`: `schedule_pure`'s
## `catchUpInstant` returns `none` unconditionally for `scSkip`, which would
## make the default schedule never fire at all. Here `scSkip` means **no
## backlog**, not "never fire": the first occurrence strictly after the
## watermark is fired when it is due within `SkipGraceMsDefault`, and a stale
## occurrence beyond that grace is dropped while the watermark advances to
## `nowMs` (reported via `missedOccurrenceMs`). `catchUpInstant` is left
## untouched and is used only for `scOnce`.

import std/[options, strutils]
import ../../core/pipeops
import ./schedule_pure

const
  SkipGraceMsDefault* = 120_000'i64
    ## How late a `scSkip` occurrence may be and still fire on a normal tick.
    ## Two minutes covers a 60 s tick plus scheduling drift. `0` means "only
    ## the exact instant"; negative values are treated as `0`.
  CatchUpHoursDefault* = 24
    ## `DONKEY_SCHEDULE_CATCHUP_MAX_H` default when the variable is unset.
  CatchUpHoursMax* = 24
    ## Hard ceiling for the catch-up lookback. The pure API clamps to the
    ## 366-day diagnostic horizon; configuration is never allowed near it.
  MaxCatchUpHoursDigits = 6
    ## Parsing bound: anything wider is rejected as absurd before it can
    ## overflow an `int`.

type
  TickDecision* = object
    ## Outcome of one tick for one schedule.
    fireAtMs*: Option[int64]
      ## At most one occurrence to enqueue, or `none`.
    watermarkMs*: int64
      ## New watermark: `max(lastRunMs, nowMs)`. On a clock rollback this is
      ## the unchanged `lastRunMs`, so the watermark never moves backwards.
    rolledBack*: bool
      ## True when `nowMs < lastRunMs`; no firing and no watermark change.
    missedOccurrenceMs*: Option[int64]
      ## `scSkip` only: a due occurrence older than `graceMs` was dropped.
      ## The caller logs it; the watermark has already advanced to `nowMs`.
      ## `none` when nothing was dropped.

func validateCatchUpHours*(raw: string): Result[int, string] =
  ## Validates the raw `DONKEY_SCHEDULE_CATCHUP_MAX_H` value at the config
  ## boundary. An unset/blank value falls back to `CatchUpHoursDefault`.
  ##
  ## The accepted range is `1..24` hours. Zero and negatives are rejected
  ## instead of being treated as "disable catch-up": the per-spec `catchUp`
  ## policy (`scSkip`) is the way to disable it. Values wider than six digits
  ## are rejected before parsing so absurd input cannot overflow.
  let s = raw.strip()
  if s.len == 0:
    return ok(CatchUpHoursDefault)

  var i = 0
  var negative = false
  if s[0] == '-':
    negative = true
    inc i
  elif s[0] == '+':
    inc i

  if i >= s.len:
    return err("invalid DONKEY_SCHEDULE_CATCHUP_MAX_H '" & raw &
      "': expected a whole number of hours")
  if s.len - i > MaxCatchUpHoursDigits:
    return err("DONKEY_SCHEDULE_CATCHUP_MAX_H is absurdly large: '" & raw & "'")

  var value = 0
  while i < s.len:
    let c = s[i]
    if c < '0' or c > '9':
      return err("invalid DONKEY_SCHEDULE_CATCHUP_MAX_H '" & raw &
        "': expected a whole number of hours")
    value = value * 10 + (ord(c) - ord('0'))
    inc i

  if negative:
    value = -value
  if value <= 0:
    return err("DONKEY_SCHEDULE_CATCHUP_MAX_H must be between 1 and " &
      $CatchUpHoursMax & " hours (got " & $value & ")")
  if value > CatchUpHoursMax:
    return err("DONKEY_SCHEDULE_CATCHUP_MAX_H exceeds the " &
      $CatchUpHoursMax & "-hour ceiling (got " & $value & ")")
  ok(value)

func decideTick*(
  spec: ScheduleSpec;
  lastRunMs, nowMs: int64;
  maxLookbackMinutes = CatchUpMaxMinutesDefault;
  graceMs = SkipGraceMsDefault,
): TickDecision =
  ## Decides what one tick does without touching I/O.
  ##
  ## - A clock rollback (`nowMs < lastRunMs`) is a no-op: no firing and the
  ##   watermark stays at `lastRunMs`.
  ## - Disabled schedules never fire, but the watermark advances so a
  ##   re-enabled schedule does not replay the disabled period.
  ## - `scSkip` looks forward only: the first occurrence after the watermark
  ##   is fired when it is at most `graceMs` old. A stale occurrence is
  ##   dropped and reported instead of firing the same instant every tick.
  ##   A never-matching cron advances nothing.
  ## - `scOnce` uses `catchUpInstant`, so at most the most recent occurrence
  ##   in `(lastRunMs, nowMs]` is returned, bounded by `maxLookbackMinutes`.
  ## - An occurrence at or below `lastRunMs` is never returned: it was already
  ##   consumed by a previous tick.
  result.rolledBack = nowMs < lastRunMs
  if result.rolledBack:
    result.watermarkMs = lastRunMs
    return

  result.watermarkMs = max(lastRunMs, nowMs)
  if not spec.enabled:
    return

  if spec.catchUp == scSkip:
    ## `skip` means "no backlog", not "never fire". The earliest unconsumed
    ## occurrence is the candidate; when it is within the grace window it is
    ## fired. When it is already stale, look for the newest occurrence inside
    ## the window instead of dropping the whole interval: starting from the
    ## watermark made a stale first occurrence shadow a newer one (every-minute
    ## cron, a 3-minute gap). If nothing is inside the window, report the
    ## earliest as missed and advance.
    let grace = max(graceMs, 0'i64)
    let candidate = nextRunAfterMs(spec, lastRunMs)
    if candidate.isNone:
      # Invalid or never-matching cron: nothing to consume, so leave the
      # watermark where it is rather than silently closing a window.
      result.watermarkMs = lastRunMs
      return
    let at = candidate.get()
    if at > nowMs:
      return
    if nowMs - at <= grace:
      result.fireAtMs = some(at)
      return
    let searchFrom = max(lastRunMs, max(0'i64, nowMs - grace))
    let recent = nextRunAfterMs(spec, searchFrom)
    if recent.isSome:
      let newest = recent.get()
      if newest <= nowMs and nowMs - newest <= grace:
        result.fireAtMs = some(newest)
        return
    result.missedOccurrenceMs = some(at)

  let instant = catchUpInstant(spec, lastRunMs, nowMs, maxLookbackMinutes)
  if instant.isSome:
    let at = instant.get()
    if at > lastRunMs and at <= nowMs:
      result.fireAtMs = some(at)
