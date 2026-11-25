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

when isMainModule:
  runTests()
