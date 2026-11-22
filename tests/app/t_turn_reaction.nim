## The reaction a turn leaves on the user's message: ⏳ while it runs, then
## ✅ or ❌ on the final reply. A fake Telegram port records the reactions.

import std/unittest
import donkey/core/pipeops
import donkey/core/types
import donkey/core/outbound/outbound
import donkey/domain/message
import donkey/ports/channel
import donkey/app/turn_reaction

var gReactions {.threadvar.}: seq[(string, string)]  ## (msgId, emoji)

proc fakePorts(): OutboundChannelPorts =
  result.telegram = OutboundChannelPort(
    setMessageReaction: proc(userId: UserId; channelId, msgId, emoji: string):
        Result[void, string] {.gcsafe.} =
      {.cast(gcsafe).}: gReactions.add((msgId, emoji))
      ok())

func inbound(messageId = "m-1"; callbackId = ""; channel = ckTelegram): InboundMessage =
  InboundMessage(userId: UserId("u1"), channel: channel, channelId: "chat-1",
                 messageId: messageId, callbackId: callbackId)

proc runTests*() =
  suite "turn reaction":
    setup:
      gReactions = @[]
      var state = initPresentationState()

    test "a turn's status message is the message id, else the channel id":
      check statusMessageId(inbound("m-1")) == "m-1"
      check statusMessageId(inbound("")) == "chat-1"

    test "callbacks and channels without reactions are not staged":
      check shouldStageReaction(inbound())
      check not shouldStageReaction(inbound(callbackId = "cb"))
      check not shouldStageReaction(inbound(channel = ckEmail))

    test "a final reply marks the turn done, an error reply marks it failed":
      check not isErrorReply(OutboundMessage(text: "ok", replyKind: rkFinalAnswer))
      check isErrorReply(OutboundMessage(text: "falhou", replyKind: rkTurnError))
      ## Replies that still carry no kind are recognised by their wording.
      check isErrorReply(OutboundMessage(text: "Desculpe, o provedor falhou."))

    test "staging leaves ⏳ and remembers the message; the reply closes it":
      stageReaction(state, fakePorts(), inbound())
      check gReactions == @[("m-1", "⏳")]
      completeReactionFor(state, fakePorts(), OutboundMessage(
        userId: UserId("u1"), channel: ckTelegram, text: "pronto",
        replyKind: rkFinalAnswer))
      check gReactions == @[("m-1", "⏳"), ("m-1", "✅")]
      ## Closed: a second reply does not react again.
      completeReactionFor(state, fakePorts(), OutboundMessage(
        userId: UserId("u1"), channel: ckTelegram, text: "mais"))
      check gReactions.len == 2

    test "a partial reply leaves the turn running; an error closes it with ❌":
      stageReaction(state, fakePorts(), inbound())
      completeReactionFor(state, fakePorts(), OutboundMessage(
        userId: UserId("u1"), channel: ckTelegram, text: "...", isPartial: true))
      check gReactions == @[("m-1", "⏳")]
      completeReactionFor(state, fakePorts(), OutboundMessage(
        userId: UserId("u1"), channel: ckTelegram, text: "erro",
        replyKind: rkTurnError))
      check gReactions == @[("m-1", "⏳"), ("m-1", "❌")]

when isMainModule:
  runTests()
