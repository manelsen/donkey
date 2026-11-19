## Interactive channel UI: model callback registry, presentation slots,
## keyboards/buttons, menus and the channel-facing text surfaces.

import std/[locks, os, strutils, tables]
import checksums/sha1
import results
import ../../core/commands/command_catalog
import ../../core/outbound/outbound
import ../../core/pipeops
import ../../core/utf8
import ../../core/providers/smart_routing
import ../../adapters/memory/md_file
import ../../domain/message
import ../../ports/provider
import ../../app/skill_runtime
import ./channel_catalog_view
import ./channel_prefs
import ./channel_ui_types
when defined(withPostgres) or defined(withSqlite):
  import ../../adapters/memory/magma_memory_adapter

type ModelCallbackTarget = object
  provider: string
  model: string

var modelCallbackTargets: Table[string, ModelCallbackTarget]
var modelCallbackLock: Lock
initLock(modelCallbackLock)

func modelCallbackToken(provider, model: string): string =
  "mt" & ($secureHash(provider & "\0" & model)).toLowerAscii()[0 ..< 12]

proc registerModelCallback*(provider, model: string): string {.gcsafe.} =
  ## Telegram limits callback_data to 64 bytes; OpenRouter model ids routinely
  ## exceed it. Register the full id and put a short stable token in the button.
  let token = modelCallbackToken(provider, model)
  {.cast(gcsafe).}:
    withLock modelCallbackLock:
      modelCallbackTargets[token] = ModelCallbackTarget(
        provider: provider, model: model)
  token

proc resolveModelCallback*(provider, value: string): string {.gcsafe, raises: [].} =
  ## Resolves a compact model token. Legacy full model names still work.
  var target: ModelCallbackTarget
  {.cast(gcsafe).}:
    withLock modelCallbackLock:
      target = modelCallbackTargets.getOrDefault(value)
  if target.model.len > 0:
    return if target.provider == provider: target.model else: ""
  if value.len == 14 and value.startsWith("mt"):
    return ""
  value

func uiSlotKey*(userId: UserId; slot: string): string =
  $userId & "|" & slot

proc getUiMsgId*(state: PresentationState;
                 channel: ChannelKind;
                 userId: UserId;
                 slot: string): string =
  state.replacementMsgIds.getOrDefault(replacementSurfaceKey(channel, userId, slot))

proc setUiMsgId*(state: var PresentationState;
                 channel: ChannelKind;
                 userId: UserId;
                 slot, msgId: string) =
  if msgId.len > 0:
    state.replacementMsgIds[replacementSurfaceKey(channel, userId, slot)] = msgId

proc clearUiMsgId*(state: var PresentationState;
                   channel: ChannelKind;
                   userId: UserId;
                   slot: string) =
  state.replacementMsgIds.del(replacementSurfaceKey(channel, userId, slot))

func donkeyHomeDir*(memory: MdFileAdapter): string =
  donkeyHomeDirFromPaddocks(memory.paddocksDir)

func userSkillsPath*(memory: MdFileAdapter; userId: UserId): string =
  skill_runtime.userSkillsPath(memory.paddockDir(userId))

proc buildThinkButtons*(memory: MdFileAdapter;
                        userId: UserId): seq[seq[(string, string)]] =
  let curr = memory.getCurrentThinkLevel(userId)
  var row: seq[(string, string)]
  for lvl in ThinkLevels:
    let label = if lvl == curr: "✓ " & lvl else: lvl
    row.add((label, "think:set:" & lvl))
  @[row]

proc buildProviderButtons*(memory: MdFileAdapter;
                           userId: UserId): seq[seq[(string, string)]] =
  let (currProv, _) = memory.getCurrentProviderModel(userId)
  result = @[]
  var row: seq[(string, string)]
  for (prov, _) in modelMenu():
    let label = if prov == currProv: "✓ " & prov else: prov
    row.add((label, "models:provider:" & prov))
    if row.len == 3:
      result.add(row)
      row = @[]
  if row.len > 0:
    result.add(row)

proc buildModelButtons*(memory: MdFileAdapter;
                        provider: string;
                        userId: UserId): seq[seq[(string, string)]] =
  let (currProv, currModel) = memory.getCurrentProviderModel(userId)
  result = @[]
  for (prov, models) in modelMenu():
    if prov != provider:
      continue
    var row: seq[(string, string)]
    for model in models:
      let rawLabel = if prov == currProv and model == currModel: "✓ " & model else: model
      let label = clipUtf8(rawLabel, 60)
      row.add((label, "models:set:" & prov & ":" & registerModelCallback(prov, model)))
      if row.len == 2:
        result.add(row)
        row = @[]
    if row.len > 0:
      result.add(row)
  result.add(@[("← voltar", "models:back")])

proc buildModelPageButtons*(provider: string;
                            entries: seq[ModelCatalogEntry];
                            currentProvider: string;
                            currentModel: string;
                            page: int): seq[seq[(string, string)]] =
  let safePage = clampPage(page, entries)
  var row: seq[(string, string)]
  for entry in pageEntries(entries, safePage):
    let selected = provider == currentProvider and entry.modelName == currentModel
    let alreadyTagged = entry.isFree and entry.label.toLowerAscii().contains("free")
    let freeTag = if entry.isFree and not alreadyTagged: " [free]" else: ""
    let prefix = if selected: "✓ " else: ""
    let baseLabel = prefix & entry.label
    let label = clipUtf8(baseLabel, max(0, 60 - freeTag.len)) & freeTag
    row.add((label, "models:set:" & provider & ":" &
             registerModelCallback(provider, entry.modelName)))
    if row.len == 2:
      result.add(row)
      row = @[]
  if row.len > 0:
    result.add(row)

  ## Navegação em única linha (máx 5 botões permitidos por row no Discord)
  var navRow: seq[(string, string)]
  if safePage > 0:
    navRow.add(("← ant", "models:page:" & provider & ":" & $(safePage - 1)))
  if safePage + 1 < pageCount(entries):
    navRow.add(("próx →", "models:page:" & provider & ":" & $(safePage + 1)))
  navRow.add(("← voltar", "models:back"))
  result.add(navRow)

proc applySkillTextCommand*(memory: MdFileAdapter;
                            userId: UserId;
                            value: string;
                            homeDir = "";
                            registry = "";
                            searchBackend: skill_runtime.SkillSearchBackend = nil;
                            installBackend: skill_runtime.SkillInstallBackend = nil): Result[string, string] =
  skill_runtime.applySkillCommand(
    memory.paddockDir(userId),
    value,
    homeDir = if homeDir.len > 0: homeDir else: memory.donkeyHomeDir(),
    registry = registry,
    searchBackend = searchBackend,
    installBackend = installBackend,
  )

proc buildProviderStatusLine*(memory: MdFileAdapter; userId: UserId): string =
  let prefs = parseSmartRoutingPrefs(memory.loadContext(userId).preferencesMd)
  let availability = availableProvidersFromEnv()
  let (provider, model) = memory.getCurrentProviderModel(userId)
  if prefs.usesSmartRouting:
    let preview = formatSelectionPreview(previewSmartRouteSelections(prefs, availability))
    if preview.len > 0:
      "Provider: auto [" & prefs.budgetPolicy & "] (" & preview & ")"
    else:
      "Provider: auto [" & prefs.budgetPolicy & "]"
  else:
    "Provider: " & provider & " / " & model

proc buildTextStatusText*(memory: MdFileAdapter;
                          userId: UserId;
                          toolsCount: int;
                          sessionCount: int;
                          daemonStartMs: int64): string =
  let ctx = memory.loadContext(userId)
  let memLines = ctx.memoryMd.countLines()
  let uptimeSec = (nowMs() - daemonStartMs) div 1_000
  let uptimeStr = if uptimeSec < 60: $uptimeSec & "s"
                  elif uptimeSec < 3600: $(uptimeSec div 60) & "m"
                  else: $(uptimeSec div 3600) & "h " & $((uptimeSec mod 3600) div 60) & "m"
  let providerLine = buildProviderStatusLine(memory, userId)
  let prefs = memory.loadChannelPrefs(userId)
  "Status\n\n" &
    providerLine & "\n" &
    "Thinking: " & prefs.thinking & "\n" &
    "Reasoning: " & prefs.reasoning & "\n" &
    "Tools: " & $toolsCount & "\n" &
    "Sessões ativas: " & $sessionCount & "\n" &
    "Memórias: " & $memLines & " linhas\n" &
    "Uptime: " & uptimeStr

proc buildAboutText*(memory: MdFileAdapter;
                     userId: UserId;
                     toolsCount: int;
                     toolClientsCount: int;
                     sessionCount: int): string =
  let (prov, mdl) = memory.getCurrentProviderModel(userId)
  let storage =
    if getEnv("DONKEY_PG_DSN").strip.len > 0 or memory.magmaDsn.len > 0:
      "PostgreSQL-backed MAGMA"
    elif memory.magmaSqlitePath.len > 0:
      "SQLite-first MAGMA (" & memory.magmaSqlitePath & ")"
    else:
      "Markdown paddocks"
  let webSearch =
    if getEnv("BRAVE_API_KEY").len > 0: "enabled"
    else: "disabled"
  var channels: seq[string] = @[]
  if getEnv("TELEGRAM_BOT_TOKEN").len > 0: channels.add("Telegram")
  if getEnv("DISCORD_BOT_TOKEN").len > 0: channels.add("Discord")
  if getEnv("WECOM_CORP_ID").len > 0: channels.add("WeCom")
  if getEnv("WECHAT_APP_ID").len > 0 or getEnv("WECHAT_CALLBACK_TOKEN").len > 0: channels.add("WeChat")
  if getEnv("FEISHU_APP_ID").len > 0: channels.add("Feishu")
  if getEnv("QQ_ONEBOT_URL").len > 0 or getEnv("QQ_OFFICIAL_APP_ID").len > 0: channels.add("QQ")
  "🫏 *Donkey*\n\n" &
    "*Provider atual:* `" & prov & " / " & mdl & "`\n" &
    "*Storage:* " & storage & "\n" &
    "*Web search:* " & webSearch & "\n" &
    "*Channels ativos:* " & (if channels.len > 0: channels.join(", ") else: "nenhum") & "\n" &
    "*Ferramentas:* " & $toolsCount & " nativas, " & $toolClientsCount & " clientes MCP\n" &
    "*Sessões ativas:* " & $sessionCount & "\n\n" &
    "Use `/doctor` para checagem completa, `/status` para a sessão atual e `/memory` para ver memória."

func buildWhoamiText*(userId: UserId; sessionId, channelId: string): string =
  "🆔 *Identity*\n\n" &
  "*Donkey ID:* `" & $userId & "`\n" &
  "*Session ID:* " & (if sessionId.len > 0: "`" & sessionId & "`" else: "_nenhuma_") & "\n" &
  "*Channel ID:* `" & channelId & "`"

func formatHelpCommandLine(line: string; withBackticks: bool): string =
  if not withBackticks:
    return line
  let sep = line.find(" — ")
  if sep < 0:
    return "`" & line & "`"
  "`" & line[0 ..< sep] & "`" & line[sep .. ^1]

func appendCatalogLines(lines: var seq[string];
                        catalog: CommandCatalog;
                        categories: openArray[CommandCategory];
                        surface: CommandSurface;
                        interactiveUi: bool;
                        withBackticks: bool;
                        indent = "";
                        includeCategoryTitle = false) =
  for category in categories:
    let commands = catalog.commandsForCategories([category], surface)
    if commands.len == 0:
      continue
    if includeCategoryTitle:
      lines.add(indent & "*" & categoryNamePt(category) & "*")
    for cmd in commands:
      let line = cmd.usageFor(interactiveUi) & " — " & cmd.helpSummaryFor(interactiveUi)
      lines.add(indent & formatHelpCommandLine(line, withBackticks))
      for detail in cmd.menuDetails:
        lines.add(indent & "  " & formatHelpCommandLine(detail, withBackticks))
    if includeCategoryTitle:
      lines.add("")

proc buildMenuButtons*(): seq[seq[(string, string)]] =
  ## Main menu buttons grouped by category.
  @[
    @[("🔍 Modelos", "models"), ("🧠 Thinking", "think"), ("💭 Reasoning", "reasoning")],
    @[("💰 Budget", "budget"), ("📖 Ajuda", "help"), ("📊 Status", "status")],
    @[("🩺 Doctor", "doctor"), ("🗑️ Esquecer", "forget"), ("♻️ Reset", "reset")],
    @[("🔗 My Code", "mycode")]
  ]

func buildMenuText*(): string =
  let catalog = newCommandCatalog()
  var lines = @[
    "🫏 *Donkey Menu*",
    "",
    "Selecione uma categoria ou comando abaixo para configurar sua sessão ou obter informações.",
    "",
  ]
  appendCatalogLines(
    lines,
    catalog,
    defaultMenuCategories(),
    csMenu,
    interactiveUi = true,
    withBackticks = false,
    includeCategoryTitle = true,
  )
  lines.join("\n").strip()

proc buildConfigButtons*(): seq[seq[(string, string)]] =
  ## Configuration menu buttons.
  @[
    @[("🔍 Selecionar Provider", "models")],
    @[("🧠 Nível de Thinking", "think"), ("💭 Toggle Reasoning", "reasoning")],
    @[("💰 Policy de Budget", "budget")],
    @[("← voltar ao menu", "menu")]
  ]

proc buildConfigText*(memory: MdFileAdapter; userId: UserId): string =
  let prefs = memory.loadChannelPrefs(userId)
  let (currProv, currModel) = memory.getCurrentProviderModel(userId)
  "⚙️ *Configurações da Sessão*\n\n" &
  "*Provider:* `" & currProv & "`\n" &
  "*Modelo:* `" & currModel & "`\n" &
  "*Thinking:* `" & prefs.thinking & "`\n" &
  "*Reasoning:* `" & prefs.reasoning & "`\n" &
  "*Budget:* `" & prefs.budget & "`\n\n" &
  "Use os botões abaixo para alterar as configurações."

func buildTasksText*(): string =
  "🕒 *Tarefas Ativas*\n\n" &
  "- `deliverDueReminders`: Entrega de lembretes agendados (Ativo)\n" &
  "- `heartbeatLoop`: Verificação de saúde do sistema (Ativo)\n\n" &
  "Nenhuma outra tarefa em execução no momento."

func buildAgentsText*(toolsCount, toolClientsCount: int): string =
  "🤖 *Agentes & Ferramentas*\n\n" &
  "*Ferramentas nativas:* " & $toolsCount & " carregadas\n" &
  "*Clientes MCP:* " & $toolClientsCount & " conectados\n\n" &
  "O assistente está pronto para usar as capacidades de navegação, shell e manipulação de arquivos."

func buildPollText*(): string =
  "🗳️ *Aprovações Pendentes*\n\n" &
  "Nenhuma solicitação de aprovação pendente no momento.\n\n" &
  "Quando uma ferramenta exigir sua confirmação (ex: deletar arquivo), ela aparecerá aqui."

func buildStartIntroText*(): string =
  "Olá! Sou o Donkey, seu assistente pessoal.\n\n" &
  "Envie qualquer mensagem para começarmos.\n" &
  "Use /help para ver os comandos disponíveis."

func buildHelpPages*(): seq[(string, string)] =
  ## Returns (title, body) per page for paginated help embeds (Discord).
  let catalog = newCommandCatalog()
  for section in defaultHelpSections():
    var sectionLines: seq[string]
    appendCatalogLines(sectionLines, catalog,
      section.categories, csHelp, interactiveUi = true, withBackticks = true)
    result.add((section.title, sectionLines.join("\n")))

func buildHelpNavButtons*(page, total: int): seq[seq[(string, string)]] =
  var row: seq[(string, string)]
  if page > 0:
    row.add(("◀ Anterior", "help:page:" & $(page - 1)))
  if page < total - 1:
    row.add(("Próximo ▶", "help:page:" & $(page + 1)))
  if row.len > 0: @[row] else: @[]

func buildHelpText*(interactiveUi: bool): string =
  let catalog = newCommandCatalog()
  var lines = @["Donkey — comandos disponíveis:", ""]
  appendCatalogLines(
    lines,
    catalog,
    defaultMenuCategories(),
    csHelp,
    interactiveUi,
    withBackticks = false,
    includeCategoryTitle = true,
  )
  lines.join("\n").strip()

when defined(withPostgres) or defined(withSqlite):
  proc noopDoctorEmbedFn(text: string): seq[float32] {.gcsafe, used.} = @[]

proc buildDoctorReport*(memory: MdFileAdapter;
                        completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                        userId: UserId;
                        toolsCount: int;
                        toolClientsCount: int;
                        sessionCount: int): string =
  var report = "🩺 Donkey Doctor\n\n"
  
  ## Teste do provider ativo do usuário (não o default da instância)
  let t0 = nowMs()
  let userPrefs = memory.loadContext(userId).preferencesMd
  let testFn = completeBuilder(userPrefs)
  var history = newHistory()
  history.addUser("ping")
  let req = buildPrompt("Reply with one word: pong", history, "")
  let resp = testFn(req)
  let delta = nowMs() - t0
  if resp.isOk:
    report.add("✅ Provider: OK (" & $delta & "ms)\n")
  else:
    let clipped = clipUtf8(resp.error.strip, 300)
    report.add("❌ Provider: " & clipped & "\n")
  
  ## Modelo atual
  let (prov, mdl) = memory.getCurrentProviderModel(userId)
  report.add("📦 Modelo: " & prov & " / " & mdl & "\n")

  when defined(withPostgres) or defined(withSqlite):
    if memory.hasMagmaBackend:
      try:
        let magma = memory.newMagmaAdapter()
        let stats = magma.stats()
        report.add(
          "🧠 Multigraph Memory: nodes=" & $stats.totalNodes &
          " memory=" & $stats.memoryNodes &
          " profiles=" & $stats.profileNodes &
          " prefs=" & $stats.preferenceNodes &
          " entities=" & $stats.entityNodes &
          " embeddings=" & $stats.embeddingNodes &
          " edges=" & $stats.totalEdges & "\n"
        )
      except CatchableError:
        report.add("❌ Multigraph Memory: failed to read graph stats\n")
  
  ## Diretório de memória
  let mpath = memory.paddocksDir
  if dirExists(mpath):
    var size = 0
    for kind, path in walkDir(mpath):
      inc size
    report.add("📁 Memory dir (debug): " & mpath & " (" & $size & " arquivos)\n")
  else:
    report.add("❌ Memory dir missing (debug): " & mpath & "\n")
  
  ## Tools e MCP
  report.add("🔧 Tools loaded: " & $toolsCount & "\n")
  report.add("🔌 MCP clients: " & $toolClientsCount & "\n")
  
  ## Sessões ativas
  report.add("👥 Active sessions: " & $sessionCount & "\n")
  
  ## Canais ativos (verifica identidade)
  var channels: seq[string] = @[]
  if getEnv("TELEGRAM_BOT_TOKEN").len > 0: channels.add("Telegram")
  if getEnv("DISCORD_BOT_TOKEN").len > 0: channels.add("Discord")
  if getEnv("FEISHU_APP_ID").len > 0: channels.add("Feishu")
  if getEnv("WECOM_CORP_ID").len > 0: channels.add("WeCom")
  if channels.len > 0:
    report.add("📡 Active channels: " & channels.join(", ") & "\n")
  else:
    report.add("📡 Active channels: nenhum\n")
  
  ## Environment checks
  let envVars = [
    ("OPENROUTER_API_KEY", "OpenRouter"),
    ("ZAI_API_KEY", "Zhipu"),
    ("ANTHROPIC_API_KEY", "Anthropic"),
    ("OPENAI_API_KEY", "OpenAI"),
    ("DEEPSEEK_API_KEY", "DeepSeek"),
    ("GROQ_API_KEY", "Groq"),
    ("GEMINI_API_KEY", "Gemini"),
    ("MINIMAX_API_KEY", "MiniMax"),
    ("NVIDIA_API_KEY", "NVIDIA NIM"),
    ("DASHSCOPE_API_KEY", "Alibaba DashScope"),
    ("FIREWORKS_API_KEY", "Fireworks AI"),
  ]
  var configuredProviders: seq[string] = @[]
  for (envVar, name) in envVars:
    if getEnv(envVar).len > 0:
      configuredProviders.add(name)
  if configuredProviders.len > 0:
    report.add("🔑 API keys: " & configuredProviders.join(", ") & "\n")
  else:
    report.add("🔑 API keys: nenhuma configurada\n")
  
  report

proc buildMemoryBootstrapSnapshot(userMd, preferencesMd, sourceLabel: string): string =
  var sections: seq[string]
  if sourceLabel.len > 0:
    sections.add(sourceLabel)
  if userMd.strip.len > 0:
    sections.add("👤 Perfil\n" & userMd.strip)
  if preferencesMd.strip.len > 0:
    sections.add("⚙️ Preferências\n" & preferencesMd.strip)
  sections.add("📝 Memória episódica\nNenhuma memória salva ainda.")
  sections.join("\n\n")

proc clearMemoryReply*(memory: MdFileAdapter; userId: UserId;
                       cleared = "Memórias apagadas."): string =
  ## Clears the user's memory and returns what to tell them. The reply only
  ## confirms what happened: when nothing was cleared it says so.
  let res = memory.clearMemory(userId)
  if res.isOk: cleared
  else: "Não foi possível apagar as memórias: " & res.error

proc buildMemoryViewText*(memory: MdFileAdapter; userId: UserId): string =
  let markdownPath = memory.memoryMdPath(userId)
  let markdownText =
    if fileExists(markdownPath): readFile(markdownPath).strip
    else: ""
  let markdownUserText =
    if fileExists(memory.userMdPath(userId)): readFile(memory.userMdPath(userId)).strip
    else: ""
  let markdownPrefsText =
    if fileExists(memory.preferencesMdPath(userId)): readFile(memory.preferencesMdPath(userId)).strip
    else: ""
  when defined(withPostgres) or defined(withSqlite):
    if memory.hasMagmaBackend:
      try:
        let magma = memory.newMagmaAdapter()
        let graphCtx = magma.loadContext(userId)
        let graphText = graphCtx.memoryMd.strip
        if graphText.len > 0:
          return "🧠 Multigraph Memory\n" & graphText
        if graphCtx.userMd.strip.len > 0 or graphCtx.preferencesMd.strip.len > 0:
          return buildMemoryBootstrapSnapshot(
            graphCtx.userMd,
            graphCtx.preferencesMd,
            "🧠 Multigraph Memory",
          )
      except CatchableError:
        discard
      if markdownText.len > 0:
        return "📄 Markdown fallback\n" & markdownText
      if markdownUserText.len > 0 or markdownPrefsText.len > 0:
        return buildMemoryBootstrapSnapshot(
          markdownUserText,
          markdownPrefsText,
          "📄 Markdown fallback",
        )
      return "Nenhuma memória salva ainda."
  if markdownText.len > 0:
    return markdownText
  if markdownUserText.len > 0 or markdownPrefsText.len > 0:
    return buildMemoryBootstrapSnapshot(markdownUserText, markdownPrefsText, "")
  else:
    "Nenhuma memória salva ainda."

proc buildPingText*(memory: MdFileAdapter;
                    userId: UserId;
                    completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.}): string =
  let t0 = nowMs()
  let (prov, mdl) = memory.getCurrentProviderModel(userId)
  let pingFn = completeBuilder("provider = \"" & prov & "\"\nmodel = \"" & mdl & "\"")
  var history = newHistory()
  history.addUser("ping")
  let req = buildPrompt("Reply with one word: pong", history, "")
  let resp = pingFn(req)
  let delta = nowMs() - t0
  if resp.isOk:
    "pong — " & prov & " / " & mdl & " — " & $delta & "ms"
  else:
    prov & " error: " & resp.error

func buildLinkCodeText*(code: string): string =
  "Your link code: `" & code & "` (valid 10 minutes)\n" &
  "Use `/continue <code>` on another channel to reconnect."

func buildContinueResultText*(linked: bool): string =
  if linked:
    "Sessão reconectada! Seu histórico foi preservado."
  else:
    "Código inválido ou expirado. Gere um novo com /mycode."
