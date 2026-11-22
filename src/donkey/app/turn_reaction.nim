## The reaction a turn leaves on the user's message, on channels that support
## reactions: ⏳ while the turn runs, then ✅ or ❌ on its final reply. The
## message reacted to is remembered in the presentation state, so the reply
## (which arrives later, through the outbox) closes the right one.

import std/strutils
import ../core/log
import ../core/types
import ../core/outbound/outbound
import ../domain/message
import ../ports/channel
import ./outbound_runtime

const
  TurnStatusSlot = "turn"
  LegacyErrorPrefixes = ["Desculpe", "Tool call loop"]
    ## Error replies built before replyKind marked them.

func statusMessageId*(msg: InboundMessage): string =
  ## The message the turn's status reacts to.
  if msg.messageId.len > 0: msg.messageId else: msg.channelId

func shouldStageReaction*(msg: InboundMessage): bool =
  ## Button presses carry no message of the user to react to.
  supportsMessageReactions(msg.channel) and msg.callbackId.len == 0 and
    statusMessageId(msg).len > 0

func isErrorReply*(reply: OutboundMessage): bool =
  ## A turn ends in error when its reply says so: by kind, or by the wording
  ## of replies that carry no kind.
  if reply.replyKind == rkTurnError:
    return true
  for prefix in LegacyErrorPrefixes:
    if reply.text.startsWith(prefix):
      return true
  false

proc react(channel: ChannelKind; userId: UserId; channelId, msgId, emoji: string;
           ports: OutboundChannelPorts) =
  discard setOutboundReaction(channel, userId, channelId, msgId, emoji, ports,
                              newLogger("status.reaction"))

proc stageReaction*(state: var PresentationState; ports: OutboundChannelPorts;
                    msg: InboundMessage) =
  ## ⏳ on the user's message, remembered until the turn's final reply.
  if not shouldStageReaction(msg):
    return
  let statusMsgId = statusMessageId(msg)
  react(msg.channel, msg.userId, msg.channelId, statusMsgId, "⏳", ports)
  state.rememberStatus(msg.channel, msg.userId, TurnStatusSlot, statusMsgId,
                       msg.channelId)

proc completeReaction*(state: var PresentationState; ports: OutboundChannelPorts;
                       channel: ChannelKind; userId: UserId;
                       channelId, msgId: string; isError: bool) =
  ## ✅ or ❌ on `msgId`, and the turn's status is forgotten.
  if not supportsMessageReactions(channel) or msgId.len == 0:
    return
  state.clearStatus(channel, userId, TurnStatusSlot)
  react(channel, userId, channelId, msgId, if isError: "❌" else: "✅", ports)

proc completeReactionFor*(state: var PresentationState; ports: OutboundChannelPorts;
                          reply: OutboundMessage) =
  ## Closes the turn a final reply belongs to. Partial (streamed) replies and
  ## replies with no staged turn leave everything as it is.
  if reply.isPartial or not supportsMessageReactions(reply.channel):
    return
  let msgId = state.lookupStatus(reply.channel, reply.userId, TurnStatusSlot)
  if msgId.len == 0:
    return
  let channelId = state.lookupStatusChannelId(reply.channel, reply.userId,
                                               TurnStatusSlot)
  completeReaction(state, ports, reply.channel, reply.userId, channelId, msgId,
                   isErrorReply(reply))
