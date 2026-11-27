## teams_runtime — the daemon loop's side of Microsoft Teams (PRD-roadmap
## E2.4).
##
## The webhook threads queue only activities whose JWT checked out
## (webhook_receiver, teams_auth). Here each one becomes a session turn the
## same way as on the other callback channels: a message with text, not seen
## before, through the shared inbound gate (DM policy, group allowlist on the
## conversation id), with `/continue` handled locally.

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
import ./teams

func groupChatId(conversationId: string): string =
  ## A channel thread's id carries `;messageid=…`; the group is the part
  ## before it, which is what an operator lists as allowed.
  conversationId.split(';')[0]

proc drainTeamsEvents*(a: var TeamsAdapter;
                       sm: var SessionManager;
                       seen: var TeamsSeen;
                       handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                       enqueueReply: proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} = nil;
                       log: Logger = newLogger("teams.runtime");
                       pickBot: proc(bot: string): ptr TeamsAdapter {.gcsafe.} = nil;
                       noteInbound: proc(userId: UserId; bot: string) {.gcsafe.} = nil): int {.gcsafe.} =
  ## Drains the queue and returns the number of activities that made a turn
  ## (or a local `/continue`). Every activity is consumed.
  var (has, act) = tryRecvActivity()
  while has:
    block next:
      if act.kind == "invoke" and act.name == "fileConsent/invoke":
        ## The answer to a file consent card (Teams complete): handled by the
        ## app that offered the file; not a turn. The pending id is a random
        ## value only that card carried.
        let owner =
          if act.bot.len == 0: addr a
          elif pickBot != nil: pickBot(act.bot)
          else: nil
        if owner.isNil:
          log.warn("teams: file consent for bot " & act.bot & ", which is not configured")
        else:
          owner[].handleFileConsent(act).isOkOr:
            log.warn("teams: file consent: " & error)
        break next
      if act.kind != "message" or (act.text.strip.len == 0 and act.attachments.len == 0):
        log.debug("teams: skipped " & act.kind & " activity " & act.id)
        break next
      if not markSeen(seen, act.id):
        log.debug("teams: redelivered activity " & act.id)
        break next
      ## The app the route found in the token's audience (E3.6): its adapter
      ## holds that app's token and conversations.
      let picked =
        if act.bot.len == 0: addr a
        elif pickBot != nil: pickBot(act.bot)
        else: nil
      if picked.isNil:
        log.warn("teams: activity for bot " & act.bot & ", which is not configured")
        break next
      let sender = act.senderKey
      let auth = authorizeInbound(sm, picked[].resolver.identityGate(), ckTeams,
                                  sender, act.text, isGroup = act.isGroup,
                                  chatId = groupChatId(act.conversationId))
      if not auth.allowed:
        log.warn("teams: unauthorized message from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        break next
      if noteInbound != nil:
        noteInbound(auth.userId, act.bot)
      let target = replyTarget(act.serviceUrl, act.conversationId, act.id)
      picked[].rememberConversation(sender, act.serviceUrl, act.conversationId).isOkOr:
        log.warn("teams: conversation not saved: " & error)
      sm.recordChannel(auth.userId, ckTeams, target, persist = false)
      var msg = InboundMessage(
        userId: auth.userId, channel: ckTeams, channelId: target,
        chatId: groupChatId(act.conversationId), rawChannelId: sender,
        messageId: act.id, text: act.text, isGroup: act.isGroup,
        bot: act.bot)   ## the turn answers with that bot's persona
      ## E9.4: the first attachment is downloaded for the turn (through the
      ## port's downloadFile); the others are named.
      var unread: seq[string]
      for i, f in act.attachments:
        if i == 0:
          msg.mediaUrl = f.fileId
          msg.mediaFileName = f.name
          msg.mediaMimeType = f.mimeType
        else:
          unread.add(if f.name.len > 0: f.name elif f.mimeType.len > 0: f.mimeType else: "anexo")
      if unread.len > 0:
        if msg.text.len > 0: msg.text.add "\n\n"
        msg.text.add "[Anexos não lidos: " & unread.join(", ") & "]"
      let command = decideCommandRequest(CommandRequest(channel: ckTeams, text: msg.text))
      if command.route == crLocal and
          decideLocalCommandAction(command) == lcaContinueLink:
        ## The code was probably minted on another channel: the shared table
        ## is the authority, as on LINE.
        let linked = picked[].linkCodes.peek(command.value).isSome and
          picked[].resolver.consumeLinkCode(command.value.strip, ckTeams, sender)
        let reply = OutboundMessage(userId: auth.userId, channel: ckTeams,
                                    text: buildContinueResultText(linked),
                                    replyTo: target)
        if enqueueReply == nil:
          log.error("teams: no outbox for /continue reply user=" & $auth.userId)
        else:
          enqueueReply(reply).isOkOr:
            log.error("teams: enqueue /continue reply failed: " & error)
        inc result
        break next
      if handleSessionFallback != nil:
        handleSessionFallback(msg)
        inc result
    (has, act) = tryRecvActivity()
