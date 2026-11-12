import std/[json, strutils, unittest]
import results
import donkey/app/tools/web_tools
import donkey/core/tooling/structured_tool_result
import donkey/ports/http

proc parse(toolResult: StructuredToolResult): JsonNode =
  parseJson(toolResult.toJson())

proc mockHttp(status: int; body: string; errMsg = ""): HttpRuntimePort =
  HttpRuntimePort(
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      if errMsg.len > 0:
        return err(errMsg)
      ok(HttpResponse(status: status, body: body))
  )

proc redirectHttp(location: string): HttpRuntimePort =
  ## First hop answers 302; only the expected rewritten URL gets a 200.
  HttpRuntimePort(
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      ok(HttpResponse(status: 500, body: "get must not follow redirects")),
    getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      if url == "https://example.com/start":
        return ok(HttpResponse(status: 302, body: "",
                               headers: @[("Location", location)]))
      if url == "https://example.com/b":
        return ok(HttpResponse(status: 200, body: "relative target"))
      ok(HttpResponse(status: 404, body: "unexpected hop: " & url))
  )

suite "structured web tools":

  test "performFetchStructured returns text body envelope":
    let parsed = parse(performFetchStructured(mockHttp(200, "<p>Hello structured web</p>"),
                                              "https://example.com",
                                              expect = "text",
                                              maxCh = 500))

    check parsed["ok"].getBool()
    check parsed["status"].getStr() == "output"
    check parsed["data"]["status"].getInt() == 200
    check parsed["data"]["headers"].kind == JArray
    check parsed["data"]["headers"].len == 0
    check parsed["data"]["body_format"].getStr() == "text"
    check parsed["data"]["body"].getStr() == "Hello structured web"

  test "performFetchStructured returns parsed json body":
    let parsed = parse(performFetchStructured(mockHttp(200, """{"ok":true,"count":2}"""),
                                              "https://example.com/api",
                                              expect = "json"))

    check parsed["ok"].getBool()
    check parsed["data"]["status"].getInt() == 200
    check parsed["data"]["body_format"].getStr() == "json"
    check parsed["data"]["body"]["ok"].getBool()
    check parsed["data"]["body"]["count"].getInt() == 2

  test "performFetchStructured blocks private urls with operational error":
    let parsed = parse(performFetchStructured(mockHttp(200, "ignored"),
                                              "http://127.0.0.1:8080/admin",
                                              expect = "text"))

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "operational_error"
    check parsed["error"]["message"].getStr().contains("private/internal")

  test "redirect into a private address is blocked per hop":
    let parsed = parse(performFetchStructured(
      redirectHttp("http://127.0.0.1:8080/admin"),
      "https://example.com/start", expect = "text"))

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "operational_error"
    check parsed["error"]["message"].getStr().contains("private/internal")

  test "relative redirect is resolved against the current URL":
    let parsed = parse(performFetchStructured(
      redirectHttp("/b"), "https://example.com/start", expect = "text"))

    check parsed["ok"].getBool()
    check parsed["data"]["status"].getInt() == 200
    check parsed["data"]["body"].getStr() == "relative target"

  test "DNS rejection blocks the fetch before the request":
    let dnsBlocked = HttpRuntimePort(
      get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
        ok(HttpResponse(status: 200, body: "must not be reached")),
      resolveHost: proc(host: string): Result[string, string] {.gcsafe.} =
        err("private address blocked: " & host)
    )
    let parsed = parse(performFetchStructured(dnsBlocked, "https://evil.example",
                                              expect = "text"))

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "operational_error"
    check parsed["error"]["message"].getStr().contains("URL blocked")
    check parsed["error"]["message"].getStr().contains("private address blocked")

  test "performFetchStructured reports HTTP status failures":
    let parsed = parse(performFetchStructured(mockHttp(404, "missing"),
                                              "https://example.com/missing",
                                              expect = "text"))

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "operational_error"
    check parsed["error"]["message"].getStr().contains("404")

  test "performFetchStructured rejects unsupported expect mode":
    let parsed = parse(performFetchStructured(mockHttp(200, "ok"),
                                              "https://example.com",
                                              expect = "xml"))

    check not parsed["ok"].getBool()
    check parsed["status"].getStr() == "usage_error"
    check parsed["error"]["message"].getStr().contains("expect")
