import std/unittest
import donkey/domain/usage_tracking

suite "Usage Tracking":

  test "getModelPricing returns default for unknown":
    let pricing = getModelPricing("unknown", "unknown")
    check pricing.inputCost == 0.0

  test "getModelPricing returns OpenAI pricing":
    let pricing = getModelPricing("openai", "gpt-4o")
    check pricing.provider == "openai"
    check pricing.inputCost == 5.0

  test "calculateCost computes correctly":
    let pricing = ModelPricing(provider: "test", model: "test", inputCost: 1.0, outputCost: 2.0)
    let cost = calculateCost(pricing, 1000000, 1000000)
    check cost == 3.0

  test "newUsageStats creates stats":
    let pricing = ModelPricing(provider: "test", model: "test", inputCost: 1.0, outputCost: 2.0)
    let stats = newUsageStats(1000, 500, pricing)
    check stats.inputTokens == 1000
    check stats.outputTokens == 500
    check stats.totalTokens == 1500

  test "addUsage accumulates stats":
    var existing = UsageStats(inputTokens: 100, outputTokens: 50, totalTokens: 150, cost: 0.01)
    let additional = UsageStats(inputTokens: 200, outputTokens: 100, totalTokens: 300, cost: 0.02)
    addUsage(existing, additional)
    check existing.inputTokens == 300
    check existing.outputTokens == 150
    check existing.totalTokens == 450

  test "formatUsageFooter returns string":
    let stats = UsageStats(inputTokens: 1500, outputTokens: 300, totalTokens: 1800, cost: 0.0125)
    let footer = formatUsageFooter(stats, "compact")
    check footer.len > 0

  test "newSessionUsage creates empty session":
    let usage = newSessionUsage("user123", "session456")
    check usage.userId == "user123"
    check usage.sessionId == "session456"
    check usage.turnCount == 0

  test "recordTurn increments counters":
    var usage = newSessionUsage("user123", "session456")
    let pricing = ModelPricing(provider: "test", model: "test", inputCost: 1.0, outputCost: 2.0)
    recordTurn(usage, 100, 50, pricing)
    check usage.turnCount == 1
    check usage.stats.inputTokens == 100
