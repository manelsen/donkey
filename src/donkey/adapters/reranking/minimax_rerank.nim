## MiniMaxRerankAdapter — second-stage reranking via MiniMax chat completions.
##
## MiniMax's M2 models do not support response_format on chat completions, so
## this adapter relies on a strict prompt plus low temperature and
## reasoning_split to keep the response parseable.

import std/json
import ../../core/pipeops
import ../../ports/reranking
import ./llm_rerank_common
import ../http/std_http
import ../provider/minimax

const
  MiniMaxDefaultRerankModel* = MiniMaxDefaultModel
  MiniMaxRerankUrl*          = MiniMaxEndpoint
  MiniMaxRerankTemperature*  = 0.01

type
  MiniMaxRerankAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string
    http*:     StdHttpAdapter
    maxChars*: int
    maxTokens*: int

proc parseScores*(content: string; count: int): seq[float32] =
  llm_rerank_common.parseScores(content, count)

proc buildBody*(a: MiniMaxRerankAdapter;
                query: string;
                candidates: seq[RerankCandidate]): JsonNode =
  %* {
    "model": a.model,
    "messages": [
      {
        "role": "system",
        "content": "You are a retrieval reranker. Return only a minified JSON object with the requested shape."
      },
      {
        "role": "user",
        "content": buildPrompt(query, candidates)
      }
    ],
    "reasoning_split": true,
    "max_tokens": a.maxTokens,
    "temperature": MiniMaxRerankTemperature,
  }

proc newMiniMaxRerankAdapter*(apiKey: string;
                              model = MiniMaxDefaultRerankModel;
                              endpoint = MiniMaxRerankUrl;
                              maxChars = DefaultRerankMaxChars;
                              maxTokens = DefaultRerankMaxTokens): MiniMaxRerankAdapter =
  MiniMaxRerankAdapter(
    apiKey: apiKey,
    model: model,
    endpoint: endpoint,
    http: newStdHttpAdapter(),
    maxChars: maxChars,
    maxTokens: maxTokens,
  )

proc rerank*(a: MiniMaxRerankAdapter;
             query: string;
             candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
  if a.apiKey.len == 0 or query.len == 0 or candidates.len == 0:
    return @[]
  rerankViaChat(a.http, a.endpoint, a.apiKey,
                a.buildBody(query, clipCandidates(candidates, a.maxChars)),
                candidates.len)

proc toRerankFn*(a: MiniMaxRerankAdapter): RerankFn =
  proc(query: string; candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
    a.rerank(query, candidates)
