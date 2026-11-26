## google_chat_runtime — the daemon loop's side of Google Chat (second
## round, front 1).
##
## The webhook queues only human messages from tokens Google signed for this
## project. Here each one becomes a session turn once (Chat redelivers),
## through the shared inbound gate (DM policy; the group allowlist on the
## space name), with `/continue` handled locally; a direct space is
## remembered for sends without a target.

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
import ./google_chat

proc drainGoogleChatEvents*(a: var GoogleChatAdapter;
                            sm: var SessionManager;
                            handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                            enqueueReply: proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} = nil;
                            log: Logger = newLogger("gchat.runtime")): int {.gcsafe.} =
  var (has, e) = tryRecvChatEvent()
  while has:
    block next:
      if not e.isTurn:
        break next
      if not a.markSeen(e.id):
        log.debug("google chat: redelivered message " & e.id)
        break next
      let auth = authorizeInbound(sm, a.resolver.identityGate(), ckGoogleChat, e.sender,
                                  e.text, isGroup = e.isGroup, chatId = e.space)
      if not auth.allowed:
        log.warn("google chat: unauthorized message from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        break next
      let target = replyTarget(e)
      if not e.isGroup:
        a.rememberSpace(e.sender, e.space).isOkOr:
          log.warn("google chat: space not saved: " & error)
      sm.recordChannel(auth.userId, ckGoogleChat, target, persist = false)
      var msg = InboundMessage(
        userId: auth.userId, channel: ckGoogleChat, channelId: target,
        chatId: e.space, rawChannelId: e.sender, messageId: e.id,
        text: e.text, isGroup: e.isGroup)
      ## E9.2: the first uploaded file is downloaded for the turn (by its
      ## resource name, through the port's downloadFile); a Drive file, which
      ## the app cannot read, and the others are named.
      var unread: seq[string]
      for f in e.attachments:
        if msg.mediaUrl.len == 0 and not f.drive and f.resourceName.len > 0:
          msg.mediaUrl = f.resourceName
          msg.mediaFileName = f.name
          msg.mediaMimeType = f.mimeType
        else:
          unread.add(if f.name.len > 0: f.name else: "anexo")
      if unread.len > 0:
        if msg.text.len > 0: msg.text.add "\n\n"
        msg.text.add "[Anexos não lidos: " & unread.join(", ") & "]"
      let command = decideCommandRequest(CommandRequest(channel: ckGoogleChat, text: msg.text))
      if command.route == crLocal and
          decideLocalCommandAction(command) == lcaContinueLink:
        let linked = a.linkCodes.peek(command.value).isSome and
          a.resolver.consumeLinkCode(command.value.strip, ckGoogleChat, e.sender)
        let reply = OutboundMessage(userId: auth.userId, channel: ckGoogleChat,
                                    text: buildContinueResultText(linked),
                                    replyTo: target)
        if enqueueReply == nil:
          log.error("google chat: no outbox for /continue reply user=" & $auth.userId)
        else:
          enqueueReply(reply).isOkOr:
            log.error("google chat: enqueue /continue reply failed: " & error)
        inc result
        break next
      if handleSessionFallback != nil:
        handleSessionFallback(msg)
        inc result
    (has, e) = tryRecvChatEvent()
