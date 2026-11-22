## Model catalog presentation shared by the channels with pickers: the
## provider/model menu, compact callback tokens for long model ids, catalog
## paging and buttons, and the /models argument parser.

import std/[algorithm, locks, sequtils, strutils, tables, times]
import checksums/sha1
import ../../core/pipeops
import ../../core/utf8
import ../../core/commands/command_text
import ../../core/providers/provider_catalog
import ../../adapters/memory/md_file
import ../../adapters/memory/channel_prefs_store
import ../../domain/message
import ../../ports/provider
import ../../infra/thread_owner

const ModelPageSize* = 6  ## Discord: máx 5 action rows. 6 modelos / 2 por row = 3 rows + 1 nav = 4 rows (seguro)

type ModelMenuEntry* = tuple[provider: string, models: seq[string]]

## The menu and the callback tokens belong to the daemon loop, where every
## channel runtime builds menus and resolves button taps. Thread-local to it
## (gcsafe, no lock, no cast); gMenuOwner reports any other thread.
var modelMenuCache {.threadvar.}: seq[ModelMenuEntry]
var gMenuOwner: ThreadOwner

template withMenuCache(body: untyped) =
  if gMenuOwner.isOwner("model menu cache"):
    body

proc buildModelMenu*(): seq[ModelMenuEntry] =
  ## Derives the model menu from the ProviderCatalog, so the UI always
  ## reflects what is actually registered as the source of truth.
  ##
  ## Providers with no catalog entries (e.g. "zen", a meta-provider that
  ## fetches models dynamically) still appear with an empty model list to
  ## keep the menu backwards-compatible.
  withMenuCache:
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
  withMenuCache:
    modelMenuCache = result

proc modelMenu*(): seq[ModelMenuEntry] =
  ## Returns the model menu derived from the ProviderCatalog.
  buildModelMenu()

type ModelCallbackTarget = object
  provider: string
  model: string

var modelCallbackTargets {.threadvar.}: Table[string, ModelCallbackTarget]

template withCallbackTargets(body: untyped) =
  if gMenuOwner.isOwner("model callback tokens"):
    body

func modelCallbackToken(provider, model: string): string =
  "mt" & ($secureHash(provider & "\0" & model)).toLowerAscii()[0 ..< 12]

proc registerModelCallback*(provider, model: string): string {.gcsafe.} =
  ## Telegram limits callback_data to 64 bytes; OpenRouter model ids routinely
  ## exceed it. Register the full id and put a short stable token in the button.
  let token = modelCallbackToken(provider, model)
  withCallbackTargets:
    modelCallbackTargets[token] = ModelCallbackTarget(
      provider: provider, model: model)
  token

proc resolveModelCallback*(provider, value: string): string {.gcsafe, raises: [].} =
  ## Resolves a compact model token. Legacy full model names still work.
  var target: ModelCallbackTarget
  withCallbackTargets:
    target = modelCallbackTargets.getOrDefault(value)
  if target.model.len > 0:
    return if target.provider == provider: target.model else: ""
  if value.len == 14 and value.startsWith("mt"):
    return ""
  value
func emptyCatalogResult*(): ModelCatalogResult =
  ModelCatalogResult(entries: @[], source: mcsFallback, fetchedAtUnix: 0)

proc buildThinkButtons*(memory: MdFileAdapter;
                        userId: UserId): seq[seq[(string, string)]] =
  let curr = memory.getCurrentThinkLevel(userId)
  var row: seq[(string, string)]
  for lvl in ThinkLevels:
    let label = if lvl == curr: "✓ " & lvl else: lvl
    row.add((label, "think:set:" & lvl))
  @[row]

proc supportedProviders*(): seq[string] =
  for (provider, _) in modelMenu():
    result.add(provider)

proc supportedModels*(provider: string): seq[string] =
  for (candidate, models) in modelMenu():
    if candidate == provider:
      return models
  @[]

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

proc parseModelsSelection*(value: string): Result[(string, string), string] =
  ## `/models <provider> <model>`: the shape and a known provider. Whether
  ## the model is offered is checked against a catalog by the caller.
  let parts = value.splitWhitespace()
  if parts.len != 2:
    return err("Use `/models <provider> <model>`.")
  let provider = parts[0]
  if provider notin supportedProviders():
    return err("Provider inválido: `" & provider & "`.")
  ok((provider, parts[1]))

proc parseModelsArgs*(value: string): Result[(string, string), string] =
  ## parseModelsSelection checked against the static model list.
  let (provider, model) = ? parseModelsSelection(value)
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

proc buildProviderCatalogText*(provider: string;
                              catalog: ModelCatalogResult): string =
  let sorted = sortModelCatalog(normalizeModelCatalog(provider, catalog.entries))
  result = "Provider: " & provider
  if sorted.len > 0:
    result.add("\nModelos:\n" & sorted.map(formatModelCatalogLine).join("\n"))
  else:
    result.add("\nNenhum modelo listado no catálogo atual.")
  result.add("\n" & buildCatalogSourceText(catalog))
  result.add("\n\nUse `/models " & provider & " <model>` para trocar.")
