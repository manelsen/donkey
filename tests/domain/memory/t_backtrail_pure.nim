## The backtrail, the pure part: the request Perplexity's decision model
## gets, the decision read back, and whether a message needs a pre-search.

import std/[json, strutils, unittest]
import results
import donkey/domain/memory/backtrail_pure

proc runTests*() =
  suite "backtrail":

    test "the request asks one choice question over the four routes":
      let j = backtrailRequest("qual é a senha do wifi?")
      check j["model"].getStr == BacktrailModel
      check j["state"].getStr == "qual é a senha do wifi?"
      let q = j["questions"]["route"]
      check q["type"].getStr == "choice"
      for key in ["fact", "recent", "order", "now"]:
        check q["criteria"].hasKey(key)

    test "a decision is read with its route and confidence":
      let r = parseBacktrailResponse(parseJson("""{"answers":{"route":{"type":"choice",
        "choice":"order","probabilities":{"fact":0.01,"recent":0.0,"order":0.98,"now":0.01},
        "confidence":0.98}}}"""))
      check r.isOk
      check r.get.route == mrOrder
      check r.get.confidence > 0.97

    test "an answer without the route or with an unknown one is an error":
      check parseBacktrailResponse(parseJson("""{"answers":{}}""")).isErr
      check parseBacktrailResponse(parseJson("""{"answers":{"route":{"choice":"maybe"}}}""")).isErr
      check parseBacktrailResponse(newJNull()).isErr

    test "only a message about the past gets a pre-search":
      check needsPreSearch(RouteDecision(route: mrFact))
      check needsPreSearch(RouteDecision(route: mrRecent))
      check needsPreSearch(RouteDecision(route: mrOrder))
      check not needsPreSearch(RouteDecision(route: mrNow))

    test "the pre-search query is the message, within session_search's limit":
      check preSearchArgs("qual é a senha do wifi?") == %*{"query": "qual é a senha do wifi?"}
      let long = repeat("palavra ", 200)
      let q = preSearchArgs(long)["query"].getStr
      check q.len <= PreSearchMaxQueryChars
      check q.len > 0

    test "a pre-search call id is unique per message":
      check preSearchCallId("m1") == "presearch-m1"
      check preSearchCallId("m1") != preSearchCallId("m2")
      check preSearchCallId("") == "presearch"

    test "a decision crosses the thread boundary as text and back":
      let d = RouteDecision(route: mrOrder, confidence: 0.91)
      let back = decodeDecision(encodeDecision(d))
      check back.isOk
      check back.get.route == mrOrder
      check abs(back.get.confidence - 0.91) < 1e-9
      check decodeDecision("not json").isErr
      check decodeDecision("""{"route":"maybe"}""").isErr

    test "an empty message gets no pre-search query":
      check preSearchArgs("   ")["query"].getStr == ""

when isMainModule:
  runTests()
