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
import ./feishu

proc drainFeishuEvents*(fsAdapter: var FeishuAdapter;
                        feishuAppId: string;
                        sm: var SessionManager;
                        memory: MdFileAdapter;
                        completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                        modelCatalogLoader: ModelCatalogLoader;
                        toolsCount: int;
                        toolClientsCount: int;
                        daemonStartMs: int64;
                        msgSeq: var int;
                        handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if feishuAppId.len == 0:
    return

  var (hasEvent, event) = fsAdapter.tryRecvEvent()
  while hasEvent:
    if event.msgType == "text" and (event.content |> strip).len > 0:
      let userId = fsAdapter.resolver.resolve(ckFeishu, event.openId)
      let msg = InboundMessage(
        userId:    userId,
        channel:   ckFeishu,
        channelId: event.msgId,
        text:      event.content,
      )
      let command = decideCommandRequest(CommandRequest(channel: ckFeishu, text: event.content))
      case command.route
      of crLocal:
        let reply =
          case decideLocalCommandAction(command)
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
            buildLinkCodeText(fsAdapter.resolver.generateLinkCode(userId))
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
            buildContinueResultText(fsAdapter.resolver.consumeLinkCode(command.value, ckFeishu, event.openId))
          else:
            ""
        if reply.len > 0:
          fsAdapter.send(OutboundMessage(userId: userId, channel: ckFeishu, text: reply)).isOkOr: discard
      of crSessionTask:
        if sm.hasSession(userId):
          let entry = sm.getOrCreate(userId)
          inc msgSeq
          entry.inbox.addLastNoWait(
            newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckFeishu, event.msgId))
        else:
          let text =
            if command.kind == cmdDebug:
              "Nenhuma sessão ativa. Envie uma mensagem primeiro."
            else:
              "Nenhuma conversa ativa para reiniciar."
          fsAdapter.send(OutboundMessage(userId: userId, channel: ckFeishu, text: text)).isOkOr: discard
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
          fsAdapter.send(OutboundMessage(userId: userId, channel: ckFeishu, text: reply)).isOkOr: discard
      of crPing:
        fsAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckFeishu,
          text: buildPingText(memory, userId, completeBuilder),
        )).isOkOr: discard
      of crStatus:
        fsAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckFeishu,
          text: buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
        )).isOkOr: discard
      of crCallback, crNone:
        handleSessionFallback(msg)
    (hasEvent, event) = fsAdapter.tryRecvEvent()
