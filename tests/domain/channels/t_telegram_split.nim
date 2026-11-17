## Tests for outbound Telegram text splitting.
##
## Telegram counts 4096 UTF-16 code units per message; a byte-based split both
## over-counts astral characters and can cut a multi-byte sequence in half.

import std/[strutils, unicode, unittest]
import donkey/domain/channels/telegram_split

func runes(s: string): seq[Rune] =
  for r in s.runes: result.add(r)

suite "telegram_split — UTF-16 message length":

  test "TG-001: counts astral characters as two UTF-16 units":
    check utf16Units("abc") == 3
    check utf16Units("😀") == 2
    check utf16Units("a😀b") == 4

  test "TG-001: a message under the limit is returned unchanged":
    let text = "hello"
    check splitForTelegram(text, 4096) == @[text]

  test "TG-001: splitting never exceeds the UTF-16 limit":
    var text = ""
    for _ in 0 ..< 3000: text.add("😀")   # 6000 UTF-16 units
    let chunks = splitForTelegram(text, 4096)
    check chunks.len == 2
    for chunk in chunks:
      check utf16Units(chunk) <= 4096

  test "TG-001: splitting keeps every character intact":
    var text = strutils.repeat('a', 4095)
    for _ in 0 ..< 10: text.add("😀")
    let chunks = splitForTelegram(text, 4096)
    check chunks.join("") == text
    for chunk in chunks:
      check utf16Units(chunk) <= 4096
      # A chunk that ends mid-sequence would decode to fewer runes.
      check chunk.runes.len > 0

  test "TG-001: prefers a newline near the limit":
    let head = strutils.repeat('a', 4000)
    let tail = strutils.repeat('b', 200)
    let text = head & "\n" & tail
    let chunks = splitForTelegram(text, 4096)
    check chunks.len == 2
    check chunks[0] == head & "\n"
    check chunks[1] == tail

  test "TG-001: prefers a space when there is no newline":
    let head = strutils.repeat('a', 4000)
    let tail = strutils.repeat('b', 200)
    let text = head & " " & tail
    let chunks = splitForTelegram(text, 4096)
    check chunks.len == 2
    check chunks[0] == head & " "
    check chunks[1] == tail

  test "TG-001: hard-cuts an unbroken run on a character boundary":
    let text = strutils.repeat('x', 5000)
    let chunks = splitForTelegram(text, 4096)
    check chunks.len == 2
    check chunks[0].len == 4096
    check chunks.join("") == text

  test "TG-001: empty text yields one empty chunk":
    check splitForTelegram("", 4096) == @[""]


  test "TG-001: a leading newline does not create a whitespace-only chunk":
    let text = "\n" & strutils.repeat('a', 4096)
    let chunks = splitForTelegram(text, 4096)
    for chunk in chunks:
      check chunk.strip.len > 0
      check utf16Units(chunk) <= 4096
    check chunks.join("") == text

  test "TG-001: a newline after content is preserved":
    let text = "a\n" & strutils.repeat('a', 4096)
    let chunks = splitForTelegram(text, 4096)
    check chunks[0] == "a\n"
    check chunks.join("") == text
