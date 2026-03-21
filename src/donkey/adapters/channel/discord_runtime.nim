import std/[strutils, tables]
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
import ./common_runtime
import ./discord

proc sendDiscordReply(event: DiscordRawEvent;
                      dcAdapter: DiscordAdapter;
                      userId: UserId;
                      text: string;
                      log: Logger) =
  if event.interactionId.len > 0:
    dcAdapter.sendInteractionResponse(
      event.interactionId, event.interactionToken, text).isOkOr:
        log.error("dc interaction resp: " & error)
    return
  dcAdapter.send(OutboundMessage(
    userId: userId,
    channel: ckDiscord,
    text: text,
  )).isOkOr:
    log.error("dc send reply: " & error)

proc sendDiscordKeyboard(dcAdapter: DiscordAdapter;
                         event: DiscordRawEvent;
                         userId: UserId;
                         title: string;
                         buttons: seq[seq[(string, string)]];
                         ackText: string;
                         log: Logger): string =
  let msgId = dcAdapter.sendKeyboard(userId, title, buttons).valueOr:
    log.error("dc send keyboard: " & error)
    return ""
  if event.interactionId.len > 0:
    dcAdapter.sendInteractionResponse(
      event.interactionId, event.interactionToken, ackText).isOkOr:
        log.error("dc interaction resp: " & error)
  msgId

proc handleDiscordUiCommand(event: DiscordRawEvent;
                            dcAdapter: DiscordAdapter;
                            kbdMsgIds: var Table[string, string];
                            memory: MdFileAdapter;
                            userId: UserId;
                            command: CommandDecision;
                            modelCatalogLoader: ModelCatalogLoader;
                            log: Logger): bool =
  case command.kind
  of cmdModels:
    let providerOnly =
      if command.value.strip.len > 0: parseModelsProviderArg(command.value).valueOr: ""
      else: ""
    if providerOnly.len > 0:
      let kbdId = kbdMsgIds.getOrDefault($userId)
      let (currProv, currModel) = memory.getCurrentProviderModel(userId)
      let catalog = modelCatalogLoader(providerOnly).valueOr: emptyCatalogResult()
      let title = buildModelPageTitle(providerOnly, 0,
        pageCount(normalizeModelCatalog(providerOnly, catalog.entries))) &
        "\n" & buildCatalogSourceText(catalog)
      let buttons = buildModelPageButtons(providerOnly, catalog.entries, currProv, currModel, 0)
      if kbdId.len > 0:
        dcAdapter.editKeyboard(userId, kbdId, title, buttons).isOkOr:
          log.error("dc provider direct menu: " & error)
      else:
        let msgId = sendDiscordKeyboard(
          dcAdapter, event, userId, title, buttons,
          "Abri o catálogo de " & providerOnly & " na sua DM.", log,
        )
        if msgId.len > 0:
          kbdMsgIds[$userId] = msgId
    elif command.value.strip.len > 0:
      let reply = memory.applyModelsTextCommand(userId, command.value, modelCatalogLoader).valueOr: error
      sendDiscordReply(event, dcAdapter, userId, reply, log)
    else:
      let kbdId = kbdMsgIds.getOrDefault($userId)
      if kbdId.len > 0:
        dcAdapter.editKeyboard(
          userId, kbdId, "Escolha o provider:", memory.buildProviderButtons(userId)).isOkOr:
            log.error("dc provider reopen: " & error)
      else:
        let msgId = sendDiscordKeyboard(
          dcAdapter, event, userId,
          "Escolha o provider:",
          memory.buildProviderButtons(userId),
          "Abri o seletor de modelo na sua DM.",
          log,
        )
        if msgId.len > 0:
          kbdMsgIds[$userId] = msgId
    true
  of cmdThink:
    if command.value.strip.len > 0:
      let reply = memory.applyThinkTextCommand(userId, command.value).valueOr: error
      sendDiscordReply(event, dcAdapter, userId, reply, log)
    else:
      let kbdId = kbdMsgIds.getOrDefault($userId)
      if kbdId.len > 0:
        dcAdapter.editKeyboard(
          userId, kbdId, "Nível de raciocínio:", memory.buildThinkButtons(userId)).isOkOr:
            log.error("dc think reopen: " & error)
      else:
        let msgId = sendDiscordKeyboard(
          dcAdapter, event, userId,
          "Nível de raciocínio:",
          memory.buildThinkButtons(userId),
          "Abri o seletor de thinking na sua DM.",
          log,
        )
        if msgId.len > 0:
          kbdMsgIds[$userId] = msgId
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
                             log: Logger): bool =
  case callback.kind
  of cbkModelsProvider:
    let (currProv, currModel) = memory.getCurrentProviderModel(userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let kbdId = kbdMsgIds.getOrDefault($userId)
    if kbdId.len > 0:
      dcAdapter.editKeyboard(
        userId, kbdId,
        buildModelPageTitle(callback.provider, 0, pageCount(normalizeModelCatalog(callback.provider, catalog.entries))) &
          "\n" & buildCatalogSourceText(catalog),
        buildModelPageButtons(callback.provider, catalog.entries, currProv, currModel, 0)).isOkOr:
          log.error("dc model menu: " & error)
    true
  of cbkModelsSet:
    memory.saveChannelPreference(userId, "provider", callback.provider)
    memory.saveChannelPreference(userId, "model", callback.model)
    let kbdId = kbdMsgIds.getOrDefault($userId)
    if kbdId.len > 0:
      dcAdapter.editKeyboard(userId, kbdId,
        "Modelo definido: " & callback.provider & " / " & callback.model,
        @[]).isOkOr:
          log.error("dc model confirm: " & error)
      kbdMsgIds.del($userId)
    else:
      dcAdapter.send(OutboundMessage(
        userId: userId,
        channel: ckDiscord,
        text: "Modelo definido: " & callback.provider & " / " & callback.model,
      )).isOkOr:
        log.error("dc model confirm: " & error)
    true
  of cbkModelsPage:
    let (currProv, currModel) = memory.getCurrentProviderModel(userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let kbdId = kbdMsgIds.getOrDefault($userId)
    if kbdId.len > 0:
      dcAdapter.editKeyboard(
        userId, kbdId,
        buildModelPageTitle(callback.provider, callback.page,
                            pageCount(normalizeModelCatalog(callback.provider, catalog.entries))) &
          "\n" & buildCatalogSourceText(catalog),
        buildModelPageButtons(callback.provider, catalog.entries, currProv, currModel, callback.page)).isOkOr:
          log.error("dc model page: " & error)
    true
  of cbkModelsBack:
    let kbdId = kbdMsgIds.getOrDefault($userId)
    if kbdId.len > 0:
      dcAdapter.editKeyboard(
        userId, kbdId, "Escolha o provider:", memory.buildProviderButtons(userId)).isOkOr:
          log.error("dc provider menu: " & error)
    true
  of cbkThinkSet:
    let level = callback.value
    if level in ThinkLevels:
      memory.saveChannelPreference(userId, "thinking", level)
      let kbdId = kbdMsgIds.getOrDefault($userId)
      if kbdId.len > 0:
        dcAdapter.editKeyboard(userId, kbdId, "Thinking definido: " & level, @[]).isOkOr:
          log.error("dc think confirm: " & error)
        kbdMsgIds.del($userId)
      else:
        dcAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckDiscord,
          text: "Thinking definido: " & level,
        )).isOkOr:
          log.error("dc think confirm: " & error)
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
                         log: Logger;
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  case event.kind
  of deMessage:
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    let command = decideCommandRequest(CommandRequest(channel: ckDiscord, text: event.content))
    case command.route
    of crLocal:
      case decideLocalCommandAction(command)
      of lcaStartIntro:
        sendDiscordReply(event, dcAdapter, userId, buildStartIntroText(), log)
      of lcaGenerateLinkCode:
        sendDiscordReply(event, dcAdapter, userId, buildLinkCodeText(dcAdapter.resolver.generateLinkCode(userId)), log)
      of lcaClearMemory:
        memory.clearMemory(userId)
        sendDiscordReply(event, dcAdapter, userId, "Memórias apagadas.", log)
      of lcaDoctorReport:
        sendDiscordReply(
          event, dcAdapter, userId,
          buildDoctorReport(memory, completeBuilder, userId, toolsCount, toolClientsCount, sm.sessionCount()),
          log)
      of lcaHelpText:
        sendDiscordReply(event, dcAdapter, userId, buildHelpText(true), log)
      of lcaShowMemory:
        let memText = memory.loadContext(userId).memoryMd.strip
        sendDiscordReply(event, dcAdapter, userId,
                         if memText.len > 0: memText else: "Nenhuma memória salva ainda.", log)
      of lcaContinueLink:
        let linked = dcAdapter.resolver.consumeLinkCode(command.value, ckDiscord, event.discordUserId)
        sendDiscordReply(event, dcAdapter, userId, buildContinueResultText(linked), log)
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
        sendDiscordReply(event, dcAdapter, userId, text, log)
    of crUi:
      discard handleDiscordUiCommand(event, dcAdapter, kbdMsgIds, memory, userId, command, modelCatalogLoader, log)
    of crPing:
      sendDiscordReply(event, dcAdapter, userId, buildPingText(memory, userId, completeBuilder), log)
    of crStatus:
      sendDiscordReply(
        event, dcAdapter, userId,
        buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
        log)
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
        log.error("dc interaction response: " & error)

  of deModalRequest:
    dcAdapter.sendInteractionModal(
      event.interactionId, event.interactionToken).isOkOr:
        log.error("dc send modal: " & error)

  of deButtonClick:
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    dcAdapter.sendButtonAck(
      event.interactionId, event.interactionToken).isOkOr:
        log.error("dc button ack: " & error)
    let callback = decideCallbackRequest(
      CallbackRequest(channel: ckDiscord, data: event.content))
    case callback.route
    of cbrUi:
      discard handleDiscordUiCallback(event, dcAdapter, kbdMsgIds, memory, userId, callback, modelCatalogLoader, log)
    of cbrSessionTask:
      let entry = sm.getOrCreate(userId)
      inc msgSeq
      entry.inbox.addLastNoWait(
        newTaskMsg($msgSeq, callbackTaskKind(callback), $userId, callback.value, ckDiscord, ""))
    of cbrNone:
      discard

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
                         log: Logger;
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if discordToken.len == 0:
    return

  var (hasEvent, event) = dcAdapter.tryRecvEvent()
  while hasEvent:
    handleDiscordEvent(sm, event, dcAdapter, kbdMsgIds, memory, completeBuilder,
                       modelCatalogLoader, toolsCount, toolClientsCount, daemonStartMs, msgSeq, log,
                       handleSessionFallback)
    (hasEvent, event) = dcAdapter.tryRecvEvent()
