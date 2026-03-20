import std/[os, strutils, tables]
import chronos/asyncsync
import parsetoml
import results
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

  TelegramCallbackKind* = enum
    tckUnknown
    tckModelsProvider
    tckModelsSet
    tckModelsBack
    tckThinkSet
    tckCore

  TelegramCallback* = object
    kind*:     TelegramCallbackKind
    provider*: string
    model*:    string
    value*:    string

  TelegramCoreCommandKind* = enum
    tcmdNone
    tcmdStart
    tcmdForget
    tcmdDoctor
    tcmdHelp
    tcmdMemory
    tcmdDebug
    tcmdReset
    tcmdMyCode
    tcmdContinue

  TelegramCoreCommand* = object
    kind*:  TelegramCoreCommandKind
    value*: string

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

proc parseTelegramCallback*(data: string): TelegramCallback =
  if data.startsWith("models:provider:"):
    return TelegramCallback(
      kind: tckModelsProvider,
      provider: data[16 .. ^1],
    )
  if data.startsWith("models:set:"):
    let parts = data[11 .. ^1].split(':', 1)
    if parts.len == 2:
      return TelegramCallback(
        kind: tckModelsSet,
        provider: parts[0],
        model: parts[1],
      )
  if data == "models:back":
    return TelegramCallback(kind: tckModelsBack)
  if data.startsWith("think:set:"):
    return TelegramCallback(kind: tckThinkSet, value: data[10 .. ^1])
  if data.startsWith("personality:") or data.startsWith("name:"):
    return TelegramCallback(kind: tckCore, value: data)
  TelegramCallback(kind: tckUnknown)

proc parseTelegramCoreCommand*(cmd: string): TelegramCoreCommand =
  case cmd
  of "/start": TelegramCoreCommand(kind: tcmdStart)
  of "/forget": TelegramCoreCommand(kind: tcmdForget)
  of "/doctor": TelegramCoreCommand(kind: tcmdDoctor)
  of "/help": TelegramCoreCommand(kind: tcmdHelp)
  of "/memory": TelegramCoreCommand(kind: tcmdMemory)
  of "/debug": TelegramCoreCommand(kind: tcmdDebug)
  of "/reset": TelegramCoreCommand(kind: tcmdReset)
  of "/mycode": TelegramCoreCommand(kind: tcmdMyCode)
  else:
    if cmd.startsWith("/continue "):
      TelegramCoreCommand(kind: tcmdContinue, value: cmd[10 .. ^1].strip)
    else:
      TelegramCoreCommand(kind: tcmdNone)

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
                           cmd: string;
                           tgAdapter: var TelegramAdapter;
                           kbdMsgIds: var Table[string, string];
                           memory: MdFileAdapter): bool =
  if cmd != "/models":
    return false
  let kbdId = tgAdapter.sendKeyboard(msg.userId,
    "Escolha o provider:", memory.buildProviderButtons(msg.userId),
    replyTo = msg.channelId).valueOr: ""
  if kbdId.len > 0:
    kbdMsgIds[$msg.userId] = kbdId
  true

proc handleTelegramModelCallback*(msg: InboundMessage;
                                  data: string;
                                  tgAdapter: var TelegramAdapter;
                                  kbdMsgIds: var Table[string, string];
                                  memory: MdFileAdapter): bool =
  let callback = parseTelegramCallback(data)
  case callback.kind
  of tckModelsProvider:
    let kbdId = kbdMsgIds.getOrDefault($msg.userId)
    if kbdId.len > 0:
      tgAdapter.editKeyboard(msg.userId, kbdId,
                             memory.buildModelButtons(callback.provider, msg.userId)).isOkOr:
        discard
    return true

  of tckModelsSet:
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

  of tckModelsBack:
    let kbdId = kbdMsgIds.getOrDefault($msg.userId)
    if kbdId.len > 0:
      tgAdapter.editKeyboard(msg.userId, kbdId,
                             memory.buildProviderButtons(msg.userId)).isOkOr:
        discard
    return true

  else:
    false

proc handleTelegramThinkingCallback*(msg: InboundMessage;
                                     data: string;
                                     tgAdapter: var TelegramAdapter;
                                     kbdMsgIds: var Table[string, string];
                                     memory: MdFileAdapter): bool =
  let callback = parseTelegramCallback(data)
  if callback.kind != tckThinkSet:
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
                          cmd: string;
                          tgAdapter: var TelegramAdapter;
                          kbdMsgIds: var Table[string, string];
                          memory: MdFileAdapter): bool =
  if cmd != "/think":
    return false
  let thinkId = tgAdapter.sendKeyboard(msg.userId,
    "Nível de raciocínio:", memory.buildThinkButtons(msg.userId),
    replyTo = msg.channelId).valueOr: ""
  if thinkId.len > 0:
    kbdMsgIds[$msg.userId] = thinkId
  true

proc handleTelegramUiCommand*(msg: InboundMessage;
                              cmd: string;
                              tgAdapter: var TelegramAdapter;
                              kbdMsgIds: var Table[string, string];
                              memory: MdFileAdapter): bool =
  case cmd
  of "/models":
    handleTelegramModels(msg, cmd, tgAdapter, kbdMsgIds, memory)
  of "/think":
    handleTelegramThink(msg, cmd, tgAdapter, kbdMsgIds, memory)
  else:
    false

proc handleTelegramUiCallback*(msg: InboundMessage;
                               data: string;
                               tgAdapter: var TelegramAdapter;
                               kbdMsgIds: var Table[string, string];
                               memory: MdFileAdapter): bool =
  handleTelegramModelCallback(msg, data, tgAdapter, kbdMsgIds, memory) or
    handleTelegramThinkingCallback(msg, data, tgAdapter, kbdMsgIds, memory)

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
                         cmd: string;
                         tgAdapter: var TelegramAdapter;
                         memory: MdFileAdapter;
                         completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.}): bool =
  if cmd != "/ping":
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
                           cmd: string;
                           tgAdapter: var TelegramAdapter;
                           memory: MdFileAdapter;
                           toolsCount: int;
                           sessionCount: int;
                           daemonStartMs: int64): bool =
  if cmd != "/status":
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
                                cmd: string;
                                tgAdapter: var TelegramAdapter;
                                memory: MdFileAdapter;
                                completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                                toolsCount: int;
                                toolClientsCount: int;
                                msgSeq: var int): bool =
  let coreCommand = parseTelegramCoreCommand(cmd)
  case coreCommand.kind
  of tcmdStart:
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
  of tcmdMyCode:
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
  of tcmdForget:
    memory.clearMemory(msg.userId)
    tgAdapter.send(OutboundMessage(
      userId:  msg.userId,
      channel: ckTelegram,
      text:    "🗑️ Memórias apagadas.",
      replyTo: msg.channelId,
    )).isOkOr:
      discard
    return true
  of tcmdDoctor:
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
  of tcmdHelp:
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
  of tcmdMemory:
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
  of tcmdDebug:
    if sm.hasSession(msg.userId):
      let entry = sm.getOrCreate(msg.userId)
      inc msgSeq
      entry.inbox.addLastNoWait(
        newTaskMsg($msgSeq, tkDebugToggle, $msg.userId, "", ckTelegram, msg.channelId))
    else:
      tgAdapter.send(OutboundMessage(
        userId:  msg.userId,
        channel: ckTelegram,
        text:    "Nenhuma sessão ativa. Envie uma mensagem primeiro.",
        replyTo: msg.channelId,
      )).isOkOr:
        discard
    return true
  of tcmdReset:
    if sm.hasSession(msg.userId):
      let entry = sm.getOrCreate(msg.userId)
      inc msgSeq
      entry.inbox.addLastNoWait(
        newTaskMsg($msgSeq, tkReset, $msg.userId, "", ckTelegram, msg.channelId))
    else:
      tgAdapter.send(OutboundMessage(
        userId:  msg.userId,
        channel: ckTelegram,
        text:    "Nenhuma conversa ativa para reiniciar.",
        replyTo: msg.channelId,
      )).isOkOr:
        discard
    return true
  of tcmdContinue:
    let rawTgId = tgAdapter.resolver.reverseChannel(msg.userId, ckTelegram)
    let linked = tgAdapter.resolver.consumeLinkCode(coreCommand.value, ckTelegram, rawTgId)
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

proc handleTelegramCoreCallback*(sm: var SessionManager;
                                 msg: InboundMessage;
                                 data: string;
                                 msgSeq: var int): bool =
  let callback = parseTelegramCallback(data)
  if callback.kind == tckCore:
    let entry = sm.getOrCreate(msg.userId)
    inc msgSeq
    let tk = if callback.value.startsWith("name:"): tkNameChoice else: tkPersonalityChoice
    entry.inbox.addLastNoWait(
      newTaskMsg($msgSeq, tk, $msg.userId, callback.value, ckTelegram, msg.channelId))
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
  let cmd = msg.text |> strip
  if handleTelegramCoreCommand(sm, msg, cmd, tgAdapter, memory,
                               completeBuilder, toolsCount, toolClientsCount, msgSeq):
    return true
  if handleTelegramUiCommand(msg, cmd, tgAdapter, kbdMsgIds, memory):
    return true
  if cmd.startsWith("/callback "):
    let data = cmd[10 .. ^1] |> strip
    if handleTelegramUiCallback(msg, data, tgAdapter, kbdMsgIds, memory):
      return true
    if handleTelegramCoreCallback(sm, msg, data, msgSeq):
      return true
  if handleTelegramPing(msg, cmd, tgAdapter, memory, completeBuilder):
    return true
  if handleTelegramStatus(msg, cmd, tgAdapter, memory,
                          toolsCount, sm.sessionCount(), daemonStartMs):
    return true
  false
