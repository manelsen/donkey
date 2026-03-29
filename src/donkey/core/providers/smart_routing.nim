## Pure smart-routing heuristics for provider/model selection.
##
## This module never talks to providers or the filesystem. It only turns
## persisted prefs plus request shape into an ordered list of provider/model
## candidates for the shell to try.

import std/[algorithm, strutils]
import ../../domain/message

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

func defaultModelForProvider*(providerName: string): string =
  case providerName
  of "openrouter": "openai/gpt-4o-mini"
  of "anthropic": "claude-opus-4-6"
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
  of "gemini": availability.gemini
  of "minimax": availability.minimax
  of "zai": availability.zai
  of "zai-coding": availability.zaiCoding
  else: false

func addIfAvailable(selections: var seq[ProviderSelection];
                    availability: ProviderAvailability;
                    providerName: string;
                    modelName = "") =
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

  if signals.hasImage:
    result.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
    result.addIfAvailable(availability, "gemini", "gemini-2.5-flash")

  if signals.approxInputChars >= LongContextChars:
    result.addIfAvailable(availability, "gemini", "gemini-2.5-pro")
    result.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")
    result.addIfAvailable(availability, "openrouter", "openai/gpt-4o")

  case signals.thinking
  of "high":
    if signals.hasTools:
      result.addIfAvailable(availability, "anthropic", "claude-opus-4-6")
      result.addIfAvailable(availability, "zai-coding", "glm-5")
      result.addIfAvailable(availability, "gemini", "gemini-2.5-pro")
      result.addIfAvailable(availability, "openrouter", "openai/gpt-4o")
    else:
      result.addIfAvailable(availability, "anthropic", "claude-opus-4-6")
      result.addIfAvailable(availability, "gemini", "gemini-2.5-pro")
      result.addIfAvailable(availability, "zai", "glm-5")
      result.addIfAvailable(availability, "openrouter", "openai/gpt-4o")
  of "medium":
    if signals.hasTools:
      result.addIfAvailable(availability, "zai-coding", "glm-5")
      result.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")
      result.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
      result.addIfAvailable(availability, "gemini", "gemini-2.5-flash")
    else:
      result.addIfAvailable(availability, "zai", "glm-5")
      result.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
      result.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")
      result.addIfAvailable(availability, "gemini", "gemini-2.5-flash")
      result.addIfAvailable(availability, "minimax", "MiniMax-M2")
  else:
    if signals.hasTools:
      result.addIfAvailable(availability, "zai-coding", "glm-4.7")
      result.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
      result.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")
      result.addIfAvailable(availability, "gemini", "gemini-2.5-flash")
    else:
      result.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
      result.addIfAvailable(availability, "zai", "glm-4.7")
      result.addIfAvailable(availability, "gemini", "gemini-2.5-flash")
      result.addIfAvailable(availability, "minimax", "MiniMax-M2")
      result.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")

  if signals.hasTools:
    result.addIfAvailable(availability, "zai-coding", "glm-4.7")
    result.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
    result.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")
    result.addIfAvailable(availability, "gemini", "gemini-2.5-flash")
    result.addIfAvailable(availability, "zai", "glm-4.7")
  else:
    result.addIfAvailable(availability, "openrouter", "openai/gpt-4o-mini")
    result.addIfAvailable(availability, "zai", "glm-4.7")
    result.addIfAvailable(availability, "gemini", "gemini-2.5-flash")
    result.addIfAvailable(availability, "anthropic", "claude-sonnet-4-6")
    result.addIfAvailable(availability, "minimax", "MiniMax-M2")
    result.addIfAvailable(availability, "zai-coding", "glm-4.7")

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
