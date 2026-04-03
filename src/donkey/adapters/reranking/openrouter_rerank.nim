## OpenRouterRerankAdapter — second-stage reranking via OpenRouter chat completions.
##
## This is a pragmatic reranker for the current Donkey stack:
##   1. retrieve candidates with dense/vector search
##   2. score the top candidates jointly against the query
##   3. return one score per candidate
##
## It uses structured outputs plus OpenRouter's response-healing plugin so the
## caller receives stable JSON without a bespoke parsing loop.

import std/[json, strutils]
import ../../core/pipeops
import ../../core/app_meta
import ../../ports/reranking
import ./llm_rerank_common
import ../http/std_http

const
  OpenRouterRerankUrl*      = "https://openrouter.ai/api/v1/chat/completions"
  DefaultRerankModel*       = "qwen/qwen3-32b"
  DefaultRerankMaxTokens*   = llm_rerank_common.DefaultRerankMaxTokens
  DefaultRerankMaxChars*    = llm_rerank_common.DefaultRerankMaxChars
  DefaultRerankTemperature* = 0.0

type
  OpenRouterRerankAdapter* = object
    apiKey*:   string
    model*:    string
    http*:     StdHttpAdapter
    maxChars*: int
    maxTokens*: int

proc buildBody*(a: OpenRouterRerankAdapter;
                query: string;
                candidates: seq[RerankCandidate]): JsonNode =
  %* {
    "model": a.model,
    "messages": [
      {
        "role": "system",
        "content": "You are a retrieval reranker. Return only JSON that matches the schema."
      },
      {
        "role": "user",
        "content": buildPrompt(query, candidates)
      }
    ],
    "max_tokens": a.maxTokens,
    "temperature": DefaultRerankTemperature,
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "rerank_scores",
        "strict": true,
        "schema": buildSchema()
      }
    },
    "plugins": [
      {
        "id": "response-healing"
      }
    ]
  }

proc parseScores*(content: string; count: int): seq[float32] =
  llm_rerank_common.parseScores(content, count)

proc newOpenRouterRerankAdapter*(apiKey: string;
                                 model = DefaultRerankModel;
                                 maxChars = DefaultRerankMaxChars;
                                 maxTokens = DefaultRerankMaxTokens): OpenRouterRerankAdapter =
  OpenRouterRerankAdapter(
    apiKey: apiKey,
    model: model,
    http: newStdHttpAdapter(),
    maxChars: maxChars,
    maxTokens: maxTokens,
  )

proc rerank*(a: OpenRouterRerankAdapter;
             query: string;
             candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
  if a.apiKey.len == 0 or query.strip.len == 0 or candidates.len == 0:
    return @[]

  var clipped: seq[RerankCandidate]
  clipped.setLen(candidates.len)
  for i, candidate in candidates:
    clipped[i] = candidate
    clipped[i].content = truncateCandidate(candidate.content, a.maxChars)

  let headers = @[
    ("Authorization", "Bearer " & a.apiKey),
    ("Content-Type", "application/json"),
    ("HTTP-Referer", OpenRouterRefererUrl),
    ("X-Title", AppName),
  ]
  let resp = a.http.post(OpenRouterRerankUrl, $a.buildBody(query, clipped), headers)
  if resp.isErr:
    return @[]

  try:
    let body = parseJson(resp.value.body)
    let choices = body["choices"]
    if choices.kind != JArray or choices.len == 0:
      return @[]
    let content = choices[0]["message"]["content"].getStr("")
    return parseScores(content, candidates.len)
  except CatchableError:
    @[]

proc toRerankFn*(a: OpenRouterRerankAdapter): RerankFn =
  proc(query: string; candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
    a.rerank(query, candidates)
