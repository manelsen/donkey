import std/[strutils, tables]
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log as core_log
import ../../core/outbound/outbound
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ../identity/identity_resolver
import ./common_runtime
import ./discord

proc sendDiscordReply(event: DiscordRawEvent;
                      dcAdapter: DiscordAdapter;
                      userId: UserId;
                      text: string;
                      logger: Logger) =
  if event.interactionId.len > 0:
    dcAdapter.sendInteractionResponse(
      event.interactionId, event.interactionToken, text).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc interaction resp: " & error)
    return
  dcAdapter.send(OutboundMessage(
    userId: userId,
    channel: ckDiscord,
    text: text,
    replyTo: if event.channelId.len > 0: "channel:" & event.channelId else: "",
  )).isOkOr:
    core_log.log(logger, core_log.lvlError, "dc send reply: " & error)

proc sendDiscordEmbed(event: DiscordRawEvent;
                      dcAdapter: DiscordAdapter;
                      userId: UserId;
                      title, description: string;
                      color: int;
                      logger: Logger) =
  ## Sends a Discord embed when the event has an interactionId, otherwise plain text.
  if event.interactionId.len > 0:
    dcAdapter.sendInteractionEmbedPage(
      event.interactionId, event.interactionToken,
      title, description, color, @[]).isOkOr:
        core_log.log(logger, core_log.lvlWarn, "dc embed fallback: " & error)
        sendDiscordReply(event, dcAdapter, userId, description, logger)
  else:
    sendDiscordReply(event, dcAdapter, userId, description, logger)

proc sendDiscordKeyboard(dcAdapter: DiscordAdapter;
                         event: DiscordRawEvent;
                         presentationState: var PresentationState;
                         userId: UserId;
                         slot: string;
                         title: string;
                         buttons: seq[seq[(string, string)]];
                         ackText: string;
                         logger: Logger) =
  if event.interactionId.len > 0:
    let r = dcAdapter.sendInteractionKeyboard(
      event.interactionId, event.interactionToken, title, buttons)
    if r.isOk:
      common_runtime.setUiMsgId(presentationState, ckDiscord, userId, slot, "interaction")
      return
    ## Interaction expired or already used — fall back to a regular DM keyboard
    core_log.log(logger, core_log.lvlWarn,
      "dc interaction keyboard fallback (expired?): " & r.error)

  let msgId = dcAdapter.sendKeyboard(userId, title, buttons).valueOr:
    core_log.log(logger, core_log.lvlError, "dc send keyboard: " & error)
    return
  common_runtime.setUiMsgId(presentationState, ckDiscord, userId, slot, msgId)

proc smartEditKeyboard(dcAdapter: DiscordAdapter;
                       event: DiscordRawEvent;
                       userId: UserId;
                       msgId: string;
                       text: string;
                       buttons: seq[seq[(string, string)]]): Result[void, string] =
  if msgId == "interaction" and event.interactionToken.len > 0:
    dcAdapter.editInteractionKeyboard(event.interactionToken, text, buttons)
  else:
    dcAdapter.editKeyboard(userId, msgId, text, buttons)

proc handleDiscordUiCommand(event: DiscordRawEvent;
                            dcAdapter: DiscordAdapter;
                            presentationState: var PresentationState;
                            memory: MdFileAdapter;
                            userId: UserId;
                            command: CommandDecision;
                            modelCatalogLoader: ModelCatalogLoader;
                            toolsCount: int;
                            toolClientsCount: int;
                            daemonStartMs: int64;
                            msgSeq: var int;
                            logger: Logger): bool =
  case command.kind
  of cmdConfig:
    let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotConfig)
    if kbdId.len > 0 and event.interactionId.len == 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId, memory.buildConfigText(userId), buildConfigButtons()).isOkOr:
          core_log.log(logger, core_log.lvlWarn, "dc config keyboard: " & error)
    else:
      sendDiscordKeyboard(
        dcAdapter, event, presentationState, userId, UiSlotConfig,
        memory.buildConfigText(userId), buildConfigButtons(),
        "Abri a configuração na sua DM.", logger,
      )
    true
  of cmdTasks:
    sendDiscordEmbed(event, dcAdapter, userId,
      "🕒 Tarefas", buildTasksText(), 0x95A5A6, logger)
    true
  of cmdAgents:
    sendDiscordEmbed(event, dcAdapter, userId,
      "🤖 Agentes", buildAgentsText(toolsCount, toolClientsCount), 0x95A5A6, logger)
    true
  of cmdPoll:
    sendDiscordEmbed(event, dcAdapter, userId,
      "🗳️ Polls", buildPollText(), 0x95A5A6, logger)
    true
  of cmdModels:
    let providerOnly =
      if command.value.strip.len > 0: parseModelsProviderArg(command.value).valueOr: ""
      else: ""
    if providerOnly.len > 0:
      let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
      let (currProv, currModel) = memory.getCurrentProviderModel(userId)
      let catalog = modelCatalogLoader(providerOnly).valueOr: emptyCatalogResult()
      let entries = sortModelCatalog(normalizeModelCatalog(providerOnly, catalog.entries))
      let title = buildModelPageText(providerOnly, 0, entries, catalog)
      let buttons = buildModelPageButtons(providerOnly, entries, currProv, currModel, 0)
      if kbdId.len > 0 and event.interactionId.len == 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, title, buttons).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc provider direct menu: " & error)
      else:
        sendDiscordKeyboard(
          dcAdapter, event, presentationState, userId, UiSlotModels, title, buttons,
          "Abri o catálogo de " & providerOnly & " na sua DM.", logger,
        )
    elif command.value.strip.len > 0:
      let reply = memory.applyModelsTextCommand(userId, command.value, modelCatalogLoader).valueOr: error
      sendDiscordReply(event, dcAdapter, userId, reply, logger)
    else:
      let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
      if kbdId.len > 0 and event.interactionId.len == 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, "Escolha o provider:", memory.buildProviderButtons(userId)).isOkOr:
            core_log.log(logger, core_log.lvlError, "dc provider reopen: " & error)
      else:
        sendDiscordKeyboard(
          dcAdapter, event, presentationState, userId, UiSlotModels,
          "Escolha o provider:",
          memory.buildProviderButtons(userId),
          "Abri o seletor de modelo na sua DM.",
          logger,
        )
    true
  of cmdThink:
    if command.value.strip.len > 0:
      let reply = memory.applyThinkTextCommand(userId, command.value).valueOr: error
      sendDiscordReply(event, dcAdapter, userId, reply, logger)
    else:
      let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotThink)
      if kbdId.len > 0 and event.interactionId.len == 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, "Nível de raciocínio:", memory.buildThinkButtons(userId)).isOkOr:
            core_log.log(logger, core_log.lvlError, "dc think reopen: " & error)
      else:
        sendDiscordKeyboard(
          dcAdapter, event, presentationState, userId, UiSlotThink,
          "Nível de raciocínio:",
          memory.buildThinkButtons(userId),
          "Abri o seletor de thinking na sua DM.",
          logger,
        )
    true
  of cmdBudget:
    let reply = memory.applyBudgetTextCommand(userId, command.value).valueOr: error
    sendDiscordReply(event, dcAdapter, userId, reply, logger)
    true
  of cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts:
    sendDiscordReply(event, dcAdapter, userId, buildDeferredUiCommandText(command.kind), logger)
    true
  else:
    false

proc handleDiscordUiCallback(event: DiscordRawEvent;
                             dcAdapter: DiscordAdapter;
                             presentationState: var PresentationState;
                             memory: MdFileAdapter;
                             userId: UserId;
                             callback: CallbackDecision;
                             modelCatalogLoader: ModelCatalogLoader;
                             toolsCount: int;
                             toolClientsCount: int;
                             daemonStartMs: int64;
                             msgSeq: var int;
                             logger: Logger): bool =
  logger.info("dc callback " & $callback.kind & " from " & $userId)
  case callback.kind
  of cbkModelsProvider:
    let (currProv, currModel) = memory.getCurrentProviderModel(userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId,
        buildModelPageText(callback.provider, 0, entries, catalog),
        buildModelPageButtons(callback.provider, entries, currProv, currModel, 0)).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc model menu: " & error)
    true
  of cbkModelsSet:
    memory.saveChannelPreference(userId, "provider", callback.provider)
    memory.saveChannelPreference(userId, "model", callback.model)
    let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(event, userId, kbdId,
        "Modelo definido: " & callback.provider & " / " & callback.model,
        @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc model confirm: " & error)
      common_runtime.clearUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
    else:
      dcAdapter.send(OutboundMessage(
        userId: userId,
        channel: ckDiscord,
        text: "Modelo definido: " & callback.provider & " / " & callback.model,
      )).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc model confirm: " & error)
    true
  of cbkModelsPage:
    let (currProv, currModel) = memory.getCurrentProviderModel(userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId,
        buildModelPageText(callback.provider, callback.page, entries, catalog),
        buildModelPageButtons(callback.provider, entries, currProv, currModel, callback.page)).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc model page: " & error)
    true
  of cbkModelsBack:
    let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId, "Escolha o provider:", memory.buildProviderButtons(userId)).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc provider menu: " & error)
    true
  of cbkHelpPage:
    const HelpColor = 0x5865F2
    let pages = buildHelpPages()
    let page  = min(max(callback.page, 0), pages.len - 1)
    let (pTitle, pBody) = pages[page]
    let title   = "📖 Ajuda — " & pTitle & " (" & $(page + 1) & "/" & $pages.len & ")"
    let buttons = buildHelpNavButtons(page, pages.len)
    dcAdapter.editInteractionEmbedPage(
      event.interactionToken, title, pBody, HelpColor, buttons).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc help page: " & error)
    true
  of cbkThinkSet:
    let level = callback.value
    if level in ThinkLevels:
      memory.saveChannelPreference(userId, "thinking", level)
      let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotThink)
      if kbdId.len > 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, "Thinking definido: " & level, @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc think confirm: " & error)
        common_runtime.clearUiMsgId(presentationState, ckDiscord, userId, UiSlotThink)
      else:
        dcAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckDiscord,
          text: "Thinking definido: " & level,
        )).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc think confirm: " & error)
    true
  of cbkReasoning:
    let prefs = common_runtime.loadChannelPrefs(memory, userId)
    let next = if prefs.reasoning == "on": "off" else: "on"
    common_runtime.saveChannelPreference(memory, userId, "reasoning", next)
    dcAdapter.send(OutboundMessage(
      userId: userId,
      channel: ckDiscord,
      text: "🧠 Reasoning " & (if next == "on": "ativado." else: "desativado."),
    )).isOkOr:
      core_log.log(logger, core_log.lvlError, "dc reasoning toggle: " & error)
    true
  else:
    false

proc handleDiscordEvent*(sm: var SessionManager;
                         event: DiscordRawEvent;
                         dcAdapter: DiscordAdapter;
                         presentationState: var PresentationState;
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                         modelCatalogLoader: ModelCatalogLoader;
                         toolsCount: int;
                         toolClientsCount: int;
                         daemonStartMs: int64;
                         msgSeq: var int;
                         logger: Logger;
                         handleInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                         completeInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  case event.kind
  of deMessage:
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    let inbound = InboundMessage(
      userId:    userId,
      channel:   ckDiscord,
      channelId: event.channelId,
      messageId: event.messageId,
      text:      event.content,
    )
    handleInboundStatus(inbound)
    ## Save last processed message_id for offline recovery
    if event.messageId.len > 0:
      memory.saveChannelPreference(userId, "discord_last_msg_id", event.messageId)
    let command = decideCommandRequest(CommandRequest(channel: ckDiscord, text: event.content))
    case command.route
    of crLocal:
      case decideLocalCommandAction(command)
      of lcaShowAbout:
        sendDiscordEmbed(event, dcAdapter, userId,
          "🫏 Donkey",
          buildAboutText(memory, userId, toolsCount, toolClientsCount, sm.sessionCount()),
          0x5865F2, logger)
      of lcaStartIntro:
        sendDiscordEmbed(event, dcAdapter, userId,
          "👋 Donkey", buildStartIntroText(), 0x5865F2, logger)
      of lcaSkillCommand:
        let reply = applySkillTextCommand(
          memory,
          userId,
          command.value,
          homeDir = memory.donkeyHomeDir(),
        ).valueOr:
          error
        sendDiscordReply(
          event,
          dcAdapter,
          userId,
          reply,
          logger,
        )
      of lcaShowMenu:
        let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotMenu)
        if kbdId.len > 0 and event.interactionId.len == 0:
          dcAdapter.smartEditKeyboard(
            event, userId, kbdId, buildMenuText(), buildMenuButtons()).isOkOr:
              core_log.log(logger, core_log.lvlWarn, "dc menu keyboard: " & error)
        else:
          sendDiscordKeyboard(
            dcAdapter, event, presentationState, userId, UiSlotMenu,
            buildMenuText(), buildMenuButtons(),
            "Abri o menu na sua DM.", logger,
          )
      of lcaShowWhoami:
        let sessId = if sm.hasSession(userId): "active" else: ""
        sendDiscordEmbed(event, dcAdapter, userId,
          "🆔 Identity", buildWhoamiText(userId, sessId, event.discordUserId), 0x5865F2, logger)
      of lcaGenerateLinkCode:
        sendDiscordEmbed(event, dcAdapter, userId,
          "🔗 Link Code", buildLinkCodeText(dcAdapter.resolver.generateLinkCode(userId)), 0x5865F2, logger)
      of lcaClearMemory:
        memory.clearMemory(userId)
        sendDiscordEmbed(event, dcAdapter, userId,
          "🗑️ Memórias", "Memórias apagadas.", 0xE67E22, logger)
      of lcaDoctorReport:
        sendDiscordEmbed(event, dcAdapter, userId,
          "🩺 Doctor",
          buildDoctorReport(memory, completeBuilder, userId, toolsCount, toolClientsCount, sm.sessionCount()),
          0x95A5A6, logger)
      of lcaHelpText:
        let pages = buildHelpPages()
        if event.interactionId.len > 0 and pages.len > 0:
          let (pTitle, pBody) = pages[0]
          dcAdapter.sendInteractionEmbedPage(
            event.interactionId, event.interactionToken,
            "📖 Ajuda — " & pTitle & " (1/" & $pages.len & ")",
            pBody, 0x5865F2, buildHelpNavButtons(0, pages.len)).isOkOr:
              core_log.log(logger, core_log.lvlWarn, "dc help embed: " & error)
              sendDiscordReply(event, dcAdapter, userId, buildHelpText(true), logger)
        else:
          sendDiscordReply(event, dcAdapter, userId, buildHelpText(true), logger)
      of lcaShowMemory:
        sendDiscordEmbed(event, dcAdapter, userId,
          "🧠 Memórias",
          buildMemoryViewText(memory, userId),
          0x9B59B6, logger)
      of lcaContinueLink:
        let linked = dcAdapter.resolver.consumeLinkCode(command.value, ckDiscord, event.discordUserId)
        sendDiscordEmbed(event, dcAdapter, userId,
          "🔗 Continue", buildContinueResultText(linked),
          if linked: 0x57F287 else: 0xED4245, logger)
      of lcaReasoningToggle:
        let prefs = common_runtime.loadChannelPrefs(memory, userId)
        let next = if prefs.reasoning == "on": "off" else: "on"
        common_runtime.saveChannelPreference(memory, userId, "reasoning", next)
        sendDiscordEmbed(event, dcAdapter, userId,
          "🧠 Reasoning",
          if next == "on": "Reasoning ativado." else: "Reasoning desativado.",
          0x57F287, logger)
      else:
        discard
      completeInboundStatus(inbound)
    of crSessionTask:
      if sm.hasSession(userId):
        let entry = sm.getOrCreate(userId)
        inc msgSeq
        entry.inbox.addLastNoWait(
          newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckDiscord, ""))
        completeInboundStatus(inbound)
      else:
        let errText =
          if command.kind == cmdDebug: "Nenhuma sessão ativa. Envie uma mensagem primeiro."
          else: "Nenhuma conversa ativa para reiniciar."
        sendDiscordEmbed(event, dcAdapter, userId, "ℹ️ Info", errText, 0xED4245, logger)
        completeInboundStatus(inbound)
    of crUi:
      discard handleDiscordUiCommand(event, dcAdapter, presentationState, memory, userId, command, modelCatalogLoader, toolsCount, toolClientsCount, daemonStartMs, msgSeq, logger)
      completeInboundStatus(inbound)
    of crPing:
      let pingText = buildPingText(memory, userId, completeBuilder)
      let pingColor = if "error" in pingText: 0xED4245 else: 0x57F287
      sendDiscordEmbed(event, dcAdapter, userId, "🏓 Ping", pingText, pingColor, logger)
      completeInboundStatus(inbound)
    of crStatus:
      sendDiscordEmbed(event, dcAdapter, userId,
        "📊 Status",
        buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
        0x57F287, logger)
      completeInboundStatus(inbound)
    of crCallback, crNone:
      handleSessionFallback(inbound)

  of deInteraction:
    let code = event.content |> strip
    let linked = dcAdapter.resolver.consumeLinkCode(
      code, ckDiscord, event.discordUserId)
    let replyText =
      if linked: "✅ Session reconnected! Your conversation history carries over."
      else:      "❌ Invalid or expired code. Generate a fresh one with `/mycode`."
    dcAdapter.sendInteractionResponse(
      event.interactionId, event.interactionToken, replyText).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc interaction response: " & error)

  of deModalRequest:
    dcAdapter.sendInteractionModal(
      event.interactionId, event.interactionToken).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc send modal: " & error)

  of deButtonClick:
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    dcAdapter.sendDeferredUpdate(
      event.interactionId, event.interactionToken).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc deferred update: " & error)
    let callback = decideCallbackRequest(
      CallbackRequest(channel: ckDiscord, data: event.content))
    case callback.route
    of cbrUi:
      discard handleDiscordUiCallback(event, dcAdapter, presentationState, memory, userId, callback, modelCatalogLoader, toolsCount, toolClientsCount, daemonStartMs, msgSeq, logger)
    of cbrSessionTask:
      let entry = sm.getOrCreate(userId)
      inc msgSeq
      entry.inbox.addLastNoWait(
        newTaskMsg($msgSeq, callbackTaskKind(callback), $userId, callback.value, ckDiscord, event.messageId))
    of cbrNone:
      discard

proc checkDiscordOfflineMessages*(sm: var SessionManager;
                                   dcAdapter: DiscordAdapter;
                                   discordToken: string;
                                   presentationState: var PresentationState;
                                   memory: MdFileAdapter;
                                   completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                                   modelCatalogLoader: ModelCatalogLoader;
                                   toolsCount: int;
                                   toolClientsCount: int;
                                   daemonStartMs: int64;
                                   msgSeq: var int;
                                   logger: Logger;
                                   handleInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                                   completeInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                                   handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  ## One-time startup check for messages received while the bot was down.
  ## NOTE: Discord does NOT deliver DMs sent while bot was offline.
  ## We fetch recent messages and filter by last processed message_id.
  if discordToken.len == 0:
    return
  logger.info("discord: checking for offline messages...")
  for userIdStr, _ in sm.entries:
    let userId = UserId(userIdStr)
    let discordId = dcAdapter.resolver.reverseChannel(userId, ckDiscord)
    if discordId.len == 0:
      continue
    let ctx = memory.loadContext(userId)
    let lastMsgId = ctx.preferencesMd.strip
    let chId = dcAdapter.dmChannelFor(discordId).valueOr:
      logger.warn("discord offline: cannot get DM channel for " & discordId)
      continue
    let msgs = dcAdapter.fetchUnreadMessages(chId, 50).valueOr:
      logger.warn("discord offline: cannot fetch messages for " & discordId)
      continue
    var newMsgCount = 0
    for i in countdown(msgs.len - 1, 0):
      let msg = msgs[i]
      let msgId = msg.getOrDefault("id").getStr("")
      if lastMsgId.len > 0 and msgId <= lastMsgId:
        continue
      newMsgCount.inc
      let content = msg.getOrDefault("content").getStr("")
      logger.info("discord offline: processing message " & msgId & " from " & discordId)
      handleDiscordEvent(sm, DiscordRawEvent(
        kind:          deMessage,
        discordUserId: discordId,
        content:       content,
        channelId:     chId,
        messageId:     msgId,
      ), dcAdapter, presentationState, memory, completeBuilder,
         modelCatalogLoader, toolsCount, toolClientsCount, daemonStartMs, msgSeq, logger,
         handleInboundStatus, completeInboundStatus,
         handleSessionFallback)
      memory.saveChannelPreference(userId, "discord_last_msg_id", msgId)
    if newMsgCount > 0:
      logger.info("discord: processed " & $newMsgCount & " offline message(s) for " & userIdStr)

proc drainDiscordEvents*(sm: var SessionManager;
                         dcAdapter: DiscordAdapter;
                         discordToken: string;
                         presentationState: var PresentationState;
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                         modelCatalogLoader: ModelCatalogLoader;
                         toolsCount: int;
                         toolClientsCount: int;
                         daemonStartMs: int64;
                         msgSeq: var int;
                         logger: Logger;
                         handleInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                         completeInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if discordToken.len == 0:
    return
  ## Process real-time events
  var (hasEvent, event) = dcAdapter.tryRecvEvent()
  while hasEvent:
    logger.info("discord event: " & $event.kind & " from " & event.discordUserId)
    handleDiscordEvent(sm, event, dcAdapter, presentationState, memory, completeBuilder,
                       modelCatalogLoader, toolsCount, toolClientsCount, daemonStartMs, msgSeq, logger,
                       handleInboundStatus,
                       completeInboundStatus,
                       handleSessionFallback)
    (hasEvent, event) = dcAdapter.tryRecvEvent()
