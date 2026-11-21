## media_download unit tests — HTTP status handling via a fake HttpPort.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/core/media_download
import donkey/ports/http

type FakeHttp = object
  status: int
  body:   string
  fail:   string

proc reply(f: FakeHttp): Result[HttpResponse, string] =
  if f.fail.len > 0: err(f.fail)
  else: ok(HttpResponse(status: f.status, body: f.body))

proc get(f: FakeHttp; url: string; h: seq[HttpHeader]): Result[HttpResponse, string] = f.reply
proc post(f: FakeHttp; url, b: string; h: seq[HttpHeader]): Result[HttpResponse, string] = f.reply
proc put(f: FakeHttp; url, b: string; h: seq[HttpHeader]): Result[HttpResponse, string] = f.reply
proc patch(f: FakeHttp; url, b: string; h: seq[HttpHeader]): Result[HttpResponse, string] = f.reply
proc delete(f: FakeHttp; url: string; h: seq[HttpHeader]): Result[HttpResponse, string] = f.reply

proc runTests*() =
  suite "fetchBytes":

    test "2xx returns body bytes":
      let r = FakeHttp(status: 200, body: "abc").fetchBytes("https://x/f", @[])
      check r.isOk
      check r.get == @[byte('a'), byte('b'), byte('c')]

    test "non-2xx is an error, not an error page saved as the file":
      let r = FakeHttp(status: 404, body: "<html>not found</html>").fetchBytes("https://x/f", @[])
      check r.isErr
      check "404" in r.error

    test "3xx is an error":
      check FakeHttp(status: 302, body: "").fetchBytes("https://x/f", @[]).isErr

    test "transport error propagates":
      let r = FakeHttp(fail: "boom").fetchBytes("https://x/f", @[])
      check r.isErr
      check "boom" in r.error

  suite "downloadUrlAsBytes":

    test "rejects non-2xx":
      check FakeHttp(status: 500, body: "oops").downloadUrlAsBytes("https://x/f").isErr

    test "returns bytes on 200":
      check FakeHttp(status: 200, body: "hi").downloadUrlAsBytes("https://x/f").get.len == 2

when isMainModule:
  runTests()
