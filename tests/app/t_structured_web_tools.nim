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
