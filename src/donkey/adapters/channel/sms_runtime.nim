## sms_runtime — the daemon loop's side of SMS (second round, front 1).
##
## The webhook queues only messages Twilio signed. Here each one becomes a
## session turn the same way as on the other channels: once per message id,
## through the shared inbound gate (DM policy), with `/continue` handled
## locally. A message with media and no text gets a short answer: SMS is
## text only here.

import std/[options, strutils]
import ../../app/inbound_gate
import ../../app/session_manager
import ../../core/commands/command_routing
import ../../core/log
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ./common_runtime
import ../identity/identity_resolver
import ./sms

const MediaOnlyText* = "Por SMS eu só leio texto; mande a mensagem escrita."

proc drainSmsEvents*(a: var SmsAdapter;
                     sm: var SessionManager;
                     handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                     enqueueReply: proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} = nil;
                     log: Logger = newLogger("sms.runtime")): int {.gcsafe.} =
  ## Drains the queue and returns the number of messages that made a turn
  ## (or a local answer). Every message is consumed.
  var (has, m) = tryRecvSms()
  while has:
    block next:
      if not a.markSeen(m.sid):
        log.debug("sms: redelivered message " & m.sid)
        break next
      let auth = authorizeInbound(sm, a.resolver.identityGate(), ckSms, m.sender, m.text)
      if not auth.allowed:
        log.warn("sms: unauthorized message from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        break next
      proc answer(text: string) =
        let reply = OutboundMessage(userId: auth.userId, channel: ckSms,
                                    text: text, replyTo: m.sender)
        if enqueueReply == nil:
          log.error("sms: no outbox for a local reply user=" & $auth.userId)
        else:
          enqueueReply(reply).isOkOr:
            log.error("sms: enqueue local reply failed: " & error)
      if m.text.strip.len == 0:
        if m.mediaCount > 0:
          answer(MediaOnlyText)
          inc result
        break next
      sm.recordChannel(auth.userId, ckSms, m.sender, persist = false)
      let msg = InboundMessage(
        userId: auth.userId, channel: ckSms, channelId: m.sender,
        rawChannelId: m.sender, messageId: m.sid, text: m.text)
      let command = decideCommandRequest(CommandRequest(channel: ckSms, text: msg.text))
      if command.route == crLocal and
          decideLocalCommandAction(command) == lcaContinueLink:
        let linked = a.linkCodes.peek(command.value).isSome and
          a.resolver.consumeLinkCode(command.value.strip, ckSms, m.sender)
        answer(buildContinueResultText(linked))
        inc result
        break next
      if handleSessionFallback != nil:
        handleSessionFallback(msg)
        inc result
    (has, m) = tryRecvSms()
