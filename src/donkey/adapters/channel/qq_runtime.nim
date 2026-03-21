import std/strutils
import chronos/asyncsync
import ../../core/commands/command_routing
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ./common_runtime
import ./qq_channel

func qqSupportsRichUi*(kind: QQBackendKind): bool =
  kind == qbkOfficial

func qqHelpText*(kind: QQBackendKind): string =
  if not qqSupportsRichUi(kind):
    return buildHelpText(false)
  "## Donkey\n\n" &
    "- `/start` apresentação\n" &
    "- `/help` esta ajuda\n" &
    "- `/models` seletor de modelo\n" &
    "- `/think` seletor de raciocínio\n" &
    "- `/memory` mostra memórias\n" &
    "- `/forget` apaga memórias\n" &
    "- `/status` visão geral da sessão\n" &
    "- `/ping` testa o provider\n" &
    "- `/debug` alterna modo verbose\n" &
    "- `/doctor` diagnóstico do sistema\n" &
    "- `/mycode` gera código de linkagem\n" &
    "- `/continue <code>` conecta este QQ a outra sessão\n" &
    "- `/reset` reinicia a conversa atual"

func qqDirectModelProvider*(kind: QQBackendKind;
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
                         page, totalPages: int;
                         catalog: ModelCatalogResult): string =
  qqPickerText(
    buildModelPageTitle(provider, page, totalPages),
    buildCatalogSourceText(catalog),
  )

func qqProviderPickerTitle*(): string =
  qqPickerText("Escolha o provider", "Selecione a família de modelos para abrir o catálogo.")

func qqThinkPickerTitle*(): string =
  qqPickerText("Nível de raciocínio", "Escolha quanta deliberação o agente deve usar.")

func qqModelConfirmedText*(provider, model: string): string =
  qqPickerText("Modelo definido", "**" & provider & " / " & model & "**")

func qqThinkingConfirmedText*(level: string): string =
  qqPickerText("Thinking definido", "**" & level & "**")

func qqStatusText*(provider, model, thinking: string;
                   toolsCount, sessionCount: int;
                   uptimeStr: string): string =
  "## Status\n\n" &
    "- Provider: **" & provider & " / " & model & "**\n" &
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
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    qqAdapter.sendKeyboard(
      msg.userId,
      qqModelPickerTitle(
        callback.provider, 0,
        pageCount(normalizeModelCatalog(callback.provider, catalog.entries)),
        catalog),
      buildModelPageButtons(callback.provider, catalog.entries, currProv, currModel, 0),
      replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        discard
    true
  of cbkModelsSet:
    memory.saveChannelPreference(msg.userId, "provider", callback.provider)
    memory.saveChannelPreference(msg.userId, "model", callback.model)
    qqAdapter.send(OutboundMessage(
      userId: msg.userId,
      channel: ckQQ,
      text: qqModelConfirmedText(callback.provider, callback.model),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    true
  of cbkModelsPage:
    let catalog = modelCatalogLoader(callback.provider).valueOr: emptyCatalogResult()
    let (currProv, currModel) = memory.getCurrentProviderModel(msg.userId)
    qqAdapter.sendKeyboard(
      msg.userId,
      qqModelPickerTitle(
        callback.provider, callback.page,
        pageCount(normalizeModelCatalog(callback.provider, catalog.entries)),
        catalog),
      buildModelPageButtons(callback.provider, catalog.entries, currProv, currModel, callback.page),
      replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        discard
    true
  of cbkModelsBack:
    qqAdapter.sendKeyboard(
      msg.userId,
      qqProviderPickerTitle(),
      memory.buildProviderButtons(msg.userId),
      replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        discard
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
    memory.saveChannelPreference(msg.userId, "thinking", level)
    qqAdapter.send(OutboundMessage(
      userId: msg.userId,
      channel: ckQQ,
      text: qqThinkingConfirmedText(level),
      replyTo: msg.channelId,
    )).isOkOr:
      discard
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
        qqAdapter.sendKeyboard(
          msg.userId,
          qqModelPickerTitle(
            provider, 0,
            pageCount(normalizeModelCatalog(provider, catalog.entries)),
            catalog),
          buildModelPageButtons(provider, catalog.entries, currProv, currModel, 0),
          replyTo = msg.channelId,
          allowedRawUserId = rawUserId).isOkOr:
            discard
        return true
    if command.value.strip.len > 0 or qqAdapter.kind != qbkOfficial:
      let reply = memory.applyModelsTextCommand(msg.userId, command.value, modelCatalogLoader).valueOr: error
      qqAdapter.send(OutboundMessage(userId: msg.userId, channel: ckQQ, text: reply, replyTo: msg.channelId)).isOkOr:
        discard
      return true
    qqAdapter.sendKeyboard(msg.userId, qqProviderPickerTitle(),
      memory.buildProviderButtons(msg.userId), replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        discard
    true
  of cmdThink:
    if not qqShouldOpenThinkPicker(qqAdapter.kind, command):
      let reply = memory.applyThinkTextCommand(msg.userId, command.value).valueOr: error
      qqAdapter.send(OutboundMessage(userId: msg.userId, channel: ckQQ, text: reply, replyTo: msg.channelId)).isOkOr:
        discard
      return true
    qqAdapter.sendKeyboard(msg.userId, qqThinkPickerTitle(),
      memory.buildThinkButtons(msg.userId), replyTo = msg.channelId,
      allowedRawUserId = rawUserId).isOkOr:
        discard
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

proc drainQQEvents*(qqAdapter: var QQChannelAdapter;
                    sm: var SessionManager;
                    memory: MdFileAdapter;
                    completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                    modelCatalogLoader: ModelCatalogLoader;
                    toolsCount: int;
                    toolClientsCount: int;
                    daemonStartMs: int64;
                    msgSeq: var int;
                    handleSessionFallback: proc(msg: InboundMessage) {.gcsafe.}) =
  if not qqAdapter.enabled():
    return

  var (hasEvent, event) = qqAdapter.tryRecvEvent()
  while hasEvent:
    if event.content.strip.len > 0:
      let userId = qqAdapter.resolveUser(event)
      let msg = InboundMessage(
        userId: userId,
        channel: ckQQ,
        channelId: event.messageId,
        text: event.content,
      )
      let command = decideCommandRequest(CommandRequest(channel: ckQQ, text: event.content))
      case command.route
      of crLocal:
        case decideLocalCommandAction(command)
        of lcaStartIntro:
          qqAdapter.send(OutboundMessage(userId: userId, channel: ckQQ, text: buildStartIntroText())).isOkOr: discard
        of lcaGenerateLinkCode:
          qqAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckQQ,
            text: buildLinkCodeText(qqAdapter.generateLinkCode(userId)),
          )).isOkOr: discard
        of lcaClearMemory:
          memory.clearMemory(userId)
          qqAdapter.send(OutboundMessage(userId: userId, channel: ckQQ, text: "Memórias apagadas.")).isOkOr: discard
        of lcaDoctorReport:
          qqAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckQQ,
            text: buildDoctorReport(memory, completeBuilder, userId, toolsCount, toolClientsCount, sm.sessionCount()),
          )).isOkOr: discard
        of lcaHelpText:
          qqAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckQQ,
            text: qqHelpText(qqAdapter.kind),
          )).isOkOr: discard
        of lcaShowMemory:
          let memText = memory.loadContext(userId).memoryMd.strip
          qqAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckQQ,
            text: if memText.len > 0: memText else: "Nenhuma memória salva ainda.",
          )).isOkOr: discard
        of lcaContinueLink:
          let linked = qqAdapter.consumeLinkCode(command.value, qqRawIdentity(event))
          qqAdapter.send(OutboundMessage(
            userId: userId,
            channel: ckQQ,
            text: buildContinueResultText(linked),
          )).isOkOr: discard
        else:
          discard
      of crSessionTask:
        if sm.hasSession(userId):
          let entry = sm.getOrCreate(userId)
          inc msgSeq
          entry.inbox.addLastNoWait(
            newTaskMsg($msgSeq, commandTaskKind(command), $userId, "", ckQQ, event.messageId))
        else:
          let text =
            if command.kind == cmdDebug:
              "Nenhuma sessão ativa. Envie uma mensagem primeiro."
            else:
              "Nenhuma conversa ativa para reiniciar."
          qqAdapter.send(OutboundMessage(userId: userId, channel: ckQQ, text: text)).isOkOr: discard
      of crUi:
        discard handleQQUiCommand(msg, command, qqAdapter, memory, modelCatalogLoader, event.userId)
      of crPing:
        qqAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckQQ,
          text: buildPingText(memory, userId, completeBuilder),
        )).isOkOr: discard
      of crStatus:
        let (provider, model) = memory.getCurrentProviderModel(userId)
        let thinking = memory.getCurrentThinkLevel(userId)
        let uptimeSec = (nowMs() - daemonStartMs) div 1_000
        let uptimeStr =
          if uptimeSec < 60: $uptimeSec & "s"
          elif uptimeSec < 3600: $(uptimeSec div 60) & "m"
          else: $(uptimeSec div 3600) & "h " & $((uptimeSec mod 3600) div 60) & "m"
        qqAdapter.send(OutboundMessage(
          userId: userId,
          channel: ckQQ,
          text:
            if qqAdapter.kind == qbkOfficial:
              qqStatusText(provider, model, thinking, toolsCount, sm.sessionCount(), uptimeStr)
            else:
              buildTextStatusText(memory, userId, toolsCount, sm.sessionCount(), daemonStartMs),
        )).isOkOr: discard
      of crCallback:
        let callback = decideCallbackRequest(CallbackRequest(channel: ckQQ, data: command.value))
        case callback.route
        of cbrUi:
          discard handleQQUiCallback(msg, callback, qqAdapter, memory, modelCatalogLoader, event.userId)
        of cbrSessionTask:
          if sm.hasSession(userId):
            let entry = sm.getOrCreate(userId)
            inc msgSeq
            entry.inbox.addLastNoWait(
              newTaskMsg($msgSeq, callbackTaskKind(callback), $userId, callback.value, ckQQ, event.messageId))
        else:
          handleSessionFallback(msg)
      of crNone:
        handleSessionFallback(msg)
    (hasEvent, event) = qqAdapter.tryRecvEvent()
