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
import ./wechat

proc sendWeChatReply(wchAdapter: var WeChatAdapter;
                     userId: UserId;
                     text: string) =
  wchAdapter.send(OutboundMessage(
    userId: userId,
    channel: ckWeChat,
    text: text,
  )).isOkOr:
    discard

proc drainWeChatEvents*(wchAdapter: var WeChatAdapter;
                        wechatAppId: string;
                        sm: var SessionManager;
                        memory: MdFileAdapter;
                        completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                        modelCatalogLoader: ModelCatalogLoader;
                        toolsCount: int;
                        toolClientsCount: int;
                        daemonStartMs: int64;
                        msgSeq: var int;
                        handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if wechatAppId.len == 0:
    return

  var (hasEvent, event) = wchAdapter.tryRecvEvent()
  while hasEvent:
    if event.msgType == "text" and event.content.strip.len > 0:
      let userId = resolve(wchAdapter.resolver, ckWeChat, event.fromUser)
      let msg = InboundMessage(
        userId: userId,
        channel: ckWeChat,
        channelId: event.msgId,
        text: event.content,
      )
      let command = decideCommandRequest(CommandRequest(channel: ckWeChat, text: event.content))
      case command.route
      of crLocal:
        case decideLocalCommandAction(command)
        of lcaStartIntro:
          wchAdapter.sendWeChatReply(userId, buildStartIntroText())
        of lcaGenerateLinkCode:
          wchAdapter.sendWeChatReply(userId, buildLinkCodeText(wchAdapter.resolver.generateLinkCode(userId)))
        of lcaClearMemory:
          memory.clearMemory(userId)
          wchAdapter.sendWeChatReply(userId, "Memórias apagadas.")
        of lcaDoctorReport:
          wchAdapter.sendWeChatReply(
            userId,
            buildDoctorReport(memory, completeBuilder, userId, toolsCount, toolClientsCount, sm.sessionCount()))
        of lcaHelpText:
          wchAdapter.sendWeChatReply(userId, buildHelpText(false))
        of lcaShowMemory:
          wchAdapter.sendWeChatReply(userId, buildMemoryViewText(memory, userId))
        of lcaContinueLink:
          let linked = wchAdapter.resolver.consumeLinkCode(command.value, ckWeChat, event.fromUser)
          wchAdapter.sendWeChatReply(userId, buildContinueResultText(linked))
        else:
          discard
      of crSessionTask:
        if sm.hasSession(userId):
          let entry = sm.getOrCreate(userId)
          inc msgSeq
          entry.inbox.addLastNoWait(
            newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckWeChat, event.msgId))
        else:
          let text =
            if command.kind == cmdDebug:
              "Nenhuma sessão ativa. Envie uma mensagem primeiro."
            else:
              "Nenhuma conversa ativa para reiniciar."
          wchAdapter.sendWeChatReply(userId, text)
      of crUi:
        let reply =
          case command.kind
          of cmdModels:
            memory.applyModelsTextCommand(userId, command.value, modelCatalogLoader).valueOr: error
          of cmdThink:
            memory.applyThinkTextCommand(userId, command.value).valueOr: error
          of cmdBudget:
            memory.applyBudgetTextCommand(userId, command.value).valueOr: error
          else:
            ""
        if reply.len > 0:
          wchAdapter.sendWeChatReply(userId, reply)
      of crPing:
        wchAdapter.sendWeChatReply(userId, buildPingText(memory, userId, completeBuilder))
      of crStatus:
        wchAdapter.sendWeChatReply(
          userId, buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs))
      of crCallback, crNone:
        handleSessionFallback(msg)
    (hasEvent, event) = wchAdapter.tryRecvEvent()
