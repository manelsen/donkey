## The Perplexity gatekeeper adapter against a fake HTTP port: the request it
## sends and how it reads the answer and the failures.

import std/[json, strutils, unittest]
import donkey/adapters/decision/perplexity_gatekeeper
import donkey/core/pipeops
import donkey/ports/gatekeeper

type Seen = ref object
  url, body: string
  headers: seq[(string, string)]

proc fake(seen: Seen; status: int; body: string): GatekeeperPost =
  result = proc(url, payload: string; headers: seq[(string, string)]): Result[(int, string), string] {.gcsafe, raises: [].} =
    seen.url = url
    seen.body = payload
    seen.headers = headers
    ok((status, body))

proc runTests*() =
  suite "perplexity gatekeeper":

    test "posts the message to the decisions endpoint with the key":
      let seen = Seen()
      let port = perplexityGatekeeper("pplx-test", fake(seen, 200,
        """{"answers":{"route":{"choice":"fact","confidence":0.9}}}"""))
      let r = port.classify("qual é a senha do wifi?")
      check r.isOk and r.get.route == mrFact
      check seen.url == PerplexityDecisionsUrl
      check ("Authorization", "Bearer pplx-test") in seen.headers
      check parseJson(seen.body)["state"].getStr == "qual é a senha do wifi?"

    test "a refused or unreadable answer is an error, never a route":
      let seen = Seen()
      check perplexityGatekeeper("k", fake(seen, 401, "{}")).classify("oi").isErr
      check perplexityGatekeeper("k", fake(seen, 200, "not json")).classify("oi").isErr
      let down = proc(url, payload: string; headers: seq[(string, string)]): Result[(int, string), string] {.gcsafe, raises: [].} =
        err("connection refused")
      check perplexityGatekeeper("k", down).classify("oi").isErr

    test "an empty key gives no gatekeeper":
      check not perplexityGatekeeper("", nil).gatekeeperAvailable
      check not perplexityGatekeeper("   ", nil).gatekeeperAvailable

when isMainModule:
  runTests()
