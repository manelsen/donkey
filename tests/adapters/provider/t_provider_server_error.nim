## A provider that answers 5xx must reach the caller as
## "<Name> API error <code> <reason>: <body>", the text prompt_building and the
## orchestrator classify on. The production transport sends the POST once and
## must hand that final response over instead of a generic transport error.

import std/[nativesockets, net, strutils, unittest]
import donkey/core/pipeops
import donkey/ports/http
import donkey/adapters/provider/provider_http

const ErrorBody = """{"error":"upstream overloaded"}"""

var gHits: int
var gServerThread: Thread[int]

proc serveOnce(fd: int) {.thread.} =
  let server = newSocket(SocketHandle(fd), AF_INET, SOCK_STREAM,
                         IPPROTO_TCP, buffered = false)
  var client: Socket
  try:
    server.accept(client)
    var contentLength = 0
    discard client.recvLine(timeout = 5000)
    while true:
      let line = client.recvLine(timeout = 5000)
      if line.len == 0 or line == "\r\n": break
      if line.toLowerAscii.startsWith("content-length:"):
        contentLength = parseInt(line.split(':', 1)[1].strip)
    if contentLength > 0:
      discard client.recv(contentLength, timeout = 5000)
    {.cast(gcsafe).}:
      inc gHits
    client.send("HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\n" &
                "Content-Length: " & $ErrorBody.len & "\r\nConnection: close\r\n\r\n" &
                ErrorBody)
    client.close()
  except CatchableError:
    discard
  server.close()

proc startServer(): int =
  let listener = newSocket(buffered = false)
  listener.setSockOpt(OptReuseAddr, true)
  listener.bindAddr(Port(0), "127.0.0.1")
  listener.listen()
  result = int(listener.getLocalAddr()[1])
  createThread(gServerThread, serveOnce, int(listener.getFd()))

proc runTests*() =
  suite "provider transport: final 5xx response":
    test "a 503 keeps the provider name, the status and the body":
      let port = startServer()
      let res = postProvider(HttpRuntimePort(), "OpenRouter",
                             "http://127.0.0.1:" & $port & "/v1/chat/completions",
                             "{}", @[("Content-Type", "application/json")])
      joinThread(gServerThread)
      check res.isErr
      check res.error.startsWith("OpenRouter API error 503")
      check "upstream overloaded" in res.error
      check gHits == 1

when isMainModule:
  runTests()
