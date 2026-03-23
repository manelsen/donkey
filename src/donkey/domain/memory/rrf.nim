## Reciprocal Rank Fusion
## Pure logic to merge BM25 and Cosine Similarity scores (nullclaw style)
## RRF formula: score = Σ 1/(k + rank) where k=60 typically

import std/[sequtils, algorithm, tables]
import ../../core/pipeops

type
  RankedItem*[T] = object
    item*: T
    score*: float
    rank*: int

  FusionResult*[T] = object
    item*: T
    rrfScore*: float
    originalRanks*: string ## comma-separated "bm25:rank,cosine:rank"

const
  DefaultRrfK*: float = 60.0

func rrfScore*(rank: int; k: float = DefaultRrfK): float {.inline.} =
  ## Compute Reciprocal Rank score for a single rank
  ## rrf = 1 / (k + rank) where rank is 0-indexed
  1.0 / (k + float(rank))

func rrfScoreWeighted*(rank: int; weight: float; k: float = DefaultRrfK): float {.inline.} =
  ## Weighted RRF: weight * 1 / (k + rank)
  weight / (k + float(rank))

func fuseRanks*(bm25Rank, cosineRank: int; k: float = DefaultRrfK): float {.inline.} =
  ## Fuse two ranks using standard RRF (equal weights)
  ## Missing ranks (rank < 0) are skipped
  var total: float = 0.0
  if bm25Rank >= 0:
    total += rrfScore(bm25Rank, k)
  if cosineRank >= 0:
    total += rrfScore(cosineRank, k)
  total

func rankItems*[T](items: seq[tuple[item: T, score: float]]; ascending: bool = false): seq[RankedItem[T]] =
  ## Rank items by score, producing 0-indexed ranks
  ## ascending=false means highest score = rank 0
  if items.len == 0:
    return @[]

  var indexed: seq[tuple[idx: int, score: float]]
  for i, it in items:
    indexed.add((i, it.score))

  sort(indexed, proc(a, b: tuple[idx: int, score: float]): int =
    if ascending:
      cmp(a.score, b.score)
    else:
      cmp(b.score, a.score)
  )

  result = newSeq[RankedItem[T]](items.len)
  for rank, entry in indexed:
    result[rank] = RankedItem[T](
      item: items[entry.idx].item,
      score: entry.score,
      rank: rank
    )

func fuseRankedLists*[T](
  bm25Items: seq[RankedItem[T]];
  cosineItems: seq[RankedItem[T]];
  k: float = DefaultRrfK
): seq[FusionResult[T]] =
  ## Fuse two ranked lists using RRF
  ## Creates a map from item -> bm25 rank, then merges with cosine ranks
  
  if bm25Items.len == 0 and cosineItems.len == 0:
    return @[]
  
  var itemToBm25: Table[T, int]
  for it in bm25Items:
    itemToBm25[it.item] = it.rank
  
  var itemToCosine: Table[T, int]
  for it in cosineItems:
    itemToCosine[it.item] = it.rank
  
  var allItems: seq[T]
  var seen: Table[T, bool]
  for it in bm25Items:
    if not seen.hasKey(it.item):
      seen[it.item] = true
      allItems.add(it.item)
  for it in cosineItems:
    if not seen.hasKey(it.item):
      seen[it.item] = true
      allItems.add(it.item)
  
  result = newSeq[FusionResult[T]](allItems.len)
  for i, item in allItems:
    let bm25Rank = itemToBm25.getOrDefault(item, -1)
    let cosineRank = itemToCosine.getOrDefault(item, -1)
    
    var bm25Part = ""
    var cosinePart = ""
    if bm25Rank >= 0:
      bm25Part = "bm25:" & $bm25Rank
    if cosineRank >= 0:
      cosinePart = "cosine:" & $cosineRank
    
    let ranks = if bm25Part.len > 0 and cosinePart.len > 0:
      bm25Part & "," & cosinePart
    elif bm25Part.len > 0:
      bm25Part
    else:
      cosinePart
    
    let rrf = fuseRanks(bm25Rank, cosineRank, k)
    result[i] = FusionResult[T](
      item: item,
      rrfScore: rrf,
      originalRanks: ranks
    )
  
  sort(result, proc(a, b: FusionResult[T]): int =
    cmp(b.rrfScore, a.rrfScore)
  )

func fuseRankedListsWeighted*[T](
  bm25Items: seq[RankedItem[T]];
  cosineItems: seq[RankedItem[T]];
  bm25Weight: float;
  cosineWeight: float;
  k: float = DefaultRrfK
): seq[FusionResult[T]] =
  ## Fuse two ranked lists using weighted RRF
  ## Weights control relative importance: weight * 1 / (k + rank)
  
  if bm25Items.len == 0 and cosineItems.len == 0:
    return @[]
  
  var itemToBm25: Table[T, int]
  for it in bm25Items:
    itemToBm25[it.item] = it.rank
  
  var itemToCosine: Table[T, int]
  for it in cosineItems:
    itemToCosine[it.item] = it.rank
  
  var allItems: seq[T]
  var seen: Table[T, bool]
  for it in bm25Items:
    if not seen.hasKey(it.item):
      seen[it.item] = true
      allItems.add(it.item)
  for it in cosineItems:
    if not seen.hasKey(it.item):
      seen[it.item] = true
      allItems.add(it.item)
  
  result = newSeq[FusionResult[T]](allItems.len)
  for i, item in allItems:
    let bm25Rank = itemToBm25.getOrDefault(item, -1)
    let cosineRank = itemToCosine.getOrDefault(item, -1)
    
    var bm25Part = ""
    var cosinePart = ""
    if bm25Rank >= 0:
      bm25Part = "bm25:" & $bm25Rank
    if cosineRank >= 0:
      cosinePart = "cosine:" & $cosineRank
    
    let ranks = if bm25Part.len > 0 and cosinePart.len > 0:
      bm25Part & "," & cosinePart
    elif bm25Part.len > 0:
      bm25Part
    else:
      cosinePart
    
    var rrf: float = 0.0
    if bm25Rank >= 0:
      rrf += rrfScoreWeighted(bm25Rank, bm25Weight, k)
    if cosineRank >= 0:
      rrf += rrfScoreWeighted(cosineRank, cosineWeight, k)
    
    result[i] = FusionResult[T](
      item: item,
      rrfScore: rrf,
      originalRanks: ranks
    )
  
  sort(result, proc(a, b: FusionResult[T]): int =
    cmp(b.rrfScore, a.rrfScore)
  )

func topK*[T](fused: seq[FusionResult[T]]; k: int): seq[FusionResult[T]] =
  ## Return top K results from fused list (sorted descending by RRF score)
  if k <= 0:
    return @[]
  if fused.len == 0:
    return @[]
  
  var sortedFused = fused
  sort(sortedFused, proc(a, b: FusionResult[T]): int =
    cmp(b.rrfScore, a.rrfScore)
  )
  
  if sortedFused.len <= k:
    return sortedFused
  sortedFused[0 ..< k]

func rrfScores*[T](fused: seq[FusionResult[T]]): seq[float] =
  ## Extract just the RRF scores as a sequence
  fused.mapIt(it.rrfScore)

func items*[T](fused: seq[FusionResult[T]]): seq[T] =
  ## Extract just the items from a fused list
  fused.mapIt(it.item)
