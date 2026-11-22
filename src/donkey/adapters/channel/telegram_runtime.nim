import std/[strutils, tables]
import chronos/asyncsync
import results
import ../../core/commands/command_routing
import ../../core/log as core_log
import ../../core/outbound/outbound
import ../../core/pipeops
import ../../core/security/approval
import ../../adapters/memory/md_file
import ../../app/inbound_gate
import ../../app/approval_runtime
import ../../app/session_manager
import ../../app/album_mention_gate
import ../../domain/agent_message
import ../../domain/message
import ../../domain/channels/telegram_policy
import ../../domain/channels/telegram_pure
import ../../ports/provider
import ../../app/command_dispatch
import ../../ports/channel_capability
import ../identity/identity_resolver
import ./common_runtime
import ./telegram

proc logSendFailure(operation, error: string) {.gcsafe.} =
  ## A reply that could not be delivered is logged, never dropped silently.
  newLogger("tg.runtime").warn(operation & ": send failed: " & error)


var gAlbumMentionsGate {.threadvar.}: AlbumMentionGate
  ## Telegram messages are handled on the daemon loop only: thread-local to it,
  ## so reading and updating the gate is gcsafe without a cast.

proc gAlbumMentions(): AlbumMentionGate =
  ## The loop's gate, created on first use (a threadvar starts nil).
  if gAlbumMentionsGate == nil:
    gAlbumMentionsGate = newAlbumMentionGate()
  gAlbumMentionsGate

func replyTarget*(msg: InboundMessage): string =
  ## Carries the forum thread along with the message id, so command replies
  ## also land in the topic the user wrote in.
  telegramReplyTarget(msg.chatId, msg.channelId, msg.threadId)


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
proc loadTelegramPrefs*(memory: MdFileAdapter; userId: UserId): Result[TelegramPrefs, string] =
  loadChannelPrefs(memory, userId)

proc saveTelegramPreference*(memory: MdFileAdapter;
                             userId: UserId;
                             key, value: string): Result[void, string]
                             {.discardable.} =
  saveChannelPreference(memory, userId, key, value)

# ── Shared dispatcher wiring and Telegram presentation ───────────────────────

proc telegramCommandEnv(memory: MdFileAdapter;
                        completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                        modelCatalogLoader: ModelCatalogLoader = nil;
                        toolsCount = 0; toolClientsCount = 0;
                        daemonStartMs = 0'i64): CommandEnv =
  CommandEnv(services: newCommandServices(memory, completeBuilder, modelCatalogLoader,
                                          toolsCount, toolClientsCount, daemonStartMs))

proc telegramCommandRequest(msg: InboundMessage; command: CommandDecision;
                            tgAdapter: TelegramAdapter;
                            ensureTaskSession: proc(msg: InboundMessage; taskKind: TaskKind;
                                                    payload: string) {.gcsafe.} = nil):
                            CommandDispatchRequest =
  ## Telegram starts a session for a session command when there is none.
  var ensure: EnsureSessionFn = nil
  if ensureTaskSession != nil:
    ensure = proc(kind: TaskKind; payload: string) {.gcsafe.} =
      ensureTaskSession(msg, kind, payload)
  CommandDispatchRequest(
    command: command, userId: msg.userId, channel: ckTelegram,
    messageId: replyTarget(msg),
    rawId:  # the sender, not the first Telegram account linked to the user
      if msg.rawChannelId.len > 0: msg.rawChannelId
      else: tgAdapter.resolver.reverseChannel(msg.userId, ckTelegram),
    links: tgAdapter.resolver.identityLinkPort(),
    sessionMode: smCreate, ensureSession: ensure, interactiveUi: true)

func decorateTelegramStatus*(text: string): string =
  text
    .replace("Status", "*📊 Status*")
    .replace("Provider: ", "🤖 Provider: ")
    .replace("\nThinking: ", "\n🧠 Thinking: ")
    .replace("\nReasoning: ", "\n💭 Reasoning: ")
    .replace("\nTools: ", "\n🔧 Tools: ")
    .replace("\nSessões ativas: ", "\n💬 Sessões ativas: ")
    .replace("\nMemórias: ", "\n📝 Memórias: ")
    .replace(" linhas\nUptime: ", " linhas\n⏱ Uptime: ")

func decorateTelegramDoctor(report: string): string =
  ## The report already carries its status marks (command_services); only
  ## the title is set in bold here.
  report.replace("🩺 Donkey Doctor", "*🩺 Donkey Doctor*")

func telegramReplyText*(reply: CommandReply): string =
  ## Telegram markdown and emoji around the dispatcher's plain text.
  let mark = if reply.failed: "❌ " else: "✅ "
  case reply.topic
  of rtHelp:
    reply.text.replace("Donkey", "Donkey 🫏") & "\n\n" &
      "Envie qualquer mensagem para conversar. Imagens e documentos são aceitos."
  of rtDoctor:
    if reply.failed: reply.text else: decorateTelegramDoctor(reply.text)
  of rtStatus:
    if reply.failed: reply.text else: decorateTelegramStatus(reply.text)
  of rtPing:
    (if reply.failed: "❌ " else: "🏓 ") & reply.text
  of rtClearMemory:
    (if reply.failed: "" else: "🗑️ ") & reply.text
  of rtContinue, rtReasoning:
    mark & reply.text
  else:
    reply.text

func telegramReplyRoute*(msg: InboundMessage; reply: CommandReply): ReplyRoute =
  ## A group is a shared space and the bot has no private path from it.
  routeReply(reply, inSharedSpace = msg.isGroup, hasPrivatePath = false)

proc sendTelegramText(tgAdapter: var TelegramAdapter; msg: InboundMessage;
                      text: string; logger: Logger) =
  tgAdapter.send(OutboundMessage(
    userId:  msg.userId,
    channel: ckTelegram,
    text:    text,
    replyTo: replyTarget(msg),
  )).isOkOr:
    logger.error("tg send failed for user=" & $msg.userId & " reason=" & error)

proc tellPrefsUnreadable(tgAdapter: var TelegramAdapter;
                         presentationState: var PresentationState;
                         msg: InboundMessage; reason, slot: string) =
  ## A picker needs the current preferences to mark the selection. When they
  ## cannot be read the user is told so: in the picker message when there is
  ## one, otherwise (none, or deleted by the user) in a new message. Either
  ## way the picker is over, so its slot is cleared: the next command opens
  ## a fresh one instead of editing a notice that may be gone.
  let text = preferencesUnreadableText(reason)
  let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, slot)
  common_runtime.clearUiMsgId(presentationState, ckTelegram, msg.userId, slot)
  if kbdId.len > 0 and
     tgAdapter.editKeyboardText(msg.userId, kbdId, text, @[]).isOk:
    return
  tgAdapter.send(OutboundMessage(userId: msg.userId, channel: ckTelegram,
                                 text: text, replyTo: replyTarget(msg))).isOkOr:
    logSendFailure("preferences unreadable", error)

proc presentTelegramOutcome(tgAdapter: var TelegramAdapter; msg: InboundMessage;
                            outcome: CommandOutcome; logger: Logger): bool =
  ## False only for a fallback: the message belongs to the session.
  case outcome.kind
  of cokFallback:
    false
  of cokAccepted:
    sendTelegramText(tgAdapter, msg, acceptedText(outcome.task), logger)
    true
  of cokReply:
    let text =
      case telegramReplyRoute(msg, outcome.reply)
      of rrNotice: RequesterOnlyNotice
      of rrConversation, rrPrivate: telegramReplyText(outcome.reply)
    if text.len > 0:
      sendTelegramText(tgAdapter, msg, text, logger)
    true

proc presentTelegramUiText(tgAdapter: var TelegramAdapter; msg: InboundMessage;
                           command: CommandDecision; memory: MdFileAdapter;
                           modelCatalogLoader: ModelCatalogLoader = nil;
                           toolsCount = 0; toolClientsCount = 0): bool =
  ## Text forms of UI commands come from the shared dispatcher.
  let env = telegramCommandEnv(memory, nil, modelCatalogLoader, toolsCount,
                               toolClientsCount)
  let outcome = dispatchUiCommand(env, telegramCommandRequest(msg, command, tgAdapter))
  presentTelegramOutcome(tgAdapter, msg, outcome, newLogger("tg.ui"))


proc clearTelegramKeyboard*(tgAdapter: var TelegramAdapter;
                            presentationState: var PresentationState;
                            userId: UserId;
                            slot = UiSlotModels) =
  let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, userId, slot)
  if kbdId.len > 0:
    tgAdapter.editKeyboard(userId, kbdId, @[]).isOkOr:
      logSendFailure("clearTelegramKeyboard", error)
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
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId).valueOr:
      tellPrefsUnreadable(tgAdapter, presentationState, msg, error, UiSlotModels)
      return true
    let title = buildModelPageText(providerOnly, 0, entries, catalog)
    let buttons = buildModelPageButtons(providerOnly, entries, currProv, currModel, 0)
    if currentKbdId.len > 0:
      tgAdapter.editKeyboardText(msg.userId, currentKbdId, title, buttons).isOkOr:
        logSendFailure("handleTelegramModels", error)
    else:
      let sentId = tgAdapter.sendKeyboard(msg.userId, title, buttons, replyTo = replyTarget(msg)).valueOr:
        core_log.log(logger, core_log.lvlError, "tg send keyboard error: " & error)
        return true
      common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels, sentId)
    return true
  if command.value.strip.len > 0:
    return presentTelegramUiText(tgAdapter, msg, command, memory, modelCatalogLoader)
  let currentKbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
  let (currProv, _) = memory.getCurrentProviderModel(msg.userId).valueOr:
    tellPrefsUnreadable(tgAdapter, presentationState, msg, error, UiSlotModels)
    return true
  if currentKbdId.len > 0:
    tgAdapter.editKeyboardText(
      msg.userId, currentKbdId,
      "Escolha o provider:",
      buildProviderButtons(currProv)).isOkOr:
        logSendFailure("handleTelegramModels", error)
  else:
    let sentId = tgAdapter.sendKeyboard(msg.userId,
      "Escolha o provider:", buildProviderButtons(currProv),
      replyTo = replyTarget(msg)).valueOr:
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
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId).valueOr:
      tellPrefsUnreadable(tgAdapter, presentationState, msg, error, UiSlotModels)
      return true
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
    let model = resolveModelCallback(callback.provider, callback.model)
    if model.len == 0:
      logger.warn("tg callback models:set: unresolved token " & callback.model)
      tgAdapter.send(OutboundMessage(
        userId: msg.userId,
        channel: ckTelegram,
        text: "Essa seleção expirou. Abra /models novamente.",
        replyTo: replyTarget(msg),
      )).isOkOr:
        logSendFailure("handleTelegramModelCallback", error)
      return true
    logger.info("tg callback models:set:" & callback.provider & ":" & model)
    let saved = memory.saveChannelPreferences(
      msg.userId, [("provider", callback.provider), ("model", model)])
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        savedOrError(saved, "✅ Modelo definido: " & callback.provider & " / " & model),
        @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "tg editKeyboard models:set error: " & error)
      common_runtime.clearUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
    else:
      tgAdapter.send(OutboundMessage(
        userId:  msg.userId,
        channel: ckTelegram,
        text:    savedOrError(saved, "✅ Modelo definido: " & callback.provider & " / " & model),
        replyTo: replyTarget(msg),
      )).isOkOr:
        core_log.log(logger, core_log.lvlError, "tg send models:set error: " & error)
    return true

  of cbkModelsPage:
    logger.info("tg callback models:page:" & callback.provider & ":" & $callback.page)
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotModels)
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId).valueOr:
      tellPrefsUnreadable(tgAdapter, presentationState, msg, error, UiSlotModels)
      return true
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
    let (currProv, _) = memory.getCurrentProviderModel(msg.userId).valueOr:
      tellPrefsUnreadable(tgAdapter, presentationState, msg, error, UiSlotModels)
      return true
    if kbdId.len > 0:
      tgAdapter.editKeyboard(msg.userId, kbdId,
                             buildProviderButtons(currProv)).isOkOr:
        logSendFailure("handleTelegramModelCallback", error)
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
    let saved = memory.saveTelegramPreference(msg.userId, "thinking", level)
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotThink)
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(
        msg.userId, kbdId,
        savedOrError(saved, "🧠 Thinking: " & level),
        @[]).isOkOr:
          logSendFailure("handleTelegramThinkingCallback", error)
      common_runtime.clearUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotThink)
    else:
      tgAdapter.send(OutboundMessage(
        userId:  msg.userId,
        channel: ckTelegram,
        text:    "🧠 Thinking: *" & level & "*",
        replyTo: replyTarget(msg),
      )).isOkOr:
        logSendFailure("handleTelegramThinkingCallback", error)
  true

proc handleTelegramThink*(msg: InboundMessage;
                          command: CommandDecision;
                          tgAdapter: var TelegramAdapter;
                          presentationState: var PresentationState;
                          memory: MdFileAdapter): bool =
  if command.kind != cmdThink:
    return false
  if command.value.strip.len > 0:
    return presentTelegramUiText(tgAdapter, msg, command, memory)
  let currentKbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotThink)
  let level = memory.getCurrentThinkLevel(msg.userId).valueOr:
    tellPrefsUnreadable(tgAdapter, presentationState, msg, error, UiSlotThink)
    return true
  if currentKbdId.len > 0:
    tgAdapter.editKeyboardText(
      msg.userId, currentKbdId,
      "Nível de raciocínio:",
      buildThinkButtons(level)).isOkOr:
        logSendFailure("handleTelegramThink", error)
  else:
    let sentId = tgAdapter.sendKeyboard(msg.userId,
      "Nível de raciocínio:", buildThinkButtons(level),
      replyTo = replyTarget(msg)).valueOr:
        return true
    common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotThink, sentId)
  true

proc handleTelegramBudget*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           memory: MdFileAdapter): bool =
  if command.kind != cmdBudget:
    return false
  presentTelegramUiText(tgAdapter, msg, command, memory)


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
    let configText = memory.buildConfigText(msg.userId).valueOr:
      tellPrefsUnreadable(tgAdapter, presentationState, msg, error, UiSlotConfig)
      return true
    if currentKbdId.len > 0:
      discard tgAdapter.editKeyboardText(
        msg.userId, currentKbdId, configText, buildConfigButtons())
    else:
      let sentId = tgAdapter.sendKeyboard(
        msg.userId, configText, buildConfigButtons(), replyTo = replyTarget(msg)).valueOr:
          return true
      common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotConfig, sentId)
    true
  of cmdTasks, cmdAgents, cmdPoll:
    presentTelegramUiText(tgAdapter, msg, command, memory,
                          toolsCount = toolsCount, toolClientsCount = toolClientsCount)
  of cmdModels:
    handleTelegramModels(msg, command, tgAdapter, presentationState, memory, modelCatalogLoader, logger)
  of cmdThink:
    handleTelegramThink(msg, command, tgAdapter, presentationState, memory)
  of cmdBudget:
    handleTelegramBudget(msg, command, tgAdapter, memory)
  of cmdVerbose, cmdExec, cmdQueue, cmdUsage, cmdTts:
    presentTelegramUiText(tgAdapter, msg, command, memory)
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
    let pages = buildHelpPages(commandCaps(ckTelegram))
    let page  = min(max(callback.page, 0), pages.len - 1)
    let (pTitle, pBody) = pages[page]
    let helpText = "📖 Ajuda — " & pTitle & " (" & $(page + 1) & "/" & $pages.len & ")\n\n" & pBody
    let buttons = buildHelpNavButtons(page, pages.len)
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotHelp)
    if kbdId.len > 0:
      tgAdapter.editKeyboardText(msg.userId, kbdId, helpText, buttons).isOkOr:
        core_log.log(logger, core_log.lvlError, "tg help page error: " & error)
    else:
      let sentId = tgAdapter.sendKeyboard(msg.userId, helpText, buttons, replyTo = replyTarget(msg)).valueOr:
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
                              daemonStartMs: int64): Result[string, string] =
  ok(decorateTelegramStatus(
    ? buildTextStatusText(memory, userId, toolsCount, sessionCount, daemonStartMs)))

proc handleTelegramPing*(msg: InboundMessage;
                         command: CommandDecision;
                         tgAdapter: var TelegramAdapter;
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.}): bool =
  if command.kind != cmdPing:
    return false
  let pong = telegramCommandEnv(memory, completeBuilder).services.ping(msg.userId)
  let outcome =
    if pong.isOk: replied(rtPing, pong.get)
    else: replied(rtPing, pong.error, failed = true)
  presentTelegramOutcome(tgAdapter, msg, outcome, newLogger("tg.ping"))

proc handleTelegramStatus*(msg: InboundMessage;
                           command: CommandDecision;
                           tgAdapter: var TelegramAdapter;
                           memory: MdFileAdapter;
                           toolsCount: int;
                           sessionCount: int;
                           daemonStartMs: int64): bool =
  if command.kind != cmdStatus:
    return false
  let env = telegramCommandEnv(memory, nil, toolsCount = toolsCount,
                               daemonStartMs = daemonStartMs)
  let text = env.services.status(msg.userId, sessionCount)
  let outcome =
    if text.isOk: replied(rtStatus, text.get)
    else: replied(rtStatus, text.error, failed = true)
  presentTelegramOutcome(tgAdapter, msg, outcome, newLogger("tg.status"))

proc handleTelegramCommand*(sm: var SessionManager;
                            msg: InboundMessage;
                            command: CommandDecision;
                            tgAdapter: var TelegramAdapter;
                            presentationState: var PresentationState;
                            memory: MdFileAdapter;
                            completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                            modelCatalogLoader: ModelCatalogLoader;
                            toolsCount: int;
                            toolClientsCount: int;
                            msgSeq: var int;
                            daemonStartMs: int64;
                            logger: Logger;
                            ensureTaskSession: proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} = nil): bool =
  ## Every Telegram command goes through the shared dispatcher. Telegram only
  ## presents: the menu as a keyboard, a refreshed config keyboard after
  ## /reasoning, markdown and progress texts, and the group refusal for
  ## requester-only commands. False → the message belongs to the session.
  let action = decideLocalCommandAction(command)
  if command.route == crLocal and action == lcaShowMenu:
    let currentKbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotMenu)
    if currentKbdId.len > 0:
      discard tgAdapter.editKeyboardText(
        msg.userId, currentKbdId, buildMenuText(), buildMenuButtons())
    else:
      let sentId = tgAdapter.sendKeyboard(
        msg.userId, buildMenuText(), buildMenuButtons(), replyTo = replyTarget(msg)).valueOr:
          return true
      common_runtime.setUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotMenu, sentId)
    return true
  if msg.isGroup and requesterOnlyCommand(command):
    ## No private path from a group: refuse before minting or consuming a
    ## link code, or printing diagnostics where everyone can read them.
    sendTelegramText(tgAdapter, msg, RequesterOnlyNotice, logger)
    return true
  let env = telegramCommandEnv(memory, completeBuilder, modelCatalogLoader,
                               toolsCount, toolClientsCount, daemonStartMs)
  let outcome = dispatchCommand(env, sm, msgSeq,
    telegramCommandRequest(msg, command, tgAdapter, ensureTaskSession))
  if command.route == crLocal and action == lcaReasoningToggle and
     outcome.kind == cokReply and not outcome.reply.failed:
    let kbdId = common_runtime.getUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotConfig)
    let configText = memory.buildConfigText(msg.userId)
    if kbdId.len > 0 and configText.isOk:
      let edited = tgAdapter.editKeyboardText(msg.userId, kbdId,
        configText.get, buildConfigButtons())
      if edited.isOk:
        return true
      ## The /config message may be gone. The preference is already saved:
      ## confirm it below instead of running the toggle again.
      logSendFailure("reasoning keyboard edit", edited.error)
      common_runtime.clearUiMsgId(presentationState, ckTelegram, msg.userId, UiSlotConfig)
  presentTelegramOutcome(tgAdapter, msg, outcome, logger)

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
  ## Local commands (menu buttons and callbacks reach them through here).
  if command.route != crLocal:
    return false
  handleTelegramCommand(sm, msg, command, tgAdapter, presentationState, memory,
                        completeBuilder, nil, toolsCount, toolClientsCount,
                        msgSeq, 0, logger)

proc handleTelegramTaskCommand*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 command: CommandDecision;
                                 tgAdapter: var TelegramAdapter;
                                 msgSeq: var int;
                                 logger: Logger;
                                 ensureTaskSession: proc(msg: InboundMessage; taskKind: TaskKind; payload: string) {.gcsafe.} = nil): bool =
  ## Session commands go through the shared dispatcher (which interrupts the
  ## running turn for /stop, /new, /restart and /reset); Telegram only adds
  ## the progress text.
  if not isSessionTaskCommand(command.kind):
    return false
  let outcome = dispatchCommand(CommandEnv(), sm, msgSeq,
    telegramCommandRequest(msg, command, tgAdapter, ensureTaskSession))
  presentTelegramOutcome(tgAdapter, msg, outcome, logger)

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
                   callback.value, ckTelegram, replyTarget(msg)))
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
  ## Behavior derived from hermes-agent (MIT) fix 1e18e0503f; see
  ## docs/hermes-mining/telegram/CASES.md#tg-015
  ##
  ## In groups the bot may see every message. With the mention gate enabled,
  ## only messages that mention the bot start a turn; `/cmd@bot` already works
  ## because parseCommandText strips the suffix.
  let botUsername = telegramBotUsername()
  ## Callbacks are button taps, not free text: the mention gate does not apply.
  if msg.isGroup and msg.callbackId.len == 0 and
     telegramRequireMention() and botUsername.len > 0 and
     not isApprovalCommandText(msg.text):
    let nowMs = epochMs()
    let key = albumKey($msg.userId, msg.mediaGroupId)
    if isAddressedToBot(msg.text, botUsername):
      rememberAddressedAlbum(gAlbumMentions(), key, nowMs)
    elif not albumAddressed(gAlbumMentions(), key, nowMs):
      logger.debug("telegram: group message not addressed to the bot, ignored")
      ## A dropped button tap still needs its acknowledgement, or the client
      ## keeps the spinner for half a minute.
      if msg.callbackId.len > 0:
        discard tgAdapter.answerCallback(msg.callbackId)
      return true
    if gAlbumMentions().untilMs.len > 64:
      clearExpiredAlbums(gAlbumMentions(), nowMs)
  let pairingRawId =
    if msg.rawChannelId.len > 0: msg.rawChannelId else: msg.channelId
  let auth = authorizeResolvedInbound(
    sm, tgAdapter.resolver.identityGate(), ckTelegram, msg.userId, msg.text,
    rawId = pairingRawId,
    isGroup = msg.isGroup,
    chatId = (if msg.chatId.len > 0: msg.chatId else: msg.channelId))
  if not auth.allowed:
    logger.warn("telegram: unauthorized command/message from " & $msg.userId)
    return true
  let approvalReply = tryHandleApprovalInput(msg.userId, msg.text)
  if approvalReply.isSome:
    tgAdapter.send(OutboundMessage(
      userId: msg.userId, channel: ckTelegram,
      text: approvalReply.get, replyTo: replyTarget(msg))).isOkOr:
      logger.error("tg send approval reply failed: " & error)
    return true
  let command = decideCommandRequest(CommandRequest(channel: msg.channel, text: msg.text))
  if command.route == crNone:
    return false
  if command.route == crCallback:
    let approvalReply = tryHandleApprovalInput(msg.userId, command.value)
    if approvalReply.isSome:
      discard tgAdapter.answerCallback(msg.callbackId)
      tgAdapter.send(OutboundMessage(
        userId: msg.userId, channel: ckTelegram,
        text: approvalReply.get, replyTo: replyTarget(msg))).isOkOr:
        logger.error("tg send approval callback failed: " & error)
      return true
    let callback = decideCallbackRequest(CallbackRequest(channel: msg.channel, data: command.value))
    return
      case callback.route
      of cbrUi:
        handleTelegramUiCallback(msg, callback, sm, tgAdapter, presentationState, memory, completeBuilder, modelCatalogLoader, toolClientsCount, toolsCount, msgSeq, daemonStartMs, logger, ensureTaskSession)
      of cbrSessionTask:
        handleTelegramCoreCallback(sm, msg, callback, tgAdapter, msgSeq, ensureTaskSession)
      of cbrNone:
        false
  if command.route == crUi and
     handleTelegramUiCommand(msg, command, tgAdapter, presentationState, memory,
                             modelCatalogLoader, toolClientsCount, toolsCount, logger):
    return true
  handleTelegramCommand(sm, msg, command, tgAdapter, presentationState, memory,
                        completeBuilder, modelCatalogLoader, toolsCount,
                        toolClientsCount, msgSeq, daemonStartMs, logger,
                        ensureTaskSession)
