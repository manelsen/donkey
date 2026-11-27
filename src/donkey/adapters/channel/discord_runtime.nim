import std/[strutils, tables]
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/log as core_log
import ../../core/outbound/outbound
import ../../core/pipeops
import ../../domain/channels/discord_pure
import ../../adapters/memory/md_file
import ../../app/inbound_gate
import ../../app/approval_runtime
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ../../app/command_dispatch
import ../../ports/channel_capability
import ../identity/identity_resolver
import ./common_runtime
import ./command_services
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


proc tellPrefsUnreadable(event: DiscordRawEvent; dcAdapter: DiscordAdapter;
                         userId: UserId; reason: string; logger: Logger) =
  ## A picker needs the current preferences to mark the selection; when they
  ## cannot be read the user is told so instead of seeing defaults.
  sendDiscordEmbed(event, dcAdapter, userId, "⚙️ Preferências",
                   preferencesUnreadableText(reason), 0xE74C3C, logger)
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
    let configText = configViewText(memory, userId).valueOr:
      tellPrefsUnreadable(event, dcAdapter, userId, error, logger)
      return true
    if kbdId.len > 0 and event.interactionId.len == 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId, configText, buildConfigButtons()).isOkOr:
          core_log.log(logger, core_log.lvlWarn, "dc config keyboard: " & error)
    else:
      sendDiscordKeyboard(
        dcAdapter, event, presentationState, userId, UiSlotConfig,
        configText, buildConfigButtons(),
        "Abri a configuração na sua DM.", logger,
      )
    true
  of cmdTasks:
    sendDiscordEmbed(event, dcAdapter, userId,
      "🕒 Tarefas", taskBoardText(memory, userId).get(buildTasksText()), 0x95A5A6, logger)
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
      let (currProv, currModel) = memory.getCurrentProviderModel(userId).valueOr:
        tellPrefsUnreadable(event, dcAdapter, userId, error, logger)
        return true
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
      return false  ## text form: answered by the shared dispatcher
    else:
      let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
      let (currProv, _) = memory.getCurrentProviderModel(userId).valueOr:
        tellPrefsUnreadable(event, dcAdapter, userId, error, logger)
        return true
      if kbdId.len > 0 and event.interactionId.len == 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, "Escolha o provider:", buildProviderButtons(currProv)).isOkOr:
            core_log.log(logger, core_log.lvlError, "dc provider reopen: " & error)
      else:
        sendDiscordKeyboard(
          dcAdapter, event, presentationState, userId, UiSlotModels,
          "Escolha o provider:",
          buildProviderButtons(currProv),
          "Abri o seletor de modelo na sua DM.",
          logger,
        )
    true
  of cmdThink:
    if command.value.strip.len > 0:
      return false  ## text form: answered by the shared dispatcher
    else:
      let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotThink)
      let level = memory.getCurrentThinkLevel(userId).valueOr:
        tellPrefsUnreadable(event, dcAdapter, userId, error, logger)
        return true
      if kbdId.len > 0 and event.interactionId.len == 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, "Nível de raciocínio:", buildThinkButtons(level)).isOkOr:
            core_log.log(logger, core_log.lvlError, "dc think reopen: " & error)
      else:
        sendDiscordKeyboard(
          dcAdapter, event, presentationState, userId, UiSlotThink,
          "Nível de raciocínio:",
          buildThinkButtons(level),
          "Abri o seletor de thinking na sua DM.",
          logger,
        )
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
    let (currProv, currModel) = memory.getCurrentProviderModel(userId).valueOr:
      tellPrefsUnreadable(event, dcAdapter, userId, error, logger)
      return true
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
    let model = common_runtime.resolveModelCallback(callback.provider, callback.model)
    if model.len == 0:
      core_log.log(logger, core_log.lvlWarn,
        "dc model selection expired: " & callback.model)
      return true
    let saved = memory.saveChannelPreferences(
      userId, [("provider", callback.provider), ("model", model)])
    let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(event, userId, kbdId,
        savedOrError(saved, "Modelo definido: " & callback.provider & " / " & model),
        @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc model confirm: " & error)
      common_runtime.clearUiMsgId(presentationState, ckDiscord, userId, UiSlotModels)
    else:
      dcAdapter.send(OutboundMessage(
        userId: userId,
        channel: ckDiscord,
        text: savedOrError(saved, "Modelo definido: " & callback.provider & " / " & model),
      )).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc model confirm: " & error)
    true
  of cbkModelsPage:
    let (currProv, currModel) = memory.getCurrentProviderModel(userId).valueOr:
      tellPrefsUnreadable(event, dcAdapter, userId, error, logger)
      return true
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
    let (currProv, _) = memory.getCurrentProviderModel(userId).valueOr:
      tellPrefsUnreadable(event, dcAdapter, userId, error, logger)
      return true
    if kbdId.len > 0:
      dcAdapter.smartEditKeyboard(
        event, userId, kbdId, "Escolha o provider:", buildProviderButtons(currProv)).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc provider menu: " & error)
    true
  of cbkHelpPage:
    const HelpColor = 0x5865F2
    let pages = buildHelpPages(commandCaps(ckDiscord))
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
      let saved = memory.saveChannelPreference(userId, "thinking", level)
      let kbdId = common_runtime.getUiMsgId(presentationState, ckDiscord, userId, UiSlotThink)
      if kbdId.len > 0:
        dcAdapter.smartEditKeyboard(event, userId, kbdId, savedOrError(saved, "Thinking definido: " & level), @[]).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc think confirm: " & error)
        common_runtime.clearUiMsgId(presentationState, ckDiscord, userId, UiSlotThink)
      else:
        dcAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckDiscord,
          text: savedOrError(saved, "Thinking definido: " & level),
        )).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc think confirm: " & error)
    true
  of cbkReasoning:
    ## The toggle flips what is stored: without it, flipping the default
    ## could switch reasoning the wrong way.
    let prefs = common_runtime.loadChannelPrefs(memory, userId).valueOr:
      tellPrefsUnreadable(event, dcAdapter, userId, error, logger)
      return true
    let next = if prefs.reasoning == "on": "off" else: "on"
    let saved = common_runtime.saveChannelPreference(memory, userId, "reasoning", next)
    dcAdapter.send(OutboundMessage(
      userId: userId,
      channel: ckDiscord,
      text: savedOrError(saved, "🧠 Reasoning " & (if next == "on": "ativado." else: "desativado.")),
    )).isOkOr:
      core_log.log(logger, core_log.lvlError, "dc reasoning toggle: " & error)
    true
  else:
    false

type
  DiscordReplySink* = object
    ## The two ways a command reply leaves the Discord runtime. Tests swap in
    ## a recorder; production wraps the adapter (`discordReplySink`).
    respond*: proc(event: DiscordRawEvent; title, text: string; color: int;
                   ephemeral: bool): Result[void, string] {.gcsafe.}
      ## The initial response to an interaction (an embed when `title` is set).
    post*: proc(event: DiscordRawEvent; userId: UserId; text: string;
                private: bool): Result[void, string] {.gcsafe.}
      ## A message: in the event's channel, or in the user's DM when `private`.

proc discordReplySink*(dcAdapter: DiscordAdapter): DiscordReplySink =
  DiscordReplySink(
    respond: proc(event: DiscordRawEvent; title, text: string; color: int;
                  ephemeral: bool): Result[void, string] {.gcsafe.} =
      if title.len > 0:
        let embed = dcAdapter.sendInteractionEmbedPage(
          event.interactionId, event.interactionToken, title, text, color, @[],
          ephemeral = ephemeral)
        if embed.isOk:
          return ok()
      dcAdapter.sendInteractionResponse(
        event.interactionId, event.interactionToken, text, ephemeral = ephemeral),
    post: proc(event: DiscordRawEvent; userId: UserId; text: string;
               private: bool): Result[void, string] {.gcsafe.} =
      ## The DM goes to the Discord account that sent the command, not to
      ## whichever account of the same user the resolver lists first.
      let target =
        if private: "channel:" & ? dcAdapter.dmChannelFor(event.discordUserId)
        elif event.channelId.len > 0: "channel:" & event.channelId
        else: ""
      dcAdapter.send(OutboundMessage(
        userId: userId, channel: ckDiscord, text: text, replyTo: target)),
  )

func discordReplyStyle*(reply: CommandReply): (string, int) =
  ## Discord renders most command replies as colored embeds.
  case reply.topic
  of rtAbout:       ("🫏 Donkey", 0x5865F2)
  of rtStartIntro:  ("👋 Donkey", 0x5865F2)
  of rtLinkCode:    ("🔗 Link Code", 0x5865F2)
  of rtClearMemory: ("🗑️ Memórias", 0xE67E22)
  of rtDoctor:      ("🩺 Doctor", 0x95A5A6)
  of rtMemory:      ("🧠 Memórias", 0x9B59B6)
  of rtContinue:    ("🔗 Continue", if reply.failed: 0xED4245 else: 0x57F287)
  of rtNoSession:   ("ℹ️ Info", 0xED4245)
  of rtPing:        ("🏓 Ping", if reply.failed: 0xED4245 else: 0x57F287)
  of rtStatus:      ("📊 Status", 0x57F287)
  of rtWhoami:      ("🆔 Identity", 0x5865F2)
  of rtReasoning:   ("🧠 Reasoning", 0x57F287)
  of rtEditor:      ("🖥️ Editores", if reply.failed: 0xED4245 else: 0x5865F2)
  of rtHelp, rtSkill, rtUi, rtMenu, rtConfig, rtUnsupported: ("", 0)

func discordReplyRoute*(event: DiscordRawEvent; reply: CommandReply): ReplyRoute =
  ## An interaction reply can be ephemeral, so it never needs another path. A
  ## text command may come from a server channel: requester-only replies go
  ## to the DM instead.
  routeReply(reply, inSharedSpace = event.interactionId.len == 0,
             hasPrivatePath = true)

const DiscordFallbackAck* = "⏳ Processando..."

proc presentDiscordOutcome*(sink: DiscordReplySink; event: DiscordRawEvent;
                            userId: UserId; outcome: CommandOutcome;
                            logger: Logger) =
  ## Presents a dispatcher outcome. An interaction always gets exactly one
  ## initial response, whatever the outcome; a requester-only reply is
  ## ephemeral on an interaction and goes by DM otherwise, and is never
  ## posted publicly when that fails.
  let isInteraction = event.interactionId.len > 0
  case outcome.kind
  of cokFallback:
    if isInteraction:
      sink.respond(event, "", DiscordFallbackAck, 0, ephemeral = true).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc interaction ack: " & error)
  of cokAccepted:
    if isInteraction:
      sink.respond(event, "", acceptedText(outcome.task), 0, ephemeral = true).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc interaction ack: " & error)
  of cokReply:
    let reply = outcome.reply
    if reply.topic == rtUnsupported and not isInteraction:
      return
    let text =
      if reply.topic == rtUnsupported: UnsupportedCommandText else: reply.text
    let (title, color) = discordReplyStyle(reply)
    if isInteraction:
      let ephemeral = reply.requesterOnly or reply.topic == rtUnsupported
      sink.respond(event, title, text, color, ephemeral).isOkOr:
        core_log.log(logger, core_log.lvlError,
                     "dc interaction " & $reply.topic & ": " & error)
      return
    case discordReplyRoute(event, reply)
    of rrConversation:
      sink.post(event, userId, text, private = false).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc send " & $reply.topic & ": " & error)
    of rrPrivate:
      sink.post(event, userId, text, private = true).isOkOr:
        core_log.log(logger, core_log.lvlError,
                     "dc DM " & $reply.topic & " failed (not posted publicly): " & error)
    of rrNotice:
      sink.post(event, userId, RequesterOnlyNotice, private = false).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc send notice: " & error)

proc handleDiscordLocalExtra(event: DiscordRawEvent;
                             dcAdapter: DiscordAdapter;
                             presentationState: var PresentationState;
                             userId: UserId;
                             command: CommandDecision;
                             logger: Logger): bool =
  ## Discord-only presentation of local commands: the keyboard menu and paged
  ## help in interactions. False → use the shared dispatcher.
  if command.route != crLocal:
    return false
  case decideLocalCommandAction(command)
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
    true
  of lcaHelpText:
    let pages = buildHelpPages(commandCaps(ckDiscord))
    if event.interactionId.len == 0 or pages.len == 0:
      return false
    let (pTitle, pBody) = pages[0]
    dcAdapter.sendInteractionEmbedPage(
      event.interactionId, event.interactionToken,
      "📖 Ajuda — " & pTitle & " (1/" & $pages.len & ")",
      pBody, 0x5865F2, buildHelpNavButtons(0, pages.len)).isOkOr:
        core_log.log(logger, core_log.lvlWarn, "dc help embed: " & error)
        sendDiscordReply(event, dcAdapter, userId,
                         helpTextFor(ckDiscord, interactiveUi = true), logger)
    true
  else:
    false

proc discordCommandRequest(dcAdapter: DiscordAdapter; event: DiscordRawEvent;
                           command: CommandDecision;
                           userId: UserId): CommandDispatchRequest =
  ## Session tasks from Discord carry no message id (no reaction target).
  CommandDispatchRequest(
    command: command, userId: userId, channel: ckDiscord, messageId: "",
    rawId: event.discordUserId, links: dcAdapter.resolver.identityLinkPort(),
    interactiveUi: true)

proc handleDiscordEvent*(sm: var SessionManager;
                         event: DiscordRawEvent;
                         dcAdapter: DiscordAdapter;
                         presentationState: var PresentationState;
                         env: ChannelRuntimeEnv;
                         msgSeq: var int;
                         logger: Logger;
                         handleInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                         completeInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  let memory = env.memory
  let modelCatalogLoader = env.modelCatalogLoader
  let toolsCount = env.toolsCount
  let toolClientsCount = env.toolClientsCount
  let daemonStartMs = env.daemonStartMs
  case event.kind
  of deMessage:
    if dcAdapter.isDuplicateMessage(event.messageId):
      logger.debug("discord: message " & event.messageId & " already handled")
      return
    var event = event
    if event.guildId.len > 0 and event.interactionId.len == 0:
      ## (A slash command is already explicit: no mention to look for.)
      ## In a server: the bot's mention is not part of what was said, and with
      ## DONKEY_DISCORD_REQUIRE_MENTION only messages for the bot are answered.
      let botId = dcAdapter.botUserId()
      if dcAdapter.requireMention and
          not addressesBot(event.content, botId, event.referencedAuthorId):
        logger.debug("discord: message " & event.messageId & " not addressed to the bot")
        return
      event.content = stripBotMention(event.content, botId)
      if event.content.len == 0 and event.attachmentUrl.len == 0:
        return  ## a bare ping carries nothing to answer
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    var inbound = InboundMessage(
      userId:    userId,
      channel:   ckDiscord,
      channelId: event.channelId,
      messageId: event.messageId,
      text:      event.content,
      mediaUrl:  event.attachmentUrl,
      mediaFileName: event.attachmentName,
      mediaMimeType: event.attachmentMime,
      quotedText: event.referencedContent,
      bot:       event.bot,   ## the turn answers with that bot's persona
    )
    if event.extraAttachments.len > 0:
      ## One attachment per turn is downloaded; say which ones were not.
      if inbound.text.len > 0: inbound.text.add("\n\n")
      inbound.text.add("[Outros anexos não lidos: " &
                       event.extraAttachments.join(", ") & "]")
    let approvalReply = tryHandleApprovalInput(userId, event.content)
    if approvalReply.isSome:
      sendDiscordReply(event, dcAdapter, userId, approvalReply.get, logger)
      return
    handleInboundStatus(inbound)
    ## The DM recovery cursor: a message answered here moves it now; one handed
    ## to a turn moves it after that turn's final reply
    ## (`settleDiscordCursorOnReply`). A server message never moves it: the
    ## cursor only recovers DMs.
    ## Only an adapter with a cursor (the default bot's) recovers DMs: a bot's
    ## DM ids would move the default bot's cursor past its own DMs.
    let tracksCursor = event.messageId.len > 0 and event.guildId.len == 0 and
                       event.interactionId.len == 0 and not dcAdapter.cursor.isNil
    proc answeredNow() =
      ## With a DM of this user still in a turn, the answered message joins
      ## the pending one: moving the cursor now would pass the unfinished DM.
      if tracksCursor and dcAdapter.hasPendingCursor(userId):
        dcAdapter.notePendingCursor(userId, event.messageId)
      elif tracksCursor:
        discard memory.saveChannelPreference(userId, "discord_last_msg_id",
          laterSnowflake(memory.loadChannelPreference(userId, "discord_last_msg_id").get(""),
                         event.messageId))
    let command = decideCommandRequest(CommandRequest(channel: ckDiscord, text: event.content))
    if command.route == crUi and
       handleDiscordUiCommand(event, dcAdapter, presentationState, memory, userId,
                              command, modelCatalogLoader, toolsCount,
                              toolClientsCount, daemonStartMs, msgSeq, logger):
      answeredNow()
      completeInboundStatus(inbound)
    elif handleDiscordLocalExtra(event, dcAdapter, presentationState,
                                 userId, command, logger):
      answeredNow()
      completeInboundStatus(inbound)
    else:
      let outcome = dispatchCommand(env.commands, sm, msgSeq,
        discordCommandRequest(dcAdapter, event, command, userId))
      presentDiscordOutcome(discordReplySink(dcAdapter), event, userId, outcome, logger)
      if outcome.kind == cokFallback:
        if tracksCursor:
          dcAdapter.notePendingCursor(userId, event.messageId)
        handleSessionFallback(inbound)
      else:
        answeredNow()
        completeInboundStatus(inbound)

  of deInteraction:
    ## The /continue modal submits a bare code.
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    let command = newCommandDecision(cmdContinue, event.content |> strip)
    let outcome = dispatchCommand(env.commands, sm, msgSeq,
      discordCommandRequest(dcAdapter, event, command, userId))
    presentDiscordOutcome(discordReplySink(dcAdapter), event, userId, outcome, logger)

  of deModalRequest:
    dcAdapter.sendInteractionModal(
      event.interactionId, event.interactionToken).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc send modal: " & error)

  of deResync:
    discard  ## handled by the drain loop
  of deButtonClick:
    let userId = dcAdapter.resolver.resolve(ckDiscord, event.discordUserId)
    dcAdapter.sendDeferredUpdate(
      event.interactionId, event.interactionToken).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc deferred update: " & error)
    let approvalReply = tryHandleApprovalInput(userId, event.content)
    if approvalReply.isSome:
      dcAdapter.send(OutboundMessage(
        userId: userId, channel: ckDiscord, text: approvalReply.get)).isOkOr:
        core_log.log(logger, core_log.lvlError, "dc approval reply: " & error)
      return
    let callback = decideCallbackRequest(
      CallbackRequest(channel: ckDiscord, data: event.content))
    case callback.route
    of cbrUi:
      discard handleDiscordUiCallback(event, dcAdapter, presentationState, memory, userId, callback, modelCatalogLoader, toolsCount, toolClientsCount, daemonStartMs, msgSeq, logger)
    of cbrSessionTask:
      ## Only into a live session: creating an entry here left one without an
      ## orchestrator, the task never ran and the entry stayed behind.
      if not enqueueSessionTask(sm, msgSeq, userId, callbackTaskKind(callback),
                                callback.value, ckDiscord, event.messageId):
        dcAdapter.send(OutboundMessage(userId: userId, channel: ckDiscord,
                                       text: NoLiveSessionText)).isOkOr:
          core_log.log(logger, core_log.lvlError, "dc no-session reply: " & error)
    of cbrNone:
      discard

const DiscordEpochMs = 1420070400000'i64

func discordSnowflakeFloor*(epochMs: int64): int64 =
  ## Converts a Unix-millisecond instant to the equivalent Discord snowflake
  ## lower bound. Discord snowflakes encode `(ms - DiscordEpoch) << 22`.
  if epochMs <= DiscordEpochMs:
    0
  else:
    (epochMs - DiscordEpochMs) shl 22

func discordMessageAfterCursor*(msgId, lastMsgId: string; floor: int64): bool =
  ## Cursor-first ordering; when no cursor exists yet, fall back to the
  ## session's persisted inbound clock so history is not replayed.
  ## Snowflakes are 64-bit integers, not fixed-width strings: compare them
  ## numerically so an 18-digit cursor does not hide a 19-digit message.
  var id: int64
  try:
    id = parseBiggestInt(msgId)
  except ValueError:
    return false
  if lastMsgId.len > 0:
    try:
      return id > parseBiggestInt(lastMsgId)
    except ValueError:
      return false
  floor > 0 and id >= floor

proc checkDiscordOfflineMessages*(sm: var SessionManager;
                                   dcAdapter: DiscordAdapter;
                                   discordToken: string;
                                   presentationState: var PresentationState;
                                   env: ChannelRuntimeEnv;
                                   msgSeq: var int;
                                   logger: Logger;
                                   handleInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                                   completeInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                                   handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  ## One-time startup check for messages received while the bot was down.
  let memory = env.memory
  ## NOTE: Discord does NOT deliver DMs sent while bot was offline.
  ## We fetch recent messages and filter by last processed message_id.
  if discordToken.len == 0:
    return
  logger.info("discord: checking for offline messages...")
  for userIdStr, entry in sm.entries:
    let userId = UserId(userIdStr)
    if not sm.allows(userId):
      logger.warn("discord offline: skipping unauthorized session owner " & userIdStr)
      continue
    let discordId = dcAdapter.resolver.reverseChannel(userId, ckDiscord)
    if discordId.len == 0:
      continue
    ## An unreadable cursor is not an absent one: absent marks the history as
    ## seen and skips it, so this user waits for the next check instead.
    let lastMsgId = memory.loadChannelPreference(userId, "discord_last_msg_id").valueOr:
      logger.warn("discord offline: cannot read the cursor of " & userIdStr & ": " & error)
      continue
    let floorId = discordSnowflakeFloor(entry.lastInboundEpochMs)
    let chId = dcAdapter.dmChannelFor(discordId).valueOr:
      logger.warn("discord offline: cannot get DM channel for " & discordId)
      continue
    let msgs = dcAdapter.fetchUnreadMessages(chId, 50).valueOr:
      logger.warn("discord offline: cannot fetch messages for " & discordId)
      continue
    if lastMsgId.len == 0 and floorId == 0 and msgs.len > 0:
      ## No cursor and no session clock: mark the fetched history as seen
      ## rather than replaying commands/tasks from before the link.
      let newestId = msgs[0].getOrDefault("id").getStr("")
      if newestId.len > 0:
        memory.saveChannelPreference(userId, "discord_last_msg_id", newestId)
      logger.warn("discord offline: no cursor/clock for " & userIdStr &
                  "; skipping historical messages")
      continue
    var newMsgCount = 0
    for i in countdown(msgs.len - 1, 0):
      let msg = msgs[i]
      let msgId = msg.getOrDefault("id").getStr("")
      if not discordMessageAfterCursor(msgId, lastMsgId, floorId):
        continue
      ## Same parse as the gateway, so attachments and attachment-only
      ## messages are recovered too. The REST payload has no guild_id for a DM.
      let parsed = parseDispatch("MESSAGE_CREATE", msg)
      if parsed.kind != dekMessage:
        ## Nothing to answer (a bot, an empty message): it settles with the
        ## rest, so it cannot jump the cursor past a message still in a turn.
        dcAdapter.notePendingCursor(userId, msgId)
        continue
      newMsgCount.inc
      var event = messageEventOf(parsed)
      event.discordUserId = discordId
      event.channelId = chId
      logger.info("discord offline: processing message " & msgId & " from " & discordId)
      handleDiscordEvent(sm, event, dcAdapter, presentationState, env, msgSeq, logger,
         handleInboundStatus, completeInboundStatus,
         handleSessionFallback)
    if newMsgCount > 0:
      logger.info("discord: processed " & $newMsgCount & " offline message(s) for " & userIdStr)

proc drainDiscordEvents*(sm: var SessionManager;
                         dcAdapter: DiscordAdapter;
                         discordToken: string;
                         presentationState: var PresentationState;
                         env: ChannelRuntimeEnv;
                         msgSeq: var int;
                         logger: Logger;
                         handleInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                         completeInboundStatus: proc(msg: InboundMessage) {.gcsafe.};
                         handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                         pickBot: proc(bot: string): ptr DiscordAdapter {.gcsafe.} = nil;
                         noteInbound: proc(userId: UserId; bot: string) {.gcsafe.} = nil) =
  ## Every bot's events come through one queue, each tagged with its bot
  ## (E3.4): `pickBot` gives that bot's adapter, so replies, interactions and
  ## keyboards use its token, and `noteInbound` makes it the bot that answers
  ## the person, before anything is sent. Without a default token only the
  ## bots' events are handled.
  var primary = dcAdapter
  let gate = dcAdapter.resolver.identityGate()
  var (hasEvent, event) = dcAdapter.tryRecvEvent()
  while hasEvent:
    block next:
      let picked =
        if event.bot.len == 0:
          (if discordToken.len > 0: addr primary else: nil)
        elif pickBot != nil: pickBot(event.bot)
        else: nil
      if picked.isNil:
        if event.bot.len > 0:
          logger.warn("discord: event from bot " & event.bot & ", which is not configured")
        break next
      if event.kind == deResync:
        if event.bot.len > 0:
          ## The DM cursor is the default bot's (discord_bots).
          logger.info("discord: bot " & event.bot &
                      " reconnected; missed DMs are recovered only on the default bot")
          break next
        ## Same recovery as at startup; messages already handled are dropped
        ## by the dedup, the rest are processed in order.
        checkDiscordOfflineMessages(sm, dcAdapter, discordToken, presentationState,
                                    env, msgSeq, logger, handleInboundStatus,
                                    completeInboundStatus, handleSessionFallback)
        break next
      if not discordChannelAllowed(picked[].allowedChannels, event.guildId,
                                   event.originChannelId):
        ## Before the identity gate, like TG-016: no turn, identity or pairing.
        logger.debug("discord: server " & event.guildId & " is not in the allowlist")
        break next
      let linkSource =
        case event.kind
        of deMessage:       ilsCommandText
        of deInteraction:   ilsBareCode
        of deModalRequest:  ilsModalOnly
        else:               ilsNone
      let auth = authorizeInbound(
        sm, gate, ckDiscord, event.discordUserId, event.content, linkSource)
      if not auth.allowed:
        logger.warn("discord: unauthorized event from " &
          (if auth.identified: $auth.userId else: "unidentified sender"))
        break next
      logger.info("discord event: " & $event.kind & " from " &
        (if auth.identified: $auth.userId else: "unidentified sender"))
      if noteInbound != nil and auth.identified:
        noteInbound(auth.userId, event.bot)
      handleDiscordEvent(sm, event, picked[], presentationState, env, msgSeq, logger,
                         handleInboundStatus,
                         completeInboundStatus,
                         handleSessionFallback)
    (hasEvent, event) = dcAdapter.tryRecvEvent()

proc settleDiscordCursorOnReply*(dcAdapter: DiscordAdapter; sm: var SessionManager;
                                 reply: OutboundMessage) =
  ## Called for every outbound message. A turn's final reply (answer or
  ## error) on Discord settles the user's pending DM cursor — but only when
  ## nothing else of theirs is queued: a merged or later message may still be
  ## in a turn, and the cursor must not pass it.
  if reply.channel != ckDiscord or reply.isPartial or
      reply.replyKind notin {rkFinalAnswer, rkTurnError}:
    return
  if sm.hasSession(reply.userId):
    let entry = sm.get(reply.userId)
    if not entry.inbox.isNil and entry.inbox.len > 0:
      return
  dcAdapter.settleCursor(reply.userId)
