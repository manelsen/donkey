## Dead letters (second round, front 4): a reply the channel refused is kept
## and tried again at 1, 5 and 30 minutes; after that it stays dead, visible
## to the operator, until it ages out. Only plain text replies qualify.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/domain/dead_letters_pure

const Min = 60_000'i64

proc reply(text = "resposta"): OutboundMessage =
  OutboundMessage(userId: UserId("u-1"), channel: ckTelegram, text: text, replyTo: "42")

proc runTests*() =
  suite "dead letters":

    test "only plain text replies are kept; streams, edits, media and keyboards are not":
      check deadLetterEligible(reply())
      var m = reply(); m.isPartial = true; m.streamId = "s"
      check not deadLetterEligible(m)
      m = reply(); m.streamId = "s"          ## a stream's final answer, sent whole
      check deadLetterEligible(m)
      m = reply(); m.editTargetId = "9"
      check not deadLetterEligible(m)
      m = reply(); m.mediaUrl = "/x.png"
      check not deadLetterEligible(m)
      m = reply(); m.keyboard = @[@[("a", "b")]]
      check not deadLetterEligible(m)
      check not deadLetterEligible(reply("   "))

    test "a failure is kept, due again in a minute":
      var letters: seq[DeadLetter]
      letters.recordFailure("d1", reply(), "HTTP 502", 1_000)
      check letters.len == 1
      check letters[0].attempts == 1 and letters[0].nextAtMs == 1_000 + Min
      check letters[0].lastError == "HTTP 502" and not letters[0].dead
      check dueLetters(letters, 1_000 + Min - 1).len == 0
      check dueLetters(letters, 1_000 + Min).len == 1

    test "each retry that fails waits longer: 1, 5, then 30 minutes; then it is dead":
      var letters: seq[DeadLetter]
      letters.recordFailure("d1", reply(), "e1", 0)
      letters.retryFailed("d1", "e2", Min)
      check letters[0].attempts == 2 and letters[0].nextAtMs == Min + 5 * Min
      letters.retryFailed("d1", "e3", 6 * Min)
      check letters[0].attempts == 3 and letters[0].nextAtMs == 6 * Min + 30 * Min
      letters.retryFailed("d1", "e4", 36 * Min)
      check letters[0].dead and letters[0].lastError == "e4"
      check dueLetters(letters, 1_000 * Min).len == 0

    test "a retry that goes through takes the letter out":
      var letters: seq[DeadLetter]
      letters.recordFailure("d1", reply(), "e", 0)
      letters.recordFailure("d2", reply("outra"), "e", 0)
      letters.retrySucceeded("d1")
      check letters.len == 1 and letters[0].id == "d2"

    test "letters older than a week, or beyond the cap, are dropped, oldest first":
      var letters: seq[DeadLetter]
      letters.recordFailure("old", reply(), "e", 0)
      letters.recordFailure("new", reply(), "e", 8 * 24 * 60 * Min)
      prune(letters, 8 * 24 * 60 * Min)
      check letters.len == 1 and letters[0].id == "new"
      for i in 0 ..< MaxDeadLetters + 5:
        letters.recordFailure("x" & $i, reply(), "e", 8 * 24 * 60 * Min + i)
      prune(letters, 8 * 24 * 60 * Min + 10_000)
      check letters.len == MaxDeadLetters and letters[0].id != "new"

    test "the message comes back as it was, for the retry":
      var letters: seq[DeadLetter]
      letters.recordFailure("d1", reply(), "e", 0)
      let m = letters[0].message
      check m.userId == UserId("u-1") and m.channel == ckTelegram
      check m.text == "resposta" and m.replyTo == "42"

    test "they survive a restart as JSON; a broken file is an error, not an empty list":
      var letters: seq[DeadLetter]
      letters.recordFailure("d1", reply("olá \"aspas\""), "e", 5)
      let back = decodeDeadLetters(encodeDeadLetters(letters)).get
      check back.len == 1 and back[0].text == "olá \"aspas\"" and back[0].channel == ckTelegram
      check decodeDeadLetters("").get.len == 0
      check decodeDeadLetters("{broken").isErr

    test "a line for the operator: when, where, why, and the start of the text":
      var letters: seq[DeadLetter]
      letters.recordFailure("d1", reply("x".repeat(300)), "HTTP 502", 0)
      let line = operatorLine(letters[0])
      check "d1" in line and "telegram" in line and "HTTP 502" in line
      check line.len < 300

when isMainModule:
  runTests()
