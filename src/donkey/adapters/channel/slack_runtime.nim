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
import ./text_command_dispatch

proc replyToEvent(slAdapter: var SlackAdapter;
                  event: SlackRawEvent;
                  userId: UserId;
                  text: string;
                  sensitive = false): Result[void, string] =
  ## Slash commands reply through response_url (ephemeral) unless the content
  ## is sensitive; everything else uses the adapter's DM path.
  if not sensitive and event.kind == srSlashCommand and event.responseUrl.len > 0:
    let viaUrl = slAdapter.respondToUrl(event.responseUrl, text)
    if viaUrl.isOk:
      return ok()
  slAdapter.send(OutboundMessage(userId: userId, channel: ckSlack, text: text))

proc slackCommandOutcome(slAdapter: var SlackAdapter;
                         sm: var SessionManager;
                         msgSeq: var int;
                         env: CommandEnv;
                         command: CommandDecision;
                         userId: UserId;
                         event: SlackRawEvent;
                         messageId: string): CommandOutcome =
  ## Slack-only commands (Block Kit menus, whoami, reasoning toggle, extra UI
  ## views) first; everything else goes through the shared dispatcher.
  let memory = env.memory
  case command.route
  of crLocal:
    case decideLocalCommandAction(command)
    of lcaShowMenu:
      let text = buildMenuText()
      if slAdapter.sendKeyboard(userId, text, buildMenuButtons()).isOk:
        return CommandOutcome(kind: cokSilent)
      return replied(rtMenu, text)
    of lcaShowWhoami:
      return replied(rtWhoami, buildWhoamiText(userId, "", event.channelId),
                     sensitive = true)
    of lcaReasoningToggle:
      let prefs = loadChannelPrefs(memory, userId)
      let next = if prefs.reasoning == "on": "off" else: "on"
      let saved = saveChannelPreference(memory, userId, "reasoning", next)
      return replied(rtReasoning, savedOrError(saved, "Reasoning: " & next))
    else:
      discard
  of crUi:
    case command.kind
    of cmdConfig:
      let text = memory.buildConfigText(userId)
      if slAdapter.sendKeyboard(userId, text, buildConfigButtons()).isOk:
        return CommandOutcome(kind: cokSilent)
      return replied(rtUi, text)
    of cmdTasks:
      return replied(rtUi, buildTasksText())
    of cmdAgents:
      return replied(rtUi, buildAgentsText(env.toolsCount, env.toolClientsCount))
    of cmdPoll:
      return replied(rtUi, buildPollText())
    else:
      discard
  else:
    discard
  dispatchTextCommand(env, sm, msgSeq, command, userId, ckSlack, messageId,
                      slAdapter.resolver, event.slackUserId)

proc drainSlackEvents*(slAdapter: var SlackAdapter;
                       sm: var SessionManager;
                       env: CommandEnv;
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
        let outcome =
          try:
            slackCommandOutcome(slAdapter, sm, msgSeq, env, command, userId,
                                event, messageId)
          except CatchableError as e:
            replied(rtUnsupported, "Erro ao processar comando: " & e.msg)
        case outcome.kind
        of cokFallback:
          handleSessionFallback(msg)
        of cokSilent:
          discard
        of cokReply:
          ## Slack answers unsupported commands instead of staying silent.
          if outcome.reply.text.len > 0:
            replyToEvent(slAdapter, event, userId, outcome.reply.text,
                         outcome.reply.sensitive).isOkOr:
              log.error("sl send " & $outcome.reply.topic & " failed for user=" &
                        $userId & " reason=" & error)
      else:
        handleSessionFallback(msg)

    except CatchableError as e:
      log.error("slack: event processing failed: " & e.msg)
    (hasEvent, event) = slAdapter.tryRecvEvent()
