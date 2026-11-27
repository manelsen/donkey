## E12.3: the lines between the daemon and a channel run as its own process.

import std/unittest
import std/strutils
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/channel_wire

proc runTests*() =
  suite "channel wire":
    test "an event, the state and an outbound line make a round trip":
      for f in [WireFrame(kind: wfEvent, payload: """{"nick":"ana","text":"oi\nlinha"}"""),
                WireFrame(kind: wfUp), WireFrame(kind: wfDown),
                WireFrame(kind: wfOut, payload: "PRIVMSG #a :olá")]:
        let line = encodeFrame(f)
        check '\n' notin line
        check line.startsWith(WireMark)
        let back = decodeFrame(line)
        check back.isOk and back.get == f

    test "a line without the mark is the child's log, not a frame":
      let d = decodeFrame("2026-11-27 INFO irc: connected")
      check d.isOk and d.get.kind == wfLog
      check d.get.payload == "2026-11-27 INFO irc: connected"

    test "a marked line that does not parse is an error, not a crash":
      check decodeFrame(WireMark & "{not json").isErr
      check decodeFrame(WireMark & """{"k":"nope"}""").isErr
      check decodeFrame(WireMark & """[1,2]""").isErr

    test "DONKEY_CHANNEL_PROCESSES: which channels run as their own process":
      check processChannels("").get == {}
      check processChannels(" irc ").get == {ckIrc}
      check processChannels("IRC,irc").get == {ckIrc}
      let bad = processChannels("irc, telegram")
      check bad.isErr and "telegram" in bad.error and "irc" in bad.error

when isMainModule:
  runTests()
