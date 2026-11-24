## query_policy_pure — how a recall query is ranked.
##
## Memories are ranked by several lists fused by reciprocal rank. This module
## decides the weight of each list from the wording of the query. No I/O: the
## adapter only runs the searches the policy asks for.

import std/strutils
import ./session_search_pure

type
  QueryIntent* = enum
    qiSemantic, qiTemporal

  QueryPolicy* = object
    ## Weights of the ranked lists fused by reciprocal rank.
    intent*:         QueryIntent
    semanticWeight*: float   ## nearest embeddings
    lexicalWeight*:  float   ## literal query terms
    temporalWeight*: float   ## most recent memories
    neighborWeight*: float   ## memories next to a semantic hit in time

const
  ## Whole words that make a query a question about a recent period, in
  ## English and Portuguese (accents are folded before matching). Words about
  ## order or dates ("first", "before", "after", "when", "quando", "antes",
  ## "primeira", "cronológica", "anterior") are not here on purpose: "which
  ## came first?" needs both events found by what they are, and recency at
  ## 0.40 buried them under the newest memories (bench/search/RESULTS.md).
  RecentPeriodWords = [
    "yesterday", "last", "ago", "today",
    "ontem", "anteontem", "hoje",
    "ultimo", "ultima", "ultimos", "ultimas",
    "atras", "passado", "passada",
  ]
  ## Word beginnings with the same meaning: recent, recently, recente,
  ## recentemente.
  RecentPeriodStems = ["recent"]

func defaultPolicy*(): QueryPolicy =
  ## Meaning and literal terms weigh the same: names, error messages and
  ## file names are found by their words, paraphrases by their embedding.
  QueryPolicy(intent: qiSemantic, semanticWeight: 0.5, lexicalWeight: 0.5,
              temporalWeight: 0.0, neighborWeight: 0.0)

func temporalPolicy*(): QueryPolicy =
  ## Recency and the memories next to the hits join meaning and terms.
  QueryPolicy(intent: qiTemporal, semanticWeight: 0.30, lexicalWeight: 0.20,
              temporalWeight: 0.40, neighborWeight: 0.10)

func asksAboutRecentPeriod*(query: string): bool =
  ## Matches whole words, not substrings: "contem" holds "ontem" and
  ## "elastic" holds "last", and neither is about time.
  for word in queryTerms(query):
    if word in RecentPeriodWords:
      return true
    for stem in RecentPeriodStems:
      if word.startsWith(stem):
        return true
  false

func classifyQuery*(query: string): QueryPolicy =
  ## A query about a recent period also ranks by recency and pulls in the
  ## memories next to its hits; any other query, including one about order
  ## or a date, ranks by meaning and words.
  if asksAboutRecentPeriod(query): temporalPolicy() else: defaultPolicy()
