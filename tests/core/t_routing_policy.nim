import std/[unittest, options]
import donkey/core/providers/smart_routing
import donkey/core/providers/provider_catalog
import donkey/domain/message

suite "routing_policy — catalog-driven":

  test "selectBestModel returns empty for unavailable provider":
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        openrouter: false, anthropic: false, zaiAnthropic: false,
        gemini: false, minimax: false, zai: false, zaiCoding: false,
      ),
    )
    let sel = rc.selectBestModel("openrouter")
    check sel.providerName.len == 0

  test "selectBestModel returns best model for provider with tools":
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        openrouter: true, anthropic: false, zaiAnthropic: false,
        gemini: false, minimax: false, zai: false, zaiCoding: false,
      ),
    )
    let sel = rc.selectBestModel("openrouter", hasTools = true, hasThinking = true)
    check sel.providerName == "openrouter"
    check sel.modelName.len > 0

  test "selectBestModel returns best model for provider with image":
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        gemini: true, openrouter: false, anthropic: false, zaiAnthropic: false,
        minimax: false, zai: false, zaiCoding: false,
      ),
    )
    let sel = rc.selectBestModel("gemini", hasImage = true)
    check sel.providerName == "gemini"
    check sel.modelName.len > 0

  test "addSelectionIfAvailable adds model when provider is available":
    var selections: seq[ProviderSelection] = @[]
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        minimax: true, openrouter: false, anthropic: false, zaiAnthropic: false,
        gemini: false, zai: false, zaiCoding: false,
      ),
    )
    addSelectionIfAvailable(selections, rc, "minimax")
    check selections.len == 1
    check selections[0].providerName == "minimax"

  test "addSelectionIfAvailable does not add when provider is unavailable":
    var selections: seq[ProviderSelection] = @[]
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        minimax: false, openrouter: false, anthropic: false, zaiAnthropic: false,
        gemini: false, zai: false, zaiCoding: false,
      ),
    )
    addSelectionIfAvailable(selections, rc, "minimax")
    check selections.len == 0

  test "addAnthropicWithFallback adds direct anthropic when available":
    var selections: seq[ProviderSelection] = @[]
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        anthropic: true, zaiAnthropic: false,
        openrouter: false, gemini: false, minimax: false, zai: false, zaiCoding: false,
      ),
    )
    addAnthropicWithFallback(selections, rc)
    check selections.len == 1
    check selections[0].providerName == "anthropic"

  test "addAnthropicWithFallback falls back to zai-anthropic when direct unavailable":
    var selections: seq[ProviderSelection] = @[]
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        anthropic: false, zaiAnthropic: true,
        openrouter: false, gemini: false, minimax: false, zai: false, zaiCoding: false,
      ),
    )
    addAnthropicWithFallback(selections, rc)
    check selections.len == 1
    check selections[0].providerName == "zai-anthropic"

  test "addAnthropicWithFallback adds nothing when both unavailable":
    var selections: seq[ProviderSelection] = @[]
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        anthropic: false, zaiAnthropic: false,
        openrouter: false, gemini: false, minimax: false, zai: false, zaiCoding: false,
      ),
    )
    addAnthropicWithFallback(selections, rc)
    check selections.len == 0

  test "smartRouteSelections with no availability returns deduped results":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "hello")]
    )
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openrouter: false, anthropic: false, zaiAnthropic: false,
      gemini: false, minimax: false, zai: false, zaiCoding: false,
    ))
    # With no availability, should still return deduped (possibly empty)
    let deduped = dedupeSelections(selections)
    check deduped.len == selections.len

  test "smartRouteSelections with full availability returns multiple candidates":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "hello")]
    )
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openrouter: true, anthropic: true, zaiAnthropic: true,
      gemini: true, minimax: true, zai: true, zaiCoding: true,
    ))
    check selections.len > 1

  test "smartRouteSelections for high thinking + tools prefers capable models":
    let prefs = parseSmartRoutingPrefs("thinking = \"high\"")
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "refactor")],
      tools: @[ToolDescription(name: "bash")]
    )
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openrouter: true, anthropic: true, zaiAnthropic: true,
      gemini: true, minimax: false, zai: true, zaiCoding: true,
    ))
    check selections.len > 0
    # First should be a model with tools + thinking
    check selections[0].providerName in ["anthropic", "zai-anthropic", "zai-coding", "openrouter"]

  test "smartRouteSelections for image request prefers multimodal providers":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "describe", imageUrl: "https://x/y.png")]
    )
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openrouter: true, anthropic: false, zaiAnthropic: false,
      gemini: true, minimax: false, zai: false, zaiCoding: false,
    ))
    check selections.len >= 1
    # First candidates should be image-capable
    if selections.len >= 2:
      check selections[0].providerName in ["openrouter", "gemini"]

  test "defaultModelForProvider returns catalog model for known provider":
    let catalog = buildDefaultCatalog()
    let model = defaultModelForProvider("gemini", catalog)
    check model.len > 0
    # Should be a model from the catalog, not hardcoded
    let lookup = catalog.lookup(model)
    check lookup.isSome

  test "defaultModelForProvider returns fallback for unknown provider":
    let model = defaultModelForProvider("unknown-provider-xyz")
    check model == "glm-4.7"

  test "queryModels returns models sorted by priority":
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        openrouter: true, anthropic: true, zaiAnthropic: true,
        gemini: true, minimax: true, zai: true, zaiCoding: true,
      ),
    )
    let models = rc.queryModels("openrouter", hasTools = true)
    check models.len > 0
    # Should be sorted by quality-first priority
    if models.len >= 2:
      check ord(models[0].budgetPriority) >= ord(models[1].budgetPriority) or
            models[0].budgetPriority == bpHigh

  test "RoutingCatalog wraps catalog and availability cleanly":
    let catalog = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: catalog,
      availability: ProviderAvailability(
        openrouter: true, anthropic: false, zaiAnthropic: false,
        gemini: false, minimax: false, zai: false, zaiCoding: false,
      ),
    )
    check rc.catalog.len > 0
    check rc.availability.openrouter
    check not rc.availability.anthropic
