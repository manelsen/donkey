## Pure scheduler runtime tests — US-003 slice.
##
## Covers the tick decision (fire at most one occurrence, advance the
## watermark, never re-fire a consumed instant, rollback, disabled schedules)
## and the `CATCHUP_MAX_H` configuration guard. No clock: every instant is an
## explicit epoch millisecond.

import std/[options, unittest]
import results
import donkey/domain/automation/schedule_pure
import donkey/domain/automation/schedule_runtime

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

suite "schedule runtime — validateCatchUpHours":

  test "empty input falls back to the 24-hour default":
    check CatchUpHoursDefault == 24
    check CatchUpHoursMax == 24
    check validateCatchUpHours("").get() == 24
    check validateCatchUpHours("   ").get() == 24
    check validateCatchUpHours("\t").get() == 24

  test "accepts the documented range, including 24":
    check validateCatchUpHours("1").get() == 1
    check validateCatchUpHours("6").get() == 6
    check validateCatchUpHours("24").get() == 24
    check validateCatchUpHours(" 24 ").get() == 24

  test "rejects zero":
    let r = validateCatchUpHours("0")
    check r.isErr
    check r.error ==
      "DONKEY_SCHEDULE_CATCHUP_MAX_H must be between 1 and 24 hours (got 0)"

  test "rejects negative values":
    for raw in ["-1", "-24", "-0"]:
      let r = validateCatchUpHours(raw)
      check r.isErr
    check validateCatchUpHours("-1").error ==
      "DONKEY_SCHEDULE_CATCHUP_MAX_H must be between 1 and 24 hours (got -1)"

  test "rejects 25 and anything above the hard ceiling":
    let r = validateCatchUpHours("25")
    check r.isErr
    check r.error ==
      "DONKEY_SCHEDULE_CATCHUP_MAX_H exceeds the 24-hour ceiling (got 25)"
    check validateCatchUpHours("48").isErr
    check validateCatchUpHours("100").isErr
    check validateCatchUpHours("999999").isErr

  test "rejects absurd and non-numeric values without overflowing":
    for raw in [
      "abc", "1.5", "1h", " 1 2 ", "999999999999999999999",
      "123456789", "+", "-",
    ]:
      check validateCatchUpHours(raw).isErr
    check validateCatchUpHours("abc").error ==
      "invalid DONKEY_SCHEDULE_CATCHUP_MAX_H 'abc': expected a whole number of hours"
    check validateCatchUpHours("999999999999999999999").error ==
      "DONKEY_SCHEDULE_CATCHUP_MAX_H is absurdly large: '999999999999999999999'"

suite "schedule runtime — decideTick":

  test "creation instant does not fire":
    let createdAt = at(12, 0)
    let spec = makeSpec("* * * * *", createdAt = createdAt)
    let decision = decideTick(spec, createdAt, createdAt)
    check decision.fireAtMs.isNone
    check decision.watermarkMs == createdAt
    check decision.rolledBack == false

  test "the first matching tick fires once at the occurrence":
    let spec = makeSpec("* * * * *")
    let decision = decideTick(spec, at(11, 59), at(12, 0))
    check decision.fireAtMs == some(at(12, 0))
    check decision.watermarkMs == at(12, 0)

  test "a consumed occurrence is not returned again":
    let spec = makeSpec("* * * * *")
    let decision = decideTick(spec, at(12, 0), at(12, 0) + 30_000)
    check decision.fireAtMs.isNone
    # The watermark may still advance to the tick instant; the consumed
    # occurrence stays behind the open left edge of the next window.
    check decision.watermarkMs == at(12, 0) + 30_000

  test "scSkip never fires but still advances the watermark":
    let spec = makeSpec("*/15 * * * *", catchUp = scSkip)
    let decision = decideTick(spec, at(11, 0), at(12, 30))
    check decision.fireAtMs.isNone
    check decision.watermarkMs == at(12, 30)

  test "a disabled schedule never fires but still advances the watermark":
    let spec = makeSpec("* * * * *", enabled = false)
    let decision = decideTick(spec, at(11, 59), at(12, 30))
    check decision.fireAtMs.isNone
    check decision.watermarkMs == at(12, 30)

  test "clock rollback fires nothing and keeps the watermark":
    let spec = makeSpec("* * * * *")
    let decision = decideTick(spec, at(12, 10), at(12, 5))
    check decision.fireAtMs.isNone
    check decision.watermarkMs == at(12, 10)
    check decision.rolledBack

  test "the injected lookback bounds the catch-up scan":
    let spec = makeSpec("0 * * * *")
    check decideTick(spec, at(10, 30), at(12, 30)).fireAtMs == some(at(12, 0))
    check decideTick(
      spec, at(10, 30), at(12, 30), maxLookbackMinutes = 10
    ).fireAtMs.isNone

  test "an offset schedule fires the real UTC instant":
    # 09:00 at UTC-03:00 is 12:00Z.
    var spec = makeSpec("0 9 * * *")
    spec.tzOffsetMinutes = -180
    check decideTick(spec, at(11, 0), at(12, 0)).fireAtMs == some(at(12, 0))

suite "schedule runtime — scSkip means no backlog, not never fire":

  test "scSkip fires the occurrence at the exact tick instant":
    let spec = makeSpec("* * * * *", catchUp = scSkip)
    let decision = decideTick(spec, at(11, 59), at(12, 0))
    check decision.fireAtMs == some(at(12, 0))
    check decision.watermarkMs == at(12, 0)
    check decision.missedOccurrenceMs.isNone

  test "scSkip fires an occurrence 30 s late, inside the 2-minute grace":
    let spec = makeSpec("* * * * *", catchUp = scSkip)
    let decision = decideTick(spec, at(11, 59), at(12, 0) + 30_000)
    check decision.fireAtMs == some(at(12, 0))
    check decision.watermarkMs == at(12, 0) + 30_000
    check decision.missedOccurrenceMs.isNone

  test "scSkip drops a 30-day-stale occurrence, advances and reports it":
    let spec = makeSpec("0 9 * * *", catchUp = scSkip)
    let now = 30 * DayMs + at(12, 0)
    let decision = decideTick(spec, 0'i64, now)
    check decision.fireAtMs.isNone
    check decision.missedOccurrenceMs == some(at(9, 0))
    check decision.watermarkMs == now

    # The next tick starts from `now`: the stale instant is not revisited.
    let next = decideTick(spec, decision.watermarkMs, now + MinuteMs)
    check next.fireAtMs.isNone
    check next.missedOccurrenceMs.isNone
    check next.watermarkMs == now + MinuteMs

  test "scSkip with graceMs=0 only fires the exact instant":
    let spec = makeSpec("* * * * *", catchUp = scSkip)
    let exact = decideTick(spec, at(11, 59), at(12, 0), graceMs = 0)
    check exact.fireAtMs == some(at(12, 0))
    let late = decideTick(
      spec, at(11, 59), at(12, 0) + 30_000, graceMs = 0
    )
    check late.fireAtMs.isNone
    check late.missedOccurrenceMs == some(at(12, 0))
    check late.watermarkMs == at(12, 0) + 30_000

  test "scSkip rollback fires nothing and keeps the watermark":
    let spec = makeSpec("* * * * *", catchUp = scSkip)
    let decision = decideTick(spec, at(12, 10), at(12, 5))
    check decision.fireAtMs.isNone
    check decision.missedOccurrenceMs.isNone
    check decision.watermarkMs == at(12, 10)
    check decision.rolledBack

  test "scSkip with a never-matching cron advances nothing":
    let spec = makeSpec("0 0 30 2 *", catchUp = scSkip)
    let decision = decideTick(spec, at(12, 0), at(12, 30))
    check decision.fireAtMs.isNone
    check decision.missedOccurrenceMs.isNone
    check decision.watermarkMs == at(12, 0)

  test "scOnce still fires the newest occurrence after a 30-day gap":
    let spec = makeSpec("0 9 * * *", catchUp = scOnce)
    let now = 30 * DayMs + at(12, 0)
    let decision = decideTick(spec, 0'i64, now)
    check decision.fireAtMs == some(now - 3 * HourMs)
    check decision.missedOccurrenceMs.isNone
    check decision.watermarkMs == now
