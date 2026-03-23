import std/tables
import results
import ../core/log
import ../core/outbound/outbound
import ../ports/channel
import ../domain/message

export outbound

proc channelPortFor(ports: OutboundChannelPorts;
                    channel: ChannelKind): OutboundChannelPort =
  case channel
  of ckTelegram: ports.telegram
  of ckDiscord:  ports.discord
  of ckWeCom:    ports.wecom
  of ckWeChat:   ports.wechat
  of ckQQ:       ports.qq
  of ckFeishu:   ports.feishu
  of ckSlack:     ports.slack
  of ckWhatsApp:  ports.whatsapp

proc sendImmediateOutbound*(msg: OutboundMessage;
                            ports: OutboundChannelPorts;
                            log: Logger) {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  port.send(msg).isOkOr:
    case msg.channel
    of ckTelegram: log.error("tg send: " & error)
    of ckDiscord:  log.error("dc send: " & error)
    of ckWeCom:    log.error("wc send: " & error)
    of ckWeChat:   log.error("wechat send: " & error)
    of ckQQ:       log.error("qq send: " & error)
    of ckFeishu:   log.error("fs send: " & error)
    of ckSlack:     log.error("sl send: " & error)
    of ckWhatsApp:  log.error("wa send: " & error)

proc editStreamOutbound*(msg: OutboundMessage;
                         channelMsgId: string;
                         ports: OutboundChannelPorts;
                         log: Logger) {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  port.editMessage(msg.userId, channelMsgId, msg.text).isOkOr:
    case msg.channel
    of ckTelegram: log.warn("tg editMessage: " & error)
    of ckDiscord:  log.warn("dc editMessage: " & error)
    of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp: discard

proc createStreamOutbound*(msg: OutboundMessage;
                           ports: OutboundChannelPorts;
                           log: Logger): string {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  port.sendReturnId(msg).valueOr:
    case msg.channel
    of ckTelegram: log.error("tg sendReturnId: " & error)
    of ckDiscord:  log.error("dc sendReturnId: " & error)
    of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp: discard
    ""

proc routeOutbound*(msg: OutboundMessage;
                    ports: OutboundChannelPorts;
                    log: Logger;
                    streamMsgIds: var Table[string, string]) {.gcsafe.} =
  let decision = decideOutbound(msg, streamMsgIds)
  case decision.intent
  of oiSend:
    sendImmediateOutbound(msg, ports, log)
  of oiStreamUpdate:
    editStreamOutbound(msg, decision.existingMsgId, ports, log)
  of oiStreamCreate:
    let channelMsgId = createStreamOutbound(msg, ports, log)
    if channelMsgId.len > 0:
      streamMsgIds[msg.streamId] = channelMsgId
  of oiSuppress:
    discard
  if decision.shouldCleanup:
    streamMsgIds.del(msg.streamId)
