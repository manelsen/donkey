## telegram_split.nim — split outbound text for the Telegram Bot API.
##
## Telegram counts message length in UTF-16 code units (the `text` field limit
## is 4096). Splitting by UTF-8 bytes over-counts astral characters and can cut
## a multi-byte sequence in half, which the API rejects or the sanitizer drops.
##
## Behavior derived from hermes-agent (MIT) fix 8725; see
## docs/hermes-mining/telegram/CASES.md#tg-001

import std/unicode

const TelegramTextLimit* = 4096

func utf16Units*(s: string): int =
  ## Number of UTF-16 code units Telegram charges for `s`.
  for r in s.runes:
    result += (if int(r) > 0xFFFF: 2 else: 1)

func splitForTelegram*(text: string; limit = TelegramTextLimit): seq[string] =
  ## Splits `text` into chunks of at most `limit` UTF-16 code units without
  ## breaking a character. Prefers a newline, then a space, in the second half
  ## of the window; falls back to a hard cut on a character boundary.
  if text.len == 0:
    return @[""]
  if utf16Units(text) <= limit:
    return @[text]

  var chunks: seq[string] = @[]
  var current = ""
  var currentUnits = 0
  var lastBreak = -1          ## byte index in `current` just after a break
  var lastBreakUnits = 0

  for r in text.runes:
    let units = if int(r) > 0xFFFF: 2 else: 1
    ## Repeat the cut: after moving the tail of a break, the remainder can
    ## still exceed the limit when the limit is very small.
    while currentUnits + units > limit and currentUnits > 0:
      let prefix = if lastBreak > 0: current[0 ..< lastBreak] else: ""
      if prefix.strip.len > 0:
        chunks.add(prefix)
        current = current[lastBreak .. ^1]
        currentUnits -= lastBreakUnits
      else:
        ## A break with no content before it would create a whitespace-only
        ## chunk; cut on the character boundary instead.
        chunks.add(current)
        current = ""
        currentUnits = 0
      lastBreak = -1
      lastBreakUnits = 0
    current.add($r)
    currentUnits += units
    if r.int == 10 or r.int == 32:
      lastBreak = current.len
      lastBreakUnits = currentUnits

  if current.len > 0:
    chunks.add(current)
  chunks
