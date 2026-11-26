## US-000 — LINE exists as a first-class channel identity.
##
## Proves the public label, the deliberately send-only capability descriptor
## (every other flag false, so a future copy of FullCapability cannot slip in)
## and that the outbound runtime routes ckLine through OutboundChannelPorts.line.

import std/unittest
import results
import donkey/core/log
import donkey/core/types
import donkey/domain/message
import donkey/ports/channel
import donkey/ports/channel_capability
import donkey/app/outbound_runtime

var lineSends = 0

proc fakeLineSend(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
  inc lineSends
  ok()

proc runTests*() =
  suite "ChannelKind — LINE":

    test "ckLine has the public label line":
      check $ckLine == "line"

    test "ckLine kept its ordinal; later channels come after it":
      ## Ordinals are part of persisted state: a new channel is appended.
      check ord(ckLine) == 13
      check ckTeams == succ(ckLine)
      check ckMattermost == succ(ckTeams)
      check ckSms == succ(ckMattermost)
      check ckIrc == succ(ckSms)
      check ckGoogleChat == high(ChannelKind) and ckGoogleChat == succ(ckIrc)

  suite "capability — LINE":

    test "LINE is send-only, not a copy of FullCapability":
      ## Descriptor has nine flags: send plus the seven listed in the PRD
      ## (sendReturnId, editMessage, sendKeyboard, editKeyboard,
      ## setMessageReaction, downloadFile, sendMedia) and sendVoice. All eight
      ## non-send flags must stay false.
      let caps = capability(ckLine)
      check caps.send
      check not caps.sendReturnId
      check not caps.editMessage
      check not caps.sendKeyboard
      check not caps.editKeyboard
      check not caps.setMessageReaction
      check not caps.downloadFile
      check not caps.sendMedia
      check not caps.sendVoice

    test "supports() mirrors the descriptor for every flag":
      for flag in ChannelCapabilityFlag:
        if flag == cfSend:
          check supports(ckLine, flag)
        else:
          check not supports(ckLine, flag)

    test "registry entry matches capability()":
      check channelCapabilityRegistry()[ckLine] == capability(ckLine)

  suite "outbound wiring — LINE":

    test "OutboundChannelPorts exposes a line port":
      var ports = OutboundChannelPorts()
      check ports.line.send == nil
      ports.line = OutboundChannelPort(send: fakeLineSend)
      check ports.line.send != nil

    test "outbound runtime routes ckLine through the line port":
      let log = newLogger("test.line", lvlError, proc(e: LogEntry) = discard)
      var ports = OutboundChannelPorts()
      ports.line = OutboundChannelPort(send: fakeLineSend)
      lineSends = 0
      sendImmediateOutbound(
        OutboundMessage(userId: UserId("U1"), channel: ckLine, text: "hi"),
        ports, log)
      check lineSends == 1

when isMainModule:
  runTests()
