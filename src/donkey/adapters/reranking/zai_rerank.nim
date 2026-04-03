## ZaiRerankAdapter — second-stage reranking via Z.AI chat completions.
##
## Z.AI documents JSON mode on chat completions via:
##   response_format = {"type": "json_object"}

import std/json
import ../../core/pipeops
import ../../ports/reranking
import ./llm_rerank_common
import ../http/std_http
import ../provider/zhipu

const
  ZaiRerankUrl*             = ZaiGeneralEndpoint
  ZaiCodingRerankUrl*       = ZhipuEndpoint
  ZaiDefaultRerankModel*    = "glm-4.7"
  ZaiDefaultTemperature*    = 0.0

type
  ZaiRerankAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string
    http*:     StdHttpAdapter
    maxChars*: int
    maxTokens*: int

proc parseScores*(content: string; count: int): seq[float32] =
  llm_rerank_common.parseScores(content, count)

proc buildBody*(a: ZaiRerankAdapter;
                query: string;
                candidates: seq[RerankCandidate]): JsonNode =
  %* {
    "model": a.model,
    "messages": [
      {
        "role": "system",
        "content": "You are a retrieval reranker. Return only JSON matching the requested shape."
      },
      {
        "role": "user",
        "content": buildPrompt(query, candidates)
      }
    ],
    "thinking": {
      "type": "disabled"
    },
    "max_tokens": a.maxTokens,
    "temperature": ZaiDefaultTemperature,
    "response_format": {
      "type": "json_object"
    }
  }

proc newZaiRerankAdapter*(apiKey: string;
                          model = ZaiDefaultRerankModel;
                          endpoint = ZaiRerankUrl;
                          maxChars = DefaultRerankMaxChars;
                          maxTokens = DefaultRerankMaxTokens): ZaiRerankAdapter =
  ZaiRerankAdapter(
    apiKey: apiKey,
    model: model,
    endpoint: endpoint,
    http: newStdHttpAdapter(),
    maxChars: maxChars,
    maxTokens: maxTokens,
  )

proc newZaiCodingRerankAdapter*(apiKey: string;
                                model = ZaiDefaultRerankModel;
                                maxChars = DefaultRerankMaxChars;
                                maxTokens = DefaultRerankMaxTokens): ZaiRerankAdapter =
  newZaiRerankAdapter(
    apiKey,
    model = model,
    endpoint = ZaiCodingRerankUrl,
    maxChars = maxChars,
    maxTokens = maxTokens,
  )

proc rerank*(a: ZaiRerankAdapter;
             query: string;
             candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
  if a.apiKey.len == 0 or query.len == 0 or candidates.len == 0:
    return @[]

  var clipped: seq[RerankCandidate]
  clipped.setLen(candidates.len)
  for i, candidate in candidates:
    clipped[i] = candidate
    clipped[i].content = truncateCandidate(candidate.content, a.maxChars)

  let headers = @[
    ("Authorization", "Bearer " & a.apiKey),
    ("Content-Type", "application/json"),
  ]
  let resp = a.http.post(a.endpoint, $a.buildBody(query, clipped), headers)
  if resp.isErr:
    return @[]

  try:
    let body = parseJson(resp.value.body)
    let choices = body["choices"]
    if choices.kind != JArray or choices.len == 0:
      return @[]
    let content = choices[0]["message"]["content"].getStr("")
    parseScores(content, candidates.len)
  except CatchableError:
    @[]

proc toRerankFn*(a: ZaiRerankAdapter): RerankFn =
  proc(query: string; candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
    a.rerank(query, candidates)
