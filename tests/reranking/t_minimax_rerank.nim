## MiniMaxRerankAdapter unit tests.

import std/[json, unittest]
import donkey/adapters/reranking/minimax_rerank
import donkey/ports/reranking

proc verifyRerankingPort[T: RerankingPort](r: T) {.used.} = discard

suite "newMiniMaxRerankAdapter":

  test "default model is set":
    let a = newMiniMaxRerankAdapter("key")
    check a.model == MiniMaxDefaultRerankModel
    check a.endpoint == MiniMaxRerankUrl

  test "custom model is used":
    let a = newMiniMaxRerankAdapter("key", model = "MiniMax-M2")
    check a.model == "MiniMax-M2"

suite "MiniMaxRerankAdapter request body":

  test "buildBody uses low temperature and reasoning split":
    let a = newMiniMaxRerankAdapter("key", model = "MiniMax-M2.7")
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
    check body["model"].getStr("") == "MiniMax-M2.7"
    check body["reasoning_split"].getBool(false)
    check abs(body["temperature"].getFloat(1.0) - MiniMaxRerankTemperature) < 0.0001

suite "MiniMaxRerankAdapter parsing":

  test "parseScores clamps values":
    let scores = parseScores("""{"scores":[{"id":0,"score":2.4}]}""", 1)
    check scores.len == 1
    check scores[0] == 1.0'f32

suite "MiniMaxRerankAdapter satisfies RerankingPort concept":

  test "compile-time concept check passes":
    let a = newMiniMaxRerankAdapter("tok")
    verifyRerankingPort(a)
    check true
