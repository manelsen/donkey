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
                          log: Logger = newLogger("wa.outbound");
                          pickNumber: proc(number: string): (ptr WhatsAppAdapter, string) {.gcsafe.} = nil;
                          noteInbound: proc(userId: UserId; bot: string) {.gcsafe.} = nil) =
  ## With `[[bots]]` on WhatsApp (E3.5) the numbers of the account share this
  ## queue: `pickNumber` gives the adapter and bot of the number an event was
  ## sent to, and `noteInbound` makes that bot the person's before anything
  ## is sent. Without it only the default number is served.
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
    var picked: ptr WhatsAppAdapter = nil
    var bot = ""
    if event.phoneNumberId.len > 0 and event.phoneNumberId == whatsappPhoneNumberId:
      picked = addr waAdapter
    elif pickNumber != nil:
      (picked, bot) = pickNumber(event.phoneNumberId)
    if picked.isNil:
      log.debug("whatsapp: message for number '" & event.phoneNumberId &
                "' ignored (this one is " & whatsappPhoneNumberId & ")")
      (hasEvent, event) = waAdapter.tryRecvEvent()
      continue
    ## Only text/interactive events run the command dispatcher; a media
    ## caption containing `/continue <code>` must not mint an identity.
    let gateText =
      if event.kind in {wrkText, wrkInteractive}: event.text else: ""
    let auth = authorizeInbound(sm, picked[].resolver.identityGate(), ckWhatsApp,
                                event.waUserId, gateText)
    if not auth.allowed:
      log.warn("whatsapp: unauthorized message from " &
               (if auth.identified: $auth.userId else: "unidentified sender"))
      (hasEvent, event) = waAdapter.tryRecvEvent()
      continue
    let userId = auth.userId
    if noteInbound != nil:
      noteInbound(userId, bot)

    if event.phoneNumberId.len > 0 and event.messageId.len > 0:
      picked[].ack(event.phoneNumberId, event.messageId)

    let approvalReply = tryHandleApprovalInput(userId, event.text)
    if approvalReply.isSome:
      picked[].send(OutboundMessage(
        userId: userId, channel: ckWhatsApp, text: approvalReply.get)).isOkOr:
        log.error("wa send approval reply failed: " & error)
      (hasEvent, event) = waAdapter.tryRecvEvent()
      continue

    if event.kind == wrkText:
      rememberWaText(event.messageId, event.text)
    let msg = InboundMessage(
      userId: userId,
      channel: ckWhatsApp,
      channelId: event.messageId,
      messageId: event.messageId,
      text: event.text,
      mediaUrl: event.mediaId,
      quotedText: quotedWaText(event.replyToId),
      bot: bot,   ## the turn answers with that bot's persona
    )

    if event.kind in {wrkText, wrkInteractive} and event.text.strip.len > 0:
      let command = decideCommandRequest(CommandRequest(channel: ckWhatsApp, text: event.text))
      let outcome = dispatchCommand(env.commands, sm, msgSeq,
          commandRequest(command, userId, ckWhatsApp, event.messageId, event.waUserId,
                         picked[].resolver, privateChat = true))   ## a business number talks one to one
      case outcome.kind
      of cokFallback:
        handleSessionFallback(msg)
      of cokAccepted:
        discard
      of cokReply:
        if outcome.reply.shouldSend:
          picked[].send(OutboundMessage(userId: userId, channel: ckWhatsApp,
                                         text: outcome.reply.text)).isOkOr:
            log.error("wa send " & $outcome.reply.topic & " failed for user=" &
                      $userId & " reason=" & error)
    else:
      handleSessionFallback(msg)

    (hasEvent, event) = waAdapter.tryRecvEvent()
