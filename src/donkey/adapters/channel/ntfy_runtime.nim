## ntfy_runtime — the daemon loop's side of ntfy (E13.1).
##
## The polling thread queues the person's messages on the topic. Here each
## one becomes a session turn the same way as on the other channels: once per
## message id, through the shared inbound gate (DM policy), with `/continue`
## handled locally. The topic is the sender: whoever can write to it.

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
import ./ntfy


proc drainNtfyEvents*(a: var NtfyAdapter;
                      sm: var SessionManager;
                      handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                      enqueueReply: proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} = nil;
                      log: Logger = newLogger("ntfy.runtime")): int {.gcsafe.} =
  ## Drains the queue; returns how many messages made a turn or a local answer.
  var (has, m) = tryRecvNtfy()
  while has:
    block next:
      if not a.markSeen(m.id):
        log.debug("ntfy: message seen before " & m.id)
        break next
      let auth = authorizeInbound(sm, a.resolver.identityGate(), ckNtfy, m.topic, m.text)
      if not auth.allowed:
        log.warn("ntfy: unauthorized message on topic " & m.topic)
        break next
      sm.recordChannel(auth.userId, ckNtfy, m.topic, persist = false)
      let msg = InboundMessage(userId: auth.userId, channel: ckNtfy, channelId: m.topic,
                               rawChannelId: m.topic, messageId: m.id, text: m.text)
      let command = decideCommandRequest(CommandRequest(channel: ckNtfy, text: msg.text))
      if command.route == crLocal and decideLocalCommandAction(command) == lcaContinueLink:
        let linked = a.linkCodes.peek(command.value).isSome and
          a.resolver.consumeLinkCode(command.value.strip, ckNtfy, m.topic)
        let reply = OutboundMessage(userId: auth.userId, channel: ckNtfy,
                                    text: buildContinueResultText(linked), replyTo: m.topic)
        if enqueueReply == nil:
          log.error("ntfy: no outbox for /continue reply user=" & $auth.userId)
        else:
          enqueueReply(reply).isOkOr:
            log.error("ntfy: enqueue /continue reply failed: " & error)
        inc result
        break next
      if handleSessionFallback != nil:
        handleSessionFallback(msg)
        inc result
    (has, m) = tryRecvNtfy()
