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
  ## Whole words that make a query a question about time, in English and
  ## Portuguese, the latter with and without accents.
  TemporalWords = [
    "when", "yesterday", "last", "before", "after", "earlier", "first",
    "then", "ago", "today",
    "quando", "ontem", "anteontem", "hoje", "antes", "depois",
    "último", "ultimo", "última", "ultima",
    "últimos", "ultimos", "últimas", "ultimas",
    "primeiro", "primeira", "atrás", "atras", "passado", "passada",
  ]
  ## Word beginnings with the same meaning: recent, recently, recente,
  ## recentemente; chronological, cronológica; anterior, anteriormente.
  TemporalStems = ["recent", "chronolog", "cronol", "anterior"]

func defaultPolicy*(): QueryPolicy =
  ## Meaning and literal terms weigh the same: names, error messages and
  ## file names are found by their words, paraphrases by their embedding.
  QueryPolicy(intent: qiSemantic, semanticWeight: 0.5, lexicalWeight: 0.5,
              temporalWeight: 0.0, neighborWeight: 0.0)

func asksAboutTime*(query: string): bool =
  ## Matches whole words, not substrings: "contem" holds "ontem" and
  ## "elastic" holds "last", and neither is about time.
  for word in queryTerms(query):
    if word in TemporalWords:
      return true
    for stem in TemporalStems:
      if word.startsWith(stem):
        return true
  false

func classifyQuery*(query: string): QueryPolicy =
  ## A query that asks about time also ranks by recency and pulls in the
  ## memories next to its hits.
  result = defaultPolicy()
  if asksAboutTime(query):
    result.intent = qiTemporal
    result.semanticWeight = 0.30
    result.lexicalWeight  = 0.20
    result.temporalWeight = 0.40
    result.neighborWeight = 0.10
