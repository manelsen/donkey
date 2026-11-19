## Pure schedule spec tests — US-001 (spec/offset) and US-002 (window,
## missed occurrences, and catch-up).
##
## Covers fixed-offset timezone parsing, cron validation, the
## `(lastRunMs, nowMs]` window, strict next-run lookup, the 366-day
## diagnostic horizon, clock rollback, bounded catch-up, and
## first-observation semantics.
## No real clock: every instant below is an explicit epoch millisecond.

import std/[options, strutils, unittest]
import results
import donkey/core/types
import donkey/domain/automation/schedule_pure

const
  MinuteMs = 60_000'i64
  HourMs = 3_600_000'i64
  DayMs = 24 * HourMs

func at(hour, minute: int): int64 =
  ## Epoch milliseconds on 1970-01-01 UTC (fixed test clock).
  int64(hour) * HourMs + int64(minute) * MinuteMs

func dayAt(day, hour, minute: int): int64 =
  ## Epoch milliseconds on 1970-01-01 UTC plus `day` whole days.
  int64(day) * DayMs + int64(hour) * HourMs + int64(minute) * MinuteMs

func makeSpec(
  cron: string;
  tz = 0;
  catchUp = scSkip;
  createdAt = 0'i64;
  enabled = true;
  id = "sched-1";
  userId = "user-1";
  channel = "telegram";
  payload = "payload";
): ScheduleSpec =
  ScheduleSpec(
    id: id,
    cronExpr: cron,
    tzOffsetMinutes: tz,
    userId: userId,
    channel: channel,
    payload: payload,
    catchUp: catchUp,
    enabled: enabled,
    createdAtMs: createdAt,
  )

proc runTests*() =
  suite "schedule spec — parseTzOffset":

    test "accepts UTC-03:00":
      let r = parseTzOffset("UTC-03:00")
      check r.isOk
      check r.get() == -180

    test "accepts UTC+05:30":
      let r = parseTzOffset("UTC+05:30")
      check r.isOk
      check r.get() == 330

    test "accepts both range boundaries":
      check parseTzOffset("UTC-14:00").get() == -840
      check parseTzOffset("UTC+14:00").get() == 840

    test "accepts a bare fixed offset":
      check parseTzOffset("-03:00").get() == -180
      check parseTzOffset("+00:00").get() == 0

    test "rejects an IANA name with an explicit error":
      let r = parseTzOffset("America/Sao_Paulo")
      check r.isErr
      check r.error ==
        "unsupported timezone 'America/Sao_Paulo': IANA names are not supported, use fixed UTC±HH:MM"

    test "rejects an offset outside ±14:00":
      let r = parseTzOffset("UTC+15:00")
      check r.isErr
      check r.error == "timezone offset out of range: 'UTC+15:00' (max ±14:00)"

    test "rejects UTC+14:30: the range is a minute count, not an hour count":
      # `14:30` is 870 minutes, over the 840-minute cap. A range check written
      # against the *hour* component alone (14 <= 14) would wrongly accept it.
      let r = parseTzOffset("UTC+14:30")
      check r.isErr
      check r.error == "timezone offset out of range: 'UTC+14:30' (max ±14:00)"
      check parseTzOffset("UTC-14:30").isErr
      # The exact boundary stays accepted.
      check parseTzOffset("UTC+14:00").get() == 840

    test "rejects lowercase 'utc+03:00': the UTC prefix is case-sensitive":
      let r = parseTzOffset("utc+03:00")
      check r.isErr
      check r.error == "invalid timezone offset 'utc+03:00': expected UTC±HH:MM"
      check parseTzOffset("Utc+03:00").isErr
      # The bare form (no prefix) remains accepted.
      check parseTzOffset("+03:00").get() == 180

    test "rejects an invalid minute component":
      let r = parseTzOffset("UTC+03:60")
      check r.isErr
      check r.error == "invalid timezone offset 'UTC+03:60': expected UTC±HH:MM"

    test "rejects empty and missing-sign inputs":
      check parseTzOffset("").error ==
        "invalid timezone offset '': expected UTC±HH:MM"
      check parseTzOffset("03:00").isErr
      check parseTzOffset("UTC").isErr

  suite "schedule spec — validateScheduleSpec":

    test "accepts a valid spec":
      check validateScheduleSpec(makeSpec("*/5 * * * *")).isOk

    test "accepts every ChannelKind name, including the newly added line":
      # Iterating the enum (rather than a hardcoded {telegram, slack, cli} set)
      # makes a new channel kind fail here until validation learns it too.
      for kind in ChannelKind:
        check validateScheduleSpec(makeSpec("* * * * *", channel = $kind)).isOk
      # Named explicitly so a regression on any of these is obvious in the log.
      check validateScheduleSpec(makeSpec("* * * * *", channel = "line")).isOk
      check validateScheduleSpec(makeSpec("* * * * *", channel = "discord")).isOk
      check validateScheduleSpec(makeSpec("* * * * *", channel = "matrix")).isOk
      # There is no `ckWebhook` in ChannelKind, so "webhook" is not a kind.

    test "rejects an unknown channel spelling such as 'telegramx'":
      let r = validateScheduleSpec(makeSpec("* * * * *", channel = "telegramx"))
      check r.isErr
      check r.error == "invalid channel: unknown channel kind: telegramx"

    test "rejects channel spelling variants: validation is case- and space-sensitive":
      # `channel` is matched by exact `$ChannelKind` equality. It is NOT stripped
      # or lowercased, so "Telegram" and " telegram" are distinct unknown names.
      let cased = validateScheduleSpec(makeSpec("* * * * *", channel = "Telegram"))
      check cased.isErr
      check cased.error == "invalid channel: unknown channel kind: Telegram"
      # The raw value is echoed, including its leading space (hence two spaces
      # after the colon). Pinning this documents that no trimming happens.
      let spaced = validateScheduleSpec(makeSpec("* * * * *", channel = " telegram"))
      check spaced.isErr
      check spaced.error == "invalid channel: unknown channel kind:  telegram"
      # Trailing whitespace is equally significant.
      check validateScheduleSpec(makeSpec("* * * * *", channel = "telegram ")).isErr

    test "accepts a payload of exactly 4096 bytes":
      let spec = makeSpec("0 9 * * *", payload = repeat('x', 4096))
      check validateScheduleSpec(spec).isOk

    test "rejects an empty id":
      let r = validateScheduleSpec(makeSpec("* * * * *", id = ""))
      check r.isErr
      check r.error == "schedule id must not be empty"

    test "rejects a whitespace-only id like an empty one":
      # The check is `id.strip().len == 0`; dropping the strip accepts "   ".
      for blank in ["   ", "\t", "\n", " \t\n "]:
        let r = validateScheduleSpec(makeSpec("* * * * *", id = blank))
        check r.isErr
        check r.error == "schedule id must not be empty"

    test "rejects a cron field above its range":
      let r = validateScheduleSpec(makeSpec("60 * * * *"))
      check r.isErr
      check r.error == "invalid cron expression: cron minute: ceInvalidValue"

    test "rejects a reversed range":
      let r = validateScheduleSpec(makeSpec("10-5 * * * *"))
      check r.isErr
      check r.error == "invalid cron expression: cron minute: ceInvalidRange"

    test "rejects a zero step":
      let r = validateScheduleSpec(makeSpec("*/0 * * * *"))
      check r.isErr
      check r.error == "invalid cron expression: cron minute: ceInvalidValue"

    test "rejects cron expressions with 4 or 6 fields":
      check validateScheduleSpec(makeSpec("0 9 * *")).error ==
        "invalid cron expression: cron: expected 5 fields, got 4"
      check validateScheduleSpec(makeSpec("0 9 * * * *")).error ==
        "invalid cron expression: cron: expected 5 fields, got 6"

    test "rejects an offset outside ±840 minutes":
      let r = validateScheduleSpec(makeSpec("* * * * *", tz = 900))
      check r.isErr
      check r.error == "timezone offset out of range: 900 minutes (max ±840)"

    test "rejects an empty userId":
      let r = validateScheduleSpec(makeSpec("* * * * *", userId = ""))
      check r.isErr
      check r.error == "schedule userId must not be empty"

    test "rejects a whitespace-only userId like an empty one":
      for blank in ["   ", "\t", "\n", " \t\n "]:
        let r = validateScheduleSpec(makeSpec("* * * * *", userId = blank))
        check r.isErr
        check r.error == "schedule userId must not be empty"

    test "rejects an empty payload":
      let r = validateScheduleSpec(makeSpec("* * * * *", payload = ""))
      check r.isErr
      check r.error == "schedule payload must not be empty"

    test "rejects a payload above 4 KiB":
      let r = validateScheduleSpec(makeSpec("* * * * *", payload = repeat('x', 4097)))
      check r.isErr
      check r.error == "schedule payload exceeds 4096 bytes"

    test "rejects a channel that does not parse to ChannelKind":
      let r = validateScheduleSpec(makeSpec("* * * * *", channel = "myspace"))
      check r.isErr
      check r.error == "invalid channel: unknown channel kind: myspace"

    test "reports the id error before the cron error (documented order)":
      # Both fields are invalid; the id check runs first and wins.
      let r = validateScheduleSpec(
        makeSpec("not a cron", id = "", channel = "myspace")
      )
      check r.isErr
      check r.error == "schedule id must not be empty"

    test "reports the first invalid field in the documented check order":
      # id > cron > tz > userId > payload > channel > payload length.
      check validateScheduleSpec(
        makeSpec("not a cron", tz = 900, userId = "", channel = "myspace")
      ).error == "invalid cron expression: cron: expected 5 fields, got 3"
      check validateScheduleSpec(
        makeSpec("* * * * *", tz = 900, userId = "", channel = "myspace")
      ).error == "timezone offset out of range: 900 minutes (max ±840)"
      check validateScheduleSpec(
        makeSpec("* * * * *", userId = "", payload = "", channel = "myspace")
      ).error == "schedule userId must not be empty"
      check validateScheduleSpec(
        makeSpec("* * * * *", payload = "", channel = "myspace")
      ).error == "schedule payload must not be empty"
      # The channel check precedes the 4 KiB size check.
      check validateScheduleSpec(
        makeSpec("* * * * *", payload = repeat('x', 4097), channel = "myspace")
      ).error == "invalid channel: unknown channel kind: myspace"

  suite "schedule spec — nextRunAfterMs":

    test "every minute returns the next minute boundary":
      let spec = makeSpec("* * * * *")
      check nextRunAfterMs(spec, at(12, 0) + 30_000) == some(at(12, 1))

    test "hourly at :15 crosses the hour":
      let spec = makeSpec("15 * * * *")
      check nextRunAfterMs(spec, at(12, 20)) == some(at(13, 15))

    test "exact occurrence is excluded (strictly greater than now)":
      let spec = makeSpec("* * * * *")
      check nextRunAfterMs(spec, at(12, 0)) == some(at(12, 1))

    test "fixed offset is removed before returning epoch":
      # 09:00 at UTC-03:00 is 12:00Z.
      let spec = makeSpec("0 9 * * *", tz = -180)
      check nextRunAfterMs(spec, at(9, 0)) == some(at(12, 0))

    test "changing the offset cannot retro-fire":
      let lastRun = at(11, 59)
      let now = at(12, 0)
      let shifted = makeSpec("0 9 * * *", tz = -180)  # 09:00 local == 12:00Z
      let utc = makeSpec("0 9 * * *", tz = 0)         # 09:00Z already past
      check dueInstants(shifted, lastRun, now) == @[at(12, 0)]
      check dueInstants(utc, lastRun, now).len == 0

    test "never-matching cron returns none":
      let spec = makeSpec("0 0 30 2 *")
      check nextRunAfterMs(spec, at(0, 0)).isNone

    test "leap day beyond the horizon returns none (2025-03-01 -> none)":
      # 2028-02-29 is 1095 days away: no leap day falls inside the 366-day
      # horizon, so a bounded search must report the expression as dormant.
      const now2025Mar01 = 1_740_787_200_000'i64  # 2025-03-01T00:00:00Z
      let spec = makeSpec("0 0 29 2 *")
      check nextRunAfterMs(spec, now2025Mar01).isNone

    test "leap day inside the horizon is found exactly (2027-03-01 -> 2028-02-29)":
      const now2027Mar01 = 1_803_859_200_000'i64  # 2027-03-01T00:00:00Z
      const leapDay2028 = 1_835_395_200_000'i64   # 2028-02-29T00:00:00Z
      let spec = makeSpec("0 0 29 2 *")
      check nextRunAfterMs(spec, now2027Mar01) == some(leapDay2028)
      # 2027-03-01 -> 2028-02-29 is 365 days, i.e. 525_600 minutes from the
      # first candidate (00:01) minus one; this is why the bound must be 366
      # days, not a generic 365-day "one year".
      check HorizonMinutes == 366 * 24 * 60

    test "the last minute of the horizon is still reachable (366-day bound)":
      # 2028-02-29 23:59 is 527_038 minutes after the first candidate
      # (2027-03-01 00:01), just inside the 527_040-minute horizon. A bound
      # shrunk to 365 days (525_600 minutes) or to 527_039 minutes fails here.
      const now2027Mar01 = 1_803_859_200_000'i64  # 2027-03-01T00:00:00Z
      const lastLeapMinute = 1_835_481_540_000'i64  # 2028-02-29T23:59:00Z
      let spec = makeSpec("59 23 29 2 *")
      check nextRunAfterMs(spec, now2027Mar01) == some(lastLeapMinute)

    test "sub-minute now is floored to the next minute (12:00:30 -> 12:01:00)":
      let spec = makeSpec("* * * * *")
      let next = nextRunAfterMs(spec, at(12, 0) + 30_000)
      check next == some(at(12, 1))
      check next.get() mod MinuteMs == 0  # no seconds preserved from nowMs

    test "returned instant is an actual cron match":
      let spec = makeSpec("*/7 * * * *")
      let next = nextRunAfterMs(spec, at(12, 0) + 30_000)
      check next == some(at(12, 7))

    test "invalid cron returns none instead of raising":
      let spec = makeSpec("not a cron")
      check nextRunAfterMs(spec, at(0, 0)).isNone

  suite "schedule spec — window and catch-up":

    test "window is (lastRunMs, nowMs] and includes now":
      let spec = makeSpec("* * * * *")
      check dueInstants(spec, at(11, 59), at(12, 0)) == @[at(12, 0)]
      check dueInstants(spec, at(12, 0), at(12, 0)).len == 0

    test "window returns every match in chronological order":
      let spec = makeSpec("*/15 * * * *")
      check dueInstants(spec, at(11, 0), at(12, 30)) == @[
        at(11, 15), at(11, 30), at(11, 45), at(12, 0), at(12, 15), at(12, 30)
      ]

    test "clock rollback yields an empty window and no crash":
      let spec = makeSpec("* * * * *")
      check dueInstants(spec, at(12, 10), at(12, 5)).len == 0
      check nextRunAfterMs(spec, at(12, 5)) == some(at(12, 6))

    test "clock rollback yields no catch-up":
      let spec = makeSpec("* * * * *", catchUp = scOnce)
      check catchUpInstant(spec, at(12, 10), at(12, 5)).isNone

    test "never-matching cron yields an empty window":
      let spec = makeSpec("0 0 30 2 *")
      check dueInstants(spec, at(0, 0), at(23, 59)).len == 0

    test "scSkip never fires a missed occurrence":
      let spec = makeSpec("*/15 * * * *", catchUp = scSkip)
      check catchUpInstant(spec, at(11, 0), at(12, 30)).isNone
      # scSkip returns before scanning, even with a year-old lastRunMs.
      check catchUpInstant(spec, 0'i64, at(12, 30)).isNone

    test "scOnce fires at most the most recent missed occurrence":
      let spec = makeSpec("*/15 * * * *", catchUp = scOnce)
      check catchUpInstant(spec, at(11, 0), at(12, 30)) == some(at(12, 30))
      check catchUpInstant(spec, at(12, 30), at(12, 30)).isNone

    test "scOnce fires after a 2-hour gap":
      let spec = makeSpec("0 * * * *", catchUp = scOnce)
      check catchUpInstant(spec, at(10, 30), at(12, 30)) == some(at(12, 0))

    test "scOnce fires the newest occurrence after a 30-day gap":
      # US-002: the lookback is a window over the newest match, not a gate on the
      # outage duration. The daily 09:00 cron had 31 occurrences since lastRunMs,
      # but only the most recent one (3 h before now) is caught up, never 30.
      let spec = makeSpec("0 9 * * *", catchUp = scOnce)
      let thirtyDays = 30'i64 * 24 * 60 * MinuteMs
      let now = thirtyDays + at(12, 0)
      check dueInstants(spec, at(0, 0), now).len == 31
      check catchUpInstant(spec, at(0, 0), now) == some(thirtyDays + at(9, 0))

    test "scOnce respects a custom maxLookbackMinutes":
      let spec = makeSpec("0 * * * *", catchUp = scOnce)
      check CatchUpMaxMinutesDefault == 24 * 60
      check catchUpInstant(
        spec, at(10, 0), at(12, 30),
        maxLookbackMinutes = CatchUpMaxMinutesDefault
      ) == some(at(12, 0))
      # Latest occurrence is 12:00, 30 minutes before now: outside a 10-min lookback.
      check catchUpInstant(
        spec, at(10, 0), at(12, 30), maxLookbackMinutes = 10
      ).isNone

  suite "schedule spec — first observation":

    test "creation instant does not fire":
      let createdAt = at(12, 0)
      let spec = makeSpec("* * * * *", catchUp = scOnce, createdAt = createdAt)
      check dueInstants(spec, spec.createdAtMs, spec.createdAtMs).len == 0
      check catchUpInstant(spec, spec.createdAtMs, spec.createdAtMs).isNone

    test "no firing during the creation minute":
      let createdAt = at(12, 0)
      let spec = makeSpec("* * * * *", catchUp = scOnce, createdAt = createdAt)
      check dueInstants(spec, spec.createdAtMs, createdAt + 30_000).len == 0
      check nextRunAfterMs(spec, createdAt + 30_000) == some(at(12, 1))

    test "the first full tick after creation may fire once":
      let createdAt = at(12, 0)
      let spec = makeSpec("* * * * *", catchUp = scOnce, createdAt = createdAt)
      check catchUpInstant(spec, spec.createdAtMs, at(12, 1)) == some(at(12, 1))

  suite "schedule spec — US-002 window edges":

    test "dueInstants excludes the open left edge and includes the sub-minute now":
      let spec = makeSpec("* * * * *")
      # 12:00:00 is strictly after lastRunMs = 11:59:59 and before now.
      check dueInstants(spec, at(11, 59) + 59_000, at(12, 0) + 30_000) == @[at(12, 0)]
      # An occurrence exactly at lastRunMs already belongs to the previous window.
      check dueInstants(spec, at(12, 0), at(12, 0) + 30_000).len == 0

    test "dueInstants is diagnostic and ignores the catch-up policy":
      let expected = @[at(11, 15), at(11, 30), at(11, 45), at(12, 0)]
      let skipSpec = makeSpec("*/15 * * * *", catchUp = scSkip)
      let onceSpec = makeSpec("*/15 * * * *", catchUp = scOnce)
      check dueInstants(skipSpec, at(11, 0), at(12, 0)) == expected
      check dueInstants(onceSpec, at(11, 0), at(12, 0)) == expected

    test "dueInstants returns the real UTC epoch after removing the offset":
      # 09:00 at UTC-03:00 is 12:00Z; the returned epoch must be the real one.
      let spec = makeSpec("0 9 * * *", tz = -180)
      check dueInstants(spec, at(11, 0), at(12, 0)) == @[at(12, 0)]
      # A fractional offset (+05:30) is removed the same way: 09:00 local is 03:30Z.
      let halfHour = makeSpec("0 9 * * *", tz = 330)
      check dueInstants(halfHour, at(3, 0), at(3, 30)) == @[at(3, 30)]

    test "dueInstants truncates an old backlog at the 366-day diagnostic horizon":
      check HorizonDays == 366
      check HorizonMinutes == 527_040
      let yearly = makeSpec("0 0 1 1 *")
      # 1971-02-04 12:00Z: the 366-day window keeps only 1971-01-01, not 1970-01-01.
      check dueInstants(yearly, 0'i64, dayAt(400, 12, 0)) == @[dayAt(365, 0, 0)]

    test "changing the offset cannot retro-fire in dueInstants or catch-up":
      # The old schedule fired at 12:00Z; re-reading it as UTC-03:00 moves 09:00
      # local to 12:00Z, which is already at the watermark and must not repeat.
      let shifted = makeSpec("0 9 * * *", tz = -180, catchUp = scOnce)
      check dueInstants(shifted, at(12, 0), at(12, 30)).len == 0
      check catchUpInstant(shifted, at(12, 0), at(12, 30)).isNone

    test "nextRunAfterMs is strictly greater than nowMs for every offset":
      let now = at(12, 0) + 30_000
      for tz in [-840, -180, 0, 330, 840]:
        let spec = makeSpec("* * * * *", tz = tz)
        let next = nextRunAfterMs(spec, now)
        check next.isSome
        check next.get() > now
        check next.get() mod MinuteMs == 0

  suite "schedule spec — US-002 catch-up":

    test "catch-up includes an occurrence exactly at nowMs":
      let spec = makeSpec("* * * * *", catchUp = scOnce)
      check catchUpInstant(spec, at(11, 59), at(12, 0)) == some(at(12, 0))
      check catchUpInstant(spec, at(12, 0), at(12, 0)).isNone

    test "catch-up returns the real UTC epoch after removing the offset":
      # 09:00 at UTC+05:30 is 03:30Z.
      let spec = makeSpec("0 9 * * *", tz = 330, catchUp = scOnce)
      check catchUpInstant(spec, at(3, 0), at(3, 30)) == some(at(3, 30))

    test "a consumed occurrence is never returned twice":
      let spec = makeSpec("* * * * *", catchUp = scOnce)
      # First tick fires 12:00 and advances the watermark to the tick instant.
      check catchUpInstant(spec, at(11, 59), at(12, 0) + 30_000) == some(at(12, 0))
      # Later ticks in the same minute see an empty window.
      check catchUpInstant(spec, at(12, 0) + 30_000, at(12, 0) + 45_000).isNone
      check dueInstants(spec, at(12, 0) + 30_000, at(12, 0) + 45_000).len == 0
      # A watermark parked exactly on the occurrence is equally safe.
      check catchUpInstant(spec, at(12, 0), at(12, 0) + 30_000).isNone

    test "scSkip returns none without replaying any backlog":
      let spec = makeSpec("* * * * *", catchUp = scSkip)
      check catchUpInstant(spec, 0'i64, 30 * DayMs + at(12, 0)).isNone
      # The policy short-circuits before any scan, even with a huge lookback.
      check catchUpInstant(
        spec, 0'i64, 30 * DayMs + at(12, 0),
        maxLookbackMinutes = HorizonMinutes
      ).isNone
      # An invalid expression is never parsed on the scSkip path.
      let broken = makeSpec("not a cron", catchUp = scSkip)
      check catchUpInstant(broken, 0'i64, at(12, 0)).isNone

    test "a 30-day gap fires at most once, never the 30-day backlog":
      let spec = makeSpec("0 9 * * *", catchUp = scOnce)
      let now = 30 * DayMs + at(12, 0)
      # Diagnostic view sees every missed occurrence (30 days and a bit).
      check dueInstants(spec, 0'i64, now).len == 31
      # The 24 h lookback is a window: it clips the search to the most recent
      # 09:00. The 30-day outage must not suppress the single catch-up firing.
      check catchUpInstant(spec, 0'i64, now) == some(now - 3 * HourMs)
      # Widening the injected lookback still yields exactly one firing.
      check catchUpInstant(
        spec, 0'i64, now, maxLookbackMinutes = 31 * 24 * 60
      ) == some(now - 3 * HourMs)
      # A lookback shorter than the newest match drops it entirely.
      check catchUpInstant(
        spec, 0'i64, now, maxLookbackMinutes = 2 * 60
      ).isNone

    test "scOnce clamps the lookback to the 366-day horizon":
      # Leap-day cron: the newest match is 1968-02-29, more than 366 days before
      # 1971-06-01. Even a 1300-day lookback is clamped to the horizon, so the
      # search never reaches 1968.
      let leapDay = makeSpec("0 0 29 2 *", catchUp = scOnce)
      let now = dayAt(516, 12, 0)
      check catchUpInstant(
        leapDay, dayAt(-1000, 0, 0), now, maxLookbackMinutes = 1300 * 24 * 60
      ).isNone
      # A match inside the horizon is still found once with the same cap.
      let daily = makeSpec("0 9 * * *", catchUp = scOnce)
      check catchUpInstant(
        daily, now - 300 * DayMs, now, maxLookbackMinutes = 1000 * 24 * 60
      ) == some(now - 3 * HourMs)

    test "the default lookback window is exclusive at now - lookback":
      check CatchUpMaxMinutesDefault == 24 * 60
      let yearly = makeSpec("0 0 1 1 *", catchUp = scOnce)
      let now = dayAt(1, 0, 0)  # exactly 24 h after the only match
      # (now - 24 h, now] excludes a match exactly 24 h old.
      check catchUpInstant(yearly, dayAt(-1, 0, 0), now).isNone
      # One extra minute of lookback brings the same match inside the window.
      check catchUpInstant(
        yearly, dayAt(-1, 0, 0), now, maxLookbackMinutes = 24 * 60 + 1
      ) == some(at(0, 0))

    test "scOnce returns none when the latest match is older than the lookback":
      # `0 0 1 1 *` in February: the newest match (January 1st) is far more than
      # 24 h old, even though the gap since lastRunMs is only two hours.
      let yearly = makeSpec("0 0 1 1 *", catchUp = scOnce)
      let now = dayAt(41, 12, 0)  # 1970-02-11 12:00Z
      check catchUpInstant(yearly, now - 2 * HourMs, now).isNone
      check dueInstants(yearly, now - 2 * HourMs, now).len == 0
      # The injected lookback is a hard bound, not a hint.
      let hourly = makeSpec("0 * * * *", catchUp = scOnce)
      check catchUpInstant(
        hourly, at(10, 0), at(12, 30), maxLookbackMinutes = 30
      ).isNone

    test "scOnce with a non-positive lookback returns none":
      let spec = makeSpec("* * * * *", catchUp = scOnce)
      check catchUpInstant(spec, at(11, 59), at(12, 0), maxLookbackMinutes = 0).isNone
      check catchUpInstant(spec, at(11, 59), at(12, 0), maxLookbackMinutes = -5).isNone

    test "clock rollback is an empty window for any offset":
      let spec = makeSpec("*/5 * * * *", tz = -180, catchUp = scOnce)
      check dueInstants(spec, at(12, 10), at(12, 5)).len == 0
      check catchUpInstant(spec, at(12, 10), at(12, 5)).isNone

    test "the initial watermark is createdAtMs, including sub-minute creation":
      let createdAt = at(12, 0) + 30_000
      let spec = makeSpec("* * * * *", catchUp = scOnce, createdAt = createdAt)
      check dueInstants(spec, spec.createdAtMs, createdAt).len == 0
      check catchUpInstant(spec, spec.createdAtMs, createdAt).isNone
      check nextRunAfterMs(spec, spec.createdAtMs) == some(at(12, 1))

    test "creation before an occurrence still allows a single first firing":
      let createdAt = at(11, 59) + 30_000
      let spec = makeSpec("* * * * *", catchUp = scOnce, createdAt = createdAt)
      check dueInstants(spec, spec.createdAtMs, at(12, 0)) == @[at(12, 0)]
      check catchUpInstant(spec, spec.createdAtMs, at(12, 0)) == some(at(12, 0))

    test "a userId in the reserved api: namespace is refused":
      let spec = makeSpec("* * * * *", userId = "api:alice")
      let r = validateScheduleSpec(spec)
      check r.isErr
      check r.error.contains("api:")

when isMainModule:
  runTests()
