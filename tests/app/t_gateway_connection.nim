## The gateway's request handler served through a `GatewayConnection` built
## on strings: no socket, no server. What the port buys.

import std/[strutils, unittest]
import chronos
import donkey/core/pipeops
import donkey/core/log
import donkey/ports/ipc
import donkey/ports/gateway_connection
import donkey/app/http_gateway

type Wire = ref object
  input: string     ## what the client sent, not yet read
  output: string    ## what the handler wrote

proc fakeConnection(wire: Wire): GatewayConnection =
  GatewayConnection(
    readLine: proc(limit: int; deadline: Moment):
                   Future[Result[string, string]] {.async: (raises: []).} =
      let nl = wire.input.find('\n')
      if nl < 0:
        let rest = wire.input
        wire.input = ""
        return ok(rest)
      let line = wire.input[0 ..< nl]
      wire.input = wire.input[nl + 1 .. ^1]
      return ok(line),
    readSome: proc(maxBytes: int; deadline: Moment): Future[string]
                  {.async: (raises: []).} =
      let n = min(maxBytes, wire.input.len)
      let chunk = wire.input[0 ..< n]
      wire.input = wire.input[n .. ^1]
      return chunk,
    write: proc(data: string): Future[bool] {.async: (raises: []).} =
      wire.output.add data
      return true,
    atEof: proc(): bool {.gcsafe, raises: [].} = false)  ## the client keeps it open

proc statusFn(): DaemonStatus {.gcsafe, raises: [CatchableError].} =
  DaemonStatus(sessionCount: 3)

proc logFn(n: int): seq[IpcLogEntry] {.gcsafe, raises: [CatchableError].} = @[]

proc serve(request: string; token = "secret"): string =
  let ctx = newGatewayContext(statusFn, logFn, authToken = token,
                              log = newLogger("t_gateway_connection", lvlError)).get()
  let wire = Wire(input: request)
  waitFor serveGatewayConnection(ctx, fakeConnection(wire))
  wire.output

proc runTests*() =
  suite "gateway over the connection port":
    test "a health probe is answered without credentials":
      let response = serve("GET /health HTTP/1.1\r\nHost: x\r\n\r\n")
      check response.startsWith("HTTP/1.1 200 OK\r\n")
      check "Access-Control-Allow-Origin: *" in response

    test "an /api route needs the Bearer token":
      check serve("GET /api/status HTTP/1.1\r\n\r\n").startsWith("HTTP/1.1 401")
      let response = serve(
        "GET /api/status HTTP/1.1\r\nAuthorization: Bearer secret\r\n\r\n")
      check response.startsWith("HTTP/1.1 200 OK")
      check "\"sessionCount\":3" in response.replace(" ", "")

    test "an unknown path is a 401 without the token and a 404 with it":
      check serve("GET /nope HTTP/1.1\r\n\r\n").startsWith("HTTP/1.1 401")
      check serve("GET /nope HTTP/1.1\r\nAuthorization: Bearer secret\r\n\r\n")
        .startsWith("HTTP/1.1 404")

when isMainModule:
  runTests()
