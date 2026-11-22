## The /models, /think and /budget orchestration over an in-memory store:
## read the preferences, validate, save, answer. No Markdown files.

import std/[sequtils, strutils, tables, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/core/providers/smart_routing
import donkey/core/commands/preference_commands
import donkey/app/channel_prefs_parse
import donkey/app/preference_commands
import donkey/ports/provider

var gStore {.threadvar.}: Table[string, string]
var gReadError {.threadvar.}: string
var gSaveError {.threadvar.}: string
var gSaves {.threadvar.}: seq[seq[(string, string)]]

proc readPrefs(userId: UserId): Result[string, string] {.gcsafe.} =
  if gReadError.len > 0: err(gReadError)
  else: ok(gStore.getOrDefault($userId))

proc savePrefs(userId: UserId; entries: seq[(string, string)]): Result[void, string] {.gcsafe.} =
  if gSaveError.len > 0:
    return err(gSaveError)
  gSaves.add entries
  ## Like the real store: a key already present is replaced, not repeated.
  var lines: seq[string]
  for line in gStore.getOrDefault($userId).splitLines:
    if line.strip.len > 0 and entries.allIt(not line.startsWith(it[0] & " =")):
      lines.add line
  for (key, value) in entries:
    lines.add key & " = \"" & value & "\""
  gStore[$userId] = lines.join("\n")
  ok()

proc catalogWith(provider: string): Result[ModelCatalogResult, string] {.gcsafe.} =
  ok(ModelCatalogResult(source: mcsFallback, entries: @[
    ModelCatalogEntry(providerName: provider, modelName: "live/one", label: "live/one")]))

proc emptyCatalog(provider: string): Result[ModelCatalogResult, string] {.gcsafe.} =
  ok(ModelCatalogResult(source: mcsLive, fetchedAtUnix: 1))

proc failingCatalog(provider: string): Result[ModelCatalogResult, string] {.gcsafe.} =
  err("catalog down")

proc deps(loader: ModelCatalogLoader = nil): PreferenceCommandDeps =
  PreferenceCommandDeps(
    readPreferences: readPrefs,
    savePreferences: savePrefs,
    catalogLoader: loader,
    menu: @[(provider: "openrouter", models: @["a/one"]),
            (provider: "anthropic", models: @["claude-x"])],
    availability: ProviderAvailability(),
  )

proc reset() =
  gStore = initTable[string, string]()
  gReadError = ""
  gSaveError = ""
  gSaves = @[]

let user = UserId("u1")

proc runTests*() =
  suite "/think and /budget":
    setup: reset()

    test "no argument answers with the stored value":
      gStore["u1"] = "thinking = \"high\"\nbudget = \"quality-first\""
      check deps().runThinkCommand(user, "").get.startsWith("Thinking atual: high")
      check deps().runBudgetCommand(user, "").get.startsWith("Budget atual: quality-first")

    test "a value is validated, saved and confirmed":
      check deps().runThinkCommand(user, "medium").get == "Thinking definido: medium"
      check gSaves == @[@[("thinking", "medium")]]
      check deps().runBudgetCommand(user, "cheap-first").get == "Budget definido: cheap-first"
      check deps().runThinkCommand(user, "max").error == "Nível inválido: `max`."
      check gSaves.len == 2

    test "a later value replaces the earlier one":
      check deps().runThinkCommand(user, "low").isOk
      check deps().runThinkCommand(user, "high").isOk
      check deps().runThinkCommand(user, "").get.startsWith("Thinking atual: high")

    test "the budget shown is the budget routing applies":
      gStore["u1"] = "budget = \"quality-first\" # escolha local"
      check deps().runBudgetCommand(user, "").get.startsWith("Budget atual: quality-first")

    test "an unreadable store is an error, not the defaults":
      gReadError = "graph unavailable"
      check deps().runThinkCommand(user, "").error ==
        "Não foi possível ler suas preferências: graph unavailable"

    test "a failed save is reported":
      gSaveError = "disk full"
      check deps().runThinkCommand(user, "low").error == "disk full"

  suite "/models":
    setup: reset()

    test "the help shows the stored selection and the static models":
      gStore["u1"] = "provider = \"anthropic\"\nmodel = \"claude-x\""
      let text = deps().runModelsCommand(user, "").get
      check text.startsWith("Provider atual: anthropic / claude-x")
      check "Modelos para `anthropic`: claude-x" in text

    test "the help prefers the loaded catalog and names its source":
      gStore["u1"] = "provider = \"anthropic\"\nmodel = \"claude-x\""
      let text = deps(catalogWith).runModelsCommand(user, "").get
      check "Modelos para `anthropic`: live/one" in text
      check "Fonte: fallback" in text

    test "a provider alone lists its catalog, or its static list":
      check "- `live/one`" in deps(catalogWith).runModelsCommand(user, "anthropic").get
      check "- `claude-x`" in deps().runModelsCommand(user, "anthropic").get

    test "a selection is checked against the catalog, then saved together":
      check deps(catalogWith).runModelsCommand(user, "anthropic claude-x").error ==
        "Modelo indisponível agora para `anthropic`: `claude-x`."
      check gSaves.len == 0
      check deps(catalogWith).runModelsCommand(user, "anthropic live/one").get ==
        "Modelo definido: anthropic / live/one"
      check gSaves == @[@[("provider", "anthropic"), ("model", "live/one")]]

    test "an empty loaded catalog lists the static models it will accept":
      ## The listing and the selection follow one rule: with no models in the
      ## loaded catalog, the static menu applies to both.
      check "- `claude-x`" in deps(emptyCatalog).runModelsCommand(user, "anthropic").get
      check deps(emptyCatalog).runModelsCommand(user, "anthropic claude-x").isOk

    test "a catalog that fails to load falls back to the static list":
      check deps(failingCatalog).runModelsCommand(user, "anthropic claude-x").isOk
      check deps(failingCatalog).runModelsCommand(user, "anthropic other").error ==
        "Modelo inválido para `anthropic`: `other`."

    test "an unreadable store fails the help, not the selection":
      gReadError = "graph unavailable"
      check deps().runModelsCommand(user, "").error ==
        "Não foi possível ler suas preferências: graph unavailable"
      check deps().runModelsCommand(user, "anthropic claude-x").isOk

  suite "reading preferences":
    test "malformed preferences are an error, not the defaults":
      check tryParseChannelPrefs("provider = \"anthropic\"").get.provider == "anthropic"
      check tryParseChannelPrefs("provider = [unclosed").isErr
      check tryParseChannelPrefs("").get == defaultChannelPrefs()

    test "a preference of the wrong type is an error, not the default":
      check tryParseChannelPrefs("thinking = 123").isErr
      check tryParseChannelPrefs("provider = true").isErr
      check tryParseChannelPrefs("model = [\"x\"]").isErr

    test "every help refuses a malformed document":
      reset()
      gStore["u1"] = "budget = [unclosed"
      for run in [runModelsCommand, runThinkCommand, runBudgetCommand]:
        check run(deps(), user, "").error.startsWith(
          "Não foi possível ler suas preferências: PREFERENCES.md:")

when isMainModule:
  runTests()
