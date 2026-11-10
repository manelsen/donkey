import std/[hashes, strutils]
import ../core/log
import ../core/pipeops
import ../core/outbound/outbound
import ../ports/channel
import ../ports/runtime_state
import ../domain/message
import ./metrics

export outbound

func textDigest(text: string): string =
  ## Stable-enough short reference; the ledger never stores message bodies.
  let value = $hash(text)
  if value.len > 12: value[0 ..< 12] else: value

func newDeliveryId(msg: OutboundMessage; timestampMs: int64): string =
  $timestampMs & "-" & textDigest(
    $msg.userId & "|" & $msg.channel & "|" & msg.replyTo & "|" & msg.text)

proc beginDelivery(ledger: DeliveryLedgerPort;
                   msg: OutboundMessage;
                   log: Logger): DeliveryRecord {.gcsafe.} =
  let now = epochMs()
  result = DeliveryRecord(
    id: newDeliveryId(msg, now),
    userId: $msg.userId,
    channel: msg.channel,
    channelId: msg.replyTo,
    textHash: textDigest(msg.text),
    state: dlsPending,
    attempts: 1,
    createdAtMs: now,
    updatedAtMs: now,
  )
  if ledger.recordPending == nil:
    return
  try:
    let saved = ledger.recordPending(result)
    if saved.isErr:
      log.warn("delivery ledger pending: " & saved.error)
  except CatchableError as e:
    log.warn("delivery ledger pending: " & e.msg)

proc finishDeliverySent(ledger: DeliveryLedgerPort;
                        id: string;
                        log: Logger) {.gcsafe.} =
  if ledger.markSent == nil:
    return
  try:
    let saved = ledger.markSent(id, epochMs())
    if saved.isErr:
      log.warn("delivery ledger sent: " & saved.error)
  except CatchableError as e:
    log.warn("delivery ledger sent: " & e.msg)

proc finishDeliveryFailed(ledger: DeliveryLedgerPort;
                          id, error: string;
                          log: Logger) {.gcsafe.} =
  if ledger.markFailed == nil:
    return
  try:
    let saved = ledger.markFailed(id, epochMs(), error)
    if saved.isErr:
      log.warn("delivery ledger failed: " & saved.error)
  except CatchableError as e:
    log.warn("delivery ledger failed: " & e.msg)

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
  let lowerError = error.toLowerAscii()
  if channel == ckTelegram and
     ("reaction_invalid" in lowerError or
      "message can't be reacted" in lowerError or
      "reactions are unavailable" in lowerError or
      "message reactions are not supported" in lowerError):
    return true
  case channel
  of ckTelegram: log.warn("tg setMessageReaction: " & error)
  of ckDiscord:  log.warn("dc setMessageReaction: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli:
    discard
  false

proc sendImmediateOutbound*(msg: OutboundMessage;
                            ports: OutboundChannelPorts;
                            log: Logger;
                            ledger: DeliveryLedgerPort = DeliveryLedgerPort()) {.gcsafe.} =
  let delivery = beginDelivery(ledger, msg, log)
  let port = ports.channelPortFor(msg.channel)
  if port.send == nil:
    let error = "channel " & $msg.channel & " is not configured"
    log.error("outbound: " & error)
    finishDeliveryFailed(ledger, delivery.id, error, log)
    return
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
    finishDeliveryFailed(ledger, delivery.id, error, log)
  else:
    finishDeliverySent(ledger, delivery.id, log)

proc editImmediateOutbound*(msg: OutboundMessage;
                            ports: OutboundChannelPorts;
                            log: Logger): bool {.gcsafe.} =
  let port = ports.channelPortFor(msg.channel)
  let res =
    if msg.replaceKeyboard or msg.keyboard.len > 0:
      port.editKeyboard(msg.userId, msg.editTargetId, msg.text, msg.keyboard)
    else:
      port.editMessage(msg.userId, msg.editTargetId, msg.text, msg.isHtml)
  if res.isOk:
    log.debug("sent " & $msg.channel & " (edit immediate) -> " & $msg.userId & " (" & $msg.text.len & " chars)")
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
  let res = port.editMessage(msg.userId, channelMsgId, msg.text, msg.isHtml)
  if res.isOk:
    log.debug("sent " & $msg.channel & " (edit) -> " & $msg.userId & " (" & $msg.text.len & " chars)")
    return
  let error = res.error
  case msg.channel
  of ckTelegram: log.warn("tg editMessage: " & error)
  of ckDiscord:  log.warn("dc editMessage: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli: discard

proc createStreamOutbound*(msg: OutboundMessage;
                           ports: OutboundChannelPorts;
                           log: Logger;
                           ledger: DeliveryLedgerPort = DeliveryLedgerPort()): string {.gcsafe.} =
  let delivery = beginDelivery(ledger, msg, log)
  let port = ports.channelPortFor(msg.channel)
  let res = port.sendReturnId(msg)
  if res.isOk:
    let channelMsgId = res.value
    log.info("sent " & $msg.channel & " (new stream) -> " & $msg.userId & " (" & $msg.text.len & " chars)")
    finishDeliverySent(ledger, delivery.id, log)
    return channelMsgId
  let error = res.error
  recordOutboundFailure(channelTag(msg.channel), error)
  case msg.channel
  of ckTelegram: log.error("tg sendReturnId: " & error)
  of ckDiscord:  log.error("dc sendReturnId: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli: discard
  finishDeliveryFailed(ledger, delivery.id, error, log)
  ""

proc createReplacementOutbound*(msg: OutboundMessage;
                                ports: OutboundChannelPorts;
                                log: Logger;
                                ledger: DeliveryLedgerPort = DeliveryLedgerPort()): string {.gcsafe.} =
  let delivery = beginDelivery(ledger, msg, log)
  let port = ports.channelPortFor(msg.channel)
  let res = port.sendReturnId(msg)
  if res.isOk:
    let channelMsgId = res.value
    log.info("sent " & $msg.channel & " (new replacement) -> " & $msg.userId & " slot=" & msg.replacementSlot)
    finishDeliverySent(ledger, delivery.id, log)
    return channelMsgId
  let error = res.error
  recordOutboundFailure(channelTag(msg.channel), error)
  case msg.channel
  of ckTelegram: log.error("tg sendReturnId replacement: " & error)
  of ckDiscord:  log.error("dc sendReturnId replacement: " & error)
  of ckWeCom, ckWeChat, ckQQ, ckFeishu, ckSlack, ckWhatsApp, ckSignal, ckDingTalk, ckMatrix, ckEmail, ckCli:
    discard
  finishDeliveryFailed(ledger, delivery.id, error, log)
  ""

proc routeOutbound*(msg: OutboundMessage;
                    ports: OutboundChannelPorts;
                    log: Logger;
                    presentationState: var PresentationState;
                    ledger: DeliveryLedgerPort = DeliveryLedgerPort()) {.gcsafe.} =
  if msg.editTargetId.len > 0:
    if not editImmediateOutbound(msg, ports, log):
      sendImmediateOutbound(msg, ports, log, ledger)
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
    let channelMsgId = createReplacementOutbound(msg, ports, log, ledger)
    if channelMsgId.len > 0:
      presentationState.rememberReplacement(msg, channelMsgId)
      return
    sendImmediateOutbound(msg, ports, log, ledger)
    return
  var effectiveMsg = msg
  if msg.streamId.len > 0 and supportsEditableStreams(msg.channel):
    let mergedText = appendStreamDelta(presentationState.lookupStreamText(msg), msg.text)
    if presentationState.lookupStream(msg).len > 0 and
       mergedText.len > streamMessageCharLimit(msg.channel):
      presentationState.clearStream(msg)
      effectiveMsg.text = msg.text
    else:
      effectiveMsg.text = mergedText
  let decision = decideOutbound(effectiveMsg, presentationState)
  case decision.intent
  of oiSend:
    sendImmediateOutbound(effectiveMsg, ports, log, ledger)
  of oiStreamUpdate:
    editStreamOutbound(effectiveMsg, decision.existingMsgId, ports, log)
    presentationState.rememberStreamText(effectiveMsg, effectiveMsg.text)
  of oiStreamCreate:
    let channelMsgId = createStreamOutbound(effectiveMsg, ports, log, ledger)
    if channelMsgId.len > 0:
      presentationState.rememberStream(effectiveMsg, channelMsgId)
      presentationState.rememberStreamText(effectiveMsg, effectiveMsg.text)
  of oiSuppress:
    discard
  if decision.shouldCleanup:
    presentationState.clearStream(effectiveMsg)
