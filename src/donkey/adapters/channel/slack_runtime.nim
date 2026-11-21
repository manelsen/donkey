## Slack inbound runtime — drains webhook events and dispatches commands.
##
## Events are enqueued by the Slack webhook receiver and consumed here from the
## daemon loop. Messages, slash commands and block actions share the same DM
## gate and command/session routing as the other webhook channels.

import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../identity/identity_resolver
import ../../app/inbound_gate
import ../../app/approval_runtime
import ../../domain/channels/slack_pure
import ./common_runtime
import ./slack
import ../../app/command_dispatch

proc replyToEvent(slAdapter: var SlackAdapter;
                  event: SlackRawEvent;
                  userId: UserId;
                  text: string): Result[void, string] =
  ## Slash commands reply through response_url (ephemeral); everything else,
  ## and any response_url failure, uses the requester's DM.
  if event.kind == srSlashCommand and event.responseUrl.len > 0:
    let viaUrl = slAdapter.respondToUrl(event.responseUrl, text)
    if viaUrl.isOk:
      return ok()
  slAdapter.send(OutboundMessage(userId: userId, channel: ckSlack, text: text))

proc slackCommandOutcome(slAdapter: var SlackAdapter;
                         sm: var SessionManager;
                         msgSeq: var int;
                         env: ChannelRuntimeEnv;
                         command: CommandDecision;
                         userId: UserId;
                         event: SlackRawEvent;
                         messageId: string;
                         presented: var bool): CommandOutcome =
  ## Slack presents /menu and /config as Block Kit keyboards (`presented`);
  ## when that fails, and for every other command, the shared dispatcher
  ## answers.
  if command.route == crLocal and decideLocalCommandAction(command) == lcaShowMenu:
    if slAdapter.sendKeyboard(userId, buildMenuText(), buildMenuButtons()).isOk:
      presented = true
      return fallback()
  elif command.kind == cmdConfig:
    if slAdapter.sendKeyboard(userId, env.memory.buildConfigText(userId),
                              buildConfigButtons()).isOk:
      presented = true
      return fallback()
  dispatchCommand(env.commands, sm, msgSeq,
    commandRequest(command, userId, ckSlack, messageId, event.slackUserId,
                   slAdapter.resolver))

proc drainSlackEvents*(slAdapter: var SlackAdapter;
                       sm: var SessionManager;
                       env: ChannelRuntimeEnv;
                       msgSeq: var int;
                       handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                       log: Logger = newLogger("sl.outbound")) =
  ## Drains Slack events from webhook or Socket Mode.
  var (hasEvent, event) = slAdapter.tryRecvEvent()
  while hasEvent:
    try:
      ## Slack redelivers an authenticated event when the HTTP ack is lost.
      ## Drop repeats before any command/session side effect.
      if slAdapter.isDuplicate(event):
        log.info("slack: duplicate event ignored")
        (hasEvent, event) = slAdapter.tryRecvEvent()
        continue

      ## A denied sender is consumed (so the queue advances) but never reaches
      ## the provider or session layer.
      let auth = authorizeInbound(sm, slAdapter.resolver.identityGate(), ckSlack,
                                  event.slackUserId, event.text)
      if not auth.allowed:
        log.warn("slack: unauthorized event from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        (hasEvent, event) = slAdapter.tryRecvEvent()
        continue

      let userId = auth.userId
      let approvalReply = tryHandleApprovalInput(userId, event.text)
      if approvalReply.isSome:
        replyToEvent(slAdapter, event, userId, approvalReply.get).isOkOr:
          log.error("sl send approval reply failed: " & error)
        (hasEvent, event) = slAdapter.tryRecvEvent()
        continue

      let messageId =
        if event.eventTs.len > 0: event.eventTs
        elif event.triggerId.len > 0: event.triggerId
        else: event.channelId

      ## Block actions are UI callbacks, not user text. Onboarding choices must
      ## become session tasks; the remaining actions map to text commands.
      ## Never feed "action:value" to the session fallback.
      var routedText = event.text
      if event.kind == srBlockAction:
        let callback = decideCallbackRequest(
          CallbackRequest(channel: ckSlack, data: event.text))
        if callback.kind in {cbkPersonality, cbkName}:
          if sm.hasLiveSession(userId):
            let entry = sm.getOrCreate(userId)
            inc msgSeq
            entry.inbox.addLastNoWait(
              newTaskMsg($msgSeq, callbackTaskKind(callback), $userId,
                         callback.value, ckSlack, messageId))
          else:
            slAdapter.send(OutboundMessage(
              userId: userId, channel: ckSlack,
              text: "Envie uma mensagem primeiro para iniciar o onboarding.")).isOkOr:
              log.error("sl send onboarding feedback failed for user=" & $userId &
                        " reason=" & error)
          (hasEvent, event) = slAdapter.tryRecvEvent()
          continue
        routedText = blockActionCommand(event.text)
        if routedText.len == 0:
          slAdapter.send(OutboundMessage(
            userId: userId, channel: ckSlack,
            text: "Ação não reconhecida. Use /help para ver os comandos.")).isOkOr:
            log.error("sl send unknown block action failed for user=" & $userId &
                      " reason=" & error)
          (hasEvent, event) = slAdapter.tryRecvEvent()
          continue

      let msg = InboundMessage(
        userId:    userId,
        channel:   ckSlack,
        channelId: event.channelId,
        messageId: messageId,
        text:      routedText,
      )

      if routedText.strip.len > 0:
        let command = decideCommandRequest(CommandRequest(channel: ckSlack, text: routedText))
        var presented = false
        let outcome =
          try:
            slackCommandOutcome(slAdapter, sm, msgSeq, env, command, userId,
                                event, messageId, presented)
          except CatchableError as e:
            replied(rtUnsupported, "Erro ao processar comando: " & e.msg)
        if not presented:  ## a Block Kit keyboard already answered otherwise
          case outcome.kind
          of cokFallback:
            handleSessionFallback(msg)
          of cokAccepted:
            ## A slash command expects a visible answer; plain messages stay
            ## silent while the task runs.
            if event.kind == srSlashCommand:
              replyToEvent(slAdapter, event, userId, acceptedText(outcome.task)).isOkOr:
                log.error("sl send ack failed for user=" & $userId & " reason=" & error)
          of cokReply:
            ## Slack answers unsupported commands instead of staying silent.
            ## Every Slack reply is ephemeral or a DM: none lands in a channel.
            if outcome.reply.text.len > 0:
              replyToEvent(slAdapter, event, userId, outcome.reply.text).isOkOr:
                log.error("sl send " & $outcome.reply.topic & " failed for user=" &
                          $userId & " reason=" & error)
      else:
        handleSessionFallback(msg)

    except CatchableError as e:
      log.error("slack: event processing failed: " & e.msg)
    (hasEvent, event) = slAdapter.tryRecvEvent()
