## Pure outbound routing decisions.

import std/tables
import ../../domain/message

type
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

func supportsEditableStreams*(channel: ChannelKind): bool =
  channel in {ckTelegram, ckDiscord}

func supportsEditableReplacement*(channel: ChannelKind): bool =
  channel in {ckTelegram, ckDiscord}

func classifyOutbound*(msg: OutboundMessage;
                       streamMsgIds: Table[string, string]): OutboundKind =
  if msg.streamId.len == 0:
    return okImmediate
  if not supportsEditableStreams(msg.channel):
    return (if msg.isPartial: okSuppress else: okImmediate)
  if msg.streamId in streamMsgIds:
    return okStreamUpdate
  okStreamCreate

func decideStreamAction*(msg: OutboundMessage;
                         streamMsgIds: Table[string, string]): StreamAction =
  let kind = classifyOutbound(msg, streamMsgIds)
  StreamAction(
    kind: kind,
    streamId: msg.streamId,
    existingMsgId: if kind == okStreamUpdate: streamMsgIds[msg.streamId] else: "",
  )

func isImplementedOutboundChannel*(channel: ChannelKind): bool =
  channel in {ckTelegram, ckDiscord, ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk}

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
                     streamMsgIds: Table[string, string]): OutboundDecision =
  let stream = decideStreamAction(msg, streamMsgIds)
  OutboundDecision(
    intent: toOutboundIntent(stream.kind),
    streamId: stream.streamId,
    existingMsgId: stream.existingMsgId,
    shouldCleanup: shouldClearStream(msg),
  )

func withStreamCleanup*(msg: OutboundMessage;
                        streamMsgIds: Table[string, string]): Table[string, string] =
  result = streamMsgIds
  if shouldClearStream(msg):
    result.del(msg.streamId)
