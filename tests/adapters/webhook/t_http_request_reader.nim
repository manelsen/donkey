## Bounded HTTP request reader shared by every embedded webhook server.
## Uses real loopback sockets: the client writes, then the server side reads.

import std/[monotimes, net, strutils, tables, times, unittest]
import donkey/core/pipeops
import donkey/adapters/webhook/http_request_reader

proc withRequest(raw: string; maxBody = MaxWebhookBodyBytes;
                 timeoutSec = 1): Result[WebhookRequest, string] =
  ## Writes `raw` from a loopback client (kept open) and reads it server-side.
  let server = newSocket()
  defer: server.close()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(0), "127.0.0.1")
  server.listen()
  let port = server.getLocalAddr()[1]
  let client = newSocket()
  defer: client.close()
  client.connect("127.0.0.1", port)
  if raw.len > 0:
    client.send(raw)
  var conn: Socket
  server.accept(conn)
  defer: conn.close()
  discard applyWebhookClientTimeouts(conn, timeoutSec)
  readWebhookRequest(conn, maxBody)

proc runTests*() =
  suite "parseContentLength":

    test "plain digits":
      check parseContentLength("42").get == 42
      check parseContentLength(" 0 ").get == 0

    test "rejects sign, garbage and empty":
      check parseContentLength("-1").isErr
      check parseContentLength("+1").isErr
      check parseContentLength("1e3").isErr
      check parseContentLength("").isErr

    test "rejects values that overflow int":
      check parseContentLength("99999999999999999999999").isErr

  suite "readWebhookRequest":

    test "parses method, path, query, headers and body":
      let r = withRequest("POST /hook?a=1&b=x%20y HTTP/1.1\r\n" &
                          "Host: x\r\nContent-Length: 5\r\nX-Sig: abc\r\n\r\nhello")
      check r.isOk
      let req = r.get
      check req.httpMethod == "POST"
      check req.path == "/hook"
      check req.query["a"] == "1"
      check req.query["b"] == "x y"
      check req.headers["x-sig"] == "abc"
      check req.body == "hello"

    test "huge Content-Length is rejected before allocating":
      let r = withRequest("POST / HTTP/1.1\r\nContent-Length: 99999999999\r\n\r\n")
      check r.isErr
      check r.error == "body too large"

    test "Content-Length above caller limit is rejected":
      let r = withRequest("POST / HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world",
                          maxBody = 10)
      check r.error == "body too large"

    test "malformed Content-Length is a bad request":
      let r = withRequest("POST / HTTP/1.1\r\nContent-Length: -5\r\n\r\n")
      check r.isErr
      check readErrorStatus(r.error) == 400

    test "overlong header line is rejected":
      let r = withRequest("GET / HTTP/1.1\r\nX: " & 'a'.repeat(MaxWebhookLineBytes + 10) & "\r\n\r\n")
      check r.error == "header line too long"

    test "too many headers is rejected":
      var raw = "GET / HTTP/1.1\r\n"
      for i in 0 .. MaxWebhookHeaderLines + 1:
        raw.add("X-" & $i & ": v\r\n")
      check withRequest(raw & "\r\n").error == "too many headers"

    test "truncated body is rejected":
      let r = withRequest("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc")
      check r.isErr

    test "slow client (no data) times out instead of hanging":
      let t0 = getMonoTime()
      let r = withRequest("", timeoutSec = 1)
      check r.isErr
      check (getMonoTime() - t0) < initDuration(seconds = 5)

  suite "readErrorStatus":

    test "body too large maps to 413, everything else to 400":
      check readErrorStatus("body too large") == 413
      check readErrorStatus("truncated body") == 400
      check readErrorStatus("header line too long") == 400

when isMainModule:
  runTests()
