## Bounded HTTP request reader shared by every embedded webhook server.
## Uses real loopback sockets: the client writes, then the server side reads.

import std/[monotimes, net, os, strutils, tables, times, unittest]
import donkey/core/pipeops
import donkey/adapters/webhook/http_request_reader

proc withRequest(raw: string; maxBody = MaxWebhookBodyBytes;
                 timeoutSec = 1): Result[WebhookRequest, string] =
  ## Writes `raw` from a loopback client (kept open) and reads it server-side.
  let server = newSocket(buffered = false)
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

type DripArgs = object
  port: int
  head: string
  bytes: int
  gapMs: int

proc dripClient(args: DripArgs) {.thread.} =
  ## Sends the headers, then the body one byte at a time — each gap shorter
  ## than the socket timeout, so only the total deadline can stop it.
  let s = newSocket()
  defer: s.close()
  try:
    s.connect("127.0.0.1", Port(args.port))
    ## flags = {}: without SafeDisconn a closed peer raises instead of
    ## making net.send retry forever (which would hang joinThread).
    s.send(args.head, flags = {})
    for _ in 0 ..< args.bytes:
      sleep(args.gapMs)
      s.send("x", flags = {})
  except CatchableError:
    discard

proc dripRequest(bytes, gapMs, deadlineSec: int): (Result[WebhookRequest, string], Duration) =
  ## Server side as production builds it: unbuffered client socket with a
  ## 1s idle timeout; the client drips the body from another thread.
  let server = newSocket(buffered = false)
  defer: server.close()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(0), "127.0.0.1")
  server.listen()
  var th: Thread[DripArgs]
  createThread(th, dripClient, DripArgs(
    port: server.getLocalAddr()[1].int,
    head: "POST / HTTP/1.1\r\nContent-Length: " & $bytes & "\r\n\r\n",
    bytes: bytes, gapMs: gapMs))
  var conn: Socket
  server.accept(conn)
  discard applyWebhookClientTimeouts(conn, 1)
  let t0 = getMonoTime()
  let r = readWebhookRequest(conn, deadlineSec = deadlineSec)
  let elapsed = getMonoTime() - t0
  conn.close()
  joinThread(th)
  (r, elapsed)

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

    test "the limit fits Meta's largest webhook payload (3 MB)":
      ## WhatsApp Cloud API webhooks can carry up to 3 MB; a smaller cap
      ## answers 413 and Meta drops the batch after retrying (hermes WA-002).
      check MaxWebhookBodyBytes >= 3 * 1000 * 1000

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

    test "conflicting duplicate Content-Length is rejected":
      let r = withRequest("POST / HTTP/1.1\r\nContent-Length: 2\r\n" &
                          "Content-Length: 1\r\n\r\na")
      check r.isErr
      check r.error == "conflicting content-length"
      check readErrorStatus(r.error) == 400

    test "identical duplicate Content-Length is accepted":
      let r = withRequest("POST / HTTP/1.1\r\nContent-Length: 1\r\n" &
                          "Content-Length: 1\r\n\r\na")
      check r.isOk
      check r.get.body == "a"

    test "slow-drip body is cut at the total deadline":
      let (r, elapsed) = dripRequest(bytes = 40, gapMs = 150, deadlineSec = 1)
      check r.isErr
      check elapsed < initDuration(milliseconds = 2500)

    test "active transfer longer than the idle timeout completes":
      ## Each gap (150ms) is under the idle timeout (1s); the whole body
      ## (~3s) is over it but under the total deadline (10s).
      let (r, _) = dripRequest(bytes = 20, gapMs = 150, deadlineSec = 10)
      check r.isOk
      if r.isOk:
        check r.get.body == 'x'.repeat(20)

    test "declared body never sent: idle timeout, not the total deadline":
      let t0 = getMonoTime()
      let r = withRequest("POST / HTTP/1.1\r\nContent-Length: 1\r\n\r\n",
                          timeoutSec = 1)
      check r.isErr
      check (getMonoTime() - t0) < initDuration(milliseconds = 2500)

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
