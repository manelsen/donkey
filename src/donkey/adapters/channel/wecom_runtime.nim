import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log as core_log
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ../identity/identity_resolver
import ./common_runtime
import ./wecom

# ── Markdown builders for WeCom rich replies ──────────────────────────────────
#
# WeCom markdown subset: ## heading, **bold**,
# <font color="info|comment|warning">text</font>, [link](url), > quote, - list.

func buildWeComHelpMd*(): string =
  let pages = buildHelpPages()
  result = "## 📖 Donkey — Ajuda\n"
  for (title, body) in pages:
    result.add("\n**" & title & "**\n")
    for line in body.splitLines():
      result.add(line & "\n")

func buildWeComStatusMd*(statusText: string): string =
  ## Wraps the plain-text status in a WeCom markdown card.
  "## 📊 Status\n" & statusText

func buildWeComDoctorMd*(reportText: string): string =
  "## 🩺 Doctor\n" & reportText

func buildWeComPingMd*(pingText: string): string =
  let color = if "error" in pingText: "warning" else: "info"
  "## 🏓 Ping\n<font color=\"" & color & "\">" & pingText & "</font>"

func buildWeComMycodeM*(codeText: string): string =
  "## 🔗 Link Code\n" & codeText

func buildWeComMemoryMd*(memText: string): string =
  "## 🧠 Memórias\n" & memText

# ── Reply helpers ─────────────────────────────────────────────────────────────

proc wcReply(wcAdapter: var WeComAdapter; userId: UserId; text: string; logger: Logger) =
  wcAdapter.send(OutboundMessage(userId: userId, channel: ckWeCom, text: text)).isOkOr:
    logger.error("wc send failed for user=" & $userId & " reason=" & error)

proc wcMd(wcAdapter: var WeComAdapter; userId: UserId; md: string; logger: Logger) =
  wcAdapter.sendMarkdown(userId, md).isOkOr:
    logger.warn("wc sendMarkdown failed for user=" & $userId & " reason=" & error & " — falling back to text")
    ## Fallback to plain text if markdown fails
    wcAdapter.send(OutboundMessage(userId: userId, channel: ckWeCom, text: md)).isOkOr:
      logger.error("wc send text fallback failed for user=" & $userId & " reason=" & error)

# ── Main drain ────────────────────────────────────────────────────────────────

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
                       logger: Logger;
                       handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if wecomCorpId.len == 0:
    return

  var (hasEvent, event) = wcAdapter.tryRecvEvent()
  while hasEvent:
    if event.msgType == "text" and (event.content |> strip).len > 0:
      let auth = authorizeInbound(sm, wcAdapter.resolver, ckWeCom,
                                  event.fromUser, event.content)
      if not auth.allowed:
        logger.warn("wecom: unauthorized message from " &
                    (if auth.identified: $auth.userId else: "unidentified sender"))
        (hasEvent, event) = wcAdapter.tryRecvEvent()
        continue
      let userId = auth.userId
      let inbound = InboundMessage(
        userId:    userId,
        channel:   ckWeCom,
        channelId: event.msgId,
        text:      event.content,
      )
      let command = decideCommandRequest(CommandRequest(channel: ckWeCom, text: event.content))
      case command.route
      of crLocal:
        case decideLocalCommandAction(command)
        of lcaShowAbout:
          wcMd(wcAdapter, userId, buildWeComDoctorMd(
            buildAboutText(memory, userId, toolsCount, toolClientsCount, sm.sessionCount())), logger)
        of lcaStartIntro:
          wcReply(wcAdapter, userId, buildStartIntroText(), logger)
        of lcaSkillCommand:
          let reply = applySkillTextCommand(
            memory,
            userId,
            command.value,
            homeDir = memory.donkeyHomeDir(),
          ).valueOr:
            error
          wcReply(
            wcAdapter,
            userId,
            reply,
            logger,
          )
        of lcaGenerateLinkCode:
          wcMd(wcAdapter, userId, buildWeComMycodeM(
            buildLinkCodeText(wcAdapter.resolver.generateLinkCode(userId))), logger)
        of lcaClearMemory:
          memory.clearMemory(userId)
          wcReply(wcAdapter, userId, "Memórias apagadas.", logger)
        of lcaDoctorReport:
          wcMd(wcAdapter, userId, buildWeComDoctorMd(
            buildDoctorReport(memory, completeBuilder, userId, toolsCount, toolClientsCount, sm.sessionCount())), logger)
        of lcaHelpText:
          wcMd(wcAdapter, userId, buildWeComHelpMd(), logger)
        of lcaShowMemory:
          wcMd(wcAdapter, userId, buildWeComMemoryMd(
            buildMemoryViewText(memory, userId)), logger)
        of lcaContinueLink:
          let linked = wcAdapter.resolver.consumeLinkCode(command.value, ckWeCom, event.fromUser)
          wcReply(wcAdapter, userId, buildContinueResultText(linked), logger)
        else:
          discard
      of crSessionTask:
        if sm.hasLiveSession(userId):
          let entry = sm.getOrCreate(userId)
          inc msgSeq
          entry.inbox.addLastNoWait(
            newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckWeCom, event.msgId))
        else:
          let errText =
            if command.kind == cmdDebug: "Nenhuma sessão ativa. Envie uma mensagem primeiro."
            else: "Nenhuma conversa ativa para reiniciar."
          wcReply(wcAdapter, userId, errText, logger)
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
          else: ""
        if reply.len > 0:
          wcReply(wcAdapter, userId, reply, logger)
      of crPing:
        wcMd(wcAdapter, userId, buildWeComPingMd(buildPingText(memory, userId, completeBuilder)), logger)
      of crStatus:
        wcMd(wcAdapter, userId, buildWeComStatusMd(
          buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs)), logger)
      of crCallback, crNone:
        handleSessionFallback(inbound)
    (hasEvent, event) = wcAdapter.tryRecvEvent()
