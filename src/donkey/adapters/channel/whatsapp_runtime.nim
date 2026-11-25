import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log
import ../../app/session_manager
import ../../domain/message
import ../identity/identity_resolver
import ../../app/inbound_gate
import ../../app/approval_runtime
import whatsapp
import ../../app/command_dispatch
import ./common_runtime

proc drainWhatsAppEvents*(waAdapter: var WhatsAppAdapter;
                          whatsappPhoneNumberId: string;
                          sm: var SessionManager;
                          env: ChannelRuntimeEnv;
                          msgSeq: var int;
                          handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                          log: Logger = newLogger("wa.outbound")) =
  if whatsappPhoneNumberId.len == 0 or waAdapter.accessToken.len == 0:
    return

  var (hasEvent, event) = waAdapter.tryRecvEvent()
  while hasEvent:
    ## A Meta app shared by several numbers delivers every number's changes
    ## to every webhook. One addressed to another number is not ours: no
    ## identity, no ack, no reply (from our number) to a conversation we are
    ## not part of. Hermes WA-001 (docs/hermes-mining/whatsapp/CASES.md).
    ## Meta always names the number (metadata.phone_number_id): an event
    ## without it is malformed and not shown to be ours, so it is skipped too.
    if event.phoneNumberId != whatsappPhoneNumberId:
      log.debug("whatsapp: message for number '" & event.phoneNumberId &
                "' ignored (this one is " & whatsappPhoneNumberId & ")")
      (hasEvent, event) = waAdapter.tryRecvEvent()
      continue
    ## Only text/interactive events run the command dispatcher; a media
    ## caption containing `/continue <code>` must not mint an identity.
    let gateText =
      if event.kind in {wrkText, wrkInteractive}: event.text else: ""
    let auth = authorizeInbound(sm, waAdapter.resolver.identityGate(), ckWhatsApp,
                                event.waUserId, gateText)
    if not auth.allowed:
      log.warn("whatsapp: unauthorized message from " &
               (if auth.identified: $auth.userId else: "unidentified sender"))
      (hasEvent, event) = waAdapter.tryRecvEvent()
      continue
    let userId = auth.userId

    if event.phoneNumberId.len > 0 and event.messageId.len > 0:
      waAdapter.ack(event.phoneNumberId, event.messageId)

    let approvalReply = tryHandleApprovalInput(userId, event.text)
    if approvalReply.isSome:
      waAdapter.send(OutboundMessage(
        userId: userId, channel: ckWhatsApp, text: approvalReply.get)).isOkOr:
        log.error("wa send approval reply failed: " & error)
      (hasEvent, event) = waAdapter.tryRecvEvent()
      continue

    let msg = InboundMessage(
      userId: userId,
      channel: ckWhatsApp,
      channelId: event.messageId,
      messageId: event.messageId,
      text: event.text,
      mediaUrl: event.mediaId,
    )

    if event.kind in {wrkText, wrkInteractive} and event.text.strip.len > 0:
      let command = decideCommandRequest(CommandRequest(channel: ckWhatsApp, text: event.text))
      let outcome = dispatchCommand(env.commands, sm, msgSeq,
          commandRequest(command, userId, ckWhatsApp, event.messageId, event.waUserId,
                         waAdapter.resolver))
      case outcome.kind
      of cokFallback:
        handleSessionFallback(msg)
      of cokAccepted:
        discard
      of cokReply:
        if outcome.reply.shouldSend:
          waAdapter.send(OutboundMessage(userId: userId, channel: ckWhatsApp,
                                         text: outcome.reply.text)).isOkOr:
            log.error("wa send " & $outcome.reply.topic & " failed for user=" &
                      $userId & " reason=" & error)
    else:
      handleSessionFallback(msg)

    (hasEvent, event) = waAdapter.tryRecvEvent()
