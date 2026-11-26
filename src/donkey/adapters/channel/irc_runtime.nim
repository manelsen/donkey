## irc_runtime — the daemon loop's side of IRC (second round, front 1).
##
## The connection thread queues only PRIVMSGs the bot should answer, from
## people the server knows by services account. Here each one becomes a
## session turn through the shared inbound gate (DM policy; the group
## allowlist on the channel name), with `/continue` handled locally; the
## sender's nick is remembered for sends without a target.

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
import ./irc

proc drainIrcEvents*(a: var IrcAdapter;
                     sm: var SessionManager;
                     handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                     enqueueReply: proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} = nil;
                     log: Logger = newLogger("irc.runtime")): int {.gcsafe.} =
  var (has, p) = tryRecvIrc()
  while has:
    block next:
      let auth = authorizeInbound(sm, a.resolver.identityGate(), ckIrc, p.account,
                                  p.text, isGroup = p.isGroup, chatId = p.channel)
      if not auth.allowed:
        log.warn("irc: unauthorized message from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        break next
      a.rememberNick(p.account, p.nick).isOkOr:
        log.warn("irc: nick not saved: " & error)
      sm.recordChannel(auth.userId, ckIrc, p.replyTo, persist = false)
      let msg = InboundMessage(
        userId: auth.userId, channel: ckIrc, channelId: p.replyTo,
        chatId: p.channel, rawChannelId: p.account, text: p.text,
        isGroup: p.isGroup)
      let command = decideCommandRequest(CommandRequest(channel: ckIrc, text: msg.text))
      if command.route == crLocal and
          decideLocalCommandAction(command) == lcaContinueLink:
        let linked = a.linkCodes.peek(command.value).isSome and
          a.resolver.consumeLinkCode(command.value.strip, ckIrc, p.account)
        let reply = OutboundMessage(userId: auth.userId, channel: ckIrc,
                                    text: buildContinueResultText(linked),
                                    replyTo: p.replyTo)
        if enqueueReply == nil:
          log.error("irc: no outbox for /continue reply user=" & $auth.userId)
        else:
          enqueueReply(reply).isOkOr:
            log.error("irc: enqueue /continue reply failed: " & error)
        inc result
        break next
      if handleSessionFallback != nil:
        handleSessionFallback(msg)
        inc result
    (has, p) = tryRecvIrc()
