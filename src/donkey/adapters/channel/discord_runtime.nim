import std/[strutils, tables]
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
  )).isOkOr:
    core_log.log(logger, core_log.lvlError, "dc send reply: " & error)

proc sendDiscordKeyboard(dcAdapter: DiscordAdapter;
                         event: DiscordRawEvent;
                         kbdMsgIds: var Table[string, string];
                         userId: UserId;
                         title: string;
                         buttons: seq[seq[(string, string)]];
                         ackText: string;
                         logger: Logger) =
  if event.interactionId.len > 0:
    let r = dcAdapter.sendInteractionKeyboard(
      event.interactionId, event.interactionToken, title, buttons)
    if r.isOk:
      kbdMsgIds[$userId] = "interaction"
      return
    ## Interaction expired or already used — fall back to a regular DM keyboard
    core_log.log(logger, core_log.lvlWarn,
      "dc interaction keyboard fallback (expired?): " & r.error)

  let msgId = dcAdapter.sendKeyboard(userId, title, buttons).valueOr:
    core_log.log(logger, core_log.lvlError, "dc send keyboard: " & error)
    return
  kbdMsgIds[$userId] = msgId

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
                            kbdMsgIds: var Table[string, string];
                            memory: MdFileAdapter;
                            userId: UserId;
                            command: CommandDecision;
                            modelCatalogLoader: ModelCatalogLoader;
                            logger: Logger): bool =
  case command.kind
  of cmdModels:
    let providerOnly =
      if command.value.strip.len > 0: parseModelsProviderArg(command.value).valueOr: ""
      else: ""
    if providerOnly.len > 0:
      let kbdId = kbdMsgIds.getOrDefault($userId)
      let (currProv, currModel) = memory.getCurrentProviderModel(userId)
      let catalog = modelCatalogLoader(providerOnly).valueOr: emptyCatalogResult()
      let entries = sortModelCatalog(normalizeModelCatalog(providerOnly, catalog.entries))
      let title = buildModelPageTitle(providerOnly, 0, entries) &
        "\n" & buildCatalogSourceText(catalog)
      let buttons = buildModelPageButtons(providerOnly, entries, currProv, currModel, 0)
      if kbdId.len > 0 and event.interactionId.len == 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, title, buttons).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc provider direct menu: " & error)
      else:
        sendDiscordKeyboard(
          dcAdapter, event, kbdMsgIds, userId, title, buttons,
          "Abri o catálogo de " & providerOnly & " na sua DM.", logger,
        )
    elif command.value.strip.len > 0:
      let reply = memory.applyModelsTextCommand(userId, command.value, modelCatalogLoader).valueOr: error
      sendDiscordReply(event, dcAdapter, userId, reply, logger)
    else:
      let kbdId = kbdMsgIds.getOrDefault($userId)
      if kbdId.len > 0 and event.interactionId.len == 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, "Escolha o provider:", memory.buildProviderButtons(userId)).isOkOr:
            core_log.log(logger, core_log.lvlError, "dc provider reopen: " & error)
      else:
        sendDiscordKeyboard(
          dcAdapter, event, kbdMsgIds, userId,
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
      let kbdId = kbdMsgIds.getOrDefault($userId)
      if kbdId.len > 0 and event.interactionId.len == 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, "Nível de raciocínio:", memory.buildThinkButtons(userId)).isOkOr:
            core_log.log(logger, core_log.lvlError, "dc think reopen: " & error)
      else:
        sendDiscordKeyboard(
          dcAdapter, event, kbdMsgIds, userId,
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
  else:
    false

proc handleDiscordUiCallback(event: DiscordRawEvent;
                             dcAdapter: DiscordAdapter;
                             kbdMsgIds: var Table[string, string];
                             memory: MdFileAdapter;
                             userId: UserId;
                             callback: CallbackDecision;
                             modelCatalogLoader: ModelCatalogLoader;
                             logger: Logger): bool =
  logger.info("dc callback " & $callback.kind & " from " & $userId)
  case callback.kind
  of cbkModelsProvider:
    let (currProv, currModel) = memory.getCurrentProviderModel(userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    let kbdId = kbdMsgIds.getOrDefault($userId)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId,
        buildModelPageTitle(callback.provider, 0, entries) &
          "\n" & buildCatalogSourceText(catalog),
        buildModelPageButtons(callback.provider, entries, currProv, currModel, 0)).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc model menu: " & error)
    true
  of cbkModelsSet:
    memory.saveChannelPreference(userId, "provider", callback.provider)
    memory.saveChannelPreference(userId, "model", callback.model)
    let kbdId = kbdMsgIds.getOrDefault($userId)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(event, userId, kbdId,
        "Modelo definido: " & callback.provider & " / " & callback.model,
        @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc model confirm: " & error)
      kbdMsgIds.del($userId)
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
    let kbdId = kbdMsgIds.getOrDefault($userId)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId,
        buildModelPageTitle(callback.provider, callback.page, entries) &
          "\n" & buildCatalogSourceText(catalog),
        buildModelPageButtons(callback.provider, entries, currProv, currModel, callback.page)).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc model page: " & error)
    true
  of cbkModelsBack:
    let kbdId = kbdMsgIds.getOrDefault($userId)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId, "Escolha o provider:", memory.buildProviderButtons(userId)).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc provider menu: " & error)
    true
  of cbkThinkSet:
    let level = callback.value
    if level in ThinkLevels:
      memory.saveChannelPreference(userId, "thinking", level)
      let kbdId = kbdMsgIds.getOrDefault($userId)
      if kbdId.len > 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, "Thinking definido: " & level, @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc think confirm: " & error)
        kbdMsgIds.del($userId)
      else:
        dcAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckDiscord,
          text: "Thinking definido: " & level,
        )).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc think confirm: " & error)
    true
  else:
    false

proc handleDiscordEvent*(sm: var SessionManager;
                         event: DiscordRawEvent;
                         dcAdapter: DiscordAdapter;
                         kbdMsgIds: var Table[string, string];
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                         modelCatalogLoader: ModelCatalogLoader;
                         toolsCount: int;
                         toolClientsCount: int;
                         daemonStartMs: int64;
                         msgSeq: var int;
                         logger: Logger;
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  case event.kind
  of deMessage:
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    ## Save last processed message_id for offline recovery
    if event.messageId.len > 0:
      memory.saveChannelPreference(userId, "discord_last_msg_id", event.messageId)
    let command = decideCommandRequest(CommandRequest(channel: ckDiscord, text: event.content))
    case command.route
    of crLocal:
      case decideLocalCommandAction(command)
      of lcaStartIntro:
        sendDiscordReply(event, dcAdapter, userId, buildStartIntroText(), logger)
      of lcaGenerateLinkCode:
        sendDiscordReply(event, dcAdapter, userId, buildLinkCodeText(dcAdapter.resolver.generateLinkCode(userId)), logger)
      of lcaClearMemory:
        memory.clearMemory(userId)
        sendDiscordReply(event, dcAdapter, userId, "Memórias apagadas.", logger)
      of lcaDoctorReport:
        sendDiscordReply(
          event, dcAdapter, userId,
          buildDoctorReport(memory, completeBuilder, userId, toolsCount, toolClientsCount, sm.sessionCount()),
          logger)
      of lcaHelpText:
        sendDiscordReply(event, dcAdapter, userId, buildHelpText(true), logger)
      of lcaShowMemory:
        let memText = memory.loadContext(userId).memoryMd.strip
        sendDiscordReply(event, dcAdapter, userId,
                         if memText.len > 0: memText else: "Nenhuma memória salva ainda.", logger)
      of lcaContinueLink:
        let linked = dcAdapter.resolver.consumeLinkCode(command.value, ckDiscord, event.discordUserId)
        sendDiscordReply(event, dcAdapter, userId, buildContinueResultText(linked), logger)
      else:
        discard
    of crSessionTask:
      if sm.hasSession(userId):
        let entry = sm.getOrCreate(userId)
        inc msgSeq
        entry.inbox.addLastNoWait(
          newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckDiscord, ""))
      else:
        let text =
          if command.kind == cmdDebug:
            "Nenhuma sessão ativa. Envie uma mensagem primeiro."
          else:
            "Nenhuma conversa ativa para reiniciar."
        sendDiscordReply(event, dcAdapter, userId, text, logger)
    of crUi:
      discard handleDiscordUiCommand(event, dcAdapter, kbdMsgIds, memory, userId, command, modelCatalogLoader, logger)
    of crPing:
      sendDiscordReply(event, dcAdapter, userId, buildPingText(memory, userId, completeBuilder), logger)
    of crStatus:
      sendDiscordReply(
        event, dcAdapter, userId,
        buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
        logger)
    of crCallback, crNone:
      handleSessionFallback(InboundMessage(
        userId:    userId,
        channel:   ckDiscord,
        channelId: event.messageId,
        text:      event.content,
      ))

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
      discard handleDiscordUiCallback(event, dcAdapter, kbdMsgIds, memory, userId, callback, modelCatalogLoader, logger)
    of cbrSessionTask:
      let entry = sm.getOrCreate(userId)
      inc msgSeq
      entry.inbox.addLastNoWait(
        newTaskMsg($msgSeq, callbackTaskKind(callback), $userId, callback.value, ckDiscord, ""))
    of cbrNone:
      discard

proc checkDiscordOfflineMessages*(sm: var SessionManager;
                                   dcAdapter: DiscordAdapter;
                                   discordToken: string;
                                   kbdMsgIds: var Table[string, string];
                                   memory: MdFileAdapter;
                                   completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                                   modelCatalogLoader: ModelCatalogLoader;
                                   toolsCount: int;
                                   toolClientsCount: int;
                                   daemonStartMs: int64;
                                   msgSeq: var int;
                                   logger: Logger;
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
      ), dcAdapter, kbdMsgIds, memory, completeBuilder,
         modelCatalogLoader, toolsCount, toolClientsCount, daemonStartMs, msgSeq, logger,
         handleSessionFallback)
      memory.saveChannelPreference(userId, "discord_last_msg_id", msgId)
    if newMsgCount > 0:
      logger.info("discord: processed " & $newMsgCount & " offline message(s) for " & userIdStr)

proc drainDiscordEvents*(sm: var SessionManager;
                         dcAdapter: DiscordAdapter;
                         discordToken: string;
                         kbdMsgIds: var Table[string, string];
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                         modelCatalogLoader: ModelCatalogLoader;
                         toolsCount: int;
                         toolClientsCount: int;
                         daemonStartMs: int64;
                         msgSeq: var int;
                         logger: Logger;
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if discordToken.len == 0:
    return
  ## Process real-time events
  var (hasEvent, event) = dcAdapter.tryRecvEvent()
  while hasEvent:
    logger.info("discord event: " & $event.kind & " from " & event.discordUserId)
    handleDiscordEvent(sm, event, dcAdapter, kbdMsgIds, memory, completeBuilder,
                       modelCatalogLoader, toolsCount, toolClientsCount, daemonStartMs, msgSeq, logger,
                       handleSessionFallback)
    (hasEvent, event) = dcAdapter.tryRecvEvent()
