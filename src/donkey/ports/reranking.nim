## RerankingPort — concept for second-stage retrieval rerankers.
##
## A reranker receives the user query plus a candidate list and returns one
## relevance score per candidate, aligned by index.

type
  RerankCandidate* = object
    id*:            string
    content*:       string
    kind*:          string
    timestamp*:     int64
    baseScore*:     float32
    semanticScore*: float32
    entityScore*:   float32
    temporalScore*: float32
    neighborScore*: float32
    causalScore*:   float32

  RerankFn* = proc(query: string; candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.}

  RerankingPort* = concept r
    r.rerank(string, seq[RerankCandidate]) is seq[float32]
