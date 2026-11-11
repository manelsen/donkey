## Slack inbound runtime — drains webhook events and dispatches commands.
##
## Events are enqueued by the Slack webhook receiver and consumed here from the
## daemon loop. Messages, slash commands and block actions share the same DM
## gate and command/session routing as the other webhook channels.

import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ../identity/identity_resolver
import ../../app/inbound_gate
import ../../domain/channels/slack_pure
import ./common_runtime
import ./slack

proc drainSlackEvents*(slAdapter: var SlackAdapter;
                       slackSigningSecret: string;
                       sm: var SessionManager;
                       memory: MdFileAdapter;
                       completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                       modelCatalogLoader: ModelCatalogLoader;
                       toolsCount: int;
                       toolClientsCount: int;
                       daemonStartMs: int64;
                       msgSeq: var int;
                       handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                       log: Logger = newLogger("sl.outbound")) =
  ## Drains Slack webhook events while the receiver route is enabled.
  if slackSigningSecret.len == 0:
    return

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
        case command.route
        of crLocal:
          let reply =
            case decideLocalCommandAction(command)
            of lcaShowAbout:
              buildAboutText(memory, userId, toolsCount, toolClientsCount, sm.sessionCount())
            of lcaStartIntro:
              buildStartIntroText()
            of lcaShowMenu:
              buildMenuText()
            of lcaShowWhoami:
              buildWhoamiText(userId, "", event.channelId)
            of lcaSkillCommand:
              let reply = applySkillTextCommand(
                memory,
                userId,
                command.value,
                homeDir = memory.donkeyHomeDir(),
              ).valueOr:
                error
              reply
            of lcaGenerateLinkCode:
              buildLinkCodeText(slAdapter.resolver.generateLinkCode(userId))
            of lcaClearMemory:
              memory.clearMemory(userId)
              "Memórias apagadas."
            of lcaDoctorReport:
              buildDoctorReport(memory, completeBuilder, userId, toolsCount, toolClientsCount, sm.sessionCount())
            of lcaHelpText:
              buildHelpText(false)
            of lcaShowMemory:
              buildMemoryViewText(memory, userId)
            of lcaContinueLink:
              buildContinueResultText(slAdapter.resolver.consumeLinkCode(
                command.value, ckSlack, event.slackUserId))
            of lcaReasoningToggle:
              let prefs = loadChannelPrefs(memory, userId)
              let next = if prefs.reasoning == "on": "off" else: "on"
              saveChannelPreference(memory, userId, "reasoning", next)
              "Reasoning: " & next
            else:
              "Comando indisponível neste canal. Use /help."
          if reply.len > 0:
            slAdapter.send(OutboundMessage(userId: userId, channel: ckSlack, text: reply)).isOkOr:
              log.error("sl send failed for user=" & $userId & " reason=" & error)
        of crSessionTask:
          if sm.hasLiveSession(userId):
            let entry = sm.getOrCreate(userId)
            inc msgSeq
            entry.inbox.addLastNoWait(
              newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckSlack, messageId))
          else:
            let text =
              if command.kind == cmdDebug:
                "Nenhuma sessão ativa. Envie uma mensagem primeiro."
              else:
                "Nenhuma conversa ativa para reiniciar."
            slAdapter.send(OutboundMessage(userId: userId, channel: ckSlack, text: text)).isOkOr:
              log.error("sl send sessionTask feedback failed for user=" & $userId & " reason=" & error)
        of crUi:
          let reply =
            case command.kind
            of cmdModels:
              memory.applyModelsTextCommand(userId, command.value, modelCatalogLoader).valueOr: error
            of cmdThink:
              memory.applyThinkTextCommand(userId, command.value).valueOr: error
            of cmdBudget:
              memory.applyBudgetTextCommand(userId, command.value).valueOr: error
            of cmdConfig:
              memory.buildConfigText(userId)
            of cmdTasks:
              buildTasksText()
            of cmdAgents:
              buildAgentsText(toolsCount, toolClientsCount)
            of cmdPoll:
              buildPollText()
            of cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts:
              buildDeferredUiCommandText(command.kind)
            else:
              "Comando indisponível neste canal. Use /help."
          if reply.len > 0:
            slAdapter.send(OutboundMessage(userId: userId, channel: ckSlack, text: reply)).isOkOr:
              log.error("sl send crUi failed for user=" & $userId & " reason=" & error)
        of crPing:
          slAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckSlack,
            text: buildPingText(memory, userId, completeBuilder),
          )).isOkOr:
            log.error("sl send crPing failed for user=" & $userId & " reason=" & error)
        of crStatus:
          slAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckSlack,
            text: buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
          )).isOkOr:
            log.error("sl send crStatus failed for user=" & $userId & " reason=" & error)
        of crCallback, crNone:
          handleSessionFallback(msg)
      else:
        handleSessionFallback(msg)

    except CatchableError as e:
      log.error("slack: event processing failed: " & e.msg)
    (hasEvent, event) = slAdapter.tryRecvEvent()
