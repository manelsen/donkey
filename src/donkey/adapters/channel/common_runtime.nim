import std/[algorithm, os, sequtils, strutils, times]
import parsetoml
import results
import ../../core/pipeops
import ../../core/providers/smart_routing
import ../../adapters/memory/md_file
import ../../domain/message
import ../../ports/provider

const ThinkLevels* = ["off", "low", "medium", "high"]
const BudgetPolicies* = ["cheap-first", "balanced", "quality-first"]
const ModelPageSize* = 6  ## Discord: máx 5 action rows. 6 modelos / 2 por row = 3 rows + 1 nav = 4 rows (seguro)

const ModelMenu* = [
  ("zai",        @["glm-5",      "glm-4.7",      "glm-4.6"]),
  ("zai-coding", @["glm-5",      "glm-4.7",      "glm-4.6"]),
  ("zen",        @[]),
  ("groq",       @["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "openai/gpt-oss-20b"]),
  ("openrouter", @["openai/gpt-4o-mini", "openai/gpt-4o", "anthropic/claude-opus-4-6"]),
  ("anthropic",  @["claude-opus-4-6",   "claude-sonnet-4-6"]),
  ("gemini",     @["gemini-2.5-flash",  "gemini-2.5-pro"]),
  ("minimax",    @["MiniMax-M2",        "MiniMax-Text-01"]),
]

type
  ChannelPrefs* = object
    provider*: string
    model*:    string
    thinking*: string
    budget*:   string

func defaultChannelPrefs*(): ChannelPrefs =
  ChannelPrefs(provider: "zai-coding", model: "", thinking: "off", budget: "balanced")

func emptyCatalogResult*(): ModelCatalogResult =
  ModelCatalogResult(entries: @[], source: mcsFallback, fetchedAtUnix: 0)

func availableProvidersFromEnv(): ProviderAvailability =
  ProviderAvailability(
    openrouter: getEnv("OPENROUTER_API_KEY").len > 0,
    anthropic: getEnv("ANTHROPIC_API_KEY").len > 0,
    gemini: getEnv("GEMINI_API_KEY").len > 0,
    minimax: getEnv("MINIMAX_API_KEY").len > 0,
    zai: getEnv("ZAI_API_KEY").len > 0,
    zaiCoding: getEnv("ZAI_CODING_API_KEY", getEnv("ZHIPU_API_KEY")).len > 0,
  )

proc parseChannelPrefs*(preferencesMd: string): ChannelPrefs =
  result = defaultChannelPrefs()
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
      if t.hasKey("budget"):
        result.budget = normalizeBudgetPolicy(t["budget"].getStr("balanced"))
  except:
    discard

proc loadChannelPrefs*(memory: MdFileAdapter; userId: UserId): ChannelPrefs =
  parseChannelPrefs(memory.loadContext(userId).preferencesMd)

proc saveChannelPreference*(memory: MdFileAdapter;
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

proc getCurrentProviderModel*(memory: MdFileAdapter;
                              userId: UserId): (string, string) =
  let prefs = memory.loadChannelPrefs(userId)
  (prefs.provider, prefs.model)

proc getCurrentThinkLevel*(memory: MdFileAdapter; userId: UserId): string =
  memory.loadChannelPrefs(userId).thinking

proc getCurrentBudgetPolicy*(memory: MdFileAdapter; userId: UserId): string =
  parseSmartRoutingPrefs(memory.loadContext(userId).preferencesMd).budgetPolicy

proc buildThinkButtons*(memory: MdFileAdapter;
                        userId: UserId): seq[seq[(string, string)]] =
  let curr = memory.getCurrentThinkLevel(userId)
  var row: seq[(string, string)]
  for lvl in ThinkLevels:
    let label = if lvl == curr: "✓ " & lvl else: lvl
    row.add((label, "think:set:" & lvl))
  @[row]

func supportedProviders*(): seq[string] =
  for (provider, _) in ModelMenu:
    result.add(provider)

func supportedModels*(provider: string): seq[string] =
  for (candidate, models) in ModelMenu:
    if candidate == provider:
      return models
  @[]

proc buildProviderButtons*(memory: MdFileAdapter;
                           userId: UserId): seq[seq[(string, string)]] =
  let (currProv, _) = memory.getCurrentProviderModel(userId)
  result = @[]
  var row: seq[(string, string)]
  for (prov, _) in ModelMenu:
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

func normalizeModelCatalog*(provider: string;
                            entries: seq[ModelCatalogEntry]): seq[ModelCatalogEntry] =
  for entry in entries:
    if entry.providerName == provider:
      result.add(entry)

func sortModelCatalog*(entries: seq[ModelCatalogEntry]): seq[ModelCatalogEntry] =
  result = entries
  result.sort(proc(a, b: ModelCatalogEntry): int =
    if a.isFree != b.isFree:
      return if a.isFree: -1 else: 1
    cmp(a.label.toLowerAscii(), b.label.toLowerAscii())
  )

func pageCount*(entries: seq[ModelCatalogEntry]; pageSize = ModelPageSize): int =
  if entries.len == 0: return 1
  (entries.len + pageSize - 1) div pageSize

func clampPage*(page: int; entries: seq[ModelCatalogEntry]; pageSize = ModelPageSize): int =
  min(max(page, 0), max(pageCount(entries, pageSize) - 1, 0))

func pageEntries*(entries: seq[ModelCatalogEntry];
                  page: int;
                  pageSize = ModelPageSize): seq[ModelCatalogEntry] =
  let safePage = clampPage(page, entries, pageSize)
  let start = safePage * pageSize
  let stop = min(start + pageSize, entries.len)
  if start >= stop:
    return @[]
  entries[start ..< stop]

func buildModelPageTitle*(provider: string; page: int; entries: seq[ModelCatalogEntry]): string =
  "Modelos de " & provider & " — página " & $(page + 1) & "/" & $max(pageCount(entries), 1)

proc buildCatalogSourceText*(catalog: ModelCatalogResult): string =
  let sourceText = catalogSourceLabel(catalog.source)
  if catalog.source == mcsFallback or catalog.fetchedAtUnix <= 0:
    "Fonte: " & sourceText
  else:
    "Fonte: " & sourceText & " (" & relativeAgeText(getTime().toUnix() - catalog.fetchedAtUnix) & ")"

func buildModelPageButtons*(provider: string;
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
    let label = (if selected: "✓ " else: "") & entry.label & freeTag
    row.add((label, "models:set:" & provider & ":" & entry.modelName))
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

func parseModelsArgs*(value: string): Result[(string, string), string] =
  let parts = value.splitWhitespace()
  if parts.len != 2:
    return err("Use `/models <provider> <model>`.")
  let provider = parts[0]
  let model = parts[1]
  if provider notin supportedProviders():
    return err("Provider inválido: `" & provider & "`.")
  let models = supportedModels(provider)
  if models.len > 0 and model notin models:
    return err("Modelo inválido para `" & provider & "`: `" & model & "`.")
  ok((provider, model))

func parseModelsProviderArg*(value: string): Result[string, string] =
  let parts = value.splitWhitespace()
  if parts.len != 1:
    return err("Use `/models <provider>`.")
  let provider = parts[0]
  if provider notin supportedProviders():
    return err("Provider inválido: `" & provider & "`.")
  ok(provider)

func formatModelCatalogLine(entry: ModelCatalogEntry): string =
  "- `" & entry.modelName & "`" & (if entry.isFree: " [free]" else: "")

proc buildProviderCatalogText(provider: string;
                              catalog: ModelCatalogResult): string =
  let sorted = sortModelCatalog(normalizeModelCatalog(provider, catalog.entries))
  result = "Provider: " & provider
  if sorted.len > 0:
    result.add("\nModelos:\n" & sorted.map(formatModelCatalogLine).join("\n"))
  else:
    result.add("\nNenhum modelo listado no catálogo atual.")
  result.add("\n" & buildCatalogSourceText(catalog))
  result.add("\n\nUse `/models " & provider & " <model>` para trocar.")

func parseThinkArgs*(value: string): Result[string, string] =
  let level = value.strip.toLowerAscii()
  if level.len == 0:
    return err("Use `/think <off|low|medium|high>`.")
  if level notin ThinkLevels:
    return err("Nível inválido: `" & level & "`.")
  ok(level)

func parseBudgetArgs*(value: string): Result[string, string] =
  let policy = normalizeBudgetPolicy(value)
  if value.strip.len == 0:
    return err("Use `/budget <cheap-first|balanced|quality-first>`.")
  if policy != value.strip.toLowerAscii():
    return err("Policy inválida: `" & value.strip & "`.")
  ok(policy)

proc buildModelsHelpText*(memory: MdFileAdapter;
                          userId: UserId;
                          modelCatalogLoader: ModelCatalogLoader = nil): string =
  let prefs = parseSmartRoutingPrefs(memory.loadContext(userId).preferencesMd)
  let availability = availableProvidersFromEnv()
  let (provider, model) = memory.getCurrentProviderModel(userId)
  let providerText = supportedProviders().join(", ")
  var text =
    if prefs.usesSmartRouting:
      "Provider atual: auto [" & prefs.budgetPolicy & "]"
    else:
      "Provider atual: " & provider
  if model.len > 0 and not prefs.usesSmartRouting:
    text.add(" / " & model)
  if prefs.usesSmartRouting:
    let preview = formatSelectionPreview(previewSmartRouteSelections(prefs, availability))
    if preview.len > 0:
      text.add("\nRota base: " & preview)
  text.add("\n\nProviders: " & providerText)
  var catalogInfo = ""
  let currentModels =
    if modelCatalogLoader != nil:
      let catalog = modelCatalogLoader(provider).valueOr: emptyCatalogResult()
      let sorted = sortModelCatalog(normalizeModelCatalog(provider, catalog.entries))
      catalogInfo = buildCatalogSourceText(catalog)
      if sorted.len > 0: sorted.mapIt(it.modelName) else: supportedModels(provider)
    else:
      supportedModels(provider)
  if currentModels.len > 0:
    text.add("\nModelos para `" & provider & "`: " & currentModels.join(", "))
  if catalogInfo.len > 0:
    text.add("\n" & catalogInfo)
  text.add("\n\nUse `/models <provider> <model>` para trocar.")
  text

proc buildThinkHelpText*(memory: MdFileAdapter; userId: UserId): string =
  "Thinking atual: " & memory.getCurrentThinkLevel(userId) &
  "\nNíveis: " & ThinkLevels.join(", ") &
  "\n\nUse `/think <level>` para trocar."

proc buildBudgetHelpText*(memory: MdFileAdapter; userId: UserId): string =
  "Budget atual: " & memory.getCurrentBudgetPolicy(userId) &
  "\nPolicies: " & BudgetPolicies.join(", ") &
  "\n\nUse `/budget <policy>` para trocar."

proc applyModelsTextCommand*(memory: MdFileAdapter;
                             userId: UserId;
                             value: string;
                             modelCatalogLoader: ModelCatalogLoader = nil): Result[string, string] =
  if value.strip.len == 0:
    return ok(memory.buildModelsHelpText(userId, modelCatalogLoader))
  let parts = value.splitWhitespace()
  if parts.len == 1:
    let provider = parts[0]
    if provider notin supportedProviders():
      return err("Provider inválido: `" & provider & "`.")
    if modelCatalogLoader != nil:
      let catalog = modelCatalogLoader(provider).valueOr: emptyCatalogResult()
      return ok(buildProviderCatalogText(provider, catalog))
    let entries = supportedModels(provider).mapIt(
      ModelCatalogEntry(providerName: provider, modelName: it, label: it, isFree: false, available: true))
    return ok(buildProviderCatalogText(
      provider,
      ModelCatalogResult(entries: entries, source: mcsFallback, fetchedAtUnix: 0)))
  let (provider, model) = ? parseModelsArgs(value)
  if modelCatalogLoader != nil:
    let catalog = modelCatalogLoader(provider).valueOr: emptyCatalogResult()
    let normalized = normalizeModelCatalog(provider, catalog.entries)
    if normalized.len > 0 and normalized.allIt(it.modelName != model):
      return err("Modelo indisponível agora para `" & provider & "`: `" & model & "`.")
  memory.saveChannelPreference(userId, "provider", provider)
  memory.saveChannelPreference(userId, "model", model)
  ok("Modelo definido: " & provider & " / " & model)

proc applyThinkTextCommand*(memory: MdFileAdapter;
                            userId: UserId;
                            value: string): Result[string, string] =
  if value.strip.len == 0:
    return ok(memory.buildThinkHelpText(userId))
  let level = ? parseThinkArgs(value)
  memory.saveChannelPreference(userId, "thinking", level)
  ok("Thinking definido: " & level)

proc applyBudgetTextCommand*(memory: MdFileAdapter;
                             userId: UserId;
                             value: string): Result[string, string] =
  if value.strip.len == 0:
    return ok(memory.buildBudgetHelpText(userId))
  let policy = ? parseBudgetArgs(value)
  memory.saveChannelPreference(userId, "budget", policy)
  ok("Budget definido: " & policy)

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
  let thinking = memory.getCurrentThinkLevel(userId)
  let ctx = memory.loadContext(userId)
  let memLines = ctx.memoryMd.countLines()
  let uptimeSec = (nowMs() - daemonStartMs) div 1_000
  let uptimeStr = if uptimeSec < 60: $uptimeSec & "s"
                  elif uptimeSec < 3600: $(uptimeSec div 60) & "m"
                  else: $(uptimeSec div 3600) & "h " & $((uptimeSec mod 3600) div 60) & "m"
  let providerLine = buildProviderStatusLine(memory, userId)
  "Status\n\n" &
    providerLine & "\n" &
    "Thinking: " & thinking & "\n" &
    "Tools: " & $toolsCount & "\n" &
    "Sessões ativas: " & $sessionCount & "\n" &
    "Memórias: " & $memLines & " linhas\n" &
    "Uptime: " & uptimeStr

func buildWhoamiText*(userId: UserId; sessionId, channelId: string): string =
  "🆔 *Identity*\n\n" &
  "*Donkey ID:* `" & $userId & "`\n" &
  "*Session ID:* " & (if sessionId.len > 0: "`" & sessionId & "`" else: "_nenhuma_") & "\n" &
  "*Channel ID:* `" & channelId & "`"

proc buildMenuButtons*(): seq[seq[(string, string)]] =
  ## Main menu buttons grouped by category.
  @[
    @[("🔍 Modelos", "models"), ("🧠 Thinking", "think"), ("💰 Budget", "budget")],
    @[("📖 Ajuda", "help"), ("📊 Status", "status"), ("🩺 Doctor", "doctor")],
    @[("🗑️ Esquecer", "forget"), ("♻️ Reset", "reset"), ("🔗 My Code", "mycode")]
  ]

func buildMenuText*(): string =
  "🫏 *Donkey Menu*\n\n" &
  "Selecione uma categoria ou comando abaixo para configurar sua sessão ou obter informações."

proc buildConfigButtons*(): seq[seq[(string, string)]] =
  ## Configuration menu buttons.
  @[
    @[("🔍 Selecionar Provider", "models")],
    @[("🧠 Nível de Thinking", "think")],
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

func buildStartIntroText*(): string =
  "Olá! Sou o Donkey, seu assistente pessoal.\n\n" &
  "Envie qualquer mensagem para começarmos.\n" &
  "Use /help para ver os comandos disponíveis."

func buildHelpPages*(): seq[(string, string)] =
  ## Returns (title, body) per page for paginated help embeds (Discord).
  @[
    ("Conversa",
      "`/start` — apresentação\n" &
      "`/help` — esta mensagem\n" &
      "`/reset` — reinicia a conversa atual\n" &
      "`/memory` — exibe memórias salvas\n" &
      "`/forget` — apaga as memórias salvas"),
    ("Modelos & Config",
      "`/models` — seleciona o modelo de IA\n" &
      "`/think` — nível de raciocínio\n" &
      "`/budget` — policy de custo/qualidade\n" &
      "`/ping` — latência do provider"),
    ("Sistema",
      "`/status` — snapshot da sessão atual\n" &
      "`/debug` — ativa/desativa modo verbose\n" &
      "`/doctor` — diagnóstico do sistema\n" &
      "`/mycode` — gera código de linkagem cross-channel\n" &
      "`/continue <code>` — conecta a outra sessão"),
  ]

func buildHelpNavButtons*(page, total: int): seq[seq[(string, string)]] =
  var row: seq[(string, string)]
  if page > 0:
    row.add(("◀ Anterior", "help:page:" & $(page - 1)))
  if page < total - 1:
    row.add(("Próximo ▶", "help:page:" & $(page + 1)))
  if row.len > 0: @[row] else: @[]

func buildHelpText*(interactiveUi: bool): string =
  "Donkey — comandos disponíveis:\n\n" &
    "/start — apresentação\n" &
    "/help — esta mensagem\n" &
    "/reset — reinicia a conversa atual\n" &
    (if interactiveUi:
       "/models — seleciona o modelo de IA\n" &
       "/think — controla o nível de raciocínio\n" &
       "/budget — controla a policy de custo/qualidade\n"
     else:
       "/models [provider model] — vê ou troca o modelo de IA\n" &
       "/think [level] — vê ou troca o nível de raciocínio\n" &
       "/budget [policy] — vê ou troca a policy de custo/qualidade\n") &
    "/memory — exibe memórias salvas\n" &
    "/forget — apaga as memórias salvas\n" &
    "/status — snapshot da sessão atual\n" &
    "/ping — testa latência do provider\n" &
    "/debug — ativa/desativa modo verbose (tokens, tool calls)\n" &
    "/doctor — diagnóstico do sistema\n" &
    "/mycode — gera código de linkagem cross-channel\n" &
    "/continue <code> — conecta este canal a outra sessão"

proc buildDoctorReport*(memory: MdFileAdapter;
                        completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                        userId: UserId;
                        toolsCount: int;
                        toolClientsCount: int;
                        sessionCount: int): string =
  var report = "🩺 Donkey Doctor\n\n"
  
  ## Teste do provider
  let t0 = nowMs()
  let testFn = completeBuilder("")
  var history = newHistory()
  history.addUser("ping")
  let req = buildPrompt("Reply with one word: pong", history, "")
  let resp = testFn(req)
  let delta = nowMs() - t0
  if resp.isOk:
    report.add("✅ Provider: OK (" & $delta & "ms)\n")
  else:
    report.add("❌ Provider: " & resp.error & "\n")
  
  ## Modelo atual
  let (prov, mdl) = memory.getCurrentProviderModel(userId)
  report.add("📦 Modelo: " & prov & " / " & mdl & "\n")
  
  ## Diretório de memória
  let mpath = memory.paddocksDir
  if dirExists(mpath):
    var size = 0
    for kind, path in walkDir(mpath):
      inc size
    report.add("📁 Memory dir: " & mpath & " (" & $size & " arquivos)\n")
  else:
    report.add("❌ Memory dir missing: " & mpath & "\n")
  
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
    ("GEMINI_API_KEY", "Gemini"),
    ("MINIMAX_API_KEY", "MiniMax"),
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
