import results
import ../core/log
import ../core/outbound/outbound
import ../ports/channel
import ../domain/message
import ./metrics

export outbound

func channelTag(ch: ChannelKind): string {.gcsafe.} =
  case ch
  of ckTelegram:  "tg"
  of ckDiscord:   "dc"
  of ckWeCom:     "wc"
  of ckWeChat:    "wechat"
  of ckQQ:        "qq"
  of ckFeishu:    "fs"
  of ckSlack:     "sl"
  of ckWhatsApp:  "wa"
  of ckSignal:    "sig"
  of ckDingTalk:  "dt"
  of ckMatrix:    "mx"
  of ckEmail:     "em"
  of ckCli:       "cli"

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
  of ckSignal:    ports.signal
  of ckDingTalk:  ports.dingtalk
  of ckMatrix:    ports.matrix
  of ckEmail:     ports.email
  of ckCli:       ports.cli

proc setOutboundReaction*(channel: ChannelKind;
                          userId: UserId;
                          channelId, msgId, emoji: string;
                          ports: OutboundChannelPorts;
                          log: Logger): bool {.gcsafe.} =
  if not supportsMessageReactions(channel) or msgId.len == 0:
    return false
  let port = ports.channelPortFor(channel)
  let res = port.setMessageReaction(userId, channelId, msgId, emoji)
  if res.isOk:
    return true
  let error = res.error
  case channel
  of ckTelegram: log.warn("tg setMessageReaction: " & error)
  of ckDiscord:  log.warn("dc setMessageReaction: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli:
    discard
  false

proc sendImmediateOutbound*(msg: OutboundMessage;
                            ports: OutboundChannelPorts;
                            log: Logger) {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  let sendResult = port.send(msg)
  if sendResult.isErr:
    let error = sendResult.error
    recordOutboundFailure(channelTag(msg.channel), error)
    case msg.channel
    of ckTelegram:  log.error("tg send: " & error)
    of ckDiscord:   log.error("dc send: " & error)
    of ckWeCom:     log.error("wc send: " & error)
    of ckWeChat:    log.error("wechat send: " & error)
    of ckQQ:        log.error("qq send: " & error)
    of ckFeishu:    log.error("fs send: " & error)
    of ckSlack:     log.error("sl send: " & error)
    of ckWhatsApp:  log.error("wa send: " & error)
    of ckSignal:    log.error("sig send: " & error)
    of ckDingTalk:  log.error("dt send: " & error)
    of ckMatrix:    log.error("mx send: " & error)
    of ckEmail:     log.error("em send: " & error)
    of ckCli:       log.error("cli send: " & error)

proc editImmediateOutbound*(msg: OutboundMessage;
                            ports: OutboundChannelPorts;
                            log: Logger): bool {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  let res =
    if msg.replaceKeyboard or msg.keyboard.len > 0:
      port.editKeyboard(msg.userId, msg.editTargetId, msg.text, msg.keyboard)
    else:
      port.editMessage(msg.userId, msg.editTargetId, msg.text)
  if res.isOk:
    log.info("sent " & $msg.channel & " (edit immediate) -> " & $msg.userId & " (" & $msg.text.len & " chars)")
    return true
  let error = res.error
  case msg.channel
  of ckTelegram: log.warn("tg editImmediate: " & error)
  of ckDiscord:  log.warn("dc editImmediate: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli:
    discard
  false

proc editStreamOutbound*(msg: OutboundMessage;
                         channelMsgId: string;
                         ports: OutboundChannelPorts;
                         log: Logger) {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  let res = port.editMessage(msg.userId, channelMsgId, msg.text)
  if res.isOk:
    log.info("sent " & $msg.channel & " (edit) -> " & $msg.userId & " (" & $msg.text.len & " chars)")
    return
  let error = res.error
  case msg.channel
  of ckTelegram: log.warn("tg editMessage: " & error)
  of ckDiscord:  log.warn("dc editMessage: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli: discard

proc createStreamOutbound*(msg: OutboundMessage;
                           ports: OutboundChannelPorts;
                           log: Logger): string {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  let res = port.sendReturnId(msg)
  if res.isOk:
    let channelMsgId = res.value
    log.info("sent " & $msg.channel & " (new stream) -> " & $msg.userId & " (" & $msg.text.len & " chars)")
    return channelMsgId
  let error = res.error
  recordOutboundFailure(channelTag(msg.channel), error)
  case msg.channel
  of ckTelegram: log.error("tg sendReturnId: " & error)
  of ckDiscord:  log.error("dc sendReturnId: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli: discard
  ""

proc createReplacementOutbound*(msg: OutboundMessage;
                                ports: OutboundChannelPorts;
                                log: Logger): string {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  let res = port.sendReturnId(msg)
  if res.isOk:
    let channelMsgId = res.value
    log.info("sent " & $msg.channel & " (new replacement) -> " & $msg.userId & " slot=" & msg.replacementSlot)
    return channelMsgId
  let error = res.error
  recordOutboundFailure(channelTag(msg.channel), error)
  case msg.channel
  of ckTelegram: log.error("tg sendReturnId replacement: " & error)
  of ckDiscord:  log.error("dc sendReturnId replacement: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli:
    discard
  ""

proc routeOutbound*(msg: OutboundMessage;
                    ports: OutboundChannelPorts;
                    log: Logger;
                    presentationState: var PresentationState) {.gcsafe.} =
  if msg.editTargetId.len > 0:
    if not editImmediateOutbound(msg, ports, log):
      sendImmediateOutbound(msg, ports, log)
    return
  if msg.replacementSlot.len > 0 and supportsEditableReplacement(msg.channel):
    let existingMsgId = presentationState.lookupReplacement(msg)
    if existingMsgId.len > 0:
      var editMsg = msg
      editMsg.editTargetId = existingMsgId
      # Replacement surfaces are a single evolving UI artifact. When a surface
      # transitions from buttons to plain text, editable channels must clear the
      # previous components instead of preserving them.
      editMsg.replaceKeyboard = true
      if editImmediateOutbound(editMsg, ports, log):
        return
    let channelMsgId = createReplacementOutbound(msg, ports, log)
    if channelMsgId.len > 0:
      presentationState.rememberReplacement(msg, channelMsgId)
      return
    sendImmediateOutbound(msg, ports, log)
    return
  let decision = decideOutbound(msg, presentationState)
  case decision.intent
  of oiSend:
    sendImmediateOutbound(msg, ports, log)
  of oiStreamUpdate:
    editStreamOutbound(msg, decision.existingMsgId, ports, log)
  of oiStreamCreate:
    let channelMsgId = createStreamOutbound(msg, ports, log)
    if channelMsgId.len > 0:
      presentationState.rememberStream(msg, channelMsgId)
  of oiSuppress:
    discard
  if decision.shouldCleanup:
    presentationState.clearStream(msg)
