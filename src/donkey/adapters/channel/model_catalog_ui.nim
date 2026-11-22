## Model catalog presentation shared by the channels with pickers: the
## provider/model menu, compact callback tokens for long model ids, catalog
## paging and buttons. The buttons take the current selection as data: this
## module reads no preferences. The pure catalog rules (family, order, source
## line, listing) live in `core/commands/preference_commands`.

import std/[algorithm, sequtils, strutils, tables, times]
import checksums/sha1
import ../../core/pipeops
import ../../core/utf8
import ../../core/commands/command_text
import ../../core/providers/provider_catalog
import ../../core/commands/preference_commands
import ../../ports/provider
import ../../infra/thread_owner

export preference_commands.normalizeModelCatalog, preference_commands.sortModelCatalog

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

proc currentModelMenu*(): ModelMenu =
  ## The menu as the pure /models policy reads it.
  for (provider, models) in modelMenu():
    result.add((provider: provider, models: models))

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

func buildThinkButtons*(curr: string): seq[seq[(string, string)]] =
  ## One button per level; `curr` is marked.
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

proc buildProviderButtons*(currProv: string): seq[seq[(string, string)]] =
  ## The providers, three per row; `currProv` is marked.
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

proc buildModelButtons*(provider, currProv, currModel: string): seq[seq[(string, string)]] =
  ## `provider`'s static models, two per row; the current one is marked.
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
  catalogSourceText(catalog, getTime().toUnix())

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

proc parseModelsProviderArg*(value: string): Result[string, string] =
  let parts = value.splitWhitespace()
  if parts.len != 1:
    return err("Use `/models <provider>`.")
  let provider = parts[0]
  if provider notin supportedProviders():
    return err("Provider inválido: `" & provider & "`.")
  ok(provider)

proc buildProviderCatalogText*(provider: string;
                              catalog: ModelCatalogResult): string =
  providerCatalogText(provider, catalog, getTime().toUnix())
