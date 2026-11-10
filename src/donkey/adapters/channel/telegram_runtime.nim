import std/strutils
import chronos/asyncsync
import results
import ../../core/commands/command_routing
import ../../core/log as core_log
import ../../core/outbound/outbound
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ./common_runtime
import ./telegram

# ── Forward declarations ──────────────────────────────────────────────────────

proc handleTelegramModels*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           presentationState: var PresentationState;
                           memory: MdFileAdapter;
                           modelCatalogLoader: ModelCatalogLoader;
                           logger: Logger): bool {.gcsafe.}

proc handleTelegramThink*(msg: InboundMessage;
                          command: CommandDecision;
                          tgAdapter: var TelegramAdapter;
                          presentationState: var PresentationState;
                          memory: MdFileAdapter): bool {.gcsafe.}

proc handleTelegramBudget*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           memory: MdFileAdapter): bool {.gcsafe.}

proc handleTelegramCoreCommand*(sm: var SessionManager;
                                msg: InboundMessage;
                                command: CommandDecision;
                                tgAdapter: var TelegramAdapter;
                                presentationState: var PresentationState;
                                memory: MdFileAdapter;
                                completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                                toolsCount: int;
                                toolClientsCount: int;
                                msgSeq: var int;
                                logger: Logger): bool {.gcsafe.}

proc handleTelegramStatus*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           memory: MdFileAdapter;
                           toolsCount: int;
                           sessionCount: int;
                           daemonStartMs: int64): bool {.gcsafe.}

proc handleTelegramTaskCommand*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 command: CommandDecision;
                                 tgAdapter: var TelegramAdapter;
                                 msgSeq: var int;
                                 logger: Logger;
                                 ensureTaskSession: proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} = nil): bool {.gcsafe.}

# ── Implementation ────────────────────────────────────────────────────────────

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
                            presentationState: var PresentationState;
                            userId: UserId;
                            slot = UiSlotModels) =
  let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, userId, slot)
  if kbdId.len > 0:
    tgAdapter.editKeyboard(userId, kbdId, @[]).isOkOr:
      discard
    common_runtime.clearUiMsgId(presentationState, ckTelegram, userId, slot)

proc handleTelegramModels*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           presentationState: var PresentationState;
                           memory: MdFileAdapter;
                           modelCatalogLoader: ModelCatalogLoader;
                           logger: Logger): bool =
  if command.kind != cmdModels:
    return false
  let providerOnly =
    if command.value.strip.len > 0: parseModelsProviderArg(command.value).valueOr: ""
    else: ""
  if providerOnly.len > 0:
    let currentKbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
    let catalog = modelCatalogLoader(providerOnly).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(providerOnly, catalog.entries))
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    let title = buildModelPageText(providerOnly, 0, entries, catalog)
    let buttons = buildModelPageButtons(providerOnly, entries, currProv, currModel, 0)
    if currentKbdId.len > 0:
      tgAdapter.editKeyboardText(msg.userId, currentKbdId, title, buttons).isOkOr:
        discard
    else:
      let sentId = tgAdapter.sendKeyboard(msg.userId, title, buttons, replyTo = msg.channelId).valueOr:
        core_log.log(logger, core_log.lvlError, "tg send keyboard error: " & error)
        return true
      common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels, sentId)
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
  let currentKbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
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
    common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels, sentId)
  true

proc handleTelegramModelCallback*(msg: InboundMessage;
                                  callback: CallbackDecision;
                                  tgAdapter: var TelegramAdapter;
                                  presentationState: var PresentationState;
                                  memory: MdFileAdapter;
                                  modelCatalogLoader: ModelCatalogLoader;
                                  logger: Logger): bool =
  # Acknowledge the callback immediately to stop the loading spinner
  discard tgAdapter.answerCallback(msg.callbackId)

  case callback.kind
  of cbkModelsProvider:
    logger.info("tg callback models:provider:" & callback.provider)
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        buildModelPageText(callback.provider, 0, entries, catalog),
        buildModelPageButtons(callback.provider, entries, currProv, currModel, 0)).isOkOr:
        core_log.log(logger, core_log.lvlError, "tg editKeyboard models:provider error: " & error)
    return true

  of cbkModelsSet:
    logger.info("tg callback models:set:" & callback.provider & ":" & callback.model)
    memory.saveTelegramPreference(msg.userId, "provider", callback.provider)
    memory.saveTelegramPreference(msg.userId, "model", callback.model)
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        "✅ Modelo definido: " & callback.provider & " / " & callback.model,
        @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "tg editKeyboard models:set error: " & error)
      common_runtime.clearUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
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
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        buildModelPageText(callback.provider, callback.page, entries, catalog),
        buildModelPageButtons(callback.provider, entries, currProv, currModel, callback.page)).isOkOr:
          core_log.log(logger, core_log.lvlError, "tg editKeyboard models:page error: " & error)
    return true

  of cbkModelsBack:
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
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
                                     presentationState: var PresentationState;
                                     memory: MdFileAdapter): bool =
  if callback.kind != cbkThinkSet:
    return false

  # Acknowledge the callback immediately to stop the loading spinner
  discard tgAdapter.answerCallback(msg.callbackId)

  let level = callback.value
  if level in ThinkLevels:
    memory.saveTelegramPreference(msg.userId, "thinking", level)
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotThink)
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        "🧠 Thinking: " & level,
        @[]).isOkOr:
          discard
      common_runtime.clearUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotThink)
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
                          presentationState: var PresentationState;
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
  let currentKbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotThink)
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
    common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotThink, sentId)
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
                              presentationState: var PresentationState;
                              memory: MdFileAdapter;
                              modelCatalogLoader: ModelCatalogLoader;
                              toolClientsCount: int;
                              toolsCount: int;
                              logger: Logger): bool =
  case command.kind
  of cmdConfig:
    let currentKbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotConfig)
    if currentKbdId.len > 0:
      discard tgAdapter.editKeyboardText(
        msg.userId, currentKbdId, memory.buildConfigText(msg.userId), buildConfigButtons())
    else:
      let sentId = tgAdapter.sendKeyboard(
        msg.userId, memory.buildConfigText(msg.userId), buildConfigButtons(), replyTo = msg.channelId).valueOr:
          return true
      common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotConfig, sentId)
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
  of cmdPoll:
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildPollText(),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    true
  of cmdModels:
    handleTelegramModels(msg, command, tgAdapter, presentationState, memory, modelCatalogLoader, logger)
  of cmdThink:
    handleTelegramThink(msg, command, tgAdapter, presentationState, memory)
  of cmdBudget:
    handleTelegramBudget(msg, command, tgAdapter, memory)
  of cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts:
    let reply = buildDeferredUiCommandText(command.kind)
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    reply,
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    true
  else:
    false

proc handleTelegramUiCallback*(msg: InboundMessage;
                                callback: CallbackDecision;
                                sm: var SessionManager;
                                tgAdapter: var TelegramAdapter;
                                presentationState: var PresentationState;
                                memory: MdFileAdapter;
                                completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                                modelCatalogLoader: ModelCatalogLoader;
                                toolClientsCount: int;
                                toolsCount: int;
                                msgSeq: var int;
                                daemonStartMs: int64;
                                logger: Logger;
                                ensureTaskSession: proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} = nil): bool =
  # Acknowledge the callback immediately to stop the loading spinner
  discard tgAdapter.answerCallback(msg.callbackId)

  case callback.kind
  of cbkModelsProvider, cbkModelsSet, cbkModelsPage, cbkModelsBack:
    return handleTelegramModelCallback(msg, callback, tgAdapter, presentationState, memory, modelCatalogLoader, logger)
  of cbkThinkSet:
    return handleTelegramThinkingCallback(msg, callback, tgAdapter, presentationState, memory)
  of cbkHelpPage:
    let pages = buildHelpPages()
    let page  = min(max(callback.page, 0), pages.len - 1)
    let (pTitle, pBody) = pages[page]
    let helpText = "📖 Ajuda — " & pTitle & " (" & $(page + 1) & "/" & $pages.len & ")\n\n" & pBody
    let buttons = buildHelpNavButtons(page, pages.len)
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotHelp)
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(msg.userId, kbdId, helpText, buttons).isOkOr:
        core_log.log(logger, core_log.lvlError, "tg help page error: " & error)
    else:
      let sentId = tgAdapter.sendKeyboard(msg.userId, helpText, buttons, replyTo = msg.channelId).valueOr:
        return true
      common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotHelp, sentId)
    return true

  of cbkModels:
    return handleTelegramModels(msg, newCommandDecision(cmdModels), tgAdapter, presentationState, memory, modelCatalogLoader, logger)
  of cbkThink:
    return handleTelegramThink(msg, newCommandDecision(cmdThink), tgAdapter, presentationState, memory)
  of cbkBudget:
    return handleTelegramBudget(msg, newCommandDecision(cmdBudget), tgAdapter, memory)
  of cbkHelp:
    return handleTelegramCoreCommand(sm, msg, newCommandDecision(cmdHelp), tgAdapter, presentationState, memory, completeBuilder, toolsCount, toolClientsCount, msgSeq, logger)
  of cbkStatus:
    return handleTelegramStatus(msg, newCommandDecision(cmdStatus), tgAdapter, memory, toolsCount, sm.sessionCount(), daemonStartMs)
  of cbkDoctor:
    return handleTelegramCoreCommand(sm, msg, newCommandDecision(cmdDoctor), tgAdapter, presentationState, memory, completeBuilder, toolsCount, toolClientsCount, msgSeq, logger)
  of cbkForget:
    return handleTelegramCoreCommand(sm, msg, newCommandDecision(cmdForget), tgAdapter, presentationState, memory, completeBuilder, toolsCount, toolClientsCount, msgSeq, logger)
  of cbkReset:
    return handleTelegramTaskCommand(sm, msg, newCommandDecision(cmdReset), tgAdapter, msgSeq, logger, ensureTaskSession)
  of cbkMyCode:
    return handleTelegramCoreCommand(sm, msg, newCommandDecision(cmdMyCode), tgAdapter, presentationState, memory, completeBuilder, toolsCount, toolClientsCount, msgSeq, logger)
  of cbkReasoning:
    return handleTelegramCoreCommand(sm, msg, newCommandDecision(cmdReasoning), tgAdapter, presentationState, memory, completeBuilder, toolsCount, toolClientsCount, msgSeq, logger)
  of cbkMenu:
    return handleTelegramCoreCommand(sm, msg, newCommandDecision(cmdMenu), tgAdapter, presentationState, memory, completeBuilder, toolsCount, toolClientsCount, msgSeq, logger)
  of cbkConfig:
    return handleTelegramCoreCommand(sm, msg, newCommandDecision(cmdConfig), tgAdapter, presentationState, memory, completeBuilder, toolsCount, toolClientsCount, msgSeq, logger)

  else:
    false
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
  result = result.replace("\nReasoning: ", "\n💭 Reasoning: ")
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
                                presentationState: var PresentationState;
                                memory: MdFileAdapter;
                                completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                                toolsCount: int;
                                toolClientsCount: int;
                                msgSeq: var int;
                                logger: Logger): bool =
  case decideLocalCommandAction(command)
  of lcaShowAbout:
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildAboutText(memory, msg.userId, toolsCount, toolClientsCount, sm.sessionCount()),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
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
    let currentKbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotMenu)
    if currentKbdId.len > 0:
      discard tgAdapter.editKeyboardText(
        msg.userId, currentKbdId, buildMenuText(), buildMenuButtons())
    else:
      let sentId = tgAdapter.sendKeyboard(
        msg.userId, buildMenuText(), buildMenuButtons(), replyTo = msg.channelId).valueOr:
          return true
      common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotMenu, sentId)
    return true
  of lcaShowWhoami:
    let sessId = if sm.hasLiveSession(msg.userId): "active" else: "" # SessionManager doesn't expose sessionId easily here, using placeholder
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildWhoamiText(msg.userId, sessId, msg.channelId),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaSkillCommand:
    let reply = applySkillTextCommand(
      memory,
      msg.userId,
      command.value,
      homeDir = memory.donkeyHomeDir(),
    ).valueOr:
      error
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    reply,
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
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    buildMemoryViewText(memory, msg.userId),
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
  of lcaReasoningToggle:
    let prefs = loadChannelPrefs(memory, msg.userId)
    let next = if prefs.reasoning == "on": "off" else: "on"
    saveChannelPreference(memory, msg.userId, "reasoning", next)

    # Update current keyboard if it was a menu/config
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotConfig)
    if kbdId.len > 0:
      # If we are in the config menu, refresh it
      discard tgAdapter.editKeyboardText(msg.userId, kbdId, memory.buildConfigText(msg.userId), buildConfigButtons())
    else:
      tgAdapter.send(OutboundMessage(
        userId:  msg.userId,
        channel: ckTelegram,
        text:    "✅ Reasoning " & (if next == "on": "ativado" else: "desativado") & ".",
        replyTo: msg.channelId,
      )).isOkOr:
        logger.error("tg send lcaReasoningToggle failed for user=" & $msg.userId & " reason=" & error)
    return true
  else:
    discard

  false
proc handleTelegramTaskCommand*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 command: CommandDecision;
                                 tgAdapter: var TelegramAdapter;
                                 msgSeq: var int;
                                 logger: Logger;
                                 ensureTaskSession: proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} = nil): bool =
  if not isSessionTaskCommand(command.kind):
    return false

  # Commands that should start a session if one doesn't exist
  if command.kind in {cmdDebug, cmdReset, cmdNew, cmdCompact, cmdStop, cmdRestart, cmdBind}:
    if ensureTaskSession != nil:
      ensureTaskSession(msg, commandTaskKind(command), "")
    else:
      let entry = sm.getOrCreate(msg.userId)
      inc msgSeq
      entry.inbox.addLastNoWait(
        newTaskMsg($msgSeq, commandTaskKind(command), $msg.userId,
                   "", ckTelegram, msg.channelId))

    # Send feedback for non-silent commands
    let feedback = case command.kind
      of cmdDebug: "🐞 Alterando modo debug..."
      of cmdReset: "🔄 Reiniciando bootstrap... vou avisar quando terminar."
      of cmdNew: "🆕 Arquivando e iniciando nova sessão..."
      of cmdCompact: "🗜️ Compactando histórico..."
      of cmdStop: "🛑 Parando execução..."
      of cmdRestart: "♻️ Reiniciando..."
      of cmdBind: "🔗 Preparando vínculo..."
      else: ""
    if feedback.len > 0:
      tgAdapter.send(OutboundMessage(
        userId:  msg.userId,
        channel: ckTelegram,
        text:    feedback,
        replyTo: msg.channelId,
      )).isOkOr:
        logger.error("tg send taskCommand feedback failed for user=" & $msg.userId & " reason=" & error)
    return true

  false

proc handleTelegramCoreCallback*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 callback: CallbackDecision;
                                 tgAdapter: var TelegramAdapter;
                                 msgSeq: var int;
                                 ensureTaskSession: proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} = nil): bool =
  if callback.route == cbrSessionTask:
    discard tgAdapter.answerCallback(msg.callbackId)
    if ensureTaskSession != nil:
      ensureTaskSession(msg, callbackTaskKind(callback), callback.value)
    else:
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
                            presentationState: var PresentationState;
                            memory: MdFileAdapter;
                            completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                            modelCatalogLoader: ModelCatalogLoader;
                            toolClientsCount: int;
                            toolsCount: int;
                            msgSeq: var int;
                            daemonStartMs: int64;
                            logger: Logger;
                            ensureTaskSession: proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} = nil): bool =
  if not sm.allows(msg.userId):
    logger.warn("telegram: unauthorized command/message from " & $msg.userId)
    return true
  let command = decideCommandRequest(CommandRequest(channel: msg.channel, text: msg.text))
  case command.route
  of crLocal:
    return handleTelegramCoreCommand(sm, msg, command, tgAdapter, presentationState, memory,
                                     completeBuilder, toolsCount, toolClientsCount, msgSeq, logger)
  of crSessionTask:
    return handleTelegramTaskCommand(sm, msg, command, tgAdapter, msgSeq, logger, ensureTaskSession)
  of crUi:
    return handleTelegramUiCommand(msg, command, tgAdapter, presentationState, memory, modelCatalogLoader, toolClientsCount, toolsCount, logger)
  of crCallback:
    let callback = decideCallbackRequest(CallbackRequest(channel: msg.channel, data: command.value))
    case callback.route
    of cbrUi:
      handleTelegramUiCallback(msg, callback, sm, tgAdapter, presentationState, memory, completeBuilder, modelCatalogLoader, toolClientsCount, toolsCount, msgSeq, daemonStartMs, logger, ensureTaskSession)
    of cbrSessionTask:
      handleTelegramCoreCallback(sm, msg, callback, tgAdapter, msgSeq, ensureTaskSession)
    of cbrNone:
      false
  of crPing:
    handleTelegramPing(msg, command, tgAdapter, memory, completeBuilder)
  of crStatus:
    handleTelegramStatus(msg, command, tgAdapter, memory,
                         toolsCount, sm.sessionCount(), daemonStartMs)
  of crNone:
    false
