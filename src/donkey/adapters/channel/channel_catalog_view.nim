## Channel catalog views: provider/model menu derivation, catalog pagination
## and the model/think/budget text command helpers.
##
## Pure text and pagination only — no message callbacks or UI state.

import std/[algorithm, os, sequtils, strutils, times]
import results
import ../../core/pipeops
import ../../core/commands/command_routing
import ../../core/types
import ../../core/providers/smart_routing
import ../../core/providers/provider_catalog
import ../../adapters/memory/md_file
import ../../ports/provider
import ./channel_prefs
import ./channel_ui_types

var modelMenuCache: seq[ModelMenuEntry]

proc buildModelMenu*(): seq[ModelMenuEntry] =
  ## Derives the model menu from the ProviderCatalog, so the UI always
  ## reflects what is actually registered as the source of truth.
  ##
  ## Providers with no catalog entries (e.g. "zen", a meta-provider that
  ## fetches models dynamically) still appear with an empty model list to
  ## keep the menu backwards-compatible.
  {.cast(gcsafe).}:
    if modelMenuCache.len > 0:
      return modelMenuCache
  let cat = buildDefaultCatalog()
  var providers = cat.allProviders()
  providers.sort()  # deterministic ordering
  for provider in providers:
    let entries = cat.getByProvider(provider)
    let models = entries.mapIt(it.canonicalName)
    result.add((provider, models))
  # Providers not in the catalog but still referenced in routing:
  result.add(("zen", @[]))
  {.cast(gcsafe).}:
    modelMenuCache = result

proc modelMenu*(): seq[ModelMenuEntry] =
  ## Returns the model menu derived from the ProviderCatalog.
  buildModelMenu()

proc supportedProviders*(): seq[string] =
  for (provider, _) in modelMenu():
    result.add(provider)

proc supportedModels*(provider: string): seq[string] =
  for (candidate, models) in modelMenu():
    if candidate == provider:
      return models
  @[]

func emptyCatalogResult*(): ModelCatalogResult =
  ModelCatalogResult(entries: @[], source: mcsFallback, fetchedAtUnix: 0)

func availableProvidersFromEnv*(): ProviderAvailability =
  ## Credential presence for the channel status line. Exported so the surface
  ## tests can assert it without a message loop.
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
    nvidia: getEnv("NVIDIA_API_KEY").len > 0,
    alibaba: getEnv("DASHSCOPE_API_KEY").len > 0,
    fireworks: getEnv("FIREWORKS_API_KEY").len > 0,
  )

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

proc parseModelsArgs*(value: string): Result[(string, string), string] =
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

proc parseModelsProviderArg*(value: string): Result[string, string] =
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
  ? memory.saveChannelPreferences(userId, [("provider", provider), ("model", model)])
  ok("Modelo definido: " & provider & " / " & model)

proc applyThinkTextCommand*(memory: MdFileAdapter;
                            userId: UserId;
                            value: string): Result[string, string] =
  if value.strip.len == 0:
    return ok(memory.buildThinkHelpText(userId))
  let level = ? parseThinkArgs(value)
  ? memory.saveChannelPreference(userId, "thinking", level)
  ok("Thinking definido: " & level)

proc applyBudgetTextCommand*(memory: MdFileAdapter;
                             userId: UserId;
                             value: string): Result[string, string] =
  if value.strip.len == 0:
    return ok(memory.buildBudgetHelpText(userId))
  let policy = ? parseBudgetArgs(value)
  ? memory.saveChannelPreference(userId, "budget", policy)
  ok("Budget definido: " & policy)

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
