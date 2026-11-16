## utf8.nim — small UTF-8-safe clipping helpers.
##
## Nim strings are byte sequences. Cutting at an arbitrary byte can split a
## multi-byte code point, so user-facing previews must back up to a boundary.

func isContinuationByte(ch: char): bool =
  (ord(ch) and 0xC0) == 0x80

func clipUtf8*(text: string; maxChars: int; suffix = "…"): string =
  ## Returns `text` unchanged when it fits; otherwise returns a prefix that
  ## ends on a UTF-8 boundary plus `suffix`.
  if maxChars <= 0:
    return suffix
  if text.len <= maxChars:
    return text
  var endIdx = maxChars
  while endIdx > 0 and isContinuationByte(text[endIdx]):
    dec endIdx
  if endIdx <= 0:
    return suffix
  text[0 ..< endIdx] & suffix
