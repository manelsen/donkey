import std/[times, strutils, sequtils, algorithm, math]
import ./pipeops

## Cron Scheduler — Pure cron expression parsing and next-run calculation
##
## Supports standard 5-field cron format:
##   ┌───────────── minute (0-59)
##   │ ┌───────────── hour (0-23)
##   │ │ ┌───────────── day of month (1-31)
##   │ │ │ ┌───────────── month (1-12)
##   │ │ │ │ ┌───────────── day of week (0-6, 0 = Sunday)
##   │ │ │ │ │
##   * * * * *
##
## Special characters:
##   *     any value
##   ,     list separator (1,3,5)
##   -     range (1-5)
##   /     step (*/5 = every 5)

type
  CronField* = object
    values*: seq[int]
    hasAll*: bool  # true if "*"

  CronExpr* = object
    minute*: CronField
    hour*: CronField
    dayOfMonth*: CronField
    month*: CronField
    dayOfWeek*: CronField

  ScheduledTask*[T] = object
    id*: string
    expr*: CronExpr
    data*: T
    enabled*: bool

  # Errors for cron parsing
  CronError* = enum
    ceEmptyField
    ceInvalidValue
    ceInvalidRange
    ceInvalidStep
    ceInvalidFieldCount

const
  MinMinute* = 0
  MaxMinute* = 59
  MinHour* = 0
  MaxHour* = 23
  MinDayOfMonth* = 1
  MaxDayOfMonth* = 31
  MinMonth* = 1
  MaxMonth* = 12
  MinDayOfWeek* = 0
  MaxDayOfWeek* = 6

# ── Field parsing helpers ─────────────────────────────────────────────────────

func parseFieldValue*(s: string; minVal, maxVal: int): Result[int, CronError] =
  let trimmed = s.strip()
  if trimmed.len == 0:
    return err(ceEmptyField)
  if trimmed == "*":
    return ok(-1)  # special marker for "any"
  try:
    let v = parseInt(trimmed)
    if v < minVal or v > maxVal:
      return err(ceInvalidValue)
    ok(v)
  except ValueError:
    err(ceInvalidValue)

func parseFieldRange*(
  field: string;
  minVal, maxVal: int
): Result[seq[int], CronError] =
  let parts = field.split('-')
  if parts.len == 1:
    let v = ? parseFieldValue(parts[0], minVal, maxVal)
    if v == -1:
      let empty: seq[int] = @[]
      return ok(empty)  # empty means "all" for single *
    return ok(@[v])
  elif parts.len == 2:
    let start = ? parseFieldValue(parts[0], minVal, maxVal)
    let rangeEnd = ? parseFieldValue(parts[1], minVal, maxVal)
    if start == -1 or rangeEnd == -1:
      return err(ceInvalidRange)
    if start > rangeEnd:
      return err(ceInvalidRange)
    var values: seq[int] = @[]
    for i in start .. rangeEnd:
      values.add(i)
    ok(values)
  else:
    err(ceInvalidRange)

func parseFieldStep(
  field: string;
  minVal, maxVal: int
): Result[seq[int], CronError] =
  let parts = field.split('/')
  if parts.len != 2:
    return err(ceInvalidStep)
  let stepStr = parts[1]
  let stepVal = ? parseFieldValue(stepStr, 1, maxVal)
  if stepVal <= 0:
    return err(ceInvalidStep)
  # Parse the base (before /)
  let baseStr = parts[0]
  var startVal: int
  var hasAll = false
  if baseStr == "*":
    startVal = minVal
    hasAll = true
  else:
    let baseParts = baseStr.split('-')
    if baseParts.len == 1:
      startVal = ? parseFieldValue(baseParts[0], minVal, maxVal)
      if startVal == -1:
        startVal = minVal
        hasAll = true
    elif baseParts.len == 2:
      startVal = ? parseFieldValue(baseParts[0], minVal, maxVal)
      let rangeEnd = ? parseFieldValue(baseParts[1], minVal, maxVal)
      if startVal == -1:
        startVal = minVal
        hasAll = true
      else:
        hasAll = true
        var values: seq[int] = @[]
        for i in startVal .. rangeEnd:
          values.add(i)
        startVal = values[0]
        var stepped: seq[int] = @[]
        for i, v in values:
          if i mod stepVal == 0:
            stepped.add(v)
        return ok(stepped)
    else:
      return err(ceInvalidStep)
  # Generate values from startVal with step
  var values: seq[int] = @[]
  var current = startVal
  while current <= maxVal:
    values.add(current)
    inc(current, stepVal)
  ok(values)

func parseCronField*(field: string; minVal, maxVal: int): Result[CronField, CronError] =
  let trimmed = field.strip()
  if trimmed.len == 0:
    return err(ceEmptyField)
  # Handle comma-separated list
  let parts = trimmed.split(',')
  var allValues: seq[int] = @[]
  var hasAll = false
  for part in parts:
    let partTrimmed = part.strip()
    if partTrimmed.contains('/'):
      let stepValues = ? parseFieldStep(partTrimmed, minVal, maxVal)
      for v in stepValues:
        if v == -1:
          hasAll = true
        elif v notin allValues:
          allValues.add(v)
    elif partTrimmed.contains('-'):
      let rangeValues = ? parseFieldRange(partTrimmed, minVal, maxVal)
      if rangeValues.len == 0:
        hasAll = true
      for v in rangeValues:
        if v notin allValues:
          allValues.add(v)
    else:
      let v = ? parseFieldValue(partTrimmed, minVal, maxVal)
      if v == -1:
        hasAll = true
      elif v notin allValues:
        allValues.add(v)
  allValues.sort(system.cmp[int])
  ok(CronField(values: allValues, hasAll: hasAll))

# ── Full expression parsing ───────────────────────────────────────────────────

func parseCronExpr*(expr: string): Result[CronExpr, string] =
  let parts = expr.strip().splitWhitespace()
  if parts.len != 5:
    return err("cron: expected 5 fields, got " & $parts.len)
  let minuteR = parseCronField(parts[0], MinMinute, MaxMinute)
  if minuteR.isErr:
    return err("cron minute: " & $minuteR.error)
  let hourR = parseCronField(parts[1], MinHour, MaxHour)
  if hourR.isErr:
    return err("cron hour: " & $hourR.error)
  let dayR = parseCronField(parts[2], MinDayOfMonth, MaxDayOfMonth)
  if dayR.isErr:
    return err("cron dayOfMonth: " & $dayR.error)
  let monthR = parseCronField(parts[3], MinMonth, MaxMonth)
  if monthR.isErr:
    return err("cron month: " & $monthR.error)
  let dowR = parseCronField(parts[4], MinDayOfWeek, MaxDayOfWeek)
  if dowR.isErr:
    return err("cron dayOfWeek: " & $dowR.error)
  ok(CronExpr(
    minute: minuteR.get(),
    hour: hourR.get(),
    dayOfMonth: dayR.get(),
    month: monthR.get(),
    dayOfWeek: dowR.get()
  ))

# ── Field matching ───────────────────────────────────────────────────────────

func fieldMatches*(field: CronField; value: int): bool =
  if field.hasAll:
    return true
  value in field.values

func matchesCron*(expr: CronExpr; dt: DateTime): bool =
  # Day-of-month and day-of-week: if both are restricted (not "*"),
  # the cron matches if EITHER matches (OR semantics).
  # If one is unrestricted, use AND semantics with the restricted one.
  let domMatches = fieldMatches(expr.dayOfMonth, dt.monthday)
  let dowMatches = fieldMatches(expr.dayOfWeek, dt.weekday.ord)
  let domAll = expr.dayOfMonth.hasAll
  let dowAll = expr.dayOfWeek.hasAll
  let dayOk =
    if domAll and dowAll:
      true
    elif domAll:
      dowMatches
    elif dowAll:
      domMatches
    else:
      domMatches or dowMatches
  dayOk and
    fieldMatches(expr.minute, dt.minute) and
    fieldMatches(expr.hour, dt.hour) and
    fieldMatches(expr.month, dt.month.ord)

# ── Next run calculation ────────────────────────────────────────────────────

proc nextRun*(expr: CronExpr; fromTime: DateTime): DateTime =
  ## Calculate the next time a cron expression matches.
  ## fromTime is the reference point; returns the next matching moment.
  var dt = fromTime + initTimeInterval(minutes = 1)
  var iterations = 0
  let maxIterations = 366 * 24 * 60  # 1 year safety limit
  while iterations < maxIterations:
    if matchesCron(expr, dt):
      return dt
    # Advance to next minute using DateTime arithmetic
    dt = dt + initTimeInterval(minutes = 1)
    inc(iterations)
  dt  # fallback

# ── Validation helpers ───────────────────────────────────────────────────────

func isValidCron*(expr: string): bool =
  parseCronExpr(expr).isOk

func isValidMinuteField*(field: string): bool =
  parseCronField(field, MinMinute, MaxMinute).isOk

func isValidHourField*(field: string): bool =
  parseCronField(field, MinHour, MaxHour).isOk

func isValidDayOfMonthField*(field: string): bool =
  parseCronField(field, MinDayOfMonth, MaxDayOfMonth).isOk

func isValidMonthField*(field: string): bool =
  parseCronField(field, MinMonth, MaxMonth).isOk

func isValidDayOfWeekField*(field: string): bool =
  parseCronField(field, MinDayOfWeek, MaxDayOfWeek).isOk

# ── Common cron helpers ──────────────────────────────────────────────────────

func everyMinute*: CronExpr = CronExpr(
  minute: CronField(values: @[], hasAll: true),
  hour: CronField(values: @[], hasAll: true),
  dayOfMonth: CronField(values: @[], hasAll: true),
  month: CronField(values: @[], hasAll: true),
  dayOfWeek: CronField(values: @[], hasAll: true)
)

func everyNMinutes*(n: int): Result[CronExpr, string] =
  if n <= 0 or n > 59:
    return err("everyNMinutes: n must be 1-59")
  # Build step values: 0, n, 2n, 3n, ... up to 59
  var values: seq[int] = @[]
  var current = 0
  while current <= 59:
    values.add(current)
    inc(current, n)
  ok(CronExpr(
    minute: CronField(values: values, hasAll: false),
    hour: CronField(values: @[], hasAll: true),
    dayOfMonth: CronField(values: @[], hasAll: true),
    month: CronField(values: @[], hasAll: true),
    dayOfWeek: CronField(values: @[], hasAll: true)
  ))

func hourlyAt*(minute: int): Result[CronExpr, string] =
  if minute < 0 or minute > 59:
    return err("hourlyAt: minute must be 0-59")
  ok(CronExpr(
    minute: CronField(values: @[minute], hasAll: false),
    hour: CronField(values: @[], hasAll: true),
    dayOfMonth: CronField(values: @[], hasAll: true),
    month: CronField(values: @[], hasAll: true),
    dayOfWeek: CronField(values: @[], hasAll: true)
  ))

func dailyAt*(hour, minute: int): Result[CronExpr, string] =
  if hour < 0 or hour > 23:
    return err("dailyAt: hour must be 0-23")
  if minute < 0 or minute > 59:
    return err("dailyAt: minute must be 0-59")
  ok(CronExpr(
    minute: CronField(values: @[minute], hasAll: false),
    hour: CronField(values: @[hour], hasAll: false),
    dayOfMonth: CronField(values: @[], hasAll: true),
    month: CronField(values: @[], hasAll: true),
    dayOfWeek: CronField(values: @[], hasAll: true)
  ))

# ── Task scheduling helpers ────────────────────────────────────────────────────

func newScheduledTask*[T](
  id: string;
  expr: CronExpr;
  data: T;
  enabled: bool = true
): ScheduledTask[T] =
  ScheduledTask[T](id: id, expr: expr, data: data, enabled: enabled)

func disableTask*[T](task: var ScheduledTask[T]) =
  task.enabled = false

func enableTask*[T](task: var ScheduledTask[T]) =
  task.enabled = true

func shouldRun*(task: ScheduledTask; dt: DateTime): bool =
  task.enabled and matchesCron(task.expr, dt)

# ── Cron expression to string ────────────────────────────────────────────────

func cronFieldToStr*(field: CronField): string =
  if field.hasAll:
    return "*"
  if field.values.len == 0:
    return "*"
  field.values.mapIt($it).join(",")

func `$`*(expr: CronExpr): string =
  cronFieldToStr(expr.minute) & " " & cronFieldToStr(expr.hour) & " " &
  cronFieldToStr(expr.dayOfMonth) & " " & cronFieldToStr(expr.month) & " " &
  cronFieldToStr(expr.dayOfWeek)

func `$`*[T](task: ScheduledTask[T]): string =
  "ScheduledTask(id=" & task.id & ", expr=" & $task.expr & ", enabled=" & $task.enabled & ")"
