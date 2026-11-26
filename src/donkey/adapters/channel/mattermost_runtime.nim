## mattermost_runtime — the daemon loop's side of Mattermost (second round,
## front 1).
##
## The socket thread queues only posts the bot should answer (a direct
## message, or a channel post that mentions it). Here each one becomes a
## session turn the same way as on the other channels: through the shared
## inbound gate (DM policy; the group allowlist on the channel id), with
## `/continue` handled locally.

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
import ./mattermost

proc drainMattermostEvents*(a: var MattermostAdapter;
                            sm: var SessionManager;
                            handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                            enqueueReply: proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} = nil;
                            log: Logger = newLogger("mattermost.runtime")): int {.gcsafe.} =
  ## Drains the queue and returns the number of posts that made a turn (or a
  ## local `/continue`). Every post is consumed.
  var (has, post) = tryRecvPost()
  while has:
    block next:
      let auth = authorizeInbound(sm, a.resolver.identityGate(), ckMattermost,
                                  post.userId, post.text, isGroup = post.isGroup,
                                  chatId = post.channelId)
      if not auth.allowed:
        log.warn("mattermost: unauthorized post from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        break next
      let target = replyTarget(post)
      if not post.isGroup:
        a.rememberChannel(post.userId, post.channelId).isOkOr:
          log.warn("mattermost: channel not saved: " & error)
      sm.recordChannel(auth.userId, ckMattermost, target, persist = false)
      var msg = InboundMessage(
        userId: auth.userId, channel: ckMattermost, channelId: target,
        chatId: post.channelId, rawChannelId: post.userId,
        messageId: post.id, text: post.text, isGroup: post.isGroup)
      ## E9.1: the first file that fits is downloaded for the turn (by its id,
      ## through the port's downloadFile); the others, or one too large, are
      ## named.
      var unread: seq[string]
      for f in post.files:
        let name = if f.name.len > 0: f.name else: f.id
        if msg.mediaUrl.len == 0 and f.size <= MattermostMaxDownloadBytes:
          msg.mediaUrl = f.id
          msg.mediaFileName = f.name
          msg.mediaMimeType = f.mimeType
        else:
          unread.add name
      if unread.len > 0:
        if msg.text.len > 0: msg.text.add "\n\n"
        msg.text.add "[Anexos não lidos: " & unread.join(", ") & "]"
      let command = decideCommandRequest(CommandRequest(channel: ckMattermost, text: msg.text))
      if command.route == crLocal and
          decideLocalCommandAction(command) == lcaContinueLink:
        let linked = a.linkCodes.peek(command.value).isSome and
          a.resolver.consumeLinkCode(command.value.strip, ckMattermost, post.userId)
        let reply = OutboundMessage(userId: auth.userId, channel: ckMattermost,
                                    text: buildContinueResultText(linked),
                                    replyTo: target)
        if enqueueReply == nil:
          log.error("mattermost: no outbox for /continue reply user=" & $auth.userId)
        else:
          enqueueReply(reply).isOkOr:
            log.error("mattermost: enqueue /continue reply failed: " & error)
        inc result
        break next
      if handleSessionFallback != nil:
        handleSessionFallback(msg)
        inc result
    (has, post) = tryRecvPost()
