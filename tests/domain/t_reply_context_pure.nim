## Reply context: when the person replies to a message, the agent is told
## what they replied to, clipped to one line.

import std/[strutils, unicode, unittest]
import donkey/domain/reply_context_pure

proc runTests*() =
  suite "reply context":
    test "a reply carries the quoted text before the message":
      check withReplyContext("e isso?", "A senha é girassol42.") ==
            "[Replying to: \"A senha é girassol42.\"]\ne isso?"

    test "no quote, no prefix":
      check withReplyContext("oi", "") == "oi"
      check withReplyContext("oi", "   ") == "oi"

    test "the quote is one line and clipped, never mid-character":
      let long = "linha um\nlinha dois " & "é".repeat(400)
      let res = withReplyContext("x", long)
      let quoted = res.split("\n")[0]
      check "linha um linha dois" in quoted
      check quoted.len <= MaxQuotedChars + 40
      check quoted.endsWith("…\"]")
      check res.validateUtf8 == -1

proc runClipTests*() =
  suite "the clip keeps every whole character":
    test "a cut inside a character drops only that character":
      ## 299 ASCII bytes then "é" (2 bytes): byte 300 is the second half of
      ## "é", so the clip keeps the 299 and drops the split "é", nothing more.
      let quote = "a".repeat(299) & "é" & "b"
      let first = withReplyContext("x", quote).split("\n")[0]
      check first == "[Replying to: \"" & "a".repeat(299) & "…\"]"
    test "a cut on a boundary keeps the character before it":
      let quote = "a".repeat(298) & "é" & "b"   ## "é" ends at byte 300
      let first = withReplyContext("x", quote).split("\n")[0]
      check first == "[Replying to: \"" & "a".repeat(298) & "é…\"]"

when isMainModule:
  runTests()
  runClipTests()
