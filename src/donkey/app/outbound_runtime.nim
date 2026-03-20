import std/tables
import results
import ../core/log
import ../adapters/channel/telegram
import ../adapters/channel/discord
import ../adapters/channel/wecom
import ../adapters/channel/wechat
import ../adapters/channel/qq
import ../adapters/channel/feishu
import ../domain/message

type
  OutboundKind* = enum
    okImmediate
    okStreamCreate
    okStreamUpdate

  StreamAction* = object
    kind*:         OutboundKind
    streamId*:     string
    existingMsgId*: string

proc classifyOutbound*(msg: OutboundMessage;
                       streamMsgIds: Table[string, string]): OutboundKind =
  if msg.streamId.len == 0:
    return okImmediate
  if msg.streamId in streamMsgIds:
    return okStreamUpdate
  okStreamCreate

proc decideStreamAction*(msg: OutboundMessage;
                         streamMsgIds: Table[string, string]): StreamAction =
  let kind = classifyOutbound(msg, streamMsgIds)
  StreamAction(
    kind: kind,
    streamId: msg.streamId,
    existingMsgId: if kind == okStreamUpdate: streamMsgIds[msg.streamId] else: "",
  )

proc isImplementedOutboundChannel*(channel: ChannelKind): bool =
  channel in {ckTelegram, ckDiscord, ckWeCom, ckWeChat, ckQQ, ckFeishu}

proc shouldClearStream*(msg: OutboundMessage): bool =
  msg.streamId.len > 0 and not msg.isPartial

proc sendImmediateOutbound*(msg: OutboundMessage;
                            tgAdapter: var TelegramAdapter;
                            dcAdapter: DiscordAdapter;
                            wcAdapter: var WeComAdapter;
                            wchAdapter: var WeChatAdapter;
                            qqAdapter: var QQAdapter;
                            fsAdapter: var FeishuAdapter;
                            log: Logger) {.gcsafe.} =
  case msg.channel
  of ckTelegram:
    tgAdapter.send(msg).isOkOr:
      log.error("tg send: " & error)
  of ckDiscord:
    dcAdapter.send(msg).isOkOr:
      log.error("dc send: " & error)
  of ckWeCom:
    wcAdapter.send(msg).isOkOr:
      log.error("wc send: " & error)
  of ckWeChat:
    wchAdapter.send(msg).isOkOr:
      log.error("wechat send: " & error)
  of ckQQ:
    qqAdapter.send(msg).isOkOr:
      log.error("qq send: " & error)
  of ckFeishu:
    fsAdapter.send(msg).isOkOr:
      log.error("fs send: " & error)

proc editStreamOutbound*(msg: OutboundMessage;
                         channelMsgId: string;
                         tgAdapter: var TelegramAdapter;
                         dcAdapter: DiscordAdapter;
                         log: Logger) {.gcsafe.} =
  case msg.channel
  of ckTelegram:
    tgAdapter.editMessage(msg.userId, channelMsgId, msg.text).isOkOr:
      log.warn("tg editMessage: " & error)
  of ckDiscord:
    dcAdapter.editMessage(msg.userId, channelMsgId, msg.text).isOkOr:
      log.warn("dc editMessage: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu:
    discard

proc createStreamOutbound*(msg: OutboundMessage;
                           tgAdapter: var TelegramAdapter;
                           dcAdapter: DiscordAdapter;
                           log: Logger): string {.gcsafe.} =
  case msg.channel
  of ckTelegram:
    tgAdapter.sendReturnId(msg).valueOr:
      log.error("tg sendReturnId: " & error)
      ""
  of ckDiscord:
    dcAdapter.sendReturnId(msg).valueOr:
      log.error("dc sendReturnId: " & error)
      ""
  of ckWeCom, ckWeChat, ckQQ, ckFeishu:
    ""

proc applyStreamCleanup*(msg: OutboundMessage;
                         streamMsgIds: var Table[string, string]) =
  if shouldClearStream(msg):
    streamMsgIds.del(msg.streamId)

proc routeOutbound*(msg: OutboundMessage;
                    tgAdapter: var TelegramAdapter;
                    dcAdapter: DiscordAdapter;
                    wcAdapter: var WeComAdapter;
                    wchAdapter: var WeChatAdapter;
                    qqAdapter: var QQAdapter;
                    fsAdapter: var FeishuAdapter;
                    log: Logger;
                    streamMsgIds: var Table[string, string]) {.gcsafe.} =
  let action = decideStreamAction(msg, streamMsgIds)
  case action.kind
  of okImmediate:
    sendImmediateOutbound(msg, tgAdapter, dcAdapter, wcAdapter, wchAdapter, qqAdapter, fsAdapter, log)
  of okStreamUpdate:
    editStreamOutbound(msg, action.existingMsgId, tgAdapter, dcAdapter, log)
  of okStreamCreate:
    let channelMsgId = createStreamOutbound(msg, tgAdapter, dcAdapter, log)
    if channelMsgId.len > 0:
      streamMsgIds[msg.streamId] = channelMsgId
  applyStreamCleanup(msg, streamMsgIds)
