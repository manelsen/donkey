## ZaiRerankAdapter unit tests.

import std/[json, unittest]
import donkey/adapters/reranking/zai_rerank
import donkey/ports/reranking

proc verifyRerankingPort[T: RerankingPort](r: T) {.used.} = discard

suite "newZaiRerankAdapter":

  test "default model is set":
    let a = newZaiRerankAdapter("key")
    check a.model == ZaiDefaultRerankModel
    check a.endpoint == ZaiRerankUrl

  test "coding constructor uses coding endpoint":
    let a = newZaiCodingRerankAdapter("key")
    check a.endpoint == ZaiCodingRerankUrl

suite "ZaiRerankAdapter request body":

  test "buildBody enables json mode":
    let a = newZaiRerankAdapter("key", model = "glm-4.7")
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
    check body["model"].getStr("") == "glm-4.7"
    check body["thinking"]["type"].getStr("") == "disabled"
    check body["temperature"].getFloat(1.0) == 0.0
    check body["response_format"]["type"].getStr("") == "json_object"

suite "ZaiRerankAdapter parsing":

  test "parseScores extracts embedded JSON object":
    let scores = parseScores("""Here is the result: {"scores":[{"id":0,"score":0.6}]}""", 1)
    check scores.len == 1
    check abs(scores[0] - 0.6'f32) < 0.0001'f32

suite "ZaiRerankAdapter satisfies RerankingPort concept":

  test "compile-time concept check passes":
    let a = newZaiRerankAdapter("tok")
    verifyRerankingPort(a)
    check true
