## /models, /think and /budget orchestration: read the user's preferences,
## let the pure policy (`core/commands/preference_commands`) decide, save and
## answer. The store and the catalog loader come in as plain procs, so the
## policy runs without the Markdown store and a failed read is an error, never
## the defaults.

import std/[options, sequtils, times]
import ../core/pipeops
import ../core/types
import ../core/providers/smart_routing
import ../core/commands/preference_commands
import ../ports/provider
import ./channel_prefs_parse

export preference_commands

type
  PreferenceCommandDeps* = object
    readPreferences*: proc(userId: UserId): Result[string, string] {.gcsafe.}
      ## The user's PREFERENCES.md as the store holds it.
    savePreferences*: proc(userId: UserId;
                           entries: seq[(string, string)]): Result[void, string] {.gcsafe.}
      ## Sets every `key = value` in one write, or none.
    catalogLoader*: ModelCatalogLoader  ## nil: only the static menu is known
    menu*: ModelMenu
    availability*: ProviderAvailability ## for the smart-routing preview

proc readPrefsDoc(deps: PreferenceCommandDeps; userId: UserId): Result[string, string] =
  deps.readPreferences(userId).mapErr(preferencesUnreadableText)

proc loadCatalog(deps: PreferenceCommandDeps; provider: string): Option[ModelCatalogResult] =
  ## A catalog that fails to load counts as none: the static menu applies.
  if deps.catalogLoader == nil:
    return none(ModelCatalogResult)
  let loaded = deps.catalogLoader(provider)
  if loaded.isOk: some(loaded.get) else: none(ModelCatalogResult)

proc nowUnix(): int64 = getTime().toUnix()

proc modelsHelp(deps: PreferenceCommandDeps; userId: UserId): Result[string, string] =
  let doc = ? deps.readPrefsDoc(userId)
  let prefs = ? tryParseChannelPrefs(doc).mapErr(preferencesUnreadableText)
  let routing = parseSmartRoutingPrefs(doc)
  var view = ModelsHelpView(
    provider: prefs.provider,
    model: prefs.model,
    smartRouting: routing.usesSmartRouting,
    budgetPolicy: routing.budgetPolicy,
    providers: deps.menu.menuProviders,
    models: deps.menu.menuModels(prefs.provider),
  )
  if view.smartRouting:
    view.routePreview = formatSelectionPreview(
      previewSmartRouteSelections(routing, deps.availability))
  let catalog = deps.loadCatalog(prefs.provider)
  if catalog.isSome:
    let sorted = sortModelCatalog(normalizeModelCatalog(prefs.provider, catalog.get.entries))
    view.catalogInfo = catalogSourceText(catalog.get, nowUnix())
    if sorted.len > 0:
      view.models = sorted.mapIt(it.modelName)
  ok(modelsHelpText(view))

proc runModelsCommand*(deps: PreferenceCommandDeps; userId: UserId;
                       value: string): Result[string, string] =
  let request = ? parseModelsRequest(value, deps.menu)
  case request.kind
  of mrkHelp:
    deps.modelsHelp(userId)
  of mrkCatalog:
    ## Listed by the rule the selection follows: the loaded catalog when it
    ## has models for the provider, the static menu otherwise.
    let staticCatalog = ModelCatalogResult(
      source: mcsFallback,
      entries: deps.menu.menuModels(request.provider).mapIt(ModelCatalogEntry(
        providerName: request.provider, modelName: it, label: it, available: true)),
    )
    let loaded = deps.loadCatalog(request.provider)
    let catalog =
      if loaded.isSome and
         normalizeModelCatalog(request.provider, loaded.get.entries).len > 0: loaded.get
      else: staticCatalog
    ok(providerCatalogText(request.provider, catalog, nowUnix()))
  of mrkSelect:
    let catalogModels =
      deps.loadCatalog(request.provider)
        .map(proc(c: ModelCatalogResult): seq[string] =
          normalizeModelCatalog(request.provider, c.entries).mapIt(it.modelName))
        .get(@[])
    ? checkModelSelection(request, catalogModels, deps.menu)
    ? deps.savePreferences(userId, @[("provider", request.provider),
                                     ("model", request.model)])
    ok(modelSavedText(request.provider, request.model))

proc runThinkCommand*(deps: PreferenceCommandDeps; userId: UserId;
                      value: string): Result[string, string] =
  let request = ? parseThinkRequest(value)
  if request.show:
    let doc = ? deps.readPrefsDoc(userId)
    let prefs = ? tryParseChannelPrefs(doc).mapErr(preferencesUnreadableText)
    return ok(thinkHelpText(prefs.thinking))
  ? deps.savePreferences(userId, @[("thinking", request.value)])
  ok(thinkSavedText(request.value))

proc runBudgetCommand*(deps: PreferenceCommandDeps; userId: UserId;
                       value: string): Result[string, string] =
  let request = ? parseBudgetRequest(value)
  if request.show:
    let doc = ? deps.readPrefsDoc(userId)
    discard ? tryParseChannelPrefs(doc).mapErr(preferencesUnreadableText)
    return ok(budgetHelpText(parseSmartRoutingPrefs(doc).budgetPolicy))
  ? deps.savePreferences(userId, @[("budget", request.value)])
  ok(budgetSavedText(request.value))
