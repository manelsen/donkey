## OpenRouterRerankAdapter unit tests.
## HTTP calls are not made; tests cover construction and JSON parsing.

import std/[json, unittest]
import donkey/adapters/reranking/openrouter_rerank
import donkey/ports/reranking

proc verifyRerankingPort[T: RerankingPort](r: T) {.used.} = discard

suite "newOpenRouterRerankAdapter":

  test "default model is set":
    let a = newOpenRouterRerankAdapter("key")
    check a.model == DefaultRerankModel

  test "custom model is used":
    let a = newOpenRouterRerankAdapter("key", model = "openai/gpt-4o-mini")
    check a.model == "openai/gpt-4o-mini"

suite "OpenRouterRerankAdapter request body":

  test "buildBody enables structured output and response healing":
    let a = newOpenRouterRerankAdapter("key", model = "qwen/qwen3-32b")
    let body = a.buildBody("nim vectors", @[
      RerankCandidate(
        id: "n1",
        content: "Nim has sequences",
        kind: "memory",
        timestamp: 123,
        baseScore: 0.5,
        semanticScore: 0.4,
        entityScore: 0.0,
        temporalScore: 0.0,
        neighborScore: 0.1,
      )
    ])
    check body["model"].getStr("") == "qwen/qwen3-32b"
    check body["temperature"].getFloat(1.0) == 0.0
    check body["response_format"]["type"].getStr("") == "json_schema"
    check body["plugins"][0]["id"].getStr("") == "response-healing"

suite "OpenRouterRerankAdapter parsing":

  test "parseScores aligns by candidate id":
    let scores = parseScores("""{"scores":[{"id":1,"score":0.75},{"id":0,"score":0.25}]}""", 2)
    check scores.len == 2
    check abs(scores[0] - 0.25'f32) < 0.0001'f32
    check abs(scores[1] - 0.75'f32) < 0.0001'f32

  test "parseScores clamps invalid values":
    let scores = parseScores("""{"scores":[{"id":0,"score":2.0},{"id":1,"score":-1.0}]}""", 2)
    check scores[0] == 1.0'f32
    check scores[1] == 0.0'f32

  test "parseScores tolerates wrapped JSON":
    let scores = parseScores("""```json
{"scores":[{"id":0,"score":0.5}]}
```""", 1)
    check scores.len == 1
    check abs(scores[0] - 0.5'f32) < 0.0001'f32

suite "OpenRouterRerankAdapter satisfies RerankingPort concept":

  test "compile-time concept check passes":
    let a = newOpenRouterRerankAdapter("tok")
    verifyRerankingPort(a)
    check true
