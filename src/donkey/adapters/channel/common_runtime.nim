import std/[algorithm, os, sequtils, strutils, times]
import parsetoml
import results
import ../../core/pipeops
import ../../adapters/memory/md_file
import ../../domain/message
import ../../ports/provider

const ThinkLevels* = ["off", "low", "medium", "high"]
const ModelPageSize* = 8

const ModelMenu* = [
  ("zai",        @["glm-5",      "glm-4.7",      "glm-4.6"]),
  ("zai-coding", @["glm-5",      "glm-4.7",      "glm-4.6"]),
  ("zen",        @[]),
  ("groq",       @["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "openai/gpt-oss-20b"]),
  ("openrouter", @["openai/gpt-4o-mini", "openai/gpt-4o", "anthropic/claude-opus-4-6"]),
  ("anthropic",  @["claude-opus-4-6",   "claude-sonnet-4-6"]),
  ("gemini",     @["gemini-2.0-flash",  "gemini-2.5-pro"]),
  ("minimax",    @["MiniMax-M2",        "MiniMax-Text-01"]),
]

type
  ChannelPrefs* = object
    provider*: string
    model*:    string
    thinking*: string

func defaultChannelPrefs*(): ChannelPrefs =
  ChannelPrefs(provider: "zai-coding", model: "", thinking: "off")

func emptyCatalogResult*(): ModelCatalogResult =
  ModelCatalogResult(entries: @[], source: mcsFallback, fetchedAtUnix: 0)

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

func buildModelPageTitle*(provider: string; page, totalPages: int): string =
  "Modelos de " & provider & " — página " & $(page + 1) & "/" & $max(totalPages, 1)

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
  let sorted = sortModelCatalog(normalizeModelCatalog(provider, entries))
  let safePage = clampPage(page, sorted)
  for entry in pageEntries(sorted, safePage):
    let selected = provider == currentProvider and entry.modelName == currentModel
    let freeTag = if entry.isFree: " [free]" else: ""
    let label = (if selected: "✓ " else: "") & entry.label & freeTag
    result.add(@[(label, "models:set:" & provider & ":" & entry.modelName)])
  var nav: seq[(string, string)]
  if safePage > 0:
    nav.add(("← anterior", "models:page:" & provider & ":" & $(safePage - 1)))
  if safePage + 1 < pageCount(sorted):
    nav.add(("próxima →", "models:page:" & provider & ":" & $(safePage + 1)))
  if nav.len > 0:
    result.add(nav)
  result.add(@[("← voltar", "models:back")])

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

proc buildModelsHelpText*(memory: MdFileAdapter;
                          userId: UserId;
                          modelCatalogLoader: ModelCatalogLoader = nil): string =
  let (provider, model) = memory.getCurrentProviderModel(userId)
  let providerText = supportedProviders().join(", ")
  var text = "Provider atual: " & provider
  if model.len > 0:
    text.add(" / " & model)
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

proc buildTextStatusText*(memory: MdFileAdapter;
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
  "Status\n\n" &
    "Provider: " & provider & " / " & model & "\n" &
    "Thinking: " & thinking & "\n" &
    "Tools: " & $toolsCount & "\n" &
    "Sessões ativas: " & $sessionCount & "\n" &
    "Memórias: " & $memLines & " linhas\n" &
    "Uptime: " & uptimeStr

func buildStartIntroText*(): string =
  "Olá! Sou o Donkey, seu assistente pessoal.\n\n" &
  "Envie qualquer mensagem para começarmos.\n" &
  "Use /help para ver os comandos disponíveis."

func buildHelpText*(interactiveUi: bool): string =
  "Donkey — comandos disponíveis:\n\n" &
    "/start — apresentação\n" &
    "/help — esta mensagem\n" &
    "/reset — reinicia a conversa atual\n" &
    (if interactiveUi:
       "/models — seleciona o modelo de IA\n" &
       "/think — controla o nível de raciocínio\n"
     else:
       "/models [provider model] — vê ou troca o modelo de IA\n" &
       "/think [level] — vê ou troca o nível de raciocínio\n") &
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
  var report = "Donkey Doctor\n\n"
  let testFn = completeBuilder("")
  var history = newHistory()
  history.addUser("ping")
  let req = buildPrompt("Reply with one word: pong", history, "")
  let resp = testFn(req)
  if resp.isOk:
    report.add("Provider: OK\n")
  else:
    report.add("Provider: " & resp.error & "\n")
  let mpath = memory.paddocksDir
  report.add(if dirExists(mpath): "Memory dir: " & mpath & "\n"
             else: "Memory dir missing: " & mpath & "\n")
  report.add("Tools loaded: " & $toolsCount & "\n")
  report.add("MCP clients: " & $toolClientsCount & "\n")
  report.add("Active sessions: " & $sessionCount & "\n")
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
