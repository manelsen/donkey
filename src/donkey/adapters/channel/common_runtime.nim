import std/[algorithm, os, sequtils, strutils, tables, times]
import parsetoml
import results
import ../../core/pipeops
import ../../core/commands/command_catalog
import ../../core/commands/command_routing
import ../../core/outbound/outbound
import ../../core/providers/smart_routing
import ../../adapters/memory/md_file
import ../../domain/message
import ../../ports/provider
import ../../app/skill_runtime
when defined(withPostgres) or defined(withSqlite):
  import ../../adapters/memory/magma_memory_adapter

const ThinkLevels* = ["off", "low", "medium", "high"]
const BudgetPolicies* = ["cheap-first", "balanced", "quality-first"]
const ModelPageSize* = 6  ## Discord: máx 5 action rows. 6 modelos / 2 por row = 3 rows + 1 nav = 4 rows (seguro)
const UiSlotMenu* = "menu"
const UiSlotConfig* = "config"
const UiSlotModels* = "models"
const UiSlotThink* = "think"
const UiSlotHelp* = "help"

const ModelMenu* = [
  ("zai",        @["glm-5",      "glm-4.7",      "glm-4.6"]),
  ("zai-coding", @["glm-5",      "glm-4.7",      "glm-4.6"]),
  ("zen",        @[]),
  ("groq",       @["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "openai/gpt-oss-20b"]),
  ("openrouter", @["openai/gpt-4o-mini", "openai/gpt-4o", "anthropic/claude-opus-4-6"]),
  ("anthropic",  @["claude-opus-4-6",   "claude-sonnet-4-6"]),
  ("zai-anthropic", @["glm-4.7", "glm-4.6", "glm-4.5", "glm-4.5-air"]),
  ("gemini",     @["gemini-2.5-flash",  "gemini-2.5-pro"]),
  ("minimax",    @["MiniMax-M2",        "MiniMax-Text-01"]),
]

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


func emptyCatalogResult*(): ModelCatalogResult =
  ModelCatalogResult(entries: @[], source: mcsFallback, fetchedAtUnix: 0)

func donkeyHomeDir*(memory: MdFileAdapter): string =
  donkeyHomeDirFromPaddocks(memory.paddocksDir)

func userSkillsPath*(memory: MdFileAdapter; userId: UserId): string =
  skill_runtime.userSkillsPath(memory.paddockDir(userId))

func availableProvidersFromEnv(): ProviderAvailability =
  ProviderAvailability(
    openrouter: getEnv("OPENROUTER_API_KEY").len > 0,
    anthropic: getEnv("ANTHROPIC_API_KEY").len > 0,
    zaiAnthropic: getEnv(
      "ZAI_ANTHROPIC_API_KEY",
      getEnv(
        "ANTHROPIC_AUTH_TOKEN",
        getEnv("ZAI_CODING_API_KEY", getEnv("ZAI_API_KEY", getEnv("ZHIPU_API_KEY")))
      )
    ).len > 0,
    gemini: getEnv("GEMINI_API_KEY").len > 0,
    minimax: getEnv("MINIMAX_API_KEY").len > 0,
    zai: getEnv("ZAI_API_KEY").len > 0,
    zaiCoding: getEnv("ZAI_CODING_API_KEY", getEnv("ZHIPU_API_KEY")).len > 0,
  )

when defined(withPostgres) or defined(withSqlite):
  proc noopDoctorEmbedFn(text: string): seq[float32] {.gcsafe.} = @[]

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
      if t.hasKey("reasoning"):
        result.reasoning = t["reasoning"].getStr("on")
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
  let wantedFamily =
    case provider
    of "zai", "zai-coding", "zai-anthropic":
      "zai"
    else:
      provider
  var seen: seq[string] = @[]
  for entry in entries:
    let entryFamily =
      case entry.providerName
      of "zai", "zai-coding", "zai-anthropic":
        "zai"
      else:
        entry.providerName
    if entryFamily == wantedFamily and entry.modelName notin seen:
      result.add(entry)
      seen.add(entry.modelName)

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

proc buildModelPageText*(provider: string;
                         page: int;
                         entries: seq[ModelCatalogEntry];
                         catalog: ModelCatalogResult): string =
  result = buildModelPageTitle(provider, page, entries) & "\n" & buildCatalogSourceText(catalog)
  if entries.len == 0:
    result.add("\n\nNenhum modelo disponível para este provider no catálogo atual.")

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

func buildDeferredUiCommandText*(kind: CommandKind): string =
  case kind
  of cmdVerbose:
    "Ajuste fino de verbose ainda não foi exposto por slash command. Use `/debug` para alternar o modo de debug."
  of cmdExec:
    "A policy de exec ainda não foi exposta por slash command. Ajuste isso via configuração do runtime."
  of cmdQueue:
    "A policy de fila ainda não foi exposta por slash command."
  of cmdUsage:
    "O modo de rodapé de usage ainda não foi exposto por slash command."
  of cmdTts:
    "TTS ainda não está disponível por slash command neste canal."
  else:
    ""

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
