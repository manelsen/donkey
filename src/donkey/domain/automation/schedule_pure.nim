## Pure schedule spec — cron expression, fixed timezone offset, and window math.
##
## Everything here is `func`: no clock, disk, or environment access. Callers
## inject `nowMs`, `lastRunMs`, and the persisted offset. The timezone model is
## deliberately a fixed offset (`UTC±HH:MM`); IANA names and DST are rejected.
##
## Instants are epoch milliseconds. A cron occurrence lives on a minute
## boundary in *local* wall-clock time; the offset is added before matching and
## removed before returning the real UTC epoch.
##
## `cronExpr` holds one of three trigger forms (`parseTrigger`):
##   - a 5-field cron expression (`0 9 * * 1-5`);
##   - an alias for one: `@hourly`, `@daily`/`@midnight`, `@weekly`,
##     `@monthly`, `@yearly`/`@annually`;
##   - an interval, `@every <n><m|h|d>…` (`@every 30m`, `@every 1h30m`): the
##     occurrences are `createdAtMs + k × period`, k ≥ 1, so the first comes
##     one period after the creation. An interval has no wall clock and ignores
##     the timezone offset.

import std/[options, strutils, times]
import ../../core/pipeops
import ../../core/cron
import ../../core/types

const
  MinuteMs* = 60_000'i64
  EveryPrefix* = "@every"
  CronAliases* = [
    ("@hourly", "0 * * * *"), ("@daily", "0 0 * * *"),
    ("@midnight", "0 0 * * *"), ("@weekly", "0 0 * * 0"),
    ("@monthly", "0 0 1 * *"), ("@yearly", "0 0 1 1 *"),
    ("@annually", "0 0 1 1 *")]
  HorizonDays* = 366
  HorizonMinutes* = HorizonDays * 24 * 60
  CatchUpMaxMinutesDefault* = 24 * 60
  MinTzOffsetMinutes* = -840
  MaxTzOffsetMinutes* = 840
  MaxPayloadBytes* = 4096

type
  TriggerKind* = enum
    tkCron,      ## a cron expression or an alias for one
    tkInterval   ## `@every …`: a fixed period from the creation

  Trigger* = object
    case kind*: TriggerKind
    of tkCron:
      cron*: CronExpr
    of tkInterval:
      periodMs*: int64

  ScheduleCatchUp* = enum
    ## What to do with occurrences missed while the scheduler was down/behind.
    scSkip,  ## never fire a missed occurrence
    scOnce   ## fire at most the most recent missed occurrence

  ScheduleSpec* = object
    ## Persisted schedule definition. `cronExpr` is the original 5-field text;
    ## `channel` is the persisted channel name validated against ChannelKind.
    id*: string
    cronExpr*: string
    tzOffsetMinutes*: int
    userId*: string
    channel*: string
    payload*: string
    catchUp*: ScheduleCatchUp
    enabled*: bool
    createdAtMs*: int64

# ── Timezone offset parsing ───────────────────────────────────────────────────

func isAsciiDigit(c: char): bool =
  c >= '0' and c <= '9'

func digitValue(c: char): int =
  ord(c) - ord('0')

func parseTzOffset*(raw: string): Result[int, string] =
  ## Parses a fixed offset into minutes east of UTC.
  ##
  ## Accepts `UTC±HH:MM` (the persisted format) and the bare `±HH:MM` form.
  ## The range is `-840..840` minutes (`UTC-14:00`..`UTC+14:00`). IANA names
  ## are rejected explicitly; there is no fallback to UTC.
  let s = raw.strip()
  if s.len == 0:
    return err("invalid timezone offset '': expected UTC±HH:MM")
  if '/' in s:
    return err("unsupported timezone '" & s &
      "': IANA names are not supported, use fixed UTC±HH:MM")

  var body = s
  if s.len >= 3 and s[0 .. 2] == "UTC":
    body = s[3 .. ^1]
  elif s[0] notin {'+', '-'}:
    return err("invalid timezone offset '" & s & "': expected UTC±HH:MM")

  if body.len != 6 or body[0] notin {'+', '-'} or body[3] != ':' or
      not isAsciiDigit(body[1]) or not isAsciiDigit(body[2]) or
      not isAsciiDigit(body[4]) or not isAsciiDigit(body[5]):
    return err("invalid timezone offset '" & s & "': expected UTC±HH:MM")

  let hours = digitValue(body[1]) * 10 + digitValue(body[2])
  let minutes = digitValue(body[4]) * 10 + digitValue(body[5])
  if minutes > 59:
    return err("invalid timezone offset '" & s & "': expected UTC±HH:MM")

  let magnitude = hours * 60 + minutes
  let signed = if body[0] == '-': -magnitude else: magnitude
  if signed < MinTzOffsetMinutes or signed > MaxTzOffsetMinutes:
    return err("timezone offset out of range: '" & s & "' (max ±14:00)")
  ok(signed)

# ── Trigger parsing ──────────────────────────────────────────────────────────

func parseInterval(body: string): Result[int64, string] =
  ## `30m`, `2h`, `1d`, `1h30m`: whole numbers each followed by a unit. The
  ## period is between one minute and the 366-day horizon.
  let maxMinutes = int64(HorizonMinutes)
  if body.len == 0:
    return err("an interval needs a period, like '@every 30m'")
  var total = 0'i64
  var number = -1'i64
  for c in body:
    if c in {'0' .. '9'}:
      if number < 0: number = 0
      number = number * 10 + int64(ord(c) - ord('0'))
      if number > maxMinutes:
        return err("interval longer than " & $HorizonDays & " days: " & body)
    elif c in {'m', 'h', 'd'}:
      if number < 0:
        return err("a unit without a number in interval '" & body & "'")
      let minutes = case c
        of 'm': number
        of 'h': number * 60
        else: number * 24 * 60
      total += minutes
      if total > maxMinutes:
        return err("interval longer than " & $HorizonDays & " days: " & body)
      number = -1
    else:
      return err("unknown unit '" & $c & "' in interval '" & body &
        "': use m, h or d")
  if number >= 0:
    return err("a number without a unit in interval '" & body &
      "': use m, h or d")
  if total < 1:
    return err("interval must be at least one minute: " & body)
  ok(total * MinuteMs)

func parseTrigger*(expr: string): Result[Trigger, string] =
  ## The trigger a schedule's `cronExpr` names (see the module header).
  let s = expr.strip()
  if s.startsWith("@"):
    let word = s.splitWhitespace()[0]
    if word == EveryPrefix:
      let period = ? parseInterval(s[EveryPrefix.len .. ^1].replace(" ", ""))
      return ok(Trigger(kind: tkInterval, periodMs: period))
    for (alias, cron) in CronAliases:
      if s == alias:
        return ok(Trigger(kind: tkCron, cron: ? parseCronExpr(cron)))
    return err("unknown schedule '" & s & "': use a cron expression, " &
      "@hourly, @daily, @weekly, @monthly, @yearly or @every <n><m|h|d>")
  let cron = parseCronExpr(s)
  if cron.isErr:
    return err("invalid cron expression: " & cron.error)
  ok(Trigger(kind: tkCron, cron: cron.get()))

# ── Spec validation ──────────────────────────────────────────────────────────

func isChannelKindName(name: string): bool =
  ## Accepts every spelling of `ChannelKind`, not just the subset the legacy
  ## identity parser knows about.
  for kind in ChannelKind:
    if $kind == name:
      return true
  false

func validateScheduleSpec*(spec: ScheduleSpec): Result[void, string] =
  ## Validates a schedule before persistence. Checks are ordered and every
  ## failure is a deterministic `Err`; no exception escapes.
  if spec.id.strip().len == 0:
    return err("schedule id must not be empty")

  discard ? parseTrigger(spec.cronExpr)

  if spec.tzOffsetMinutes < MinTzOffsetMinutes or
      spec.tzOffsetMinutes > MaxTzOffsetMinutes:
    return err("timezone offset out of range: " & $spec.tzOffsetMinutes &
      " minutes (max ±840)")

  if spec.userId.strip().len == 0:
    return err("schedule userId must not be empty")
  if spec.userId.strip().startsWith("api:"):
    ## `api:` identities are request-scoped: a scheduled firing carries no turn
    ## token, so its reply would be dropped by the API bridge.
    return err("schedule userId must not use the reserved 'api:' prefix")
  if spec.payload.len == 0:
    return err("schedule payload must not be empty")

  if not isChannelKindName(spec.channel):
    return err("invalid channel: unknown channel kind: " & spec.channel)

  if spec.payload.len > MaxPayloadBytes:
    return err("schedule payload exceeds " & $MaxPayloadBytes & " bytes")
  ok()

# ── Local-minute helpers ─────────────────────────────────────────────────────

func floorDiv(a, b: int64): int64 =
  ## Floor division, safe for negative instants (pre-1970 or rollback tests).
  if a >= 0:
    a div b
  else:
    -((-a + b - 1) div b)

func localMinuteOf(instantMs, offsetMinutes: int64): int64 =
  floorDiv(instantMs + offsetMinutes * MinuteMs, MinuteMs)

func utcMsOfLocalMinute(localMinute, offsetMinutes: int64): int64 =
  localMinute * MinuteMs - offsetMinutes * MinuteMs

func localDateTime(localMinute: int64): DateTime =
  ## Local wall-clock fields for a minute since the epoch. `fromUnix(...).utc`
  ## only lazily initializes the immutable UTC zone singleton; the conversion
  ## itself is deterministic, so asserting purity here is safe.
  {.cast(noSideEffect).}:
    fromUnix(localMinute * 60).utc

func specTrigger(spec: ScheduleSpec): Option[Trigger] =
  let parsed = parseTrigger(spec.cronExpr)
  if parsed.isErr:
    none(Trigger)
  else:
    some(parsed.get())

# ── Interval math ────────────────────────────────────────────────────────────

func intervalAfter(createdAtMs, periodMs, instantMs: int64): int64 =
  ## First `createdAt + k × period` (k ≥ 1) strictly after `instantMs`.
  let k = max(floorDiv(instantMs - createdAtMs, periodMs) + 1, 1'i64)
  createdAtMs + k * periodMs

func intervalAtOrBefore(createdAtMs, periodMs, instantMs: int64): Option[int64] =
  ## Last `createdAt + k × period` (k ≥ 1) at or before `instantMs`.
  let k = floorDiv(instantMs - createdAtMs, periodMs)
  if k < 1: none(int64) else: some(createdAtMs + k * periodMs)

# ── Window and next-run math ─────────────────────────────────────────────────

func nextRunAfterMs*(spec: ScheduleSpec; nowMs: int64): Option[int64] =
  ## First cron occurrence strictly after `nowMs`, or `none` when the
  ## expression never matches within the 366-day horizon.
  ##
  ## An occurrence exactly at `nowMs` is excluded: it belongs to the closed
  ## right edge of the `(lastRunMs, nowMs]` window, not to the next run.
  let trigger = specTrigger(spec)
  if trigger.isNone:
    return none(int64)
  if trigger.get().kind == tkInterval:
    return some(intervalAfter(spec.createdAtMs, trigger.get().periodMs, nowMs))
  let expr = trigger.get().cron
  let offset = int64(spec.tzOffsetMinutes)
  let startLocal = localMinuteOf(nowMs, offset) + 1

  for i in 0'i64 ..< int64(HorizonMinutes):
    let localMinute = startLocal + i
    if matchesCron(expr, localDateTime(localMinute)):
      return some(utcMsOfLocalMinute(localMinute, offset))
  none(int64)

func dueInstants*(spec: ScheduleSpec; lastRunMs, nowMs: int64): seq[int64] =
  ## All occurrences in `(lastRunMs, nowMs]`, oldest first.
  ##
  ## The right edge is inclusive. A clock rollback (`nowMs < lastRunMs`) gives
  ## an empty window. The search is bounded by the 366-day horizon so a stale
  ## `lastRunMs` cannot replay an unbounded backlog.
  result = @[]
  if nowMs < lastRunMs:
    return
  let trigger = specTrigger(spec)
  if trigger.isNone:
    return
  if trigger.get().kind == tkInterval:
    let period = trigger.get().periodMs
    let start = max(lastRunMs, nowMs - int64(HorizonMinutes) * MinuteMs)
    var instant = intervalAfter(spec.createdAtMs, period, start)
    while instant <= nowMs:
      result.add(instant)
      instant += period
    return
  let expr = trigger.get().cron
  let offset = int64(spec.tzOffsetMinutes)
  let lastLocal = localMinuteOf(lastRunMs, offset)
  let nowLocal = localMinuteOf(nowMs, offset)
  let horizonStart = nowLocal - int64(HorizonMinutes) + 1
  var localMinute = max(lastLocal + 1, horizonStart)
  while localMinute <= nowLocal:
    if matchesCron(expr, localDateTime(localMinute)):
      result.add(utcMsOfLocalMinute(localMinute, offset))
    inc localMinute

func catchUpInstant*(
  spec: ScheduleSpec;
  lastRunMs, nowMs: int64;
  maxLookbackMinutes = CatchUpMaxMinutesDefault,
): Option[int64] =
  ## Applies the spec's catch-up policy to the missed window.
  ##
  ## `scSkip` returns `none` without scanning. `scOnce` searches backwards from
  ## `nowMs` only as far as `maxLookbackMinutes` (default 24 h, clamped to the
  ## 366-day horizon) and returns at most the most recent occurrence in
  ## `(lastRunMs, nowMs]`; a backlog is never replayed, no matter how long the
  ## outage was. The lookback is a search window, not a gate on the outage
  ## duration: a 30-day gap whose newest occurrence is 3 h old still fires once.
  ## Clock rollback yields `none`.
  if spec.catchUp == scSkip:
    return none(int64)
  if nowMs < lastRunMs:
    return none(int64)
  if maxLookbackMinutes <= 0:
    return none(int64)
  let trigger = specTrigger(spec)
  if trigger.isNone:
    return none(int64)
  let lookback = min(int64(maxLookbackMinutes), int64(HorizonMinutes))
  if trigger.get().kind == tkInterval:
    let newest = intervalAtOrBefore(
      spec.createdAtMs, trigger.get().periodMs, nowMs)
    if newest.isNone: return none(int64)
    let at = newest.get()
    if at <= lastRunMs or nowMs - at >= lookback * MinuteMs:
      return none(int64)
    return some(at)
  let expr = trigger.get().cron
  let offset = int64(spec.tzOffsetMinutes)
  let lastLocal = localMinuteOf(lastRunMs, offset)
  let nowLocal = localMinuteOf(nowMs, offset)
  let lookbackStart = nowLocal - lookback + 1
  let firstLocal = max(lastLocal + 1, lookbackStart)
  var localMinute = nowLocal
  while localMinute >= firstLocal:
    if matchesCron(expr, localDateTime(localMinute)):
      return some(utcMsOfLocalMinute(localMinute, offset))
    dec localMinute
  none(int64)

func closestGapMs*(spec: ScheduleSpec; fromMs, stopBelowMs: int64): Option[int64] =
  ## The shortest time between two consecutive occurrences after `fromMs`,
  ## within the 366-day horizon; `none` with fewer than two. The scan stops
  ## as soon as a gap below `stopBelowMs` is seen, so a dense schedule is
  ## answered at once.
  let trigger = specTrigger(spec)
  if trigger.isNone:
    return none(int64)
  if trigger.get().kind == tkInterval:
    return some(trigger.get().periodMs)
  let expr = trigger.get().cron
  let offset = int64(spec.tzOffsetMinutes)
  let startLocal = localMinuteOf(fromMs, offset) + 1
  var previous = -1'i64
  var best = none(int64)
  for i in 0'i64 ..< int64(HorizonMinutes):
    let localMinute = startLocal + i
    if matchesCron(expr, localDateTime(localMinute)):
      if previous >= 0:
        let gap = (localMinute - previous) * MinuteMs
        if best.isNone or gap < best.get():
          best = some(gap)
          if gap < stopBelowMs:
            return best
      previous = localMinute
  best
