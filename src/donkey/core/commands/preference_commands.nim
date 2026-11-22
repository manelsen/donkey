## The /models, /think and /budget policy as pure decisions: what an argument
## means, whether a model selection is allowed, what to answer, and how a
## model catalog is shown. The orchestration (read the preferences, load a
## catalog, save, reply) lives in `app/preference_commands`; the store and the
## catalog loader stay in adapters. Nothing here reads files, the environment
## or the clock: the caller passes the model menu, the loaded catalog and the
## current time.

import std/[algorithm, sequtils, strutils]
import ../pipeops
import ../../ports/provider
import ./command_args

type
  ModelMenu* = seq[tuple[provider: string, models: seq[string]]]
    ## Every provider the menu offers, with its static model list (empty for
    ## a provider whose models are only known from a live catalog).

  ModelsRequestKind* = enum
    mrkHelp     ## `/models`: the current selection and the options
    mrkCatalog  ## `/models <provider>`: that provider's catalog
    mrkSelect   ## `/models <provider> <model>`: switch to it

  ModelsRequest* = object
    kind*:     ModelsRequestKind
    provider*: string
    model*:    string

  SettingRequest* = object
    ## `/think` or `/budget`: with no argument `show` is true; otherwise
    ## `value` is the normalized new value.
    show*:  bool
    value*: string

  ModelsHelpView* = object
    ## What the /models help shows, gathered by the caller.
    provider*:     string
    model*:        string
    smartRouting*: bool    ## the provider is chosen per turn (auto)
    budgetPolicy*: string
    routePreview*: string  ## the base route of smart routing, if any
    providers*:    seq[string]
    models*:       seq[string]  ## the current provider's models
    catalogInfo*:  string       ## the catalog source line, if a catalog was loaded

# ── menu ──────────────────────────────────────────────────────────────────────

func menuProviders*(menu: ModelMenu): seq[string] =
  menu.mapIt(it.provider)

func menuModels*(menu: ModelMenu; provider: string): seq[string] =
  for (candidate, models) in menu:
    if candidate == provider:
      return models

# ── arguments ─────────────────────────────────────────────────────────────────

func parseModelsRequest*(value: string; menu: ModelMenu): Result[ModelsRequest, string] =
  let parts = value.splitWhitespace()
  if parts.len == 0:
    return ok(ModelsRequest(kind: mrkHelp))
  if parts.len > 2:
    return err("Use `/models <provider> <model>`.")
  let provider = parts[0]
  if provider notin menu.menuProviders:
    return err("Provider inválido: `" & provider & "`.")
  if parts.len == 1:
    ok(ModelsRequest(kind: mrkCatalog, provider: provider))
  else:
    ok(ModelsRequest(kind: mrkSelect, provider: provider, model: parts[1]))

func checkModelSelection*(request: ModelsRequest;
                          catalogModels: seq[string];
                          menu: ModelMenu): Result[void, string] =
  ## The selection is checked against the catalog `/models <provider>` shows;
  ## the static list applies only when no catalog was loaded, and a provider
  ## with neither accepts any model.
  if catalogModels.len > 0:
    if request.model notin catalogModels:
      return err("Modelo indisponível agora para `" & request.provider & "`: `" &
                 request.model & "`.")
    return ok()
  let staticModels = menu.menuModels(request.provider)
  if staticModels.len > 0 and request.model notin staticModels:
    return err("Modelo inválido para `" & request.provider & "`: `" &
               request.model & "`.")
  ok()

func parseThinkRequest*(value: string): Result[SettingRequest, string] =
  if value.strip.len == 0:
    return ok(SettingRequest(show: true))
  ok(SettingRequest(value: ? parseThinkArgs(value)))

func parseBudgetRequest*(value: string): Result[SettingRequest, string] =
  if value.strip.len == 0:
    return ok(SettingRequest(show: true))
  ok(SettingRequest(value: ? parseBudgetArgs(value)))

# ── answers ───────────────────────────────────────────────────────────────────

func modelsHelpText*(view: ModelsHelpView): string =
  result =
    if view.smartRouting: "Provider atual: auto [" & view.budgetPolicy & "]"
    else: "Provider atual: " & view.provider
  if view.model.len > 0 and not view.smartRouting:
    result.add(" / " & view.model)
  if view.smartRouting and view.routePreview.len > 0:
    result.add("\nRota base: " & view.routePreview)
  result.add("\n\nProviders: " & view.providers.join(", "))
  if view.models.len > 0:
    result.add("\nModelos para `" & view.provider & "`: " & view.models.join(", "))
  if view.catalogInfo.len > 0:
    result.add("\n" & view.catalogInfo)
  result.add("\n\nUse `/models <provider> <model>` para trocar.")

func thinkHelpText*(current: string): string =
  "Thinking atual: " & current &
  "\nNíveis: " & ThinkLevels.join(", ") &
  "\n\nUse `/think <level>` para trocar."

func budgetHelpText*(current: string): string =
  "Budget atual: " & current &
  "\nPolicies: " & BudgetPolicies.join(", ") &
  "\n\nUse `/budget <policy>` para trocar."

func modelSavedText*(provider, model: string): string =
  "Modelo definido: " & provider & " / " & model

func thinkSavedText*(level: string): string = "Thinking definido: " & level

func budgetSavedText*(policy: string): string = "Budget definido: " & policy

func preferencesUnreadableText*(error: string): string =
  ## What a command answers when the user's preferences cannot be read: it
  ## says so, instead of showing defaults as if they were the user's.
  "Não foi possível ler suas preferências: " & error

# ── catalog presentation ──────────────────────────────────────────────────────

func providerFamily(provider: string): string =
  case provider
  of "zai", "zai-coding", "zai-anthropic": "zai"
  else: provider

func normalizeModelCatalog*(provider: string;
                            entries: seq[ModelCatalogEntry]): seq[ModelCatalogEntry] =
  ## The entries of the provider's family, each model once.
  let wanted = providerFamily(provider)
  var seen: seq[string] = @[]
  for entry in entries:
    if providerFamily(entry.providerName) == wanted and entry.modelName notin seen:
      result.add(entry)
      seen.add(entry.modelName)

func sortModelCatalog*(entries: seq[ModelCatalogEntry]): seq[ModelCatalogEntry] =
  ## Free models first, then by label.
  result = entries
  result.sort(proc(a, b: ModelCatalogEntry): int =
    if a.isFree != b.isFree:
      return if a.isFree: -1 else: 1
    cmp(a.label.toLowerAscii(), b.label.toLowerAscii())
  )

func catalogSourceText*(catalog: ModelCatalogResult; nowUnix: int64): string =
  let sourceText = catalogSourceLabel(catalog.source)
  if catalog.source == mcsFallback or catalog.fetchedAtUnix <= 0:
    "Fonte: " & sourceText
  else:
    "Fonte: " & sourceText & " (" & relativeAgeText(nowUnix - catalog.fetchedAtUnix) & ")"

func formatModelCatalogLine(entry: ModelCatalogEntry): string =
  "- `" & entry.modelName & "`" & (if entry.isFree: " [free]" else: "")

func providerCatalogText*(provider: string;
                          catalog: ModelCatalogResult;
                          nowUnix: int64): string =
  let sorted = sortModelCatalog(normalizeModelCatalog(provider, catalog.entries))
  result = "Provider: " & provider
  if sorted.len > 0:
    result.add("\nModelos:\n" & sorted.map(formatModelCatalogLine).join("\n"))
  else:
    result.add("\nNenhum modelo listado no catálogo atual.")
  result.add("\n" & catalogSourceText(catalog, nowUnix))
  result.add("\n\nUse `/models " & provider & " <model>` para trocar.")
