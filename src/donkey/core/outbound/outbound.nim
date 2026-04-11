## Pure outbound routing decisions.

import std/[strutils, tables]
import ../../domain/message

type
  ChannelCapabilityRow* = object
    channel*: ChannelKind
    implemented*: bool
    editableReplacement*: bool
    editableStreams*: bool
    interactiveComponents*: bool
    messageReactions*: bool

  PresentationCapabilities* = object
    editableReplacement*: bool
    editableStreams*: bool
    interactiveComponents*: bool
    messageReactions*: bool

  PresentationSurfaceKind* = enum
    pskReplaceable
    pskStreaming

  PresentationMessage* = object
    text*: string
    keyboard*: seq[seq[(string, string)]]
    replacementSlot*: string
    streamId*: string
    isPartial*: bool

  PresentationSurface* = object
    kind*: PresentationSurfaceKind
    slot*: string
    fallbackText*: string
    msg*: PresentationMessage

  PresentationState* = object
    replacementMsgIds*: Table[string, string]
    streamMsgIds*: Table[string, string]
    statusMsgIds*: Table[string, string]
    statusChannelIds*: Table[string, string]

  OutboundKind* = enum
    okImmediate
    okStreamCreate
    okStreamUpdate
    okSuppress

  OutboundIntent* = enum
    oiSend
    oiStreamCreate
    oiStreamUpdate
    oiSuppress

  StreamAction* = object
    kind*:          OutboundKind
    streamId*:      string
    existingMsgId*: string

  OutboundDecision* = object
    intent*:        OutboundIntent
    streamId*:      string
    existingMsgId*: string
    shouldCleanup*: bool

const
  SharedButtonSelectionFallbackText* = "Use os botões acima para escolher."

func buildReplacementSurface*(slot: string;
                              text: string;
                              keyboard: seq[seq[(string, string)]] = @[]): PresentationSurface =
  PresentationSurface(
    kind: pskReplaceable,
    slot: slot,
    fallbackText: text,
    msg: PresentationMessage(
      text: text,
      keyboard: keyboard,
      replacementSlot: slot,
    ),
  )

func buildStreamingSurface*(slot: string;
                            streamId: string;
                            text: string;
                            isPartial: bool): PresentationSurface =
  PresentationSurface(
    kind: pskStreaming,
    slot: slot,
    fallbackText: text,
    msg: PresentationMessage(
      text: text,
      streamId: streamId,
      isPartial: isPartial,
    ),
  )

func toOutboundMessage*(surface: PresentationSurface;
                        base: OutboundMessage): OutboundMessage =
  result = base
  result.text = surface.msg.text
  result.keyboard = surface.msg.keyboard
  result.replacementSlot = surface.msg.replacementSlot
  result.streamId = surface.msg.streamId
  result.isPartial = surface.msg.isPartial

func initPresentationState*(): PresentationState =
  PresentationState(
    replacementMsgIds: initTable[string, string](),
    streamMsgIds: initTable[string, string](),
    statusMsgIds: initTable[string, string](),
    statusChannelIds: initTable[string, string](),
  )

func replacementSurfaceKey*(channel: ChannelKind;
                            userId: UserId;
                            slot: string): string =
  $channel & "|" & $userId & "|" & slot

func replacementSurfaceKey*(msg: OutboundMessage): string =
  replacementSurfaceKey(msg.channel, msg.userId, msg.replacementSlot)

func streamSurfaceKey*(channel: ChannelKind;
                       userId: UserId;
                       streamId: string): string =
  $channel & "|" & $userId & "|" & streamId

func streamSurfaceKey*(msg: OutboundMessage): string =
  streamSurfaceKey(msg.channel, msg.userId, msg.streamId)

func statusSurfaceKey*(channel: ChannelKind;
                       userId: UserId;
                       slot: string): string =
  $channel & "|" & $userId & "|" & slot

proc lookupReplacement*(state: PresentationState;
                        msg: OutboundMessage): string =
  if msg.replacementSlot.len == 0:
    return ""
  state.replacementMsgIds.getOrDefault(replacementSurfaceKey(msg))

proc lookupStream*(state: PresentationState;
                   msg: OutboundMessage): string =
  if msg.streamId.len == 0:
    return ""
  state.streamMsgIds.getOrDefault(streamSurfaceKey(msg))

proc lookupStatus*(state: PresentationState;
                   channel: ChannelKind;
                   userId: UserId;
                   slot: string): string =
  if slot.len == 0:
    return ""
  state.statusMsgIds.getOrDefault(statusSurfaceKey(channel, userId, slot))

proc lookupStatusChannelId*(state: PresentationState;
                             channel: ChannelKind;
                             userId: UserId;
                             slot: string): string =
  if slot.len == 0:
    return ""
  state.statusChannelIds.getOrDefault(statusSurfaceKey(channel, userId, slot))

proc rememberReplacement*(state: var PresentationState;
                          msg: OutboundMessage;
                          channelMsgId: string) =
  if msg.replacementSlot.len == 0 or channelMsgId.len == 0:
    return
  state.replacementMsgIds[replacementSurfaceKey(msg)] = channelMsgId

proc rememberStream*(state: var PresentationState;
                     msg: OutboundMessage;
                     channelMsgId: string) =
  if msg.streamId.len == 0 or channelMsgId.len == 0:
    return
  state.streamMsgIds[streamSurfaceKey(msg)] = channelMsgId

proc clearStream*(state: var PresentationState;
                  msg: OutboundMessage) =
  if msg.streamId.len == 0:
    return
  state.streamMsgIds.del(streamSurfaceKey(msg))

proc rememberStatus*(state: var PresentationState;
                     channel: ChannelKind;
                     userId: UserId;
                     slot: string;
                     channelMsgId: string;
                     channelId: string = "") =
  if slot.len == 0 or channelMsgId.len == 0:
    return
  let key = statusSurfaceKey(channel, userId, slot)
  state.statusMsgIds[key] = channelMsgId
  if channelId.len > 0:
    state.statusChannelIds[key] = channelId

proc clearStatus*(state: var PresentationState;
                  channel: ChannelKind;
                  userId: UserId;
                  slot: string) =
  if slot.len == 0:
    return
  let key = statusSurfaceKey(channel, userId, slot)
  state.statusMsgIds.del(key)
  state.statusChannelIds.del(key)

func presentationCapabilities*(channel: ChannelKind): PresentationCapabilities =
  case channel
  of ckTelegram, ckDiscord:
    PresentationCapabilities(
      editableReplacement: true,
      editableStreams: true,
      interactiveComponents: true,
      messageReactions: true,
    )
  else:
    PresentationCapabilities(
      editableReplacement: false,
      editableStreams: false,
      interactiveComponents: false,
      messageReactions: false,
    )

func supportsEditableStreams*(channel: ChannelKind): bool =
  presentationCapabilities(channel).editableStreams

func supportsEditableReplacement*(channel: ChannelKind): bool =
  presentationCapabilities(channel).editableReplacement

func supportsInteractiveComponents*(channel: ChannelKind): bool =
  presentationCapabilities(channel).interactiveComponents

func supportsMessageReactions*(channel: ChannelKind): bool =
  presentationCapabilities(channel).messageReactions

func replacementSlotFor*(channel: ChannelKind;
                         slot: string): string =
  if presentationCapabilities(channel).editableReplacement: slot else: ""

func interactiveSelectionFallbackText*(): string =
  SharedButtonSelectionFallbackText

func classifyOutbound*(msg: OutboundMessage;
                       state: PresentationState): OutboundKind =
  if msg.streamId.len == 0:
    return okImmediate
  if not supportsEditableStreams(msg.channel):
    return (if msg.isPartial: okSuppress else: okImmediate)
  if state.lookupStream(msg).len > 0:
    return okStreamUpdate
  okStreamCreate

func decideStreamAction*(msg: OutboundMessage;
                         state: PresentationState): StreamAction =
  let kind = classifyOutbound(msg, state)
  StreamAction(
    kind: kind,
    streamId: msg.streamId,
    existingMsgId: if kind == okStreamUpdate: state.lookupStream(msg) else: "",
  )

func isImplementedOutboundChannel*(channel: ChannelKind): bool =
  channel in {ckTelegram, ckDiscord, ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk}

func channelCapabilityRow*(channel: ChannelKind): ChannelCapabilityRow =
  let caps = presentationCapabilities(channel)
  ChannelCapabilityRow(
    channel: channel,
    implemented: isImplementedOutboundChannel(channel),
    editableReplacement: caps.editableReplacement,
    editableStreams: caps.editableStreams,
    interactiveComponents: caps.interactiveComponents,
    messageReactions: caps.messageReactions,
  )

func allChannelCapabilityRows*(): seq[ChannelCapabilityRow] =
  for channel in low(ChannelKind) .. high(ChannelKind):
    result.add(channelCapabilityRow(channel))

func boolMark(value: bool): string =
  if value: "yes" else: "no"

func formatChannelCapabilityMatrix*(): string =
  var lines = @[
    "| Channel | Implemented | Editable UI | Stream updates | Components | Reactions |",
    "|---------|-------------|-------------|----------------|------------|-----------|",
  ]
  for row in allChannelCapabilityRows():
    lines.add(
      "| " & $row.channel &
      " | " & boolMark(row.implemented) &
      " | " & boolMark(row.editableReplacement) &
      " | " & boolMark(row.editableStreams) &
      " | " & boolMark(row.interactiveComponents) &
      " | " & boolMark(row.messageReactions) & " |"
    )
  lines.join("\n")

func shouldClearStream*(msg: OutboundMessage): bool =
  msg.streamId.len > 0 and not msg.isPartial

func toOutboundIntent*(kind: OutboundKind): OutboundIntent =
  case kind
  of okImmediate:
    oiSend
  of okStreamCreate:
    oiStreamCreate
  of okStreamUpdate:
    oiStreamUpdate
  of okSuppress:
    oiSuppress

func decideOutbound*(msg: OutboundMessage;
                     state: PresentationState): OutboundDecision =
  let stream = decideStreamAction(msg, state)
  OutboundDecision(
    intent: toOutboundIntent(stream.kind),
    streamId: stream.streamId,
    existingMsgId: stream.existingMsgId,
    shouldCleanup: shouldClearStream(msg),
  )

func withStreamCleanup*(msg: OutboundMessage;
                        state: PresentationState): PresentationState =
  result = state
  if shouldClearStream(msg):
    result.clearStream(msg)
