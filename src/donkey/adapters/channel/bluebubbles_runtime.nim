## bluebubbles_runtime — the daemon loop's side of BlueBubbles (E13.3).
##
## The polling thread queues people's one-to-one iMessages. Here each one
## becomes a session turn the same way as on the other channels: once per
## message guid, through the shared inbound gate (DM policy), with
## `/continue` handled locally. The address is the sender; the answer goes
## to the chat it came from. A message with only attachments gets a short
## answer; attachments next to text are named as unread.

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
import ./bluebubbles

const AttachmentOnlyText* = "Pelo iMessage eu só leio texto; mande a mensagem escrita."

proc drainBlueBubblesEvents*(a: var BlueBubblesAdapter;
                             sm: var SessionManager;
                             handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                             enqueueReply: proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} = nil;
                             log: Logger = newLogger("bluebubbles.runtime")): int {.gcsafe.} =
  ## Drains the queue; returns how many messages made a turn or a local answer.
  var (has, m) = tryRecvBlue()
  while has:
    block next:
      if not a.markSeen(m.guid):
        log.debug("bluebubbles: message seen before " & m.guid)
        break next
      let auth = authorizeInbound(sm, a.resolver.identityGate(), ckBlueBubbles, m.address, m.text)
      if not auth.allowed:
        log.warn("bluebubbles: unauthorized message from " & m.address)
        break next
      proc answer(text: string) =
        let reply = OutboundMessage(userId: auth.userId, channel: ckBlueBubbles, text: text,
                                    replyTo: m.chatGuid)
        if enqueueReply == nil:
          log.error("bluebubbles: no outbox for a local reply user=" & $auth.userId)
        else:
          enqueueReply(reply).isOkOr:
            log.error("bluebubbles: enqueue local reply failed: " & error)
      if m.text.strip.len == 0:
        if m.attachments > 0:
          answer(AttachmentOnlyText)
          inc result
        break next
      sm.recordChannel(auth.userId, ckBlueBubbles, m.chatGuid, persist = false)
      var msg = InboundMessage(userId: auth.userId, channel: ckBlueBubbles, channelId: m.chatGuid,
                               rawChannelId: m.address, messageId: m.guid, text: m.text)
      if m.attachments > 0:
        msg.text.add "\n\n[" & $m.attachments & " anexo(s) não lido(s): pelo iMessage eu só leio texto]"
      let command = decideCommandRequest(CommandRequest(channel: ckBlueBubbles, text: m.text))
      if command.route == crLocal and decideLocalCommandAction(command) == lcaContinueLink:
        let linked = a.linkCodes.peek(command.value).isSome and
          a.resolver.consumeLinkCode(command.value.strip, ckBlueBubbles, m.address)
        answer(buildContinueResultText(linked))
        inc result
        break next
      if handleSessionFallback != nil:
        handleSessionFallback(msg)
        inc result
    (has, m) = tryRecvBlue()
