import std/[strutils, tables]
import chronos/asyncsync
import results
import ../../core/commands/command_routing
import ../../core/log as core_log
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ./common_runtime
import ./telegram

type
  TelegramPrefs* = ChannelPrefs

proc defaultTelegramPrefs*(): TelegramPrefs = defaultChannelPrefs()
proc parseTelegramPrefs*(preferencesMd: string): TelegramPrefs = parseChannelPrefs(preferencesMd)
proc loadTelegramPrefs*(memory: MdFileAdapter; userId: UserId): TelegramPrefs =
  loadChannelPrefs(memory, userId)

proc getCurrentThinkLevel*(memory: MdFileAdapter; userId: UserId): string =
  common_runtime.getCurrentThinkLevel(memory, userId)

proc getCurrentProviderModel*(memory: MdFileAdapter;
                              userId: UserId): (string, string) =
  common_runtime.getCurrentProviderModel(memory, userId)

proc buildThinkButtons*(memory: MdFileAdapter;
                        userId: UserId): seq[seq[(string, string)]] =
  common_runtime.buildThinkButtons(memory, userId)

proc buildProviderButtons*(memory: MdFileAdapter;
                           userId: UserId): seq[seq[(string, string)]] =
  common_runtime.buildProviderButtons(memory, userId)

proc buildModelButtons*(memory: MdFileAdapter;
                        provider: string;
                        userId: UserId): seq[seq[(string, string)]] =
  common_runtime.buildModelButtons(memory, provider, userId)

proc saveTelegramPreference*(memory: MdFileAdapter;
                             userId: UserId;
                             key, value: string) =
  saveChannelPreference(memory, userId, key, value)

proc clearTelegramKeyboard*(tgAdapter: var TelegramAdapter;
                            kbdMsgIds: var Table[string, string];
                            userId: UserId) =
  let kbdId = kbdMsgIds.getOrDefault($userId)
  if kbdId.len > 0:
    tgAdapter.editKeyboard(userId, kbdId, @[]).isOkOr:
      discard
    kbdMsgIds.del($userId)

proc handleTelegramModels*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           kbdMsgIds: var Table[string, string];
                           memory: MdFileAdapter;
                           modelCatalogLoader: ModelCatalogLoader;
                           logger: Logger): bool =
  if command.kind != cmdModels:
    return false
  let providerOnly =
    if command.value.strip.len > 0: parseModelsProviderArg(command.value).valueOr: ""
    else: ""
  if providerOnly.len > 0:
    let currentKbdId = kbdMsgIds.getOrDefault($msg.userId)
    let catalog = modelCatalogLoader(providerOnly).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(providerOnly, catalog.entries))
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    let title = buildModelPageTitle(providerOnly, 0, entries) &
      "\n" & buildCatalogSourceText(catalog)
    let buttons = buildModelPageButtons(providerOnly, entries, currProv, currModel, 0)
    if currentKbdId.len > 0:
      tgAdapter.editKeyboardText(msg.userId, currentKbdId, title, buttons).isOkOr:
        discard
    else:
      let sentId = tgAdapter.sendKeyboard(msg.userId, title, buttons, replyTo = msg.channelId).valueOr:
        core_log.log(logger, core_log.lvlError, "tg send keyboard error: " & error)
        return true
      kbdMsgIds[$msg.userId] = sentId
    return true
  if command.value.strip.len > 0:
    let reply = memory.applyModelsTextCommand(msg.userId, command.value, modelCatalogLoader).valueOr: error
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    reply,
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  let currentKbdId = kbdMsgIds.getOrDefault($msg.userId)
  if currentKbdId.len > 0:
    tgAdapter.editKeyboardText(
      msg.userId, currentKbdId,
      "Escolha o provider:",
      memory.buildProviderButtons(msg.userId)).isOkOr:
        discard
  else:
    let sentId = tgAdapter.sendKeyboard(msg.userId,
      "Escolha o provider:", memory.buildProviderButtons(msg.userId),
      replyTo = msg.channelId).valueOr:
        core_log.log(logger, core_log.lvlError, "tg send provider keyboard error: " & error)
        return true
    kbdMsgIds[$msg.userId] = sentId
  true

proc handleTelegramModelCallback*(msg: InboundMessage;
                                  callback: CallbackDecision;
                                  tgAdapter: var TelegramAdapter;
                                  kbdMsgIds: var Table[string, string];
                                  memory: MdFileAdapter;
                                  modelCatalogLoader: ModelCatalogLoader;
                                  logger: Logger): bool =
  case callback.kind
  of cbkModelsProvider:
    logger.info("tg callback models:provider:" & callback.provider)
    let kbdId = kbdMsgIds.getOrDefault($msg.userId)
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        buildModelPageTitle(callback.provider, 0, entries) &
          "\n" & buildCatalogSourceText(catalog),
        buildModelPageButtons(callback.provider, entries, currProv, currModel, 0)).isOkOr:
        core_log.log(logger, core_log.lvlError, "tg editKeyboard models:provider error: " & error)
    return true

  of cbkModelsSet:
    logger.info("tg callback models:set:" & callback.provider & ":" & callback.model)
    memory.saveTelegramPreference(msg.userId, "provider", callback.provider)
    memory.saveTelegramPreference(msg.userId, "model", callback.model)
    let kbdId = kbdMsgIds.getOrDefault($msg.userId)
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        "✅ Modelo definido: " & callback.provider & " / " & callback.model,
        @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "tg editKeyboard models:set error: " & error)
      kbdMsgIds.del($msg.userId)
    else:
      tgAdapter.send(OutboundMessage(
        userId:  msg.userId,
        channel: ckTelegram,
        text:    "✅ Modelo definido: " & callback.provider & " / " & callback.model,
        replyTo: msg.channelId,
      )).isOkOr:
        core_log.log(logger, core_log.lvlError, "tg send models:set error: " & error)
    return true

  of cbkModelsPage:
    logger.info("tg callback models:page:" & callback.provider & ":" & $callback.page)
    let kbdId = kbdMsgIds.getOrDefault($msg.userId)
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        buildModelPageTitle(callback.provider, callback.page, entries) &
          "\n" & buildCatalogSourceText(catalog),
        buildModelPageButtons(callback.provider, entries, currProv, currModel, callback.page)).isOkOr:
          core_log.log(logger, core_log.lvlError, "tg editKeyboard models:page error: " & error)
    return true

  of cbkModelsBack:
    let kbdId = kbdMsgIds.getOrDefault($msg.userId)
    if kbdId.len > 0:
      tgAdapter.editKeyboard(msg.userId, kbdId,
                             memory.buildProviderButtons(msg.userId)).isOkOr:
        discard
    return true

  else:
    false

proc handleTelegramThinkingCallback*(msg: InboundMessage;
                                     callback: CallbackDecision;
                                     tgAdapter: var TelegramAdapter;
                                     kbdMsgIds: var Table[string, string];
                                     memory: MdFileAdapter): bool =
  if callback.kind != cbkThinkSet:
    return false

  let level = callback.value
  if level in ThinkLevels:
    memory.saveTelegramPreference(msg.userId, "thinking", level)
    let kbdId = kbdMsgIds.getOrDefault($msg.userId)
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        "🧠 Thinking: " & level,
        @[]).isOkOr:
          discard
      kbdMsgIds.del($msg.userId)
    else:
      tgAdapter.send(OutboundMessage(
        userId:  msg.userId,
        channel: ckTelegram,
        text:    "🧠 Thinking: *" & level & "*",
        replyTo: msg.channelId,
      )).isOkOr:
        discard
  true

proc handleTelegramThink*(msg: InboundMessage;
                          command: CommandDecision;
                          tgAdapter: var TelegramAdapter;
                          kbdMsgIds: var Table[string, string];
                          memory: MdFileAdapter): bool =
  if command.kind != cmdThink:
    return false
  if command.value.strip.len > 0:
    let reply = memory.applyThinkTextCommand(msg.userId, command.value).valueOr: error
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    reply,
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  let currentKbdId = kbdMsgIds.getOrDefault($msg.userId)
  if currentKbdId.len > 0:
    tgAdapter.editKeyboardText(
      msg.userId, currentKbdId,
      "Nível de raciocínio:",
      memory.buildThinkButtons(msg.userId)).isOkOr:
        discard
  else:
    let sentId = tgAdapter.sendKeyboard(msg.userId,
      "Nível de raciocínio:", memory.buildThinkButtons(msg.userId),
      replyTo = msg.channelId).valueOr:
        return true
    kbdMsgIds[$msg.userId] = sentId
  true

proc handleTelegramBudget*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           memory: MdFileAdapter): bool =
  if command.kind != cmdBudget:
    return false
  let reply = memory.applyBudgetTextCommand(msg.userId, command.value).valueOr: error
  tgAdapter.send(OutboundMessage(
    userId:  msg.userId,
    channel: ckTelegram,
    text:    reply,
    replyTo: msg.channelId,
  )).isOkOr:
    discard
  true

proc handleTelegramUiCommand*(msg: InboundMessage;
                              command: CommandDecision;
                              tgAdapter: var TelegramAdapter;
                              kbdMsgIds: var Table[string, string];
                              memory: MdFileAdapter;
                              modelCatalogLoader: ModelCatalogLoader;
                              toolClientsCount: int;
                              toolsCount: int;
                              logger: Logger): bool =
  case command.kind
  of cmdConfig:
    discard tgAdapter.sendKeyboard(
      msg.userId, memory.buildConfigText(msg.userId), buildConfigButtons(), replyTo = msg.channelId)
    true
  of cmdTasks:
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildTasksText(),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    true
  of cmdAgents:
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildAgentsText(toolsCount, toolClientsCount),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    true
  of cmdModels:
    handleTelegramModels(msg, command, tgAdapter, kbdMsgIds, memory, modelCatalogLoader, logger)
  of cmdThink:
    handleTelegramThink(msg, command, tgAdapter, kbdMsgIds, memory)
  of cmdBudget:
    handleTelegramBudget(msg, command, tgAdapter, memory)
  else:
    false

proc handleTelegramUiCallback*(msg: InboundMessage;
                               callback: CallbackDecision;
                               tgAdapter: var TelegramAdapter;
                               kbdMsgIds: var Table[string, string];
                               memory: MdFileAdapter;
                               modelCatalogLoader: ModelCatalogLoader;
                               logger: Logger): bool =
  handleTelegramModelCallback(msg, callback, tgAdapter, kbdMsgIds, memory, modelCatalogLoader, logger) or
    handleTelegramThinkingCallback(msg, callback, tgAdapter, kbdMsgIds, memory)

proc buildTelegramStatusText*(memory: MdFileAdapter;
                              userId: UserId;
                              toolsCount: int;
                              sessionCount: int;
                              daemonStartMs: int64): string =
  let text = buildTextStatusText(memory, userId, toolsCount, sessionCount, daemonStartMs)
  result = text
  result = result.replace("Status", "*📊 Status*")
  result = result.replace("Provider: ", "🤖 Provider: ")
  result = result.replace("\nThinking: ", "\n🧠 Thinking: ")
  result = result.replace("\nTools: ", "\n🔧 Tools: ")
  result = result.replace("\nSessões ativas: ", "\n💬 Sessões ativas: ")
  result = result.replace("\nMemórias: ", "\n📝 Memórias: ")
  result = result.replace(" linhas\nUptime: ", " linhas\n⏱ Uptime: ")

proc handleTelegramPing*(msg: InboundMessage;
                         command: CommandDecision;
                         tgAdapter: var TelegramAdapter;
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.}): bool =
  if command.kind != cmdPing:
    return false

  let t0 = nowMs()
  let (prov, mdl) = memory.getCurrentProviderModel(msg.userId)
  let pingFn = completeBuilder("provider = \"" & prov & "\"\nmodel = \"" & mdl & "\"")
  var history = newHistory()
  history.addUser("ping")
  let req = buildPrompt("Reply with one word: pong", history, "")
  let resp = pingFn(req)
  let delta = nowMs() - t0
  let text = if resp.isOk:
               "🏓 pong — *" & prov & " / " & mdl & "* — *" & $delta & "ms*"
             else:
               "❌ " & prov & " error: " & resp.error
  tgAdapter.send(OutboundMessage(
    userId:  msg.userId,
    channel: ckTelegram,
    text:    text,
    replyTo: msg.channelId,
  )).isOkOr:
    discard
  true

proc handleTelegramStatus*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           memory: MdFileAdapter;
                           toolsCount: int;
                           sessionCount: int;
                           daemonStartMs: int64): bool =
  if command.kind != cmdStatus:
    return false

  tgAdapter.send(OutboundMessage(
    userId:  msg.userId,
    channel: ckTelegram,
    text:    memory.buildTelegramStatusText(msg.userId, toolsCount, sessionCount, daemonStartMs),
    replyTo: msg.channelId,
  )).isOkOr:
    discard
  true

proc handleTelegramCoreCommand*(sm: var SessionManager;
                                msg: InboundMessage;
                                command: CommandDecision;
                                tgAdapter: var TelegramAdapter;
                                memory: MdFileAdapter;
                                completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                                toolsCount: int;
                                toolClientsCount: int;
                                msgSeq: var int): bool =
  case decideLocalCommandAction(command)
  of lcaStartIntro:
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildStartIntroText(),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaShowMenu:
    discard tgAdapter.sendKeyboard(
      msg.userId, buildMenuText(), buildMenuButtons(), replyTo = msg.channelId)
    return true
  of lcaShowWhoami:
    let sessId = if sm.hasSession(msg.userId): "active" else: "" # SessionManager doesn't expose sessionId easily here, using placeholder
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildWhoamiText(msg.userId, sessId, msg.channelId),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaGenerateLinkCode:
    let code = tgAdapter.resolver.generateLinkCode(msg.userId)
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildLinkCodeText(code),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaClearMemory:
    memory.clearMemory(msg.userId)
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    "🗑️ Memórias apagadas.",
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaDoctorReport:
    var report = buildDoctorReport(
      memory, completeBuilder, msg.userId, toolsCount, toolClientsCount, sm.sessionCount())
    report = report
      .replace("Donkey Doctor", "*🩺 Donkey Doctor*")
      .replace("Provider: OK", "✅ Provider: OK")
      .replace("Provider: ", "❌ Provider: ")
      .replace("Memory dir: ", "✅ Memory dir: ")
      .replace("Memory dir missing: ", "❌ Memory dir missing: ")
      .replace("Tools loaded: ", "🔧 Tools loaded: ")
      .replace("MCP clients: ", "🔌 MCP clients: ")
      .replace("Active sessions: ", "💬 Active sessions: ")
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    report,
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaHelpText:
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildHelpText(true).replace("Donkey", "Donkey 🫏") & "\n\n" &
               "Envie qualquer mensagem para conversar. Imagens e documentos são aceitos.",
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaShowMemory:
    let ctx = memory.loadContext(msg.userId)
    let memText = ctx.memoryMd |> strip
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    if memText.len > 0: memText else: "Nenhuma memória salva ainda.",
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaContinueLink:
    let rawTgId = tgAdapter.resolver.reverseChannel(msg.userId, ckTelegram)
    let linked = tgAdapter.resolver.consumeLinkCode(command.value, ckTelegram, rawTgId)
    let replyText = if linked: "✅ " & buildContinueResultText(true)
                    else: "❌ " & buildContinueResultText(false)
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    replyText,
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  else:
    discard

  false

proc handleTelegramTaskCommand*(sm: var SessionManager;
                                msg: InboundMessage;
                                command: CommandDecision;
                                tgAdapter: var TelegramAdapter;
                                msgSeq: var int): bool =
  if not isSessionTaskCommand(command.kind):
    return false

  if sm.hasSession(msg.userId):
    let entry = sm.getOrCreate(msg.userId)
    inc msgSeq
    entry.inbox.addLastNoWait(
      newTaskMsg($msgSeq, commandTaskKind(command), $msg.userId,
                 "", ckTelegram, msg.channelId))
  else:
    let text =
      if command.kind == cmdDebug:
        "Nenhuma sessão ativa. Envie uma mensagem primeiro."
      else:
        "Nenhuma conversa ativa para reiniciar."
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    text,
      replyTo: msg.channelId,
    )).isOkOr:
      discard
  true

proc handleTelegramCoreCallback*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 callback: CallbackDecision;
                                 msgSeq: var int): bool =
  if callback.route == cbrSessionTask:
    let entry = sm.getOrCreate(msg.userId)
    inc msgSeq
    entry.inbox.addLastNoWait(
      newTaskMsg($msgSeq, callbackTaskKind(callback), $msg.userId,
                 callback.value, ckTelegram, msg.channelId))
    return true
  false

proc handleTelegramMessage*(msg: InboundMessage;
                            sm: var SessionManager;
                            tgAdapter: var TelegramAdapter;
                            kbdMsgIds: var Table[string, string];
                            memory: MdFileAdapter;
                            completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                            modelCatalogLoader: ModelCatalogLoader;
                            toolClientsCount: int;
                            toolsCount: int;
                            msgSeq: var int;
                            daemonStartMs: int64;
                            logger: Logger): bool =
  let command = decideCommandRequest(CommandRequest(channel: msg.channel, text: msg.text))
  case command.route
  of crLocal:
    return handleTelegramCoreCommand(sm, msg, command, tgAdapter, memory,
                                     completeBuilder, toolsCount, toolClientsCount, msgSeq)
  of crSessionTask:
    return handleTelegramTaskCommand(sm, msg, command, tgAdapter, msgSeq)
  of crUi:
    return handleTelegramUiCommand(msg, command, tgAdapter, kbdMsgIds, memory, modelCatalogLoader, toolClientsCount, toolsCount, logger)
  of crCallback:
    let callback = decideCallbackRequest(CallbackRequest(channel: msg.channel, data: command.value))
    case callback.route
    of cbrUi:
      handleTelegramUiCallback(msg, callback, tgAdapter, kbdMsgIds, memory, modelCatalogLoader, logger)
    of cbrSessionTask:
      handleTelegramCoreCallback(sm, msg, callback, msgSeq)
    of cbrNone:
      false
  of crPing:
    handleTelegramPing(msg, command, tgAdapter, memory, completeBuilder)
  of crStatus:
    handleTelegramStatus(msg, command, tgAdapter, memory,
                         toolsCount, sm.sessionCount(), daemonStartMs)
  of crNone:
    false
