## The /models, /think and /budget policy as pure decisions: what an argument
## means, whether a selection is allowed, and what to answer. No store, no
## catalog loader, no clock.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/commands/preference_commands
import donkey/ports/provider

let menu: ModelMenu = @[
  (provider: "openrouter", models: @["a/one", "b/two"]),
  (provider: "anthropic", models: @["claude-x"]),
  (provider: "zen", models: newSeq[string]()),
]

func entry(provider, model: string; free = false): ModelCatalogEntry =
  ModelCatalogEntry(providerName: provider, modelName: model, label: model,
                    isFree: free, available: true)

proc runTests*() =
  suite "/models arguments":
    test "no argument asks for the help view":
      check parseModelsRequest("", menu).get.kind == mrkHelp
      check parseModelsRequest("   ", menu).get.kind == mrkHelp

    test "a provider alone asks for its catalog":
      let req = parseModelsRequest("anthropic", menu).get
      check req.kind == mrkCatalog
      check req.provider == "anthropic"

    test "a provider and a model ask to select them":
      let req = parseModelsRequest("openrouter b/two", menu).get
      check req.kind == mrkSelect
      check (req.provider, req.model) == ("openrouter", "b/two")

    test "an unknown provider or a malformed request is refused":
      check parseModelsRequest("nope", menu).error == "Provider inválido: `nope`."
      check parseModelsRequest("nope x", menu).error == "Provider inválido: `nope`."
      check parseModelsRequest("openrouter a b", menu).error ==
        "Use `/models <provider> <model>`."

  suite "/models selection":
    let select = parseModelsRequest("openrouter b/two", menu).get

    test "the loaded catalog decides when there is one":
      check checkModelSelection(select, @["b/two"], menu).isOk
      check checkModelSelection(select, @["c/three"], menu).error ==
        "Modelo indisponível agora para `openrouter`: `b/two`."

    test "the static list decides when no catalog was loaded":
      check checkModelSelection(select, @[], menu).isOk
      let wrong = parseModelsRequest("openrouter z/z", menu).get
      check checkModelSelection(wrong, @[], menu).error ==
        "Modelo inválido para `openrouter`: `z/z`."

    test "a provider without a static list accepts any model":
      let zen = parseModelsRequest("zen anything", menu).get
      check checkModelSelection(zen, @[], menu).isOk

  suite "/think and /budget arguments":
    test "no argument shows the current value":
      check parseThinkRequest("").get.show
      check parseBudgetRequest(" ").get.show

    test "a valid value is normalized; an invalid one is refused":
      check parseThinkRequest("HIGH").get.value == "high"
      check parseThinkRequest("max").error == "Nível inválido: `max`."
      check parseBudgetRequest("balanced").get.value == "balanced"
      check parseBudgetRequest("lavish").error == "Policy inválida: `lavish`."

  suite "answers":
    test "help texts list the current value and the options":
      check thinkHelpText("low") ==
        "Thinking atual: low\nNíveis: off, low, medium, high\n\n" &
        "Use `/think <level>` para trocar."
      check budgetHelpText("balanced").startsWith("Budget atual: balanced\n")

    test "the models help shows an explicit selection":
      let text = modelsHelpText(ModelsHelpView(
        provider: "anthropic", model: "claude-x",
        providers: @["openrouter", "anthropic"], models: @["claude-x"]))
      check text.startsWith("Provider atual: anthropic / claude-x")
      check "Providers: openrouter, anthropic" in text
      check "Modelos para `anthropic`: claude-x" in text
      check text.endsWith("Use `/models <provider> <model>` para trocar.")

    test "the models help shows smart routing and its route":
      let text = modelsHelpText(ModelsHelpView(
        provider: "openrouter", model: "a/one", smartRouting: true,
        budgetPolicy: "cheap-first", routePreview: "openrouter/a/one"))
      check text.startsWith("Provider atual: auto [cheap-first]\nRota base: openrouter/a/one")
      check "/ a/one" notin text.splitLines()[0]

    test "confirmations and the unreadable-preferences answer":
      check modelSavedText("anthropic", "claude-x") == "Modelo definido: anthropic / claude-x"
      check thinkSavedText("high") == "Thinking definido: high"
      check budgetSavedText("balanced") == "Budget definido: balanced"
      check preferencesUnreadableText("disk") ==
        "Não foi possível ler suas preferências: disk"

  suite "catalog presentation":
    test "a catalog keeps the provider's family, once per model, free first":
      let entries = @[entry("zai-coding", "glm-5"), entry("openrouter", "x"),
                      entry("zai", "glm-5"), entry("zai", "glm-4", free = true)]
      let shown = sortModelCatalog(normalizeModelCatalog("zai", entries))
      check shown.len == 2
      check shown[0].modelName == "glm-4"
      check shown[1].modelName == "glm-5"

    test "the source line ages a live catalog and not a fallback":
      let live = ModelCatalogResult(source: mcsLive, fetchedAtUnix: 1_000)
      check catalogSourceText(live, nowUnix = 1_120) ==
        "Fonte: " & catalogSourceLabel(mcsLive) & " (" & relativeAgeText(120) & ")"
      check catalogSourceText(ModelCatalogResult(source: mcsFallback), nowUnix = 5) ==
        "Fonte: " & catalogSourceLabel(mcsFallback)

    test "a provider catalog lists its models and how to pick one":
      let catalog = ModelCatalogResult(entries: @[entry("anthropic", "claude-x")],
                                       source: mcsFallback)
      let text = providerCatalogText("anthropic", catalog, nowUnix = 0)
      check text.startsWith("Provider: anthropic\nModelos:\n- `claude-x`")
      check text.endsWith("Use `/models anthropic <model>` para trocar.")
      check "Nenhum modelo listado" in providerCatalogText(
        "anthropic", ModelCatalogResult(source: mcsFallback), nowUnix = 0)

when isMainModule:
  runTests()
