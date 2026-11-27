## The gateway's request handler served through a `GatewayConnection` built
## on strings: no socket, no server. What the port buys.

import std/[json, os, strutils, unittest]
import chronos
import donkey/core/pipeops
import donkey/core/log
import donkey/domain/agent_message
import donkey/ports/ipc
import donkey/ports/gateway_connection
import donkey/app/http_gateway
import donkey/app/editor_registry
import donkey/adapters/filesystem/fs_adapter
import donkey/core/types

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

var gRandom {.threadvar.}: int

proc editorRandom(n: int): Result[seq[byte], string] {.gcsafe.} =
  inc gRandom
  var bytes = newSeq[byte](n)
  for i in 0 ..< n: bytes[i] = byte((gRandom * 31 + i) mod 256)
  ok(bytes)

proc editorRegistry(): EditorRegistry =
  let dir = getTempDir() / "donkey_gateway_editors"
  removeDir(dir)
  newEditorRegistry(newFsAdapter(), dir / "editors.json", editorRandom,
                    proc(): int64 {.gcsafe.} = 1_000).get

proc post(path, body: string; auth = ""): string =
  "POST " & path & " HTTP/1.1\r\n" &
    (if auth.len > 0: "Authorization: Bearer " & auth & "\r\n" else: "") &
    "Content-Type: application/json\r\nContent-Length: " & $body.len & "\r\n\r\n" & body

proc serveEditor(editors: EditorRegistry; request: string): string =
  let ctx = newGatewayContext(statusFn, logFn, authToken = "secret", editors = editors,
                              log = newLogger("t_gateway_connection", lvlError)).get()
  let wire = Wire(input: request)
  waitFor serveGatewayConnection(ctx, fakeConnection(wire))
  wire.output

proc bodyOf(response: string): JsonNode =
  parseJson(response[response.find("\r\n\r\n") + 4 .. ^1])

proc runEditorTests*() =
  suite "gateway over the connection port — editors (E10.2)":
    test "pairing end to end, without the operator's token":
      let editors = editorRegistry()
      let started = serveEditor(editors, post("/v1/acp/pair", """{"name":"Zed"}"""))
      check started.startsWith("HTTP/1.1 200")
      let code = started.bodyOf["code"].getStr
      let secret = started.bodyOf["pairing"].getStr
      check started.bodyOf["confirmWith"].getStr == "/editor " & code
      let poll = post("/v1/acp/pair/poll", $(%* {"pairing": secret}))
      check serveEditor(editors, poll).startsWith("HTTP/1.1 202")
      check editors.confirmPairing(code, UserId("u-ana")).isOk
      let paired = serveEditor(editors, poll)
      check paired.startsWith("HTTP/1.1 200")
      check editors.personFor(paired.bodyOf["token"].getStr).get == UserId("u-ana")
      check serveEditor(editors, poll).startsWith("HTTP/1.1 404")   ## once

    test "the editor's chat refuses a missing or unknown credential, and the operator's":
      let editors = editorRegistry()
      let chat = """{"user":"editor","stream":true,"messages":[{"role":"user","content":"oi"}]}"""
      check serveEditor(editors, post("/v1/acp/chat/completions", chat)).startsWith("HTTP/1.1 401")
      check serveEditor(editors, post("/v1/acp/chat/completions", chat, "nope")).startsWith("HTTP/1.1 401")
      check serveEditor(editors, post("/v1/acp/chat/completions", chat, "secret")).startsWith("HTTP/1.1 401")

    test "a GET to the pairing route is a 405 and pairs nothing":
      let editors = editorRegistry()
      let response = serveEditor(editors, "GET /v1/acp/pair HTTP/1.1\r\n\r\n")
      check response.startsWith("HTTP/1.1 405")
      check response.count("HTTP/1.1") == 1
      check editors.confirmPairing("AAAAAA", UserId("u")).isErr   ## nothing pending

    test "without a registry the editor routes are not there":
      check serve(post("/v1/acp/pair", "{}")).startsWith("HTTP/1.1 404")

when isMainModule:
  runTests()
  runEditorTests()
