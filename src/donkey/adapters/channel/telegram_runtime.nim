import std/[os, strutils, tables]
import chronos/asyncsync
import parsetoml
import results
import ../../core/commands/command_routing
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../app/session_manager
import ../../domain/agent_message
import ../../domain/message
import ../../ports/provider
import ./telegram

const ThinkLevels* = ["off", "low", "medium", "high"]

const ModelMenu* = [
  ("zhipu",      @["glm-4.7",    "glm-4-plus",   "glm-z1-flash"]),
  ("openrouter", @["openai/gpt-4o-mini", "openai/gpt-4o", "anthropic/claude-opus-4-6"]),
  ("anthropic",  @["claude-opus-4-6",   "claude-sonnet-4-6"]),
  ("gemini",     @["gemini-2.0-flash",  "gemini-2.5-pro"]),
  ("minimax",    @["MiniMax-M2",        "MiniMax-Text-01"]),
]

type
  TelegramPrefs* = object
    provider*: string
    model*:    string
    thinking*: string

proc defaultTelegramPrefs*(): TelegramPrefs =
  TelegramPrefs(provider: "zhipu", model: "", thinking: "off")

proc parseTelegramPrefs*(preferencesMd: string): TelegramPrefs =
  result = defaultTelegramPrefs()
  if preferencesMd.len == 0:
    return
  try:
    {.cast(gcsafe).}:
      let t = parsetoml.parseString(preferencesMd)
      if t.hasKey("provider"):
        result.provider = t["provider"].getStr()
      if t.hasKey("model"):
        result.model = t["model"].getStr()
      if t.hasKey("thinking"):
        result.thinking = t["thinking"].getStr("off")
  except:
    discard

proc loadTelegramPrefs*(memory: MdFileAdapter; userId: UserId): TelegramPrefs =
  parseTelegramPrefs(memory.loadContext(userId).preferencesMd)

proc getCurrentThinkLevel*(memory: MdFileAdapter; userId: UserId): string =
  memory.loadTelegramPrefs(userId).thinking

proc buildThinkButtons*(memory: MdFileAdapter;
                        userId: UserId): seq[seq[(string, string)]] =
  let curr = memory.getCurrentThinkLevel(userId)
  var row: seq[(string, string)]
  for lvl in ThinkLevels:
    let label = if lvl == curr: "✓ " & lvl else: lvl
    row.add((label, "think:set:" & lvl))
  @[row]

proc getCurrentProviderModel*(memory: MdFileAdapter;
                              userId: UserId): (string, string) =
  let prefs = memory.loadTelegramPrefs(userId)
  (prefs.provider, prefs.model)

proc buildProviderButtons*(memory: MdFileAdapter;
                           userId: UserId): seq[seq[(string, string)]] =
  let (currProv, _) = memory.getCurrentProviderModel(userId)
  result = @[]
  for (prov, _) in ModelMenu:
    let label = if prov == currProv: "✓ " & prov else: prov
    result.add(@[(label, "models:provider:" & prov)])

proc buildModelButtons*(memory: MdFileAdapter;
                        provider: string;
                        userId: UserId): seq[seq[(string, string)]] =
  let (currProv, currModel) = memory.getCurrentProviderModel(userId)
  result = @[]
  for (prov, models) in ModelMenu:
    if prov != provider:
      continue
    var row: seq[(string, string)]
    for model in models:
      let label = if prov == currProv and model == currModel: "✓ " & model else: model
      row.add((label, "models:set:" & prov & ":" & model))
      if row.len == 2:
        result.add(row)
        row = @[]
    if row.len > 0:
      result.add(row)
  result.add(@[("← voltar", "models:back")])

proc saveTelegramPreference*(memory: MdFileAdapter;
                             userId: UserId;
                             key, value: string) =
  let ctx = memory.loadContext(userId)
  var lines = ctx.preferencesMd.splitLines()
  var found = false
  for i in 0 ..< lines.len:
    if lines[i].startsWith(key):
      lines[i] = key & " = \"" & value & "\""
      found = true
  if not found:
    lines.add(key & " = \"" & value & "\"")
  memory.savePreferences(userId, lines.join("\n"))

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
                           memory: MdFileAdapter): bool =
  if command.kind != cmdModels:
    return false
  let kbdId = tgAdapter.sendKeyboard(msg.userId,
    "Escolha o provider:", memory.buildProviderButtons(msg.userId),
    replyTo = msg.channelId).valueOr: ""
  if kbdId.len > 0:
    kbdMsgIds[$msg.userId] = kbdId
  true

proc handleTelegramModelCallback*(msg: InboundMessage;
                                  callback: CallbackDecision;
                                  tgAdapter: var TelegramAdapter;
                                  kbdMsgIds: var Table[string, string];
                                  memory: MdFileAdapter): bool =
  case callback.kind
  of cbkModelsProvider:
    let kbdId = kbdMsgIds.getOrDefault($msg.userId)
    if kbdId.len > 0:
      tgAdapter.editKeyboard(msg.userId, kbdId,
                             memory.buildModelButtons(callback.provider, msg.userId)).isOkOr:
        discard
    return true

  of cbkModelsSet:
    memory.saveTelegramPreference(msg.userId, "provider", callback.provider)
    memory.saveTelegramPreference(msg.userId, "model", callback.model)
    tgAdapter.clearTelegramKeyboard(kbdMsgIds, msg.userId)
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    "✅ Modelo definido: <b>" & callback.provider & " / " & callback.model & "</b>",
      replyTo: msg.channelId,
    )).isOkOr:
      discard
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
    tgAdapter.clearTelegramKeyboard(kbdMsgIds, msg.userId)
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    "🧠 Thinking: <b>" & level & "</b>",
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
  let thinkId = tgAdapter.sendKeyboard(msg.userId,
    "Nível de raciocínio:", memory.buildThinkButtons(msg.userId),
    replyTo = msg.channelId).valueOr: ""
  if thinkId.len > 0:
    kbdMsgIds[$msg.userId] = thinkId
  true

proc handleTelegramUiCommand*(msg: InboundMessage;
                              command: CommandDecision;
                              tgAdapter: var TelegramAdapter;
                              kbdMsgIds: var Table[string, string];
                              memory: MdFileAdapter): bool =
  case command.kind
  of cmdModels:
    handleTelegramModels(msg, command, tgAdapter, kbdMsgIds, memory)
  of cmdThink:
    handleTelegramThink(msg, command, tgAdapter, kbdMsgIds, memory)
  else:
    false

proc handleTelegramUiCallback*(msg: InboundMessage;
                               callback: CallbackDecision;
                               tgAdapter: var TelegramAdapter;
                               kbdMsgIds: var Table[string, string];
                               memory: MdFileAdapter): bool =
  handleTelegramModelCallback(msg, callback, tgAdapter, kbdMsgIds, memory) or
    handleTelegramThinkingCallback(msg, callback, tgAdapter, kbdMsgIds, memory)

proc buildTelegramStatusText*(memory: MdFileAdapter;
                              userId: UserId;
                              toolsCount: int;
                              sessionCount: int;
                              daemonStartMs: int64): string =
  let (provider, model) = memory.getCurrentProviderModel(userId)
  let thinking = memory.getCurrentThinkLevel(userId)
  let ctx = memory.loadContext(userId)
  let memLines = ctx.memoryMd.countLines()
  let uptimeSec = (nowMs() - daemonStartMs) div 1_000
  let uptimeStr = if uptimeSec < 60: $uptimeSec & "s"
                  elif uptimeSec < 3600: $(uptimeSec div 60) & "m"
                  else: $(uptimeSec div 3600) & "h " & $((uptimeSec mod 3600) div 60) & "m"
  "<b>📊 Status</b>\n\n" &
    "🤖 Provider: <b>" & provider & " / " & model & "</b>\n" &
    "🧠 Thinking: <b>" & thinking & "</b>\n" &
    "🔧 Tools: <b>" & $toolsCount & "</b>\n" &
    "💬 Sessões ativas: <b>" & $sessionCount & "</b>\n" &
    "📝 Memórias: <b>" & $memLines & " linhas</b>\n" &
    "⏱ Uptime: <b>" & uptimeStr & "</b>"

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
               "🏓 pong — <b>" & prov & " / " & mdl & "</b> — <b>" & $delta & "ms</b>"
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
      text:    "Olá! Sou o Donkey 🫏, seu assistente pessoal.\n\n" &
               "Envie qualquer mensagem para começarmos.\n" &
               "Use /help para ver os comandos disponíveis.",
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of lcaGenerateLinkCode:
    let code = tgAdapter.resolver.generateLinkCode(msg.userId)
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    "Your link code: `" & code & "` (valid 10 minutes)\n" &
               "Type `/continue " & code & "` on Discord to reconnect.",
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
    var report = "<b>🩺 Donkey Doctor</b>\n\n"
    let testFn = completeBuilder("")
    var history = newHistory()
    history.addUser("ping")
    let req = buildPrompt("Reply with one word: pong", history, "")
    let resp = testFn(req)
    if resp.isOk:
      report.add("✅ Provider: OK\n")
    else:
      report.add("❌ Provider: " & resp.error & "\n")
    let mpath = memory.paddocksDir
    report.add(if dirExists(mpath): "✅ Memory dir: " & mpath & "\n"
               else: "❌ Memory dir missing: " & mpath & "\n")
    report.add("🔧 Tools loaded: " & $toolsCount & "\n")
    report.add("🔌 MCP clients: " & $toolClientsCount & "\n")
    report.add("💬 Active sessions: " & $sm.sessionCount() & "\n")
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
      text:    "<b>Donkey 🫏</b> — comandos disponíveis:\n\n" &
               "/start — apresentação\n" &
               "/help — esta mensagem\n" &
               "/reset — reinicia a conversa atual\n" &
               "/models — seleciona o modelo de IA\n" &
               "/think — controla o nível de raciocínio\n" &
               "/memory — exibe memórias salvas\n" &
               "/forget — apaga as memórias salvas\n" &
               "/status — snapshot da sessão atual\n" &
               "/ping — testa latência do provider\n" &
               "/debug — ativa/desativa modo verbose (tokens, tool calls)\n" &
               "/doctor — diagnóstico do sistema\n" &
               "/mycode — gera código de linkagem cross-channel\n" &
               "/continue <code> — conecta este canal a outra sessão\n\n" &
               "Envie qualquer mensagem para conversar. " &
               "Imagens e documentos são aceitos.",
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
    let replyText = if linked: "✅ Sessão reconectada! Seu histórico foi preservado."
                    else: "❌ Código inválido ou expirado. Gere um novo com /mycode."
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
                            toolClientsCount: int;
                            toolsCount: int;
                            msgSeq: var int;
                            daemonStartMs: int64): bool =
  let command = decideCommandRequest(CommandRequest(channel: msg.channel, text: msg.text))
  case command.route
  of crLocal:
    return handleTelegramCoreCommand(sm, msg, command, tgAdapter, memory,
                                     completeBuilder, toolsCount, toolClientsCount, msgSeq)
  of crSessionTask:
    return handleTelegramTaskCommand(sm, msg, command, tgAdapter, msgSeq)
  of crUi:
    return handleTelegramUiCommand(msg, command, tgAdapter, kbdMsgIds, memory)
  of crCallback:
    let callback = decideCallbackRequest(CallbackRequest(channel: msg.channel, data: command.value))
    case callback.route
    of cbrUi:
      handleTelegramUiCallback(msg, callback, tgAdapter, kbdMsgIds, memory)
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
