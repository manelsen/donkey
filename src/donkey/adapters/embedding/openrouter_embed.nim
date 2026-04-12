## OpenRouterEmbeddingAdapter — EmbeddingPort via OpenRouter /embeddings endpoint.
##
## Model: qwen/qwen3-embedding-8b (4096-dim vectors) via OpenRouter.
## Model ID configurable; defaults to "qwen/qwen3-embedding-8b".
##
## Returns empty seq[float32] on error — caller treats as "no embedding".

import std/json
import ../../core/pipeops
import ../../core/app_meta
import ../../core/log
import ../http/std_http

const
  OpenRouterEmbedUrl* = "https://openrouter.ai/api/v1/embeddings"
  DefaultEmbedModel*  = "qwen/qwen3-embedding-8b"

type
  OpenRouterEmbeddingAdapter* = object
    apiKey*: string
    model*:  string
    http*:   StdHttpAdapter
    log*:    Logger

proc newOpenRouterEmbeddingAdapter*(apiKey: string;
                                    model = DefaultEmbedModel;
                                    log = newLogger("embedding")): OpenRouterEmbeddingAdapter =
  OpenRouterEmbeddingAdapter(
    apiKey: apiKey,
    model:  model,
    http:   newStdHttpAdapter(),
    log:    log,
  )

proc embed*(a: OpenRouterEmbeddingAdapter; text: string): seq[float32] {.gcsafe.} =
  ## Returns 4096-dim embedding vector, or empty seq on error.
  let body = $ %* {"model": a.model, "input": text}
  let headers = @[
    ("Authorization",  "Bearer " & a.apiKey),
    ("Content-Type",   "application/json"),
    ("HTTP-Referer",   OpenRouterRefererUrl),
    ("X-Title",        AppName),
  ]
  let resp = a.http.post(OpenRouterEmbedUrl, body, headers)
  if resp.isErr: return @[]
  try:
    let j    = parseJson(resp.value.body)
    let data = j["data"]
    if data.kind != JArray or data.len == 0: return @[]
    let vec = data[0]["embedding"]
    if vec.kind != JArray: return @[]
    var buf = newSeq[float32](vec.len)
    for i in 0 ..< vec.len:
      buf[i] = vec[i].getFloat(0.0).float32
    return buf
  except CatchableError:
    let errMsg = getCurrentExceptionMsg()
    a.log.warn("embedding.parse: failed to parse embedding response reason=" & errMsg)
    return @[]
