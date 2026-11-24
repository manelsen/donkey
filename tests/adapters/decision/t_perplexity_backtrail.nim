## The Perplexity backtrail adapter against a fake HTTP port: the request it
## sends and how it reads the answer and the failures.

import std/[json, strutils, unittest]
import donkey/adapters/decision/perplexity_backtrail
import donkey/core/pipeops
import donkey/ports/backtrail

type Seen = ref object
  url, body: string
  headers: seq[(string, string)]

proc fake(seen: Seen; status: int; body: string): BacktrailPost =
  result = proc(url, payload: string; headers: seq[(string, string)]): Result[(int, string), string] {.gcsafe, raises: [].} =
    seen.url = url
    seen.body = payload
    seen.headers = headers
    ok((status, body))

proc runTests*() =
  suite "perplexity backtrail":

    test "posts the message to the decisions endpoint with the key":
      let seen = Seen()
      let port = perplexityBacktrail("pplx-test", fake(seen, 200,
        """{"answers":{"route":{"choice":"fact","confidence":0.9}}}"""))
      let r = port.classify("qual é a senha do wifi?")
      check r.isOk and r.get.route == mrFact
      check seen.url == PerplexityDecisionsUrl
      check ("Authorization", "Bearer pplx-test") in seen.headers
      check parseJson(seen.body)["state"].getStr == "qual é a senha do wifi?"

    test "a refused or unreadable answer is an error, never a route":
      let seen = Seen()
      check perplexityBacktrail("k", fake(seen, 401, "{}")).classify("oi").isErr
      check perplexityBacktrail("k", fake(seen, 200, "not json")).classify("oi").isErr
      let down = proc(url, payload: string; headers: seq[(string, string)]): Result[(int, string), string] {.gcsafe, raises: [].} =
        err("connection refused")
      check perplexityBacktrail("k", down).classify("oi").isErr

    test "an empty key gives no backtrail":
      check not perplexityBacktrail("", nil).backtrailAvailable
      check not perplexityBacktrail("   ", nil).backtrailAvailable

when isMainModule:
  runTests()
