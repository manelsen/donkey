## web_fetch, fetch, http_fetch and web_search off the event loop (second
## round, §3): each call becomes a WebToolJob of plain data, which a worker
## runs with its own transport; the result comes back as plain data too.

import std/[json, strutils, unittest]
import donkey/app/tools/web_tools
import donkey/core/pipeops
import donkey/core/tooling/structured_tool_result
import donkey/domain/message
import donkey/ports/http
import donkey/infra/thread_handle

proc mockHttp(status: int; body: string): HttpRuntimePort =
  HttpRuntimePort(
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: status, body: body)),
    getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: status, body: body)))

proc runTests*() =
  suite "web tools off the loop":

    test "the job and its result share nothing with the loop (plain data)":
      check sharesNothing(WebToolJob)
      check sharesNothing(WebToolOutput)

    test "a fetch job answers like performFetch":
      let job = WebToolJob(kind: wtkFetch, url: "https://example.com", maxCh: 500, label: "web_fetch")
      let out1 = runWebToolJob(job, mockHttp(200, "<p>Olá</p>"))
      check not out1.structured
      check out1.text == performFetch(mockHttp(200, "<p>Olá</p>"), "https://example.com", 500,
                                      policyLabel = "web_fetch")

    test "a structured fetch job carries the envelope as text and its kind":
      let job = WebToolJob(kind: wtkFetchStructured, url: "https://example.com/api",
                           expect: "json", maxCh: 500, label: "http_fetch")
      let res = runWebToolJob(job, mockHttp(200, """{"ok":true}"""))
      check res.structured and res.kind == trkOutput
      check parseJson(res.text)["data"]["body"]["ok"].getBool

    test "a search job answers like performWebSearch":
      let job = WebToolJob(kind: wtkSearch, query: "nim", count: 3, apiKey: "k")
      check runWebToolJob(job, mockHttp(200, """{"type":"search"}""")).text == "(no results)"
      check "BRAVE_API_KEY" in runWebToolJob(WebToolJob(kind: wtkSearch, query: "x"),
                                             mockHttp(200, "{}")).text

when isMainModule:
  runTests()
