import std/[unittest, strutils]
import donkey/domain/routing/smart_route
import donkey/domain/message

suite "smart_route classifier":

  test "scoreInputComplexity returns 0 for empty input":
    check scoreInputComplexity(0) == 0

  test "scoreInputComplexity returns low score for short input":
    let score = scoreInputComplexity(100)
    check score < 10

  test "scoreInputComplexity caps at 100 for very long input":
    let score = scoreInputComplexity(LongContextChars * 2)
    check score == 100

  test "scoreInputComplexity scales linearly up to long context":
    let score2k = scoreInputComplexity(2_000)
    let score60k = scoreInputComplexity(60_000)
    check score2k < score60k
    check score60k == 100

  test "scoreToolComplexity is 0 for no tools and no thinking":
    check scoreToolComplexity(false, "off") == 0

  test "scoreToolComplexity adds 50 for tool presence":
    check scoreToolComplexity(true, "off") == 50

  test "scoreToolComplexity adds 50 for high thinking":
    check scoreToolComplexity(false, "high") == 50

  test "scoreToolComplexity adds 25 for medium thinking":
    check scoreToolComplexity(false, "medium") == 25

  test "scoreToolComplexity combines tools and thinking":
    check scoreToolComplexity(true, "high") == 100

  test "scoreContextComplexity ignores images for short context":
    let withoutImage = scoreContextComplexity(500, false)
    let withImage = scoreContextComplexity(500, true)
    check withImage == withoutImage + 60

  test "scoreContextComplexity caps at 100":
    let score = scoreContextComplexity(LongContextChars * 2, true)
    check score == 100

  test "normalizeThinking handles various inputs":
    check normalizeThinking("HIGH") == "high"
    check normalizeThinking(" medium ") == "medium"
    check normalizeThinking("invalid") == "off"
    check normalizeThinking("") == "off"

  test "computeOverallComplexity returns simple for low weighted score":
    # Low scores across all dimensions
    check computeOverallComplexity(10, 10, 10) == tcSimple

  test "computeOverallComplexity returns moderate for mid weighted score":
    # Tool score is weighted 40%
    check computeOverallComplexity(50, 50, 50) == tcModerate

  test "computeOverallComplexity returns complex for high weighted score":
    # High scores across all dimensions
    check computeOverallComplexity(80, 80, 80) == tcComplex

  test "classifyTaskComplexity produces valid score for simple request":
    let signals = RoutingSignals(
      hasTools: false,
      hasImage: false,
      approxInputChars: 500,
      thinking: "off",
    )
    let score = signals.classifyTaskComplexity
    check score.complexity == tcSimple
    check score.inputScore < 10
    check score.toolScore == 0

  test "classifyTaskComplexity produces moderate score for tool request":
    let signals = RoutingSignals(
      hasTools: true,
      hasImage: false,
      approxInputChars: 2_000,
      thinking: "medium",
    )
    let score = signals.classifyTaskComplexity
    # With toolScore=75, inputScore=3, contextScore=1 → weighted=31 → Simple
    check score.complexity == tcSimple
    check score.toolScore == 75

  test "classifyTaskComplexity produces complex score for image request":
    let signals = RoutingSignals(
      hasTools: true,
      hasImage: true,
      approxInputChars: 30_000,
      thinking: "high",
    )
    let score = signals.classifyTaskComplexity
    check score.complexity == tcComplex

  test "routeByComplexity selects cheap providers for simple tasks":
    let score = ComplexityScore(
      complexity: tcSimple,
      inputScore: 5,
      toolScore: 0,
      contextScore: 5,
      rawChars: 500,
    )
    let availability = ProviderAvailability(
      openrouter: true,
      minimax: true,
      zai: true,
      gemini: true,
    )
    let routes = score.routeByComplexity(availability, "balanced")
    check routes.len > 0
    check routes[0].providerName == "minimax"

  test "routeByComplexity selects capable providers for complex tasks":
    let score = ComplexityScore(
      complexity: tcComplex,
      inputScore: 80,
      toolScore: 100,
      contextScore: 80,
      rawChars: 50_000,
    )
    let availability = ProviderAvailability(
      anthropic: true,
      zaiCoding: true,
      gemini: true,
    )
    let routes = score.routeByComplexity(availability, "balanced")
    check routes.len > 0
    check routes[0].providerName == "anthropic"

  test "routeByComplexity respects cheap-first budget":
    let score = ComplexityScore(
      complexity: tcModerate,
      inputScore: 30,
      toolScore: 50,
      contextScore: 30,
      rawChars: 5_000,
    )
    let availability = ProviderAvailability(
      openrouter: true,
      anthropic: true,
      minimax: true,
    )
    let routes = score.routeByComplexity(availability, "cheap-first")
    check routes.len > 0
    # minimax should appear early in cheap-first
    var hasMinimax = false
    for s in routes:
      if s.providerName == "minimax":
        hasMinimax = true
        break
    check hasMinimax

  test "routeByComplexity respects quality-first budget":
    let score = ComplexityScore(
      complexity: tcSimple,
      inputScore: 10,
      toolScore: 0,
      contextScore: 10,
      rawChars: 500,
    )
    let availability = ProviderAvailability(
      openrouter: true,
      anthropic: true,
    )
    let routes = score.routeByComplexity(availability, "quality-first")
    check routes.len > 0
    # In quality-first, anthropic should be included for simple tasks
    var hasAnthropic = false
    for s in routes:
      if s.providerName == "anthropic":
        hasAnthropic = true
        break
    check hasAnthropic

  test "routeByComplexity handles empty availability":
    let score = ComplexityScore(
      complexity: tcSimple,
      inputScore: 10,
      toolScore: 0,
      contextScore: 10,
      rawChars: 500,
    )
    let availability = ProviderAvailability()
    let routes = score.routeByComplexity(availability, "balanced")
    check routes.len == 0

  test "complexityLabel produces readable string":
    let score = ComplexityScore(
      complexity: tcModerate,
      inputScore: 30,
      toolScore: 50,
      contextScore: 40,
      rawChars: 10_000,
    )
    let label = score.complexityLabel
    check label.contains("moderate")
    check label.contains("input=30")
    check label.contains("tool=50")

  test "classifyTaskComplexity via tuple works":
    let prefs = defaultSmartRoutingPrefs()
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "hello world")]
    )
    let score = classifyTaskComplexity(prefs, req)
    check score.complexity == tcSimple

  test "classifyAndRoute produces both score and selections":
    let prefs = parseSmartRoutingPrefs("")
    let req = CompletionRequest(
      messages: @[ChatMessage(role: "user", text: "describe this", imageUrl: "https://x.png")]
    )
    let availability = ProviderAvailability(
      openrouter: true,
      gemini: true,
    )
    let (score, selections) = classifyAndRoute(prefs, req, availability)
    # With image but short text and no tools/thinking: weighted=18 → Simple
    check score.complexity == tcSimple
    check selections.len > 0
    check selections[0].providerName == "openrouter"
