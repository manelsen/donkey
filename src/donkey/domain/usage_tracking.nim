## usage_tracking — Token and cost tracking for LLM usage.

import std/[tables, strformat]

type
  ModelPricing* = object
    provider*:   string
    model*:      string
    inputCost*:  float
    outputCost*: float

  UsageStats* = object
    inputTokens*:   int
    outputTokens*:  int
    totalTokens*:   int
    cost*:         float

  SessionUsage* = object
    userId*:       string
    sessionId*:    string
    turnCount*:    int
    stats*:        UsageStats

  ProviderUsage* = object
    provider*:     string
    model*:        string
    requestCount*: int
    totalInput*:   int
    totalOutput*:  int
    totalCost*:    float

const
  DefaultPricing* = ModelPricing(
    provider: "unknown",
    model: "unknown",
    inputCost: 0.0,
    outputCost: 0.0,
  )

  OpenAIPricing* = {
    "gpt-4o": ModelPricing(provider: "openai", model: "gpt-4o", inputCost: 5.0, outputCost: 15.0),
    "gpt-4o-mini": ModelPricing(provider: "openai", model: "gpt-4o-mini", inputCost: 0.15, outputCost: 0.60),
    "gpt-4-turbo": ModelPricing(provider: "openai", model: "gpt-4-turbo", inputCost: 10.0, outputCost: 30.0),
  }.toTable

  AnthropicPricing* = {
    "claude-3-5-sonnet-20241022": ModelPricing(provider: "anthropic", model: "claude-3-5-sonnet-20241022", inputCost: 3.0, outputCost: 15.0),
    "claude-3-sonnet-20240229": ModelPricing(provider: "anthropic", model: "claude-3-sonnet-20240229", inputCost: 3.0, outputCost: 15.0),
    "claude-3-opus-20240229": ModelPricing(provider: "anthropic", model: "claude-3-opus-20240229", inputCost: 15.0, outputCost: 75.0),
    "claude-3-haiku-20240307": ModelPricing(provider: "anthropic", model: "claude-3-haiku-20240307", inputCost: 0.25, outputCost: 1.25),
  }.toTable

  DeepSeekPricing* = {
    "deepseek-chat": ModelPricing(provider: "deepseek", model: "deepseek-chat", inputCost: 0.14, outputCost: 0.28),
    "deepseek-coder": ModelPricing(provider: "deepseek", model: "deepseek-coder", inputCost: 0.14, outputCost: 0.28),
  }.toTable

func getModelPricing*(provider, model: string): ModelPricing =
  let modelKey = model
  if provider == "openai" and OpenAIPricing.hasKey(modelKey):
    return OpenAIPricing[modelKey]
  if provider == "anthropic" and AnthropicPricing.hasKey(modelKey):
    return AnthropicPricing[modelKey]
  if provider == "deepseek" and DeepSeekPricing.hasKey(modelKey):
    return DeepSeekPricing[modelKey]
  DefaultPricing

func calculateCost*(pricing: ModelPricing; inputTokens, outputTokens: int): float =
  let inputCost = float(inputTokens) / 1_000_000.0 * pricing.inputCost
  let outputCost = float(outputTokens) / 1_000_000.0 * pricing.outputCost
  inputCost + outputCost

func newUsageStats*(inputTokens, outputTokens: int; pricing: ModelPricing): UsageStats =
  let total = inputTokens + outputTokens
  let cost = calculateCost(pricing, inputTokens, outputTokens)
  UsageStats(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    totalTokens: total,
    cost: cost,
  )

func addUsage*(existing: var UsageStats; additional: UsageStats) =
  existing.inputTokens += additional.inputTokens
  existing.outputTokens += additional.outputTokens
  existing.totalTokens += additional.totalTokens
  existing.cost += additional.cost

func formatUsageFooter*(stats: UsageStats; mode: string = "compact"): string =
  case mode
  of "full":
    "Usage: " & $stats.inputTokens & " in / " & $stats.outputTokens & " out / $" & 
      $(stats.cost) & " total"
  of "compact":
    "$" & $(stats.cost) & " (" & $stats.totalTokens & " tok)"
  of "minimal":
    $stats.totalTokens & " tok"
  else:
    ""

func `$`*(stats: UsageStats): string =
  "Tokens: " & $stats.inputTokens & " in, " & $stats.outputTokens & 
    " out | $" & $(stats.cost)

func newSessionUsage*(userId, sessionId: string): SessionUsage =
  SessionUsage(
    userId: userId,
    sessionId: sessionId,
    turnCount: 0,
    stats: UsageStats(inputTokens: 0, outputTokens: 0, totalTokens: 0, cost: 0.0),
  )

func recordTurn*(usage: var SessionUsage; inputTokens, outputTokens: int; pricing: ModelPricing) =
  usage.turnCount += 1
  usage.stats.inputTokens += inputTokens
  usage.stats.outputTokens += outputTokens
  usage.stats.totalTokens += inputTokens + outputTokens
  usage.stats.cost += calculateCost(pricing, inputTokens, outputTokens)

func formatSessionSummary*(usage: SessionUsage): string =
  "Sessao: " & $usage.turnCount & " turnos | " & 
    $usage.stats.totalTokens & " tokens | $" & 
    $((usage.stats.cost))
