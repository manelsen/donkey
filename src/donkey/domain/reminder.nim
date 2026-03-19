## Reminder domain — parseWhen and tool metadata.
## Pure functions only. No I/O.

import std/[strutils, times]

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
    "+30m (30 minutes), +2h (2 hours), +1d (1 day)."

  ReminderToolSchema* = """{"type":"object","properties":{"when":{"type":"string","description":"ISO 8601 datetime with timezone (e.g. 2025-03-18T17:25:00-03:00) or relative offset (+30m, +2h, +1d)"},"message":{"type":"string","description":"The reminder message text to deliver to the user"}},"required":["when","message"]}"""

# ── parseWhen ─────────────────────────────────────────────────────────────────

proc parseWhen*(whenStr: string; nowSec: int64 = 0): int64 =
  ## Parses a "when" string into a Unix timestamp (seconds since epoch, UTC).
  ##
  ## Accepted formats:
  ##   Relative: +30m, +2h, +1d  (minutes / hours / days from now)
  ##   Absolute: ISO 8601 with tz  2025-03-18T17:25:00-03:00
  ##             ISO 8601 UTC      2025-03-18T17:25:00Z
  ##
  ## Falls back to now+1h on unrecognised input.
  let s    = whenStr.strip()
  let base = if nowSec > 0: nowSec else: getTime().toUnix()

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
  ## Try formats in order of specificity.
  ## Nim's `z` pattern matches `+HH:MM`, `-HH:MM`, or `Z`.
  ## zzz = ±HH:MM or Z  (most common from LLMs)
  ## z   = ±HH:MM:SS or Z
  const fmts = [
    "yyyy-MM-dd'T'HH:mm:sszzz",  ## 2025-03-18T17:25:00-03:00
    "yyyy-MM-dd'T'HH:mm:ssz",    ## 2025-03-18T17:25:00Z  (or ±HH:MM:SS)
    "yyyy-MM-dd'T'HH:mm:ss",     ## naive → UTC
    "yyyy-MM-dd HH:mm:ss",
    "yyyy-MM-dd",
  ]
  for fmt in fmts:
    try:
      return parse(s, fmt, utc()).toTime().toUnix()
    except: discard

  ## ── Fallback ─────────────────────────────────────────────────────────────
  base + 3_600   ## 1 hour from now
