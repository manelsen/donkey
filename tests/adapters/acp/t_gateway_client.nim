## The HTTP client `donkey acp` uses (E10.1): pairing, polling, and a turn
## whose SSE lines arrive one by one. Against a local socket that answers
## like the gateway.

import std/[strutils, unittest]
import chronos
import donkey/core/pipeops
import donkey/app/acp_runtime
import donkey/adapters/acp/gateway_client

var gRequests {.threadvar.}: seq[string]
var gReply {.threadvar.}: string

proc serveOnce(server: StreamServer; transp: StreamTransport) {.async: (raises: []).} =
  try:
    var request = ""
    var length = 0
    while true:
      let line = await transp.readLine()
      if line.len == 0: break
      request.add line & "\n"
      if line.toLowerAscii.startsWith("content-length:"):
        length = parseInt(line.split(':')[1].strip)
    if length > 0:
      var body = newString(length)
      await transp.readExactly(addr body[0], length)
      request.add "\n" & body
    gRequests.add request
    discard await transp.write(gReply)
  except CatchableError:
    discard
  finally:
    await transp.closeWait()

proc withServer(reply: string; run: proc(base: string) {.gcsafe.}) =
  gRequests = @[]
  gReply = reply
  let server = createStreamServer(initTAddress("127.0.0.1:0"), serveOnce, {ReuseAddr})
  server.start()
  try:
    run("http://127.0.0.1:" & $server.localAddress.port)
  finally:
    server.stop()
    waitFor server.closeWait()

proc http(status: string; body: string; contentType = "application/json"): string =
  "HTTP/1.1 " & status & "\r\nContent-Type: " & contentType & "\r\nContent-Length: " &
    $body.len & "\r\nConnection: close\r\n\r\n" & body

proc runTests*() =
  suite "acp gateway client":
    test "pair: the editor's name out, the code and the secret back":
      withServer(http("200 OK", """{"code":"K7QP2M","pairing":"sec","expiresIn":600}""")) do (base: string):
        let c = newGatewayClient(base)
        let r = waitFor c.pair("Zed")
        check r.get == GatewayPairing(code: "K7QP2M", secret: "sec")
        check gRequests[0].startsWith("POST /v1/acp/pair HTTP/1.1")
        check gRequests[0].endsWith("""{"name":"Zed"}""")

    test "poll: pending, paired with the token, or gone":
      withServer(http("202 Accepted", """{"status":"pending"}""")) do (base: string):
        check (waitFor newGatewayClient(base).poll("sec")).get.state == gpPending
        check """{"pairing":"sec"}""" in gRequests[0]
      withServer(http("200 OK", """{"status":"paired","token":"tok"}""")) do (base: string):
        check (waitFor newGatewayClient(base).poll("sec")).get == GatewayPoll(state: gpPaired, token: "tok")
      withServer(http("404 Not Found", """{"status":"unknown"}""")) do (base: string):
        check (waitFor newGatewayClient(base).poll("sec")).get.state == gpUnknown

    test "a turn: the credential as Bearer, the text as the last message, lines streamed":
      let sse = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Oi\"}}]}\n\ndata: [DONE]\n\n"
      withServer(http("200 OK", sse, "text/event-stream")) do (base: string):
        var lines: seq[string]
        let reply = waitFor newGatewayClient(base).turn("tok", "revise",
          proc(line: string) {.gcsafe, raises: [].} =
            {.cast(gcsafe).}: lines.add line)
        check reply.status == 200
        check lines.len >= 2 and lines[0].startsWith("data: {") and "data: [DONE]" in lines
        check "Authorization: Bearer tok" in gRequests[0]
        check gRequests[0].startsWith("POST /v1/acp/chat/completions HTTP/1.1")
        check "\"stream\":true" in gRequests[0] and "\"content\":\"revise\"" in gRequests[0]

    test "a refusal keeps its status and body; no server is status 0 with why":
      withServer(http("401 Unauthorized", """{"error":"unknown editor"}""")) do (base: string):
        let reply = waitFor newGatewayClient(base).turn("bad", "x",
          proc(line: string) {.gcsafe, raises: [].} = discard)
        check reply.status == 401 and "unknown editor" in reply.body
      let gone = waitFor newGatewayClient("http://127.0.0.1:9").turn("t", "x",
        proc(line: string) {.gcsafe, raises: [].} = discard)
      check gone.status == 0 and gone.error.len > 0

when isMainModule:
  runTests()
