## E12.3: Discord's gateways as their own process — the wire and the glue.

import std/unittest
import donkey/adapters/channel/discord
import donkey/core/pipeops
import donkey/core/types
import donkey/core/log
import donkey/infra/event_queue

proc runTests*() =
  suite "discord — as its own process (E12.3)":
    test "a gateway event makes the round trip through the wire":
      let e = DiscordRawEvent(kind: deInteraction, discordUserId: "u1", content: "oi\nolá",
        channelId: "c1", messageId: "m1", interactionId: "i1", interactionToken: "t1",
        guildId: "g1", attachmentUrl: "https://cdn/x.png", attachmentName: "x.png",
        attachmentMime: "image/png", extraAttachments: @["y.pdf"],
        referencedAuthorId: "u2", referencedContent: "antes", bot: "suporte")
      let back = rawEventFromWire(rawEventToWire(e))
      check back.isOk and back.get == e
      check rawEventFromWire("{oops").isErr
      check rawEventFromWire("[]").isErr

    test "the daemon's side: the child's events into the queue; nothing goes back":
      let a = newDiscordAdapter("tok", "")
      let e = DiscordRawEvent(kind: deMessage, discordUserId: "u1", content: "oi", bot: "")
      discordProcessSink(rawEventToWire(e))
      let (has, got) = a.tryRecvEvent()
      check has and got == e
      discordProcessSink("{not json")
      check not a.tryRecvEvent()[0]
      check discordProcessSource() == (false, "")

    test "the child's side: the gateways' events out":
      let e = DiscordRawEvent(kind: deResync)
      gDiscordEvents.push(e)
      check discordWorkerEvent() == (true, rawEventToWire(e))
      check discordWorkerEvent() == (false, "")

    test "the command is this binary's channel-worker":
      let spec = discordWorkerSpec("/usr/bin/donkey")
      check spec.args == @["channel-worker", "discord"] and spec.channel == ckDiscord

    test "a second start is refused":
      let log = newLogger("t", lvlError)
      check startDiscordProcess("/bin/sleep", log).isOk
      check startDiscordProcess("/bin/sleep", log).isErr
      stopDiscordProcess()

when isMainModule:
  runTests()
