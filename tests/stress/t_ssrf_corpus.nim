## Stress corpus: URL policy and redirect-hop SSRF vectors.

import std/[json, strutils, unittest, uri]
import results
import donkey/app/tools/web_tools
import donkey/core/tooling/structured_tool_result
import donkey/domain/url_policy
import donkey/ports/http

proc parse(toolResult: StructuredToolResult): JsonNode =
  parseJson(toolResult.toJson())

proc mockHttp(status: int; body: string; errMsg = ""): HttpRuntimePort =
  HttpRuntimePort(
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      if errMsg.len > 0:
        return err(errMsg)
      ok(HttpResponse(status: status, body: body)),
    getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      if errMsg.len > 0:
        return err(errMsg)
      ok(HttpResponse(status: status, body: body)),
  )

proc redirectHttp(location: string): HttpRuntimePort =
  HttpRuntimePort(
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      err("get must not follow redirects"),
    getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      if url == "https://example.com/start":
        return ok(HttpResponse(status: 302, body: "",
                               headers: @[("Location", location)]))
      if url == "https://example.com/b":
        return ok(HttpResponse(status: 200, body: "relative target"))
      ok(HttpResponse(status: 404, body: "unexpected hop: " & url))
  )

proc hopHttp(maxHops: int): HttpRuntimePort =
  HttpRuntimePort(
    getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      let path = parseUri(url).path
      if path == "/start":
        return ok(HttpResponse(status: 302, body: "",
                               headers: @[("Location", "/1")]))
      var hop = 0
      try:
        hop = parseInt(path[1 .. ^1])
      except ValueError:
        discard
      if hop < maxHops:
        ok(HttpResponse(status: 302, body: "",
                        headers: @[("Location", "/" & $(hop + 1))]))
      else:
        ok(HttpResponse(status: 200, body: "done"))
  )

suite "SSRF corpus":

  test "private authority vectors are blocked":
    let vectors = [
      "http://localhost/",
      "http://localhost./",
      "http://127.0.0.1/",
      "http://127.1.2.3/",
      "http://0.0.0.0/",
      "http://[::1]/",
      "http://[::ffff:127.0.0.1]/",
      "http://169.254.169.254/latest/meta-data/",
      "http://192.168.1.1/",
      "http://10.0.0.1/",
      "http://172.16.0.1/",
      "http://172.31.255.255/",
      "http://127.0.0.1:8080/admin@example.com",
      "http://127.0.0.1:8080/admin?x=@example.com",
      "http://user:pass@127.0.0.1/",
      "http://[::1]:8080/x",
    ]
    for url in vectors:
      if not isPrivateUrl(url):
        echo "private vector was accepted: ", url
      check isPrivateUrl(url)

  test "public authority vectors stay public":
    let vectors = [
      "https://example.com/",
      "https://example.com/@",
      "https://example.com/?next=http://127.0.0.1",
      "https://api.github.com/repos/openai/openai",
      "http://172.32.0.1/",
      "http://172.15.0.1/",
      "http://site10.example.com/",
    ]
    for url in vectors:
      check not isPrivateUrl(url)

  test "authority and path extraction align with the transport":
    check extractUrlHost("http://user:pass@example.com/x") == "example.com"
    check extractUrlHost("http://127.0.0.1:8080/admin@example.com") == "127.0.0.1"
    check extractUrlHost("http://[::1]:8080/") == "::1"
    check extractUrlHost("127.0.0.1:8080/admin") == "127.0.0.1"
    check extractUrlPath("https://example.com/@") == "/@"
    check extractUrlPath("https://example.com/admin@example.com?x=1") ==
      "/admin@example.com"

  test "private redirect targets are blocked per hop":
    for location in [
      "http://127.0.0.1:8080/admin",
      "http://127.0.0.1:8080/admin@example.com",
      "http://[::1]:8080/admin",
      "http://user:pass@127.0.0.1/",
    ]:
      let parsed = parse(performFetchStructured(
        redirectHttp(location), "https://example.com/start", expect = "text"))
      check not parsed["ok"].getBool()
      check parsed["error"]["message"].getStr().contains("private/internal")

  test "relative redirects are resolved and revalidated":
    let parsed = parse(performFetchStructured(
      redirectHttp("/b"), "https://example.com/start", expect = "text"))
    check parsed["ok"].getBool()
    check parsed["data"]["body"].getStr() == "relative target"

  test "five redirect hops are allowed and six are rejected":
    let ok = parse(performFetchStructured(
      hopHttp(5), "https://example.com/start", expect = "text"))
    check ok["ok"].getBool()
    check ok["data"]["body"].getStr() == "done"

    let tooMany = parse(performFetchStructured(
      hopHttp(6), "https://example.com/start", expect = "text"))
    check not tooMany["ok"].getBool()
    check tooMany["error"]["message"].getStr().contains("too many redirects")

  test "redirect loops are rejected":
    let loop = HttpRuntimePort(
      getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
        ok(HttpResponse(status: 302, body: "",
                        headers: @[("Location", "https://example.com/start")]))
    )
    let parsed = parse(performFetchStructured(
      loop, "https://example.com/start", expect = "text"))
    check not parsed["ok"].getBool()
    check parsed["error"]["message"].getStr().contains("redirect loop")

  test "missing Location returns the 3xx and fails the HTTP check":
    let noLocation = mockHttp(302, "moved")
    let parsed = parse(performFetchStructured(
      noLocation, "https://example.com/start", expect = "text"))
    check not parsed["ok"].getBool()
    check parsed["error"]["message"].getStr().contains("302")

  test "a public host resolving to a private IP is blocked":
    let privateResolution = HttpRuntimePort(
      getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
        err("must not fetch"),
      resolveHost: proc(host: string): Result[string, string] {.gcsafe.} =
        ok("127.0.0.1")
    )
    let parsed = parse(performFetchStructured(
      privateResolution, "https://public.example", expect = "text"))
    check not parsed["ok"].getBool()
    check parsed["error"]["message"].getStr().contains("URL blocked")
    check not parsed["error"]["message"].getStr().contains("must not fetch")

  test "DNS rejection blocks before the request":
    let dnsBlocked = HttpRuntimePort(
      getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
        err("must not fetch"),
      resolveHost: proc(host: string): Result[string, string] {.gcsafe.} =
        err("private address blocked: " & host)
    )
    let parsed = parse(performFetchStructured(
      dnsBlocked, "https://evil.example", expect = "text"))
    check not parsed["ok"].getBool()
    check parsed["error"]["message"].getStr().contains("URL blocked")

  test "ports without getNoRedirect fail closed":
    var getOnly = HttpRuntimePort()
    getOnly.get = proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: 200, body: "must not be used"))
    let parsed = parse(performFetchStructured(
      getOnly, "https://example.com", expect = "text"))
    check not parsed["ok"].getBool()
    check parsed["error"]["message"].getStr().contains("redirect-safe")
