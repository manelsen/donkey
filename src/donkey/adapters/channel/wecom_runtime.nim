import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ../identity/identity_resolver
import ./common_runtime
import ./wecom

proc drainWeComEvents*(wcAdapter: var WeComAdapter;
                       wecomCorpId: string;
                       sm: var SessionManager;
                       memory: MdFileAdapter;
                       completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                       modelCatalogLoader: ModelCatalogLoader;
                       toolsCount: int;
                       toolClientsCount: int;
                       daemonStartMs: int64;
                       msgSeq: var int;
                       handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if wecomCorpId.len == 0:
    return

  var (hasEvent, event) = wcAdapter.tryRecvEvent()
  while hasEvent:
    if event.msgType == "text" and (event.content |> strip).len > 0:
      let userId = wcAdapter.resolver.resolve(ckWeCom, event.fromUser)
      let msg = InboundMessage(
        userId:    userId,
        channel:   ckWeCom,
        channelId: event.msgId,
        text:      event.content,
      )
      let command = decideCommandRequest(CommandRequest(channel: ckWeCom, text: event.content))
      case command.route
      of crLocal:
        let reply =
          case decideLocalCommandAction(command)
          of lcaStartIntro:
            buildStartIntroText()
          of lcaGenerateLinkCode:
            buildLinkCodeText(wcAdapter.resolver.generateLinkCode(userId))
          of lcaClearMemory:
            memory.clearMemory(userId)
            "Memórias apagadas."
          of lcaDoctorReport:
            buildDoctorReport(memory, completeBuilder, userId, toolsCount, toolClientsCount, sm.sessionCount())
          of lcaHelpText:
            buildHelpText(false)
          of lcaShowMemory:
            let memText = memory.loadContext(userId).memoryMd.strip
            if memText.len > 0: memText else: "Nenhuma memória salva ainda."
          of lcaContinueLink:
            buildContinueResultText(wcAdapter.resolver.consumeLinkCode(command.value, ckWeCom, event.fromUser))
          else:
            ""
        if reply.len > 0:
          wcAdapter.send(OutboundMessage(userId: userId, channel: ckWeCom, text: reply)).isOkOr: discard
      of crSessionTask:
        if sm.hasSession(userId):
          let entry = sm.getOrCreate(userId)
          inc msgSeq
          entry.inbox.addLastNoWait(
            newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckWeCom, event.msgId))
        else:
          let text =
            if command.kind == cmdDebug:
              "Nenhuma sessão ativa. Envie uma mensagem primeiro."
            else:
              "Nenhuma conversa ativa para reiniciar."
          wcAdapter.send(OutboundMessage(userId: userId, channel: ckWeCom, text: text)).isOkOr: discard
      of crUi:
        let reply =
          case command.kind
          of cmdModels:
            memory.applyModelsTextCommand(userId, command.value, modelCatalogLoader).valueOr: error
          of cmdThink:
            memory.applyThinkTextCommand(userId, command.value).valueOr: error
          else:
            ""
        if reply.len > 0:
          wcAdapter.send(OutboundMessage(userId: userId, channel: ckWeCom, text: reply)).isOkOr: discard
      of crPing:
        wcAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckWeCom,
          text: buildPingText(memory, userId, completeBuilder),
        )).isOkOr: discard
      of crStatus:
        wcAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckWeCom,
          text: buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
        )).isOkOr: discard
      of crCallback, crNone:
        handleSessionFallback(msg)
    (hasEvent, event) = wcAdapter.tryRecvEvent()
