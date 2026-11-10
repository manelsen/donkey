import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ./common_runtime
import whatsapp

proc drainWhatsAppEvents*(waAdapter: var WhatsAppAdapter;
                          whatsappPhoneNumberId: string;
                          sm: var SessionManager;
                          memory: MdFileAdapter;
                          completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                          modelCatalogLoader: ModelCatalogLoader;
                          toolsCount: int;
                          toolClientsCount: int;
                          daemonStartMs: int64;
                          msgSeq: var int;
                          handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                          log: Logger = newLogger("wa.outbound")) =
  if whatsappPhoneNumberId.len == 0 or waAdapter.accessToken.len == 0:
    return

  var (hasEvent, event) = waAdapter.tryRecvEvent()
  while hasEvent:
    let auth = authorizeInbound(sm, waAdapter.resolver, ckWhatsApp,
                                event.waUserId, event.text)
    if not auth.allowed:
      log.warn("whatsapp: unauthorized message from " &
               (if auth.identified: $auth.userId else: "unidentified sender"))
      (hasEvent, event) = waAdapter.tryRecvEvent()
      continue
    let userId = auth.userId

    if event.phoneNumberId.len > 0 and event.messageId.len > 0:
      waAdapter.ack(event.phoneNumberId, event.messageId)

    let msg = InboundMessage(
      userId: userId,
      channel: ckWhatsApp,
      channelId: event.messageId,
      messageId: event.messageId,
      text: event.text,
      mediaUrl: event.mediaId,
    )

    if event.kind in {wrkText, wrkInteractive} and event.text.strip.len > 0:
      let command = decideCommandRequest(CommandRequest(channel: ckWhatsApp, text: event.text))
      case command.route
      of crLocal:
        let reply =
          case decideLocalCommandAction(command)
          of lcaShowAbout:
            buildAboutText(memory, userId, toolsCount, toolClientsCount, sm.sessionCount())
          of lcaStartIntro:
            buildStartIntroText()
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
            buildLinkCodeText(waAdapter.resolver.generateLinkCode(userId))
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
            buildContinueResultText(waAdapter.resolver.consumeLinkCode(command.value, ckWhatsApp, event.waUserId))
          else:
            ""
        if reply.len > 0:
          waAdapter.send(OutboundMessage(userId: userId, channel: ckWhatsApp, text: reply)).isOkOr:
            log.error("wa send failed for user=" & $userId & " reason=" & error)
      of crSessionTask:
        if sm.hasLiveSession(userId):
          let entry = sm.getOrCreate(userId)
          inc msgSeq
          entry.inbox.addLastNoWait(
            newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckWhatsApp, event.messageId))
        else:
          let text =
            if command.kind == cmdDebug:
              "Nenhuma sessão ativa. Envie uma mensagem primeiro."
            else:
              "Nenhuma conversa ativa para reiniciar."
          waAdapter.send(OutboundMessage(userId: userId, channel: ckWhatsApp, text: text)).isOkOr:
            log.error("wa send sessionTask feedback failed for user=" & $userId & " reason=" & error)
      of crUi:
        let reply =
          case command.kind
          of cmdModels:
            memory.applyModelsTextCommand(userId, command.value, modelCatalogLoader).valueOr: error
          of cmdThink:
            memory.applyThinkTextCommand(userId, command.value).valueOr: error
          of cmdBudget:
            memory.applyBudgetTextCommand(userId, command.value).valueOr: error
          of cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts:
            buildDeferredUiCommandText(command.kind)
          else:
            ""
        if reply.len > 0:
          waAdapter.send(OutboundMessage(userId: userId, channel: ckWhatsApp, text: reply)).isOkOr:
            log.error("wa send crUi failed for user=" & $userId & " reason=" & error)
      of crPing:
        waAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckWhatsApp,
          text: buildPingText(memory, userId, completeBuilder),
        )).isOkOr:
          log.error("wa send crPing failed for user=" & $userId & " reason=" & error)
      of crStatus:
        waAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckWhatsApp,
          text: buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
        )).isOkOr:
          log.error("wa send crStatus failed for user=" & $userId & " reason=" & error)
      of crCallback, crNone:
        handleSessionFallback(msg)
    else:
      handleSessionFallback(msg)

    (hasEvent, event) = waAdapter.tryRecvEvent()
