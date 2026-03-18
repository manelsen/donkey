## OpenRouterEmbeddingAdapter unit tests.
## HTTP calls are not made; tests cover JSON serialization and parsing.

import std/[json, unittest]
import donkey/adapters/embedding/openrouter_embed
import donkey/ports/embedding

proc verifyEmbeddingPort[T: EmbeddingPort](e: T) {.used.} = discard

suite "buildEmbedBody":

  test "sets model and input":
    let a = newOpenRouterEmbeddingAdapter("key")
    let body = a.buildEmbedBody("hello world")
    check body["model"].getStr() == "qwen/qwen3-embedding"
    check body["input"].getStr() == "hello world"

  test "custom model is used":
    let a = newOpenRouterEmbeddingAdapter("key", model = "text-embedding-3-small")
    let body = a.buildEmbedBody("test")
    check body["model"].getStr() == "text-embedding-3-small"

suite "parseEmbedResponse":

  test "extracts first embedding vector":
    let j = %* {
      "data": [
        {"embedding": [0.1, 0.2, 0.3], "index": 0}
      ]
    }
    let vec = parseEmbedResponse(j)
    check vec.len == 3
    check vec[0] == 0.1'f32
    check vec[1] == 0.2'f32
    check vec[2] == 0.3'f32

  test "returns empty for missing data":
    let j = %* {"data": []}
    let vec = parseEmbedResponse(j)
    check vec.len == 0

suite "vecToSql":

  test "formats as pgvector literal":
    let v: seq[float32] = @[0.1'f32, 0.2'f32, 0.3'f32]
    check vecToSql(v) == "[0.1,0.2,0.3]"

  test "empty vector":
    let v: seq[float32] = @[]
    check vecToSql(v) == "[]"

suite "OpenRouterEmbeddingAdapter satisfies EmbeddingPort concept":

  test "compile-time concept check passes":
    let a = newOpenRouterEmbeddingAdapter("tok",
                                         endpoint = "https://mock.local")
    verifyEmbeddingPort(a)
    check true
