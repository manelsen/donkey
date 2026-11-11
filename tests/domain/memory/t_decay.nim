import std/[math, sequtils]
import unittest2
import ../../../src/donkey/domain/memory/decay
import ../../../src/donkey/core/pipeops

suite "domain/memory/decay":
  suite "exponentialDecay":
    test "fresh item (0 hours) returns initial score":
      check exponentialDecay(1.0, 0.0, 0.01) == 1.0

    test "after 1 hour with 0.01 rate":
      let result = exponentialDecay(1.0, 1.0, 0.01)
      check abs(result - exp(-0.01)) < 0.0001

    test "after 100 hours with 0.01 rate":
      let result = exponentialDecay(1.0, 100.0, 0.01)
      check abs(result - exp(-1.0)) < 0.0001

    test "initial score of 0 returns 0":
      check exponentialDecay(0.0, 100.0, 0.01) == 0.0

    test "negative initial score stays negative":
      check exponentialDecay(-1.0, 100.0, 0.01) == -1.0 * exp(-1.0)

  suite "linearDecay":
    test "fresh item (0 hours) returns initial score":
      check linearDecay(1.0, 0.0, 0.01) == 1.0

    test "after 50 hours with 0.01 rate":
      let result = linearDecay(1.0, 50.0, 0.01)
      check abs(result - 0.5) < 0.0001

    test "after 100 hours with 0.01 rate":
      check linearDecay(1.0, 100.0, 0.01) == 0.0

    test "after 150 hours (should clamp to 0)":
      check linearDecay(1.0, 150.0, 0.01) == 0.0

    test "initial score of 0 returns 0":
      check linearDecay(0.0, 100.0, 0.01) == 0.0

  suite "halfLifeDecay":
    test "fresh item (0 hours) returns initial score":
      check halfLifeDecay(1.0, 0.0, 24.0) == 1.0

    test "after 1 half-life returns half":
      let result = halfLifeDecay(1.0, 24.0, 24.0)
      check abs(result - 0.5) < 0.0001

    test "after 2 half-lives returns quarter":
      let result = halfLifeDecay(1.0, 48.0, 24.0)
      check abs(result - 0.25) < 0.0001

    test "after 0.5 half-life":
      let result = halfLifeDecay(1.0, 12.0, 24.0)
      check abs(result - sqrt(0.5)) < 0.0001

    test "initial score of 0 returns 0":
      check halfLifeDecay(0.0, 24.0, 24.0) == 0.0

  suite "decayScore":
    test "dmExponential model":
      let cfg = DecayConfig(model: dmExponential, decayRate: 0.01, minScore: 0.0001)
      let result = decayScore(1.0, 100.0, cfg)
      check abs(result - exp(-1.0)) < 0.0001

    test "dmLinear model":
      let cfg = DecayConfig(model: dmLinear, decayRate: 0.01, minScore: 0.0001)
      let result = decayScore(1.0, 50.0, cfg)
      check abs(result - 0.5) < 0.0001

    test "dmHalfLife model":
      let cfg = DecayConfig(model: dmHalfLife, halfLifeHours: 24.0, minScore: 0.0001)
      let result = decayScore(1.0, 24.0, cfg)
      check abs(result - 0.5) < 0.0001

    test "minScore floor prevents zero":
      let cfg = DecayConfig(model: dmLinear, decayRate: 0.1, minScore: 0.01)
      let result = decayScore(1.0, 100.0, cfg)
      check result == 0.01

  suite "defaultDecayConfig":
    test "has half-life model":
      check defaultDecayConfig().model == dmHalfLife

    test "has reasonable half-life":
      check defaultDecayConfig().halfLifeHours == 30.0 * 24.0

    test "has minScore floor":
      check defaultDecayConfig().minScore == DefaultMinScore

  suite "decayScores with hoursElapsedFn":
    type MockItem = object
      hours: float
      score: float

    test "decays multiple items":
      let items = @[
        ScoredItem[MockItem](item: MockItem(hours: 0.0, score: 1.0), score: 1.0),
        ScoredItem[MockItem](item: MockItem(hours: 24.0, score: 1.0), score: 1.0),
        ScoredItem[MockItem](item: MockItem(hours: 48.0, score: 1.0), score: 1.0)
      ]
      let cfg = DecayConfig(model: dmHalfLife, halfLifeHours: 24.0, minScore: 0.0001)
      let hoursFn = proc(item: MockItem): float = item.hours
      let result = items.decayScores(hoursFn, cfg)

      check result.len == 3
      check abs(result[0].decayedScore - 1.0) < 0.0001
      check abs(result[1].decayedScore - 0.5) < 0.0001
      check abs(result[2].decayedScore - 0.25) < 0.0001

    test "preserves original score":
      let items = @[
        ScoredItem[MockItem](item: MockItem(hours: 24.0, score: 0.8), score: 0.8)
      ]
      let cfg = DecayConfig(model: dmHalfLife, halfLifeHours: 24.0, minScore: 0.0001)
      let hoursFn = proc(item: MockItem): float = item.hours
      let result = items.decayScores(hoursFn, cfg)

      check result[0].originalScore == 0.8
      check abs(result[0].decayedScore - 0.4) < 0.0001

  suite "decayScores with pre-computed hours":
    test "decays items with hours elapsed":
      let items = @[
        (item: "a", score: 1.0, hoursElapsed: 0.0),
        (item: "b", score: 1.0, hoursElapsed: 24.0),
        (item: "c", score: 1.0, hoursElapsed: 48.0)
      ]
      let cfg = DecayConfig(model: dmHalfLife, halfLifeHours: 24.0, minScore: 0.0001)
      let result = items.decayScores(cfg)

      check result.len == 3
      check abs(result[0].decayedScore - 1.0) < 0.0001
      check abs(result[1].decayedScore - 0.5) < 0.0001
      check abs(result[2].decayedScore - 0.25) < 0.0001

    test "preserves item in decayed result":
      let items = @[(item: "test", score: 1.0, hoursElapsed: 0.0)]
      let cfg = defaultDecayConfig()
      let result = items.decayScores(cfg)
      check result[0].item == "test"

  suite "filterByDecayedScore":
    test "keeps items above threshold":
      var items = @[
        DecayedItem[string](item: "a", originalScore: 1.0, decayedScore: 0.8, hoursElapsed: 0.0),
        DecayedItem[string](item: "b", originalScore: 1.0, decayedScore: 0.3, hoursElapsed: 0.0),
        DecayedItem[string](item: "c", originalScore: 1.0, decayedScore: 0.1, hoursElapsed: 0.0)
      ]
      let filtered = items.filterByDecayedScore(0.2)
      check filtered.len == 2
      check filtered[0].item == "a"
      check filtered[1].item == "b"

    test "empty seq returns empty":
      let items: seq[DecayedItem[string]] = @[]
      check items.filterByDecayedScore(0.5).len == 0

  suite "sortByDecayedScore":
    test "sorts descending by default":
      var items = @[
        DecayedItem[string](item: "a", originalScore: 1.0, decayedScore: 0.2, hoursElapsed: 0.0),
        DecayedItem[string](item: "b", originalScore: 1.0, decayedScore: 0.8, hoursElapsed: 0.0),
        DecayedItem[string](item: "c", originalScore: 1.0, decayedScore: 0.5, hoursElapsed: 0.0)
      ]
      let sorted = items.sortByDecayedScore()
      check sorted[0].item == "b"
      check sorted[1].item == "c"
      check sorted[2].item == "a"

    test "sorts ascending when specified":
      var items = @[
        DecayedItem[string](item: "a", originalScore: 1.0, decayedScore: 0.8, hoursElapsed: 0.0)
      ]
      let sorted = items.sortByDecayedScore(ascending = true)
      check sorted[0].item == "a"

  suite "relevanceRatio":
    test "fresh item has ratio near 1.0":
      let item = DecayedItem[string](item: "test", originalScore: 1.0, decayedScore: 0.95, hoursElapsed: 0.0)
      let ratio = relevanceRatio(item)
      check abs(ratio - 0.95) < 0.0001

    test "half-decayed item has ratio near 0.5":
      let item = DecayedItem[string](item: "test", originalScore: 1.0, decayedScore: 0.5, hoursElapsed: 0.0)
      let ratio = relevanceRatio(item)
      check abs(ratio - 0.5) < 0.0001

    test "zero original score returns 0":
      let item = DecayedItem[string](item: "test", originalScore: 0.0, decayedScore: 0.0, hoursElapsed: 0.0)
      check relevanceRatio(item) == 0.0

    test "negative original score handled safely":
      let item = DecayedItem[string](item: "test", originalScore: -1.0, decayedScore: -0.5, hoursElapsed: 0.0)
      check relevanceRatio(item) == 0.0

  suite "decayedRelevance":
    test "fresh memory keeps most of its score":
      let now = 1_700_000_000'i64
      let value = decayedRelevance(1.0'f32, now, now)
      check value > 0.99'f32

    test "old memory loses relevance":
      let now = 1_700_000_000'i64
      let thirtyDays = 30'i64 * 24 * 3600
      let oldValue = decayedRelevance(1.0'f32, now - thirtyDays, now)
      let freshValue = decayedRelevance(1.0'f32, now, now)
      check oldValue < freshValue
      check oldValue > 0.0'f32
      check abs(oldValue - 0.5'f32) < 0.001'f32

    test "future timestamps are treated as fresh":
      let now = 1_700_000_000'i64
      let value = decayedRelevance(1.0'f32, now + 3600, now)
      check value > 0.99'f32
