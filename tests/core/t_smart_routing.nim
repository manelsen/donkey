import std/unittest
import donkey/core/providers/smart_routing
import donkey/core/providers/provider_catalog
import donkey/domain/message

suite "smart_routing":

  test "parseSmartRoutingPrefs keeps auto routing when no provider override":
    let prefs = parseSmartRoutingPrefs("thinking = \"high\"")
    check prefs.providerName == "zai-coding"
    check prefs.thinking == "high"
    check prefs.budgetPolicy == "balanced"
    check prefs.usesSmartRouting
    check prefs.routingLabel == "auto"

  test "parseSmartRoutingPrefs treats explicit provider as override":
    let prefs = parseSmartRoutingPrefs("""
provider = "gemini"
thinking = "low"
""")
    check prefs.providerName == "gemini"
    check not prefs.usesSmartRouting
    check prefs.routingLabel == "gemini"

  test "smartRouteSelections prefers multimodal providers for image requests":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "describe", imageUrl: "https://x/y.png")]
    )
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openrouter: true, gemini: true, anthropic: true, zai: true, zaiCoding: true
    ))
    check selections.len >= 2
    check selections[0].providerName == "openrouter"
    check selections[1].providerName == "gemini"

  test "smartRouteSelections prefers strong tool models for high thinking":
    let prefs = parseSmartRoutingPrefs("thinking = \"high\"")
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "refactor this carefully")],
      tools: @[ToolDescription(name: "bash")]
    )
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openrouter: true, anthropic: true, gemini: true, zaiCoding: true
    ))
    check selections.len > 0
    check selections[0].providerName == "anthropic"
    check selections[0].modelName == "claude-opus-5-5"

  test "smartRouteSelections falls back to zai-anthropic when anthropic is unavailable":
    let prefs = parseSmartRoutingPrefs("thinking = \"high\"")
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "refactor this carefully")],
      tools: @[ToolDescription(name: "bash")]
    )
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openrouter: true, zaiAnthropic: true, gemini: true, zaiCoding: true
    ))
    check selections.len > 0
    check selections[0].providerName == "zai-anthropic"
    check selections[0].modelName == "glm-4.7"

  test "selectBestModel respects ProviderAvailability for new providers":
    let cat = buildDefaultCatalog()
    let rc = RoutingCatalog(
      catalog: cat,
      availability: ProviderAvailability(openai: true, deepseek: true, groq: true, ollama: true),
    )
    let openaiSel = rc.selectBestModel("openai")
    check openaiSel.providerName == "openai"
    check openaiSel.modelName.len > 0

    let deepseekSel = rc.selectBestModel("deepseek")
    check deepseekSel.providerName == "deepseek"
    check deepseekSel.modelName.len > 0

    let unavailRc = RoutingCatalog(
      catalog: cat,
      availability: ProviderAvailability(),
    )
    check unavailRc.selectBestModel("openai").providerName.len == 0
    check unavailRc.selectBestModel("deepseek").providerName.len == 0

  test "smartRouteSelections returns candidates when only openai is available":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(messages: @[ChatMessage(role: "user", text: "hello")])
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(openai: true))
    check selections.len > 0
    check selections[0].providerName == "openai"

  test "smartRouteSelections returns candidates when only deepseek is available":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(messages: @[ChatMessage(role: "user", text: "hello")])
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(deepseek: true))
    check selections.len > 0
    check selections[0].providerName == "deepseek"

  test "smartRouteSelections returns candidates when only groq is available":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(messages: @[ChatMessage(role: "user", text: "hello")])
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(groq: true))
    check selections.len > 0
    check selections[0].providerName == "groq"

  test "smartRouteSelections returns candidates when only ollama is available":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(messages: @[ChatMessage(role: "user", text: "hello")])
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(ollama: true))
    check selections.len > 0
    check selections[0].providerName == "ollama"

  test "smartRouteSelections orders openai, deepseek, and zai-coding deterministically":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(messages: @[ChatMessage(role: "user", text: "hello")])
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openai: true,
      deepseek: true,
      zaiCoding: true
    ))
    check selections.len >= 3
    check selections[0].providerName == "openai"
    check selections[1].providerName == "deepseek"
    check selections[2].providerName == "zai-coding"

  test "smartRouteSelections keeps explicit provider selection untouched":
    let prefs = parseSmartRoutingPrefs("""
provider = "openrouter"
model = "openai/gpt-4o"
thinking = "high"
""")
    let req = CompletionRequest(messages: @[ChatMessage(role: "user", text: "hi")])
    let selections = smartRouteSelections(prefs, req, ProviderAvailability(
      openrouter: true, anthropic: true, gemini: true
    ))
    check selections == @[ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o")]

  test "reorderSelectionsWithFeedback demotes slow or failing routes":
    let base = @[
      ProviderSelection(providerName: "anthropic", modelName: "claude-opus-4-6"),
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
      ProviderSelection(providerName: "gemini", modelName: "gemini-2.5-flash"),
    ]
    let reordered = reorderSelectionsWithFeedback(base, @[
      RouteFeedback(route: "anthropic/claude-opus-4-6", calls: 8, okCalls: 4, errCalls: 4, avgLatencyMs: 9000),
      RouteFeedback(route: "openrouter/openai/gpt-4o-mini", calls: 8, okCalls: 8, errCalls: 0, avgLatencyMs: 700),
    ])
    check reordered[0].providerName == "openrouter"
    check reordered[^1].providerName == "anthropic"

  test "applyCircuitBreaker removes recently unhealthy routes when alternatives exist":
    let base = @[
      ProviderSelection(providerName: "anthropic", modelName: "claude-opus-4-6"),
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
      ProviderSelection(providerName: "gemini", modelName: "gemini-2.5-flash"),
    ]
    let filtered = applyCircuitBreaker(base, @[
      RouteFeedback(route: "anthropic/claude-opus-4-6", calls: 5, okCalls: 0, errCalls: 5, avgLatencyMs: 2500),
      RouteFeedback(route: "gemini/gemini-2.5-flash", calls: 6, okCalls: 1, errCalls: 5, avgLatencyMs: 19000),
    ])
    check filtered == @[
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
    ]

  test "applyCircuitBreaker keeps single explicit selection even when unhealthy":
    let base = @[
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o"),
    ]
    let filtered = applyCircuitBreaker(base, @[
      RouteFeedback(route: "openrouter/openai/gpt-4o", calls: 6, okCalls: 0, errCalls: 6, avgLatencyMs: 22000),
    ])
    check filtered == base

  test "aggregateProviderFeedback combines route health by provider":
    let aggregated = aggregateProviderFeedback(@[
      RouteFeedback(route: "openrouter/openai/gpt-4o-mini", calls: 4, okCalls: 4, errCalls: 0, avgLatencyMs: 700),
      RouteFeedback(route: "openrouter/anthropic/claude-sonnet-4-6", calls: 2, okCalls: 1, errCalls: 1, avgLatencyMs: 1300),
      RouteFeedback(route: "anthropic/claude-opus-4-6", calls: 3, okCalls: 0, errCalls: 3, avgLatencyMs: 9000),
    ])
    check aggregated.len == 2
    check aggregated[0].providerName == "openrouter"
    check aggregated[0].calls == 6
    check aggregated[0].okCalls == 5
    check aggregated[0].errCalls == 1

  test "applyProviderCircuitBreaker removes unhealthy providers when alternatives exist":
    let base = @[
      ProviderSelection(providerName: "anthropic", modelName: "claude-opus-4-6"),
      ProviderSelection(providerName: "anthropic", modelName: "claude-sonnet-4-6"),
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
    ]
    let filtered = applyProviderCircuitBreaker(base, @[
      RouteFeedback(route: "anthropic/claude-opus-4-6", calls: 5, okCalls: 0, errCalls: 5, avgLatencyMs: 19_000),
      RouteFeedback(route: "anthropic/claude-sonnet-4-6", calls: 5, okCalls: 1, errCalls: 4, avgLatencyMs: 18_500),
      RouteFeedback(route: "openrouter/openai/gpt-4o-mini", calls: 6, okCalls: 6, errCalls: 0, avgLatencyMs: 800),
    ])
    check filtered == @[
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
    ]

  test "applyProviderCircuitBreaker keeps only provider when no alternative remains":
    let base = @[
      ProviderSelection(providerName: "anthropic", modelName: "claude-opus-4-6"),
      ProviderSelection(providerName: "anthropic", modelName: "claude-sonnet-4-6"),
    ]
    let filtered = applyProviderCircuitBreaker(base, @[
      RouteFeedback(route: "anthropic/claude-opus-4-6", calls: 6, okCalls: 0, errCalls: 6, avgLatencyMs: 19_000),
      RouteFeedback(route: "anthropic/claude-sonnet-4-6", calls: 6, okCalls: 0, errCalls: 6, avgLatencyMs: 19_000),
    ])
    check filtered == base

  test "applyProviderCooldowns removes providers with active cooldowns":
    let base = @[
      ProviderSelection(providerName: "anthropic", modelName: "claude-opus-4-6"),
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
      ProviderSelection(providerName: "gemini", modelName: "gemini-2.5-flash"),
    ]
    let filtered = applyProviderCooldowns(base, @[
      ProviderCooldown(providerName: "anthropic", untilUnix: 200),
      ProviderCooldown(providerName: "gemini", untilUnix: 199),
    ], 100)
    check filtered == @[
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
    ]

  test "applyProviderCooldowns keeps base when every provider is cooling down":
    let base = @[
      ProviderSelection(providerName: "anthropic", modelName: "claude-opus-4-6"),
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
    ]
    let filtered = applyProviderCooldowns(base, @[
      ProviderCooldown(providerName: "anthropic", untilUnix: 200),
      ProviderCooldown(providerName: "openrouter", untilUnix: 210),
    ], 100)
    check filtered == base

  test "reorderSelectionsWithCost prefers cheaper priced routes":
    let base = @[
      ProviderSelection(providerName: "anthropic", modelName: "claude-opus-4-6"),
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
      ProviderSelection(providerName: "gemini", modelName: "gemini-2.5-flash"),
    ]
    let reordered = reorderSelectionsWithCost(base, @[
      RouteCostHint(route: "anthropic/claude-opus-4-6", hasPricing: true,
                    inputCostMicrosPer1k: 15_000, outputCostMicrosPer1k: 75_000),
      RouteCostHint(route: "openrouter/openai/gpt-4o-mini", hasPricing: true,
                    inputCostMicrosPer1k: 150, outputCostMicrosPer1k: 600),
    ])
    check reordered[0].providerName == "openrouter"
    check reordered[^1].providerName == "anthropic"

  test "reorderSelectionsWithCost respects quality-first policy":
    let base = @[
      ProviderSelection(providerName: "anthropic", modelName: "claude-opus-4-6"),
      ProviderSelection(providerName: "openrouter", modelName: "openai/gpt-4o-mini"),
    ]
    let reordered = reorderSelectionsWithCost(base, @[
      RouteCostHint(route: "anthropic/claude-opus-4-6", hasPricing: true,
                    inputCostMicrosPer1k: 15_000, outputCostMicrosPer1k: 75_000),
      RouteCostHint(route: "openrouter/openai/gpt-4o-mini", hasPricing: true,
                    inputCostMicrosPer1k: 150, outputCostMicrosPer1k: 600),
    ], "quality-first")
    check reordered == base
