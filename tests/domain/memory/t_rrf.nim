## Tests for Reciprocal Rank Fusion

import std/[sequtils, algorithm]
import unittest2
import ../../../src/donkey/domain/memory/rrf

suite "RRF - Reciprocal Rank Fusion":

  suite "rrfScore":
    test "rank 0 gives 1/(k+0) = 1/k":
      let score = rrfScore(0)
      check abs(score - (1.0 / 60.0)) < 0.0001

    test "rank 1 gives 1/(k+1)":
      let score = rrfScore(1)
      check abs(score - (1.0 / 61.0)) < 0.0001

    test "rank 59 gives 1/(k+59) = 1/119":
      let score = rrfScore(59)
      check abs(score - (1.0 / 119.0)) < 0.0001

    test "custom k changes formula":
      let scoreK60 = rrfScore(0, 60.0)
      let scoreK30 = rrfScore(0, 30.0)
      check scoreK30 > scoreK60

  suite "rrfScoreWeighted":
    test "weight 2 doubles the score":
      let single = rrfScoreWeighted(0, 1.0)
      let doubled = rrfScoreWeighted(0, 2.0)
      check abs(doubled - (2.0 * single)) < 0.0001

    test "zero weight gives zero score":
      let score = rrfScoreWeighted(5, 0.0)
      check abs(score) < 0.0001

  suite "fuseRanks":
    test "equal ranks sum":
      let fused = fuseRanks(0, 0)
      let expected = (1.0 / 60.0) + (1.0 / 60.0)
      check abs(fused - expected) < 0.0001

    test "different ranks":
      let fused = fuseRanks(0, 1)
      let expected = (1.0 / 60.0) + (1.0 / 61.0)
      check abs(fused - expected) < 0.0001

    test "missing ranks (-1) only count existing":
      let fused = fuseRanks(-1, 0)
      let expected = 1.0 / 60.0
      check abs(fused - expected) < 0.0001

  suite "rankItems":
    test "empty input returns empty":
      let ranked = rankItems[string](@[])
      check ranked.len == 0

    test "single item gets rank 0":
      let items = @[(item: "a", score: 1.0)]
      let ranked = rankItems(items)
      check ranked.len == 1
      check ranked[0].item == "a"
      check ranked[0].rank == 0

    test "sorts descending by score":
      let items = @[
        (item: "low", score: 0.1),
        (item: "high", score: 0.9),
        (item: "mid", score: 0.5)
      ]
      let ranked = rankItems(items)
      check ranked[0].item == "high"
      check ranked[0].rank == 0
      check ranked[1].item == "mid"
      check ranked[1].rank == 1
      check ranked[2].item == "low"
      check ranked[2].rank == 2

    test "ascending option":
      let items = @[
        (item: "low", score: 0.1),
        (item: "high", score: 0.9)
      ]
      let ranked = rankItems(items, ascending = true)
      check ranked[0].item == "low"
      check ranked[1].item == "high"

  suite "fuseRankedLists":
    test "empty lists return empty":
      let fused = fuseRankedLists[string](@[], @[])
      check fused.len == 0

    test "single list fusion":
      let bm25 = @[RankedItem[string](item: "doc1", score: 0.8, rank: 0)]
      let fused = fuseRankedLists(bm25, @[])
      check fused.len == 1
      check fused[0].item == "doc1"
      check fused[0].originalRanks == "bm25:0"

    test "merges and sorts by rrf":
      let bm25 = @[
        RankedItem[string](item: "doc1", score: 0.9, rank: 0),
        RankedItem[string](item: "doc2", score: 0.7, rank: 1)
      ]
      let cosine = @[
        RankedItem[string](item: "doc2", score: 0.95, rank: 0),
        RankedItem[string](item: "doc3", score: 0.85, rank: 1)
      ]
      let fused = fuseRankedLists(bm25, cosine)
      
      # doc2 appears in both, should rank first
      # doc1 only in bm25 rank 0
      # doc3 only in cosine rank 1
      check fused.len == 3
      check fused[0].item == "doc2" # in both lists
      check fused[0].originalRanks == "bm25:1,cosine:0"

    test "tracks original ranks":
      let bm25 = @[RankedItem[string](item: "x", score: 0.8, rank: 2)]
      let cosine = @[RankedItem[string](item: "x", score: 0.9, rank: 0)]
      let fused = fuseRankedLists(bm25, cosine)
      check fused[0].originalRanks == "bm25:2,cosine:0"

  suite "fuseRankedListsWeighted":
    test "higher weight for bm25 increases its influence":
      let bm25 = @[RankedItem[string](item: "doc1", score: 0.9, rank: 0)]
      let cosine = @[RankedItem[string](item: "doc1", score: 0.9, rank: 0)]
      
      let equal = fuseRankedListsWeighted(bm25, cosine, 1.0, 1.0)
      let bm25Heavy = fuseRankedListsWeighted(bm25, cosine, 2.0, 1.0)
      
      # bm25Heavy should have higher score since bm25 has weight 2
      check bm25Heavy[0].rrfScore > equal[0].rrfScore

  suite "topK":
    test "k=0 returns empty":
      let fused = @[FusionResult[string](item: "a", rrfScore: 0.5, originalRanks: "")]
      let top = topK(fused, 0)
      check top.len == 0

    test "k >= len returns all":
      let fused = @[
        FusionResult[string](item: "a", rrfScore: 0.5, originalRanks: ""),
        FusionResult[string](item: "b", rrfScore: 0.3, originalRanks: "")
      ]
      let top = topK(fused, 5)
      check top.len == 2

    test "returns top k sorted by score":
      let fused = @[
        FusionResult[string](item: "c", rrfScore: 0.1, originalRanks: ""),
        FusionResult[string](item: "a", rrfScore: 0.5, originalRanks: ""),
        FusionResult[string](item: "b", rrfScore: 0.3, originalRanks: "")
      ]
      let top = topK(fused, 2)
      check top.len == 2
      check top[0].item == "a"
      check top[1].item == "b"

  suite "helpers":
    test "rrfScores extracts scores":
      let fused = @[
        FusionResult[string](item: "a", rrfScore: 0.5, originalRanks: ""),
        FusionResult[string](item: "b", rrfScore: 0.3, originalRanks: "")
      ]
      let scores = rrfScores(fused)
      check scores == @[0.5, 0.3]

    test "items extracts items":
      let fused = @[
        FusionResult[string](item: "a", rrfScore: 0.5, originalRanks: ""),
        FusionResult[string](item: "b", rrfScore: 0.3, originalRanks: "")
      ]
      let extracted = items(fused)
      check extracted == @["a", "b"]

  suite "integration - typical RRF pipeline":
    test "full pipeline with BM25 + cosine":
      # Simulate BM25 results
      let bm25Raw = @[
        (item: "docA", score: 0.95),
        (item: "docB", score: 0.80),
        (item: "docC", score: 0.70)
      ]
      
      # Simulate cosine similarity results  
      let cosineRaw = @[
        (item: "docB", score: 0.90),
        (item: "docD", score: 0.85),
        (item: "docA", score: 0.75)
      ]
      
      # Rank each
      let bm25Ranked = rankItems(bm25Raw)
      let cosineRanked = rankItems(cosineRaw)
      
      # Fuse
      let fused = fuseRankedLists(bm25Ranked, cosineRanked)
      
      # Should have 4 unique docs
      check fused.len == 4
      
      # docB is in both at rank 1 (bm25) and rank 0 (cosine) - should rank high
      # docA is rank 0 (bm25) and rank 2 (cosine) - also high
      # docD is only in cosine - should be lower
      # docC is only in bm25 at rank 2 - lowest
      
      let docBPos = fused.findIt(it.item == "docB")
      let docAPos = fused.findIt(it.item == "docA")
      let docDPos = fused.findIt(it.item == "docD")
      let docCPos = fused.findIt(it.item == "docC")
      
      # docB should be first (best combined rank)
      check docBPos == 0
      # docA should be second
      check docAPos == 1
      # docD third (only in cosine at rank 1)
      check docDPos == 2
      # docC fourth (only in bm25 at rank 2)
      check docCPos == 3
