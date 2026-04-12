## Pure smart-routing heuristics for provider/model selection.
##
## This module never talks to providers or the filesystem. It only turns
## persisted prefs plus request shape into an ordered list of provider/model
## candidates for the shell to try.
##
## Model selection is driven by ProviderCatalog — no hardcoded model strings
## for routing decisions.

import std/[algorithm, strutils]
import ../../domain/message
import ./provider_catalog

const
  AutoProviderLabel* = "auto"
  LongContextChars* = 60_000

type
  SmartRoutingPrefs* = object
    providerName*: string
    modelName*: string
    thinking*: string
    budgetPolicy*: string
    providerExplicit*: bool
    modelExplicit*: bool

  ProviderAvailability* = object
    openrouter*: bool
    anthropic*: bool
    zaiAnthropic*: bool
    gemini*: bool
    minimax*: bool
    zai*: bool
    zaiCoding*: bool

  ProviderSelection* = object
    providerName*: string
    modelName*: string

  RoutingTelemetryHook* = proc(selection: ProviderSelection;
                               prefs: SmartRoutingPrefs;
                               req: CompletionRequest) {.gcsafe.}

  RoutingResultHook* = proc(selection: ProviderSelection;
                            elapsedMs: int64;
                            ok: bool) {.gcsafe.}

  RouteFeedback* = object
    route*: string
    calls*: int
    okCalls*: int
    errCalls*: int
    avgLatencyMs*: int

  ProviderFeedback* = object
    providerName*: string
    calls*: int
    okCalls*: int
    errCalls*: int
    avgLatencyMs*: int

  ProviderCooldown* = object
    providerName*: string
    untilUnix*: int64

  RoutingFeedbackHook* = proc(): seq[RouteFeedback] {.gcsafe.}
  RoutingProviderCooldownHook* = proc(): seq[ProviderCooldown] {.gcsafe.}

  RouteCostHint* = object
    route*: string
    hasPricing*: bool
    inputCostMicrosPer1k*: int
    outputCostMicrosPer1k*: int

  RoutingCostHook* = proc(): seq[RouteCostHint] {.gcsafe.}

  RoutingSignals* = object
    hasTools*: bool
    hasImage*: bool
    approxInputChars*: int
    thinking*: string

  ## Catalog-aware routing helpers.
  ## Wraps ProviderCatalog + availability for clean routing logic.
  RoutingCatalog* = object
    catalog*: ProviderCatalog
    availability*: ProviderAvailability

func defaultSmartRoutingPrefs*(): SmartRoutingPrefs =
  SmartRoutingPrefs(
    providerName: "zai-coding",
    modelName: "",
    thinking: "off",
    budgetPolicy: "balanced",
  )

func normalizeThinking*(value: string): string =
  let normalized = value.strip.toLowerAscii()
  if normalized in ["low", "medium", "high"]: normalized else: "off"

func normalizeBudgetPolicy*(value: string): string =
  let normalized = value.strip.toLowerAscii()
  if normalized in ["cheap-first", "balanced", "quality-first"]:
    normalized
  else:
    "balanced"

func parseSmartRoutingPrefs*(preferencesMd: string): SmartRoutingPrefs =
  result = defaultSmartRoutingPrefs()
  for line in preferencesMd.splitLines():
    let parts = line.split('=', 1)
    if parts.len != 2:
      continue
    let key = parts[0].strip()
    let value = parts[1].strip().strip(chars = {'"'})
    case key
    of "provider":
      result.providerName = value
      result.providerExplicit = value.len > 0
    of "model":
      result.modelName = value
      result.modelExplicit = value.len > 0
    of "thinking":
      result.thinking = normalizeThinking(value)
    of "budget":
      result.budgetPolicy = normalizeBudgetPolicy(value)
    else:
      discard

func usesSmartRouting*(prefs: SmartRoutingPrefs): bool =
  if prefs.modelExplicit:
    return false
  if prefs.providerExplicit and prefs.providerName != AutoProviderLabel:
    return false
  true

func routingLabel*(prefs: SmartRoutingPrefs): string =
  if prefs.usesSmartRouting:
    return AutoProviderLabel
  if prefs.modelName.len > 0:
    prefs.providerName & "/" & prefs.modelName
  else:
    prefs.providerName

func defaultModelForProvider*(providerName: string;
                               catalog: ProviderCatalog = buildDefaultCatalog()): string =
  ## Look up the default model for a provider from the catalog.
  ## Uses the first model returned by getByProvider (ordered by registration).
  let models = catalog.getByProvider(providerName)
  if models.len > 0:
    models[0].canonicalName
  else:
    # Fallback for unknown providers
    case providerName
    of "openrouter": "openai/gpt-4o-mini"
    of "anthropic": "claude-opus-4-6"
    of "zai-anthropic": "glm-4.7"
    of "gemini": "gemini-2.5-flash"
    of "minimax": "MiniMax-M2"
    of "zai": "glm-4.7"
    else: "glm-4.7"

func selection(providerName: string; modelName = ""): ProviderSelection =
  ProviderSelection(
    providerName: providerName,
    modelName: if modelName.len > 0: modelName else: defaultModelForProvider(providerName),
  )

func requestApproxChars*(req: CompletionRequest): int =
  result = req.system.len
  for msg in req.messages:
    result += msg.text.len
    result += msg.imageUrl.len
    result += msg.toolCallId.len
    for call in msg.toolCalls:
      result += call.name.len + call.inputJson.len

func buildRoutingSignals*(prefs: SmartRoutingPrefs;
                          req: CompletionRequest): RoutingSignals =
  var hasImage = false
  for msg in req.messages:
    if msg.imageUrl.len > 0:
      hasImage = true
      break
  RoutingSignals(
    hasTools: req.tools.len > 0,
    hasImage: hasImage,
    approxInputChars: requestApproxChars(req),
    thinking: normalizeThinking(prefs.thinking),
  )

func isAvailable(availability: ProviderAvailability; providerName: string): bool =
  case providerName
  of "openrouter": availability.openrouter
  of "anthropic": availability.anthropic
  of "zai-anthropic": availability.zaiAnthropic
  of "gemini": availability.gemini
  of "minimax": availability.minimax
  of "zai": availability.zai
  of "zai-coding": availability.zaiCoding
  else: false

# ── Catalog-driven routing helpers ────────────────────────────────────────────

func availableProviders(rc: RoutingCatalog): seq[string] {.used.} =
  ## Return list of provider names that are currently available.
  let avail = rc.availability
  if avail.openrouter: result.add("openrouter")
  if avail.anthropic: result.add("anthropic")
  if avail.zaiAnthropic: result.add("zai-anthropic")
  if avail.gemini: result.add("gemini")
  if avail.minimax: result.add("minimax")
  if avail.zai: result.add("zai")
  if avail.zaiCoding: result.add("zai-coding")

func queryModels*(rc: RoutingCatalog; providerName: string;
                 hasTools = false; hasImage = false;
                 hasThinking = false): seq[ProviderModelEntry] =
  ## Query catalog for models from a specific provider with given capabilities.
  let q = ModelQuery(
    provider: providerName,
    hasTools: hasTools,
    hasImage: hasImage,
    hasThinking: hasThinking,
  )
  let all = rc.catalog.query(q)
  # Filter by availability (already handled by provider filter, but sort by budget priority)
  orderByPriority(all, "quality-first")

func selectBestModel*(rc: RoutingCatalog; providerName: string;
                     hasTools = false; hasImage = false;
                     hasThinking = false): ProviderSelection =
  ## Select the best available model from a provider based on catalog.
  if not isAvailable(rc.availability, providerName):
    return ProviderSelection()  # empty
  let models = rc.queryModels(providerName, hasTools, hasImage, hasThinking)
  if models.len == 0:
    # Fallback: use any model from the provider
    let allModels = rc.catalog.getByProvider(providerName)
    if allModels.len > 0:
      return ProviderSelection(
        providerName: providerName,
        modelName: allModels[0].canonicalName,
      )
    return ProviderSelection()  # empty
  ProviderSelection(
    providerName: providerName,
    modelName: models[0].canonicalName,
  )

func addSelectionIfAvailable*(selections: var seq[ProviderSelection];
                             rc: RoutingCatalog; providerName: string;
                             hasTools = false; hasImage = false;
                             hasThinking = false) =
  ## Add the best model from a provider if the provider is available.
  let sel = rc.selectBestModel(providerName, hasTools, hasImage, hasThinking)
  if sel.providerName.len > 0:
    selections.add(sel)

func addAnthropicWithFallback*(selections: var seq[ProviderSelection];
                              rc: RoutingCatalog;
                              hasTools = false; hasThinking = false) =
  ## Add anthropic model, with zai-anthropic fallback.
  let direct = rc.selectBestModel("anthropic", hasTools, false, hasThinking)
  if direct.providerName.len > 0:
    selections.add(direct)
  elif rc.availability.zaiAnthropic:
    let fallback = rc.selectBestModel("zai-anthropic", hasTools, false, hasThinking)
    if fallback.providerName.len > 0:
      selections.add(fallback)

func addAnthropicCompatible(selections: var seq[ProviderSelection];
                            availability: ProviderAvailability;
                            anthropicModel: string;
                            zaiModel = "") {.used.} =
  if availability.anthropic:
    selections.add(selection("anthropic", anthropicModel))
  elif availability.zaiAnthropic:
    let modelName = if zaiModel.len > 0: zaiModel else: anthropicModel
    selections.add(selection("zai-anthropic", modelName))

func addIfAvailable(selections: var seq[ProviderSelection];
                    availability: ProviderAvailability;
                    providerName: string;
                    modelName = "") {.used.} =
  if availability.isAvailable(providerName):
    selections.add(selection(providerName, modelName))

func dedupeSelections*(selections: seq[ProviderSelection]): seq[ProviderSelection] =
  for candidate in selections:
    var seen = false
    for existing in result:
      if existing.providerName == candidate.providerName and
         existing.modelName == candidate.modelName:
        seen = true
        break
    if not seen:
      result.add(candidate)

func explicitSelection*(prefs: SmartRoutingPrefs): ProviderSelection =
  selection(
    if prefs.providerName.len > 0: prefs.providerName else: "zai-coding",
    prefs.modelName,
  )

func formatSelection*(selection: ProviderSelection): string =
  selection.providerName & "/" & selection.modelName

func feedbackBucket(feedback: RouteFeedback): int =
  if feedback.calls <= 0:
    return 0
  let errRate = (feedback.errCalls * 100) div max(feedback.calls, 1)
  if feedback.calls >= 5 and feedback.errCalls == 0 and feedback.avgLatencyMs > 0 and feedback.avgLatencyMs <= 1200:
    return -1
  if errRate >= 50 or feedback.avgLatencyMs >= 12_000:
    return 3
  if errRate >= 25 or feedback.avgLatencyMs >= 6_000:
    return 2
  if feedback.errCalls > 0 or feedback.avgLatencyMs >= 2_500:
    return 1
  0

func shouldCircuitBreakRoute*(feedback: RouteFeedback): bool =
  if feedback.calls < 4:
    return false
  let errRate = (feedback.errCalls * 100) div max(feedback.calls, 1)
  if feedback.errCalls == feedback.calls:
    return true
  if feedback.calls >= 6 and errRate >= 75:
    return true
  if errRate >= 50 and feedback.avgLatencyMs >= 15_000:
    return true
  false

func routeProviderName*(route: string): string =
  let parts = route.split('/', 1)
  if parts.len > 0: parts[0] else: ""

func aggregateProviderFeedback*(feedback: seq[RouteFeedback]): seq[ProviderFeedback] =
  for item in feedback:
    let providerName = routeProviderName(item.route)
    if providerName.len == 0:
      continue
    var found = false
    for existing in result.mitems:
      if existing.providerName == providerName:
        let totalCalls = existing.calls + item.calls
        let totalLatency =
          existing.avgLatencyMs * existing.calls + item.avgLatencyMs * item.calls
        existing.calls = totalCalls
        existing.okCalls += item.okCalls
        existing.errCalls += item.errCalls
        existing.avgLatencyMs =
          if totalCalls > 0: totalLatency div totalCalls else: 0
        found = true
        break
    if not found:
      result.add(ProviderFeedback(
        providerName: providerName,
        calls: item.calls,
        okCalls: item.okCalls,
        errCalls: item.errCalls,
        avgLatencyMs: item.avgLatencyMs,
      ))

func shouldCircuitBreakProvider*(feedback: ProviderFeedback): bool =
  if feedback.calls < 4:
    return false
  let errRate = (feedback.errCalls * 100) div max(feedback.calls, 1)
  if feedback.errCalls == feedback.calls:
    return true
  if feedback.calls >= 8 and errRate >= 75:
    return true
  if errRate >= 60 and feedback.avgLatencyMs >= 18_000:
    return true
  false

func applyProviderCooldowns*(selections: seq[ProviderSelection];
                             cooldowns: seq[ProviderCooldown];
                             nowUnix: int64): seq[ProviderSelection] =
  if selections.len <= 1:
    return selections

  for selection in selections:
    var blocked = false
    for cooldown in cooldowns:
      if cooldown.providerName == selection.providerName and cooldown.untilUnix > nowUnix:
        blocked = true
        break
    if not blocked:
      result.add(selection)

  if result.len == 0:
    selections
  else:
    result

func reorderSelectionsWithFeedback*(selections: seq[ProviderSelection];
                                    feedback: seq[RouteFeedback]): seq[ProviderSelection] =
  type RankedSelection = object
    selection: ProviderSelection
    bucket: int
    baseIndex: int

  var ranked: seq[RankedSelection] = @[]
  for i, selection in selections:
    let route = selection.formatSelection
    var bucket = 0
    for item in feedback:
      if item.route == route:
        bucket = feedbackBucket(item)
        break
    ranked.add(RankedSelection(selection: selection, bucket: bucket, baseIndex: i))

  sort(ranked, proc(a, b: RankedSelection): int =
    if a.bucket != b.bucket:
      return cmp(a.bucket, b.bucket)
    cmp(a.baseIndex, b.baseIndex)
  )

  for item in ranked:
    result.add(item.selection)

func applyCircuitBreaker*(selections: seq[ProviderSelection];
                          feedback: seq[RouteFeedback]): seq[ProviderSelection] =
  if selections.len <= 1:
    return selections

  for selection in selections:
    let route = selection.formatSelection
    var blocked = false
    for item in feedback:
      if item.route == route and item.shouldCircuitBreakRoute:
        blocked = true
        break
    if not blocked:
      result.add(selection)

  if result.len == 0:
    selections
  else:
    result

func applyProviderCircuitBreaker*(selections: seq[ProviderSelection];
                                  feedback: seq[RouteFeedback]): seq[ProviderSelection] =
  if selections.len <= 1:
    return selections

  let providerFeedback = aggregateProviderFeedback(feedback)
  for selection in selections:
    var blocked = false
    for item in providerFeedback:
      if item.providerName == selection.providerName and item.shouldCircuitBreakProvider:
        blocked = true
        break
    if not blocked:
      result.add(selection)

  if result.len == 0:
    selections
  else:
    result

func costBucket(hint: RouteCostHint; budgetPolicy: string): int =
  let policy = normalizeBudgetPolicy(budgetPolicy)
  if policy == "quality-first":
    return 0
  if not hint.hasPricing:
    return if policy == "cheap-first": 2 else: 1
  let totalMicros = hint.inputCostMicrosPer1k + hint.outputCostMicrosPer1k
  if totalMicros <= 0:
    return -1
  if policy == "cheap-first":
    if totalMicros <= 1_000:
      return -1
    if totalMicros <= 5_000:
      return 0
    if totalMicros <= 20_000:
      return 2
    return 4
  if totalMicros <= 1_000:
    return 0
  if totalMicros <= 5_000:
    return 1
  if totalMicros <= 20_000:
    return 2
  3

func reorderSelectionsWithCost*(selections: seq[ProviderSelection];
                                costs: seq[RouteCostHint];
                                budgetPolicy = "balanced"): seq[ProviderSelection] =
  type RankedSelection = object
    selection: ProviderSelection
    bucket: int
    baseIndex: int

  var ranked: seq[RankedSelection] = @[]
  for i, selection in selections:
    let route = selection.formatSelection
    var bucket = 0
    for item in costs:
      if item.route == route:
        bucket = costBucket(item, budgetPolicy)
        break
    ranked.add(RankedSelection(selection: selection, bucket: bucket, baseIndex: i))

  sort(ranked, proc(a, b: RankedSelection): int =
    if a.bucket != b.bucket:
      return cmp(a.bucket, b.bucket)
    cmp(a.baseIndex, b.baseIndex)
  )

  for item in ranked:
    result.add(item.selection)

func smartRouteSelections*(prefs: SmartRoutingPrefs;
                           req: CompletionRequest;
                           availability: ProviderAvailability): seq[ProviderSelection] =
  if not prefs.usesSmartRouting:
    return @[prefs.explicitSelection]

  let signals = buildRoutingSignals(prefs, req)
  let rc = RoutingCatalog(
    catalog: buildDefaultCatalog(),
    availability: availability,
  )

  # Image requests: prefer multimodal providers
  if signals.hasImage:
    addSelectionIfAvailable(result, rc, "openrouter", hasImage = true)
    addSelectionIfAvailable(result, rc, "gemini", hasImage = true)

  # Long context: prefer models with large context windows
  if signals.approxInputChars >= LongContextChars:
    addSelectionIfAvailable(result, rc, "gemini", hasImage = true)
    addAnthropicWithFallback(result, rc, hasTools = false, hasThinking = false)
    addSelectionIfAvailable(result, rc, "openrouter", hasThinking = true)

  # Thinking-based routing
  case signals.thinking
  of "high":
    if signals.hasTools:
      addAnthropicWithFallback(result, rc, hasTools = true, hasThinking = true)
      addSelectionIfAvailable(result, rc, "zai-coding", hasTools = true, hasThinking = true)
      addSelectionIfAvailable(result, rc, "gemini", hasTools = true, hasThinking = true)
      addSelectionIfAvailable(result, rc, "openrouter", hasTools = true, hasThinking = true)
    else:
      addAnthropicWithFallback(result, rc, hasTools = false, hasThinking = true)
      addSelectionIfAvailable(result, rc, "gemini", hasTools = false, hasThinking = true)
      addSelectionIfAvailable(result, rc, "zai", hasTools = false, hasThinking = true)
      addSelectionIfAvailable(result, rc, "openrouter", hasTools = false, hasThinking = true)
  of "medium":
    if signals.hasTools:
      addSelectionIfAvailable(result, rc, "zai-coding", hasTools = true)
      addAnthropicWithFallback(result, rc, hasTools = true)
      addSelectionIfAvailable(result, rc, "openrouter", hasTools = true)
      addSelectionIfAvailable(result, rc, "gemini", hasTools = true)
    else:
      addSelectionIfAvailable(result, rc, "zai", hasTools = false, hasThinking = true)
      addSelectionIfAvailable(result, rc, "openrouter")
      addAnthropicWithFallback(result, rc)
      addSelectionIfAvailable(result, rc, "gemini")
      addSelectionIfAvailable(result, rc, "minimax")
  else:
    if signals.hasTools:
      addSelectionIfAvailable(result, rc, "zai-coding", hasTools = true)
      addSelectionIfAvailable(result, rc, "openrouter", hasTools = true)
      addAnthropicWithFallback(result, rc, hasTools = true)
      addSelectionIfAvailable(result, rc, "gemini", hasTools = true)
      addSelectionIfAvailable(result, rc, "zai", hasTools = true)
    else:
      addSelectionIfAvailable(result, rc, "openrouter")
      addSelectionIfAvailable(result, rc, "zai")
      addSelectionIfAvailable(result, rc, "gemini")
      addAnthropicWithFallback(result, rc)
      addSelectionIfAvailable(result, rc, "minimax")
      addSelectionIfAvailable(result, rc, "zai-coding")

  # Fallback: add general-purpose models
  if signals.hasTools:
    addSelectionIfAvailable(result, rc, "zai-coding", hasTools = true)
    addSelectionIfAvailable(result, rc, "openrouter", hasTools = true)
    addAnthropicWithFallback(result, rc, hasTools = true)
    addSelectionIfAvailable(result, rc, "gemini", hasTools = true)
    addSelectionIfAvailable(result, rc, "zai", hasTools = true)
  else:
    addSelectionIfAvailable(result, rc, "openrouter")
    addSelectionIfAvailable(result, rc, "zai")
    addSelectionIfAvailable(result, rc, "gemini")
    addAnthropicWithFallback(result, rc)
    addSelectionIfAvailable(result, rc, "minimax")
    addSelectionIfAvailable(result, rc, "zai-coding")

  result = dedupeSelections(result)

func previewSmartRouteSelections*(prefs: SmartRoutingPrefs;
                                  availability: ProviderAvailability): seq[ProviderSelection] =
  smartRouteSelections(prefs, CompletionRequest(), availability)

func formatSelectionPreview*(selections: seq[ProviderSelection];
                             limit = 3): string =
  var items: seq[string] = @[]
  let take = min(limit, selections.len)
  for i in 0 ..< take:
    items.add(selections[i].formatSelection)
  items.join(" -> ")
