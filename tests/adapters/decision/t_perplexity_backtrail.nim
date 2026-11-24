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
      let r = perplexityBacktrailCall("pplx-test", "qual é a senha do wifi?", fake(seen, 200,
        """{"answers":{"route":{"choice":"fact","confidence":0.9}}}"""))
      check r.isOk and r.get.route == mrFact
      check seen.url == PerplexityDecisionsUrl
      check ("Authorization", "Bearer pplx-test") in seen.headers
      check parseJson(seen.body)["state"].getStr == "qual é a senha do wifi?"

    test "a refused or unreadable answer is an error, never a route":
      let seen = Seen()
      check perplexityBacktrailCall("k", "oi", fake(seen, 401, "{}")).isErr
      check perplexityBacktrailCall("k", "oi", fake(seen, 200, "not json")).isErr
      let down = proc(url, payload: string; headers: seq[(string, string)]): Result[(int, string), string] {.gcsafe, raises: [].} =
        err("connection refused")
      check perplexityBacktrailCall("k", "oi", down).isErr

    test "an empty key is refused before any request":
      let seen = Seen()
      check perplexityBacktrailCall("  ", "oi", fake(seen, 200, "{}")).isErr
      check seen.url == ""

    test "the worker job reads its input and refuses a bad one":
      check perplexityBacktrailJob("not json").isErr
      check perplexityBacktrailJob($(%*{"key": "", "message": "oi"})).isErr

when isMainModule:
  runTests()
