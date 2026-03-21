## Reminder domain — parseWhen and tool metadata.
## Pure functions only. No I/O.

import std/strutils

# ── Tool metadata (injected into every session) ───────────────────────────────

const
  ReminderToolName* = "schedule_reminder"

  ReminderToolDescription* =
    "Schedule a proactive message to the user at a future time. " &
    "Use this whenever the user asks to be reminded about something at a specific " &
    "time or after a delay. " &
    "IMPORTANT: always convert the user's local time to an absolute ISO 8601 " &
    "string with timezone offset before calling this tool (e.g. " &
    "\"2025-03-18T17:25:00-03:00\"). Alternatively, use a relative offset: " &
    "+30m (30 minutes), +2h (2 hours), +1d (1 day). " &
    "The reminder text is delivered later as a normal outbound message."

  ReminderToolSchema* = """{"type":"object","properties":{"when":{"type":"string","description":"ISO 8601 datetime with timezone (e.g. 2025-03-18T17:25:00-03:00) or relative offset (+30m, +2h, +1d)"},"message":{"type":"string","description":"The reminder message text to deliver to the user"}},"required":["when","message"]}"""

# ── parseWhen ─────────────────────────────────────────────────────────────────

func parseFixedInt(s: string; start, size: int): int =
  parseInt(s[start ..< start + size])

func daysFromCivil(year, month, day: int): int64 =
  let adjustedYear = year - (if month <= 2: 1 else: 0)
  let era = (if adjustedYear >= 0: adjustedYear else: adjustedYear - 399) div 400
  let yoe = adjustedYear - era * 400
  let mp = month + (if month > 2: -3 else: 9)
  let doy = (153 * mp + 2) div 5 + day - 1
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  int64(era * 146097 + doe - 719468)

func unixFromUtcParts(year, month, day, hour, minute, second: int): int64 =
  daysFromCivil(year, month, day) * 86_400 +
  int64(hour) * 3_600 +
  int64(minute) * 60 +
  int64(second)

func parseIsoWhen(s: string): int64 =
  try:
    if s.len == 10 and s[4] == '-' and s[7] == '-':
      let year = parseFixedInt(s, 0, 4)
      let month = parseFixedInt(s, 5, 2)
      let day = parseFixedInt(s, 8, 2)
      return unixFromUtcParts(year, month, day, 0, 0, 0)

    if s.len >= 19 and s[4] == '-' and s[7] == '-' and s[10] in {'T', ' '} and
       s[13] == ':' and s[16] == ':':
      let year = parseFixedInt(s, 0, 4)
      let month = parseFixedInt(s, 5, 2)
      let day = parseFixedInt(s, 8, 2)
      let hour = parseFixedInt(s, 11, 2)
      let minute = parseFixedInt(s, 14, 2)
      let second = parseFixedInt(s, 17, 2)
      var unixTs = unixFromUtcParts(year, month, day, hour, minute, second)

      if s.len == 19:
        return unixTs

      if s.len == 20 and s[^1] == 'Z':
        return unixTs

      if s.len >= 25 and s[19] in {'+', '-'} and s[22] == ':':
        let sign = if s[19] == '+': 1 else: -1
        let offsetHour = parseFixedInt(s, 20, 2)
        let offsetMinute = parseFixedInt(s, 23, 2)
        let offsetSec = int64(sign * (offsetHour * 3_600 + offsetMinute * 60))
        unixTs -= offsetSec
        return unixTs
  except ValueError:
    discard

  int64.low

func parseWhen*(whenStr: string; nowSec: int64): int64 =
  ## Parses a "when" string into a Unix timestamp (seconds since epoch, UTC).
  ##
  ## Accepted formats:
  ##   Relative: +30m, +2h, +1d  (minutes / hours / days from now)
  ##   Absolute: ISO 8601 with tz  2025-03-18T17:25:00-03:00
  ##             ISO 8601 UTC      2025-03-18T17:25:00Z
  ##
  ## Falls back to now+1h on unrecognised input.
  let s    = whenStr.strip()
  let base = nowSec

  ## ── Relative offset: +<N><unit> ─────────────────────────────────────────
  if s.len >= 2 and s[0] == '+':
    let unit   = s[^1]
    let numStr = s[1 ..< s.len - 1]
    try:
      let n = parseInt(numStr)
      return case unit
        of 'm': base + n.int64 * 60
        of 'h': base + n.int64 * 3600
        of 'd': base + n.int64 * 86400
        else:   base + n.int64 * 60   ## unknown unit → treat as minutes
    except ValueError: discard

  ## ── Absolute ISO 8601 ───────────────────────────────────────────────────
  let parsed = parseIsoWhen(s)
  if parsed != int64.low:
    return parsed

  ## ── Fallback ─────────────────────────────────────────────────────────────
  base + 3_600   ## 1 hour from now
