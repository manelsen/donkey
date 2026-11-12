import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ../identity/identity_resolver
import ../../app/inbound_gate
import ../../app/approval_runtime
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
                        handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                        log: Logger = newLogger("fs.outbound")) =
  if feishuAppId.len == 0:
    return

  var (hasEvent, event) = fsAdapter.tryRecvEvent()
  while hasEvent:
    if (event.msgType == "text" and (event.content |> strip).len > 0) or
       event.fileKey.len > 0:
      ## Only a text event runs the command dispatcher; a media-only event
      ## must not mint an identity just because its caption contains
      ## `/continue <code>` (the code would never be consumed).
      let gateText = if event.msgType == "text": event.content else: ""
      let auth = authorizeInbound(sm, fsAdapter.resolver.identityGate(), ckFeishu,
                                  event.openId, gateText)
      if not auth.allowed:
        log.warn("feishu: unauthorized message from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        (hasEvent, event) = fsAdapter.tryRecvEvent()
        continue
      let userId = auth.userId
      let approvalReply = tryHandleApprovalInput(userId, event.content)
      if approvalReply.isSome:
        fsAdapter.send(OutboundMessage(
          userId: userId, channel: ckFeishu, text: approvalReply.get)).isOkOr:
          log.error("fs send approval reply failed: " & error)
        (hasEvent, event) = fsAdapter.tryRecvEvent()
        continue
      let msg = InboundMessage(
        userId:    userId,
        channel:   ckFeishu,
        channelId: event.msgId,
        text:      event.content,
        mediaUrl:  event.fileKey,
      )
      if event.msgType == "text" and (event.content |> strip).len > 0:
        let command = decideCommandRequest(CommandRequest(channel: ckFeishu, text: event.content))
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
            fsAdapter.send(OutboundMessage(userId: userId, channel: ckFeishu, text: reply)).isOkOr:
              log.error("fs send failed for user=" & $userId & " reason=" & error)
        of crSessionTask:
          if sm.hasLiveSession(userId):
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
            fsAdapter.send(OutboundMessage(userId: userId, channel: ckFeishu, text: text)).isOkOr:
              log.error("fs send sessionTask feedback failed for user=" & $userId & " reason=" & error)
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
            fsAdapter.send(OutboundMessage(userId: userId, channel: ckFeishu, text: reply)).isOkOr:
              log.error("fs send crUi failed for user=" & $userId & " reason=" & error)
        of crPing:
          fsAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckFeishu,
            text: buildPingText(memory, userId, completeBuilder),
          )).isOkOr:
            log.error("fs send crPing failed for user=" & $userId & " reason=" & error)
        of crStatus:
          fsAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckFeishu,
            text: buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
          )).isOkOr:
            log.error("fs send crStatus failed for user=" & $userId & " reason=" & error)
        of crCallback, crNone:
          handleSessionFallback(msg)
      else:
        handleSessionFallback(msg)
    (hasEvent, event) = fsAdapter.tryRecvEvent()
