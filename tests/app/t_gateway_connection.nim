## The gateway's request handler served through a `GatewayConnection` built
## on strings: no socket, no server. What the port buys.

import std/[strutils, unittest]
import chronos
import donkey/core/pipeops
import donkey/core/log
import donkey/domain/agent_message
import donkey/ports/ipc
import donkey/ports/gateway_connection
import donkey/app/http_gateway

type Wire = ref object
  input: string     ## what the client sent, not yet read
  output: string    ## what the handler wrote
  chunk: int        ## most bytes one readSome returns; 0 = no limit

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
    readSome: proc(maxBytes: int; deadline: Moment):
                  Future[Result[string, string]] {.async: (raises: []).} =
      var n = min(maxBytes, wire.input.len)
      if wire.chunk > 0: n = min(n, wire.chunk)
      let chunk = wire.input[0 ..< n]
      wire.input = wire.input[n .. ^1]
      return ok(chunk),
    write: proc(data: string): Future[Result[void, string]] {.async: (raises: []).} =
      wire.output.add data
      return ok(),
    atEof: proc(): bool {.gcsafe, raises: [].} = false)  ## the client keeps it open

proc statusFn(): DaemonStatus {.gcsafe, raises: [CatchableError].} =
  DaemonStatus(sessionCount: 3)

proc logFn(n: int): seq[IpcLogEntry] {.gcsafe, raises: [CatchableError].} = @[]

var gActions {.threadvar.}: int

proc sessionAction(rawUserId: string; taskKind: TaskKind; payload: string):
                   GatewaySessionActionOutcome {.gcsafe, raises: [CatchableError].} =
  inc gActions
  gsaoAccepted

proc serve(request: string; token = "secret"; chunk = 0): string =
  let ctx = newGatewayContext(statusFn, logFn, authToken = token,
                              sessionActionFn = sessionAction,
                              log = newLogger("t_gateway_connection", lvlError)).get()
  let wire = Wire(input: request, chunk: chunk)
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

  suite "gateway over the connection port — request bodies":
    const actionBody = """{"action":"new"}"""
    proc sessionTask(body: string; declared = actionBody.len): string =
      "POST /api/sessions/u1/task HTTP/1.1\r\n" &
        "Authorization: Bearer secret\r\n" &
        "Content-Type: application/json\r\n" &
        "Content-Length: " & $declared & "\r\n\r\n" & body

    setup:
      gActions = 0

    test "a body that arrives in pieces is read whole":
      let response = serve(sessionTask(actionBody), chunk = 5)
      check response.startsWith("HTTP/1.1 202")
      check gActions == 1

    test "a body cut short by the end of the stream is refused":
      ## Content-Length promises more than the client sends before closing.
      let response = serve(sessionTask(actionBody[0 ..< 6]), chunk = 5)
      check response.startsWith("HTTP/1.1 400")
      check "request body incomplete" in response
      check gActions == 0

when isMainModule:
  runTests()
