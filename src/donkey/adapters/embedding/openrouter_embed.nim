## OpenRouterEmbeddingAdapter — EmbeddingPort via OpenRouter /embeddings.
##
## Model: qwen/qwen3-embedding (4096 dimensions).
## Falls back to empty vector on HTTP or parse error — callers check len > 0.
##
## vecToSql converts a seq[float32] to pgvector literal format "[x,y,z]".

import std/[json, strutils]
import ../../core/pipeops
import ../http/std_http

const
  OpenRouterEmbedEndpoint* = "https://openrouter.ai/api/v1/embeddings"
  OpenRouterEmbedModel*    = "qwen/qwen3-embedding"

type
  OpenRouterEmbeddingAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string  ## override for testing
    http*:     StdHttpAdapter

# ── JSON helpers (exported for unit testing) ─────────────────────────────────

proc buildEmbedBody*(a: OpenRouterEmbeddingAdapter; text: string): JsonNode =
  %* {"model": a.model, "input": text}

func parseEmbedResponse*(j: JsonNode): seq[float32] =
  let data = j.getOrDefault("data")
  if data == nil or data.kind != JArray or data.len == 0:
    return @[]
  let first = data[0]
  let emb = first.getOrDefault("embedding")
  if emb == nil or emb.kind != JArray:
    return @[]
  result = newSeq[float32](emb.len)
  for i in 0..<emb.len:
    result[i] = float32(emb[i].getFloat(0.0))

func vecToSql*(v: seq[float32]): string =
  ## Formats a float32 vector as a pgvector literal: "[x,y,z]".
  if v.len == 0: return "[]"
  var parts = newSeq[string](v.len)
  for i, f in v:
    ## Use $f which gives a clean decimal representation in Nim.
    let s = $f
    ## Remove trailing zeros after decimal point for compactness.
    parts[i] = s
  "[" & parts.join(",") & "]"

# ── EmbeddingPort implementation ──────────────────────────────────────────────

proc embed*(a: OpenRouterEmbeddingAdapter; text: string): seq[float32] =
  ## Returns the embedding vector, or an empty seq on any error.
  if text.len == 0: return @[]
  let headers = @[
    ("Content-Type",  "application/json"),
    ("Authorization", "Bearer " & a.apiKey),
  ]
  let url = if a.endpoint.len > 0: a.endpoint else: OpenRouterEmbedEndpoint
  let respR = a.http.post(url, $a.buildEmbedBody(text), headers)
  if respR.isErr: return @[]
  let resp = respR.value
  if resp.status < 200 or resp.status >= 300: return @[]
  try:
    parseEmbedResponse(parseJson(resp.body))
  except CatchableError:
    @[]

# ── Constructor ───────────────────────────────────────────────────────────────

proc newOpenRouterEmbeddingAdapter*(apiKey:   string;
                                    model    = OpenRouterEmbedModel;
                                    endpoint = ""): OpenRouterEmbeddingAdapter =
  OpenRouterEmbeddingAdapter(
    apiKey:   apiKey,
    model:    model,
    endpoint: endpoint,
    http:     newStdHttpAdapter(),
  )
