## simplex_runtime — the daemon loop's side of SimpleX (E13.2).
##
## The connection thread queues the direct messages contacts sent. Here each
## one becomes a session turn the same way as on the other channels: once
## per item id, through the shared inbound gate (DM policy), with
## `/continue` handled locally. The contact is the sender. A message that is
## not text (an image, a file) gets a short answer.

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
import ./simplex

const NotTextText* = "Pelo SimpleX eu só leio texto; mande a mensagem escrita."

proc drainSimplexEvents*(a: var SimplexAdapter;
                         sm: var SessionManager;
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                         enqueueReply: proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} = nil;
                         log: Logger = newLogger("simplex.runtime")): int {.gcsafe.} =
  ## Drains the queue; returns how many messages made a turn or a local answer.
  var (has, m) = tryRecvSimplex()
  while has:
    block next:
      if not a.markSeen(m.itemId):
        log.debug("simplex: item seen before " & m.itemId)
        break next
      let sender = $m.contactId
      let auth = authorizeInbound(sm, a.resolver.identityGate(), ckSimplex, sender, m.text)
      if not auth.allowed:
        log.warn("simplex: unauthorized message from contact " & sender)
        break next
      proc answer(text: string) =
        let reply = OutboundMessage(userId: auth.userId, channel: ckSimplex, text: text,
                                    replyTo: sender)
        if enqueueReply == nil:
          log.error("simplex: no outbox for a local reply user=" & $auth.userId)
        else:
          enqueueReply(reply).isOkOr:
            log.error("simplex: enqueue local reply failed: " & error)
      if m.unreadKind.len > 0:
        answer(NotTextText)
        inc result
        break next
      sm.recordChannel(auth.userId, ckSimplex, sender, persist = false)
      let msg = InboundMessage(userId: auth.userId, channel: ckSimplex, channelId: sender,
                               rawChannelId: sender, messageId: m.itemId, text: m.text)
      let command = decideCommandRequest(CommandRequest(channel: ckSimplex, text: msg.text))
      if command.route == crLocal and decideLocalCommandAction(command) == lcaContinueLink:
        let linked = a.linkCodes.peek(command.value).isSome and
          a.resolver.consumeLinkCode(command.value.strip, ckSimplex, sender)
        answer(buildContinueResultText(linked))
        inc result
        break next
      if handleSessionFallback != nil:
        handleSessionFallback(msg)
        inc result
    (has, m) = tryRecvSimplex()
