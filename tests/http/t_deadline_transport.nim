## The HTTP transport keeps a wall-clock deadline for the whole request: a
## server that answers a byte now and then, or never answers, fails the
## request at the deadline instead of holding the caller (a provider worker,
## a channel loop) forever. A local server plays each case.

import std/[atomics, nativesockets, net, os, strutils, times, unittest]
import donkey/core/pipeops
import donkey/infra/thread_handle
import donkey/adapters/http/deadline_transport
import chronos/apps/http/httpclient
import donkey/adapters/http/std_http

type ServerArg = object
  port: int

proc readRequest(client: Socket): string =
  ## The request line and headers, then a body announced by Content-Length.
  var line = ""
  var length = 0
  client.readLine(line, timeout = 2000)
  result = line
  while true:
    client.readLine(line, timeout = 2000)
    if line == "\r\n" or line.len == 0: break
    if line.toLowerAscii.startsWith("authorization:"):
      result.add "\n" & line
    if line.toLowerAscii.startsWith("content-length:"):
      length = parseInt(line.split(':')[1].strip)
  if length > 0:
    result.add "\n" & client.recv(length, timeout = 2000)

var gCounted: Atomic[int]  ## requests that reached /count
var gPortForServer: int    ## set before the server starts; read by handlers

type ConnArg = object
  fd: SocketHandle  ## plain data: the connection is rebuilt in its thread

proc handle(arg: ConnArg) {.thread.} =
  let client = newSocket(arg.fd)
  block:
    try:
      let request = readRequest(client)
      let path = request.split(' ')[1]
      case path
      of "/big":
        ## Announces and sends 2 MB: a capped read must stop and refuse it.
        client.send("HTTP/1.1 200 OK\r\nContent-Length: 2097152\r\nConnection: close\r\n\r\n")
        let chunk = "x".repeat(65536)
        for _ in 0 ..< 32:
          try: client.send(chunk)
          except CatchableError: break
      of "/bigchunked":
        ## The same without a length: the cap must hold on the bytes read.
        client.send("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
        let chunk = "x".repeat(65536)
        for _ in 0 ..< 32:
          try: client.send("10000\r\n" & chunk & "\r\n")
          except CatchableError: break
        try: client.send("0\r\n\r\n") except CatchableError: discard
      of "/ok":
        client.send("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n" &
                    "X-Probe: yes\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello")
      of "/echo":
        let body = if '\n' in request: request.split('\n', 1)[1] else: ""
        client.send("HTTP/1.1 200 OK\r\nContent-Length: " & $body.len &
                    "\r\nConnection: close\r\n\r\n" & body)
      of "/redirect307":
        client.send("HTTP/1.1 307 Temporary Redirect\r\nLocation: /echo\r\n" &
                    "Content-Length: 0\r\nConnection: close\r\n\r\n")
      of "/redirect303":
        client.send("HTTP/1.1 303 See Other\r\nLocation: /method\r\n" &
                    "Content-Length: 0\r\nConnection: close\r\n\r\n")
      of "/method":
        let meth = request.split(' ')[0]
        client.send("HTTP/1.1 200 OK\r\nContent-Length: " & $meth.len &
                    "\r\nConnection: close\r\n\r\n" & meth)
      of "/to303":
        client.send("HTTP/1.1 303 See Other\r\nLocation: /to307\r\n" &
                    "Content-Length: 0\r\nConnection: close\r\n\r\n")
      of "/to307":
        client.send("HTTP/1.1 307 Temporary Redirect\r\nLocation: /method\r\n" &
                    "Content-Length: 0\r\nConnection: close\r\n\r\n")
      of "/cross":
        ## To another host name (same server), which redirects within itself.
        client.send("HTTP/1.1 302 Found\r\nLocation: http://localhost:" &
                    $gPortForServer & "/samehost\r\nContent-Length: 0\r\n" &
                    "Connection: close\r\n\r\n")
      of "/samehost":
        client.send("HTTP/1.1 302 Found\r\nLocation: /whoami\r\n" &
                    "Content-Length: 0\r\nConnection: close\r\n\r\n")
      of "/whoami":
        var auth = "none"
        for line in request.splitLines:
          if line.toLowerAscii.startsWith("authorization:"):
            auth = line.split(':', 1)[1].strip
        client.send("HTTP/1.1 200 OK\r\nContent-Length: " & $auth.len &
                    "\r\nConnection: close\r\n\r\n" & auth)
      of "/count":
        discard gCounted.fetchAdd(1)
        client.send("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      of "/redirect":
        client.send("HTTP/1.1 302 Found\r\nLocation: /ok\r\n" &
                    "Content-Length: 0\r\nConnection: close\r\n\r\n")
      of "/drip":
        ## Headers at once, then a one-byte chunk every 300 ms. Each read
        ## (a chunk-size line, a chunk) succeeds within any read timeout, so
        ## only a deadline for the whole request ends it: this is the case
        ## std/httpclient's per-read timeout never catches.
        client.send("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        for _ in 0 ..< 1000:
          client.send("1\r\nx\r\n")
          sleep(300)
      of "/silent":
        ## Never answers; stops as soon as the client hangs up, so the next
        ## test is served (the server handles one connection at a time).
        for _ in 0 ..< 200:
          try:
            if client.recv(1, timeout = 100).len == 0: break
          except TimeoutError:
            discard
      else:
        client.send("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n")
    except CatchableError:
      discard  ## the client gave up: expected for /drip and /silent
    client.close()

proc serve(arg: ServerArg) {.thread.} =
  ## One thread per connection, so a dripping or silent reply never holds
  ## up the next test.
  let server = newSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(arg.port), "127.0.0.1")
  server.listen()
  while true:
    var client: Socket
    server.accept(client)
    discard spawnThread(handle, ConnArg(fd: client.getFd()))

proc freePort(): int =
  ## A port the OS reports free right now, so parallel test runs do not clash.
  let probe = newSocket()
  probe.bindAddr(Port(0), "127.0.0.1")
  result = probe.getLocalAddr()[1].int
  probe.close()

let gPort = freePort()
var gServer: ThreadHandle[ServerArg]

proc url(path: string): string = "http://127.0.0.1:" & $gPort & path

type BusyArg = object
  url: string

proc occupy(arg: BusyArg) {.thread.} =
  ## Holds one transport worker for about two seconds.
  discard transportRequest(TransportRequest(meth: "GET", url: arg.url,
                                            deadlineMs: 2_000))

proc timed(body: proc(): Result[TransportResponse, string]): (Result[TransportResponse, string], float) =
  let started = epochTime()
  let res = body()
  (res, epochTime() - started)

proc runTests*() =
  gPortForServer = gPort
  gServer = spawnThread(serve, ServerArg(port: gPort))
  sleep(200)

  suite "deadline transport":
    test "a normal response comes back with status, headers and body":
      let res = transportRequest(TransportRequest(
        meth: "GET", url: url("/ok"), deadlineMs: 5_000))
      check res.isOk
      check res.get.status == 200
      check res.get.body == "hello"
      check ("x-probe", "yes") in res.get.headers

    test "a body over the cap is refused, whether its length is announced or not":
      for path in ["/big", "/bigchunked"]:
        let res = transportRequest(TransportRequest(meth: "GET", url: url(path),
          deadlineMs: 10_000, maxBodyBytes: 1024 * 1024))
        check res.isErr and "larger than" in res.error
      let fits = transportRequest(TransportRequest(meth: "GET", url: url("/big"),
        deadlineMs: 10_000, maxBodyBytes: 4 * 1024 * 1024))
      check fits.isOk and fits.get.body.len == 2097152

    test "the adapter passes its cap to the transport":
      let small = newStdHttpAdapter(timeout = 10, maxRetries = 3, circuitBreaker = false,
                                    maxResponseBytes = 1024 * 1024)
      let started = epochTime()
      let res = small.get(url("/big"))
      check res.isErr and res.error.startsWith("response body larger than")
      check epochTime() - started < 2.0   ## no retry, no backoff

    test "a POST body reaches the server":
      let res = transportRequest(TransportRequest(
        meth: "POST", url: url("/echo"), body: "{\"a\":1}",
        headers: @[("Content-Type", "application/json")], deadlineMs: 5_000))
      check res.get.body == "{\"a\":1}"

    test "a server that drips bytes fails at the deadline":
      let (res, elapsed) = timed(proc(): Result[TransportResponse, string] =
        transportRequest(TransportRequest(meth: "GET", url: url("/drip"),
                                          deadlineMs: 1_000)))
      check res.isErr
      check "deadline" in res.error
      check elapsed < 3.0

    test "a server that never answers fails at the deadline":
      let (res, elapsed) = timed(proc(): Result[TransportResponse, string] =
        transportRequest(TransportRequest(meth: "GET", url: url("/silent"),
                                          deadlineMs: 1_000)))
      check res.isErr
      check elapsed < 3.0

    test "redirects follow the limit; zero returns the redirect itself":
      let held = transportRequest(TransportRequest(
        meth: "GET", url: url("/redirect"), redirectLimit: 0, deadlineMs: 5_000))
      check held.get.status == 302
      let followed = transportRequest(TransportRequest(
        meth: "GET", url: url("/redirect"), redirectLimit: 5, deadlineMs: 5_000))
      check followed.get.status == 200
      check followed.get.body == "hello"

    test "a 307 keeps the method and body; a 303 becomes a GET":
      let kept = transportRequest(TransportRequest(
        meth: "POST", url: url("/redirect307"), body: "payload",
        redirectLimit: 5, deadlineMs: 5_000))
      check kept.get.body == "payload"
      let switched = transportRequest(TransportRequest(
        meth: "POST", url: url("/redirect303"), body: "payload",
        redirectLimit: 5, deadlineMs: 5_000))
      check switched.get.body == "GET"

    test "each redirect starts from the previous hop, not the original request":
      ## POST -> 303 (now a GET without body) -> 307 keeps that GET.
      let chained = transportRequest(TransportRequest(
        meth: "POST", url: url("/to303"), body: "payload",
        headers: @[("Content-Type", "text/plain")], redirectLimit: 5,
        deadlineMs: 5_000))
      check chained.get.body == "GET"

    test "credentials dropped at a cross-host redirect never come back":
      ## 127.0.0.1 -> localhost (another host: Authorization dropped) ->
      ## localhost again: it must stay dropped.
      let res = transportRequest(TransportRequest(
        meth: "GET", url: url("/cross"),
        headers: @[("Authorization", "Bearer secret")], redirectLimit: 5,
        deadlineMs: 5_000))
      check res.get.body == "none"

    test "every redirect hop is checked against the allowlist":
      ## 127.0.0.1 is allowed; its redirect to localhost is not, and the hop
      ## must fail instead of connecting.
      let res = transportRequest(TransportRequest(
        meth: "GET", url: url("/cross"), redirectLimit: 5,
        allowlist: @["127.0.0.1"], deadlineMs: 5_000))
      check res.isErr
      check "allowlist" in res.error
      let allowed = transportRequest(TransportRequest(
        meth: "GET", url: url("/redirect"), redirectLimit: 5,
        allowlist: @["127.0.0.1"], deadlineMs: 5_000))
      check allowed.get.status == 200

    test "an IPv6 authority on the allowlist keeps its brackets":
      let address = getHttpAddress("http://[::1]:8080/x").get
      check hopAllowed(address, @["[::1]:8080"])
      check hopAllowed(address, @["::1"])
      check not hopAllowed(address, @["[::1]:9090"])

    test "a redirect from https to http is refused":
      let secure = getHttpAddress("https://api.example.com/v1").get
      check isDowngrade(secure, getHttpAddress("http://api.example.com/v1").get)
      check not isDowngrade(secure, getHttpAddress("https://other.example.com/").get)
      check not isDowngrade(getHttpAddress("http://a/").get,
                            getHttpAddress("http://b/").get)

    test "a HEAD stays a HEAD across a 303":
      let res = transportRequest(TransportRequest(
        meth: "HEAD", url: url("/redirect303"), redirectLimit: 5,
        deadlineMs: 5_000))
      check res.isOk
      check res.get.status == 200
      check res.get.body == ""  ## a GET would read "GET" back from /method

    test "a request that waited past its deadline in the queue never runs":
      ## Every worker busy on a silent server: the short request fails at its
      ## deadline and must not be sent later, after its caller was told.
      var busy: array[TransportWorkers, ThreadHandle[BusyArg]]
      for i in 0 ..< TransportWorkers:
        busy[i] = spawnThread(occupy, BusyArg(url: url("/silent")))
      sleep(300)
      gCounted.store(0)
      let res = transportRequest(TransportRequest(
        meth: "POST", url: url("/count"), deadlineMs: 500))
      check res.isErr
      for i in 0 ..< TransportWorkers: joinAndFree(busy[i])
      sleep(500)
      check gCounted.load() == 0

    test "the requests carry no ref or closure into the workers":
      check sharesNothing(TransportRequest)

  suite "StdHttpAdapter over the deadline transport":
    test "a dripping server fails the call at the adapter timeout":
      let adapter = newStdHttpAdapter(timeout = 1, maxRetries = 1,
                                      circuitBreaker = false)
      let started = epochTime()
      let res = adapter.get(url("/drip"))
      check res.isErr
      check epochTime() - started < 3.0

    test "a normal call still works through the adapter":
      let adapter = newStdHttpAdapter(timeout = 5, maxRetries = 1,
                                      circuitBreaker = false)
      let res = adapter.postNoRedirect(url("/echo"), "ping")
      check res.get.status == 200
      check res.get.body == "ping"

when isMainModule:
  runTests()
