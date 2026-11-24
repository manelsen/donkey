## OpenRouterEmbeddingAdapter — EmbeddingPort via OpenRouter /embeddings endpoint.
##
## Model: qwen/qwen3-embedding-8b (4096-dim vectors) via OpenRouter.
## Model ID configurable; defaults to "qwen/qwen3-embedding-8b".
##
## Returns empty seq[float32] on error — caller treats as "no embedding".

import std/[json, strutils]
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

# ── On a worker thread ───────────────────────────────────────────────────────
#
# The embedding call blocks its caller until the HTTP deadline. The daemon
# runs it on a worker (app/blocking_executor): the job below takes plain text
# in, builds the adapter there, and sends the vector back as text.

proc encodeEmbedding*(v: seq[float32]): string =
  var arr = newJArray()
  for x in v:
    arr.add(%x)
  $arr

proc decodeEmbedding*(text: string): Result[seq[float32], string] =
  var j: JsonNode
  try:
    j = parseJson(text)
  except CatchableError as e:
    return err("embedding: unreadable vector: " & e.msg)
  if j.kind != JArray:
    return err("embedding: the vector is not an array")
  var v = newSeq[float32](j.len)
  for i in 0 ..< j.len:
    if j[i].kind notin {JFloat, JInt}:
      return err("embedding: element " & $i & " is not a number")
    v[i] = j[i].getFloat().float32
  ok(v)

proc openRouterEmbedJob*(input: string): Result[string, string] {.nimcall, gcsafe, raises: [].} =
  ## `{"key", "text"}` in, the encoded vector out. An empty vector (the
  ## adapter's way of saying it failed) is an error, so the caller can tell.
  try:
    let j = parseJson(input)
    let key = j{"key"}.getStr("").strip
    let text = j{"text"}.getStr("")
    if key.len == 0:
      return err("embedding: no key")
    if text.strip.len == 0:
      return err("embedding: no text")
    let v = newOpenRouterEmbeddingAdapter(key).embed(text)
    if v.len == 0:
      return err("embedding: no vector")
    ok(encodeEmbedding(v))
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("embedding job: " & e.msg)
