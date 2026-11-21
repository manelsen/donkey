import std/strutils
import chronos/asyncsync
import ../../core/commands/command_catalog
import ../../core/commands/command_routing
import ../../core/pipeops
import ../../core/log
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/message
import ../../ports/provider
import ../identity/identity_resolver
import ../../app/inbound_gate
import ../../app/approval_runtime
import ./common_runtime
import ./qq_channel
import ../../app/command_dispatch
import ../../ports/channel_capability

proc logSendFailure(operation, error: string) {.gcsafe.} =
  ## A reply that could not be delivered is logged, never dropped silently.
  newLogger("qq.runtime").warn(operation & ": send failed: " & error)


func qqSupportsRichUi*(kind: QQBackendKind): bool =
  kind == qbkOfficial

func qqInSharedSpace*(event: QQInboundEvent): bool =
  ## Group messages share one identity and one reply target: the group.
  qqRawIdentity(event).startsWith("group:")

func qqHelpText*(kind: QQBackendKind): string =
  ## Lists only the commands QQ answers (no /config or /menu views).
  if not qqSupportsRichUi(kind):
    return buildHelpText(commandCaps(ckQQ), false)
  let catalog = newCommandCatalog()
  var lines = @["## Donkey", ""]
  for section in defaultHelpSections():
    for cmd in catalog.commandsForCategories(section.categories, csHelp):
      if commandAvailable(cmd.kind, commandCaps(ckQQ)):
        lines.add("- `" & cmd.usageFor(true) & "` " & cmd.helpSummaryFor(true))
  lines.join("\n")

proc qqDirectModelProvider*(kind: QQBackendKind;
                            command: CommandDecision): string =
  if kind != qbkOfficial or command.kind != cmdModels or command.value.strip.len == 0:
    return ""
  parseModelsProviderArg(command.value).valueOr: ""

func qqShouldOpenThinkPicker*(kind: QQBackendKind;
                              command: CommandDecision): bool =
  kind == qbkOfficial and command.kind == cmdThink and command.value.strip.len == 0

func qqPickerText*(title, body: string): string =
  if body.len == 0:
    "## " & title
  else:
    "## " & title & "\n\n" & body

proc qqModelPickerTitle*(provider: string;
                         page: int;
                         entries: seq[ModelCatalogEntry];
                         catalog: ModelCatalogResult): string =
  var body = buildCatalogSourceText(catalog)
  if entries.len == 0:
    body.add("\n\nNenhum modelo disponível para este provider no catálogo atual.")
  qqPickerText(buildModelPageTitle(provider, page, entries), body)

func qqProviderPickerTitle*(): string =
  qqPickerText("Escolha o provider", "Selecione a família de modelos para abrir o catálogo.")

func qqThinkPickerTitle*(): string =
  qqPickerText("Nível de raciocínio", "Escolha quanta deliberação o agente deve usar.")

func qqModelConfirmedText*(provider, model: string): string =
  qqPickerText("Modelo definido", "**" & provider & " / " & model & "**")

func qqThinkingConfirmedText*(level: string): string =
  qqPickerText("Thinking definido", "**" & level & "**")

func qqStatusText*(providerLine, thinking: string;
                   toolsCount, sessionCount: int;
                   uptimeStr: string): string =
  "## Status\n\n" &
    "- " & providerLine.replace("Provider: ", "Provider: **") & "**\n" &
    "- Thinking: **" & thinking & "**\n" &
    "- Tools: **" & $toolsCount & "**\n" &
    "- Sessões ativas: **" & $sessionCount & "**\n" &
    "- Uptime: **" & uptimeStr & "**"

proc handleQQModelCallback(msg: InboundMessage;
                           callback: CallbackDecision;
                           qqAdapter: var QQChannelAdapter;
                           memory: MdFileAdapter;
                           modelCatalogLoader: ModelCatalogLoader;
                           rawUserId = ""): bool =
  case callback.kind
  of cbkModelsProvider:
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    qqAdapter.sendKeyboard(
      msg.userId,
      qqModelPickerTitle(callback.provider, 0, entries, catalog),
      buildModelPageButtons(callback.provider, entries, currProv, currModel, 0),
      replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        logSendFailure("handleQQModelCallback", error)
    true
  of cbkModelsSet:
    let model = resolveModelCallback(callback.provider, callback.model)
    if model.len == 0:
      return true
    let saved = memory.saveChannelPreferences(
      msg.userId, [("provider", callback.provider), ("model", model)])
    qqAdapter.send(OutboundMessage(
      userId: msg.userId,
      channel: ckQQ,
      text: savedOrError(saved, qqModelConfirmedText(callback.provider, model)),
      replyTo: msg.channelId,
    )).isOkOr:
      logSendFailure("handleQQModelCallback", error)
    true
  of cbkModelsPage:
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let entries = sortModelCatalog(normalizeModelCatalog(callback.provider, catalog.entries))
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    qqAdapter.sendKeyboard(
      msg.userId,
      qqModelPickerTitle(callback.provider, callback.page, entries, catalog),
      buildModelPageButtons(callback.provider, entries, currProv, currModel, callback.page),
      replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        logSendFailure("handleQQModelCallback", error)
    true
  of cbkModelsBack:
    qqAdapter.sendKeyboard(
      msg.userId,
      qqProviderPickerTitle(),
      memory.buildProviderButtons(msg.userId),
      replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        logSendFailure("handleQQModelCallback", error)
    true
  else:
    false

proc handleQQThinkingCallback(msg: InboundMessage;
                              callback: CallbackDecision;
                              qqAdapter: var QQChannelAdapter;
                              memory: MdFileAdapter): bool =
  if callback.kind != cbkThinkSet:
    return false
  let level = callback.value
  if level in ThinkLevels:
    let saved = memory.saveChannelPreference(msg.userId, "thinking", level)
    qqAdapter.send(OutboundMessage(
      userId: msg.userId,
      channel: ckQQ,
      text: savedOrError(saved, qqThinkingConfirmedText(level)),
      replyTo: msg.channelId,
    )).isOkOr:
      logSendFailure("handleQQThinkingCallback", error)
  true

proc handleQQUiCommand(msg: InboundMessage;
                       command: CommandDecision;
                       qqAdapter: var QQChannelAdapter;
                       memory: MdFileAdapter;
                       modelCatalogLoader: ModelCatalogLoader;
                       rawUserId = ""): bool =
  case command.kind
  of cmdModels:
    let provider = qqDirectModelProvider(qqAdapter.kind, command)
    if provider.len > 0:
        let catalog = modelCatalogLoader(provider).valueOr: emptyCatalogResult()
        let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
        let entries = sortModelCatalog(normalizeModelCatalog(provider, catalog.entries))
        qqAdapter.sendKeyboard(
          msg.userId,
          qqModelPickerTitle(provider, 0, entries, catalog),
          buildModelPageButtons(provider, entries, currProv, currModel, 0),
          replyTo = msg.channelId,
          allowedRawUserId = rawUserId).isOkOr:
            logSendFailure("handleQQUiCommand", error)
        return true
    if command.value.strip.len > 0 or qqAdapter.kind != qbkOfficial:
      return false  ## text form: answered by the shared dispatcher
    qqAdapter.sendKeyboard(msg.userId, qqProviderPickerTitle(),
      memory.buildProviderButtons(msg.userId), replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        logSendFailure("handleQQUiCommand", error)
    true
  of cmdThink:
    if not qqShouldOpenThinkPicker(qqAdapter.kind, command):
      return false  ## text form: answered by the shared dispatcher
    qqAdapter.sendKeyboard(msg.userId, qqThinkPickerTitle(),
      memory.buildThinkButtons(msg.userId), replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        logSendFailure("handleQQUiCommand", error)
    true
  else:
    false

proc handleQQUiCallback(msg: InboundMessage;
                        callback: CallbackDecision;
                        qqAdapter: var QQChannelAdapter;
                        memory: MdFileAdapter;
                        modelCatalogLoader: ModelCatalogLoader;
                        rawUserId = ""): bool =
  handleQQModelCallback(msg, callback, qqAdapter, memory, modelCatalogLoader, rawUserId) or
    handleQQThinkingCallback(msg, callback, qqAdapter, memory)

proc qqUptimeText*(daemonStartMs: int64; now = nowMs()): string =
  let uptimeSec = (now - daemonStartMs) div 1_000
  if uptimeSec < 60: $uptimeSec & "s"
  elif uptimeSec < 3600: $(uptimeSec div 60) & "m"
  else: $(uptimeSec div 3600) & "h " & $((uptimeSec mod 3600) div 60) & "m"

proc drainQQEvents*(qqAdapter: var QQChannelAdapter;
                    sm: var SessionManager;
                    env: ChannelRuntimeEnv;
                    msgSeq: var int;
                    handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.};
                    log: Logger = newLogger("qq.outbound")) =
  if not qqAdapter.enabled():
    return

  var (hasEvent, event) = qqAdapter.tryRecvEvent()
  while hasEvent:
    if event.content.strip.len > 0:
      let rawId = qqRawIdentity(event)
      let auth = authorizeInbound(sm, qqAdapter.resolver.identityGate(), ckQQ,
                                  rawId, event.content)
      if not auth.allowed:
        log.warn("qq: unauthorized message from " &
                 (if auth.identified: $auth.userId else: "unidentified sender"))
        (hasEvent, event) = qqAdapter.tryRecvEvent()
        continue
      let userId = auth.userId
      let approvalReply = tryHandleApprovalInput(userId, event.content)
      if approvalReply.isSome:
        qqAdapter.send(OutboundMessage(
          userId: userId, channel: ckQQ, text: approvalReply.get,
          replyTo: event.messageId)).isOkOr:
          log.error("qq send approval reply failed: " & error)
        (hasEvent, event) = qqAdapter.tryRecvEvent()
        continue
      let msg = InboundMessage(
        userId: userId,
        channel: ckQQ,
        channelId: event.messageId,
        text: event.content,
      )
      let command = decideCommandRequest(CommandRequest(channel: ckQQ, text: event.content))
      let shared = qqInSharedSpace(event)
      if command.route == crCallback:
        let callback = decideCallbackRequest(CallbackRequest(channel: ckQQ, data: command.value))
        case callback.route
        of cbrUi:
          discard handleQQUiCallback(msg, callback, qqAdapter, env.memory,
                                     env.modelCatalogLoader, event.userId)
        of cbrSessionTask:
          discard enqueueSessionTask(sm, msgSeq, userId, callbackTaskKind(callback),
                                     callback.value, ckQQ, event.messageId)
        else:
          handleSessionFallback(msg)
      elif command.route == crUi and
           handleQQUiCommand(msg, command, qqAdapter, env.memory,
                             env.modelCatalogLoader, event.userId):
        ## Keyboards on the official backend.
        discard
      elif shared and requesterOnlyCommand(command):
        ## QQ has no private path from a group: refuse before minting or
        ## consuming anything.
        ## The official API only accepts passive replies: carry the message id.
        qqAdapter.send(OutboundMessage(userId: userId, channel: ckQQ,
                                       text: RequesterOnlyNotice,
                                       replyTo: event.messageId)).isOkOr:
          log.error("qq send notice failed for user=" & $userId & " reason=" & error)
      elif command.route == crStatus and command.kind == cmdStatus and
           qqAdapter.kind == qbkOfficial:
        let text = qqStatusText(buildProviderStatusLine(env.memory, userId),
                                env.memory.getCurrentThinkLevel(userId), env.toolsCount,
                                sm.sessionCount(), qqUptimeText(env.daemonStartMs))
        qqAdapter.send(OutboundMessage(userId: userId, channel: ckQQ, text: text)).isOkOr:
          log.error("qq send status failed for user=" & $userId & " reason=" & error)
      else:
        let outcome = dispatchCommand(env.commands, sm, msgSeq,
          commandRequest(command, userId, ckQQ, event.messageId, rawId,
                         qqAdapter.resolver))
        case outcome.kind
        of cokFallback:
          handleSessionFallback(msg)
        of cokAccepted:
          discard
        of cokReply:
          if outcome.reply.shouldSend:
            let (_, delivered) = replyDelivery(outcome.reply, shared,
                                               hasPrivatePath = false)
            let text =
              if outcome.reply.topic == rtHelp: qqHelpText(qqAdapter.kind)
              else: delivered
            qqAdapter.send(OutboundMessage(
              userId: userId, channel: ckQQ, text: text,
              replyTo: if outcome.reply.topic == rtUi: msg.channelId else: "",
            )).isOkOr:
              log.error("qq send " & $outcome.reply.topic & " failed for user=" &
                        $userId & " reason=" & error)
    (hasEvent, event) = qqAdapter.tryRecvEvent()
