## Embedded webhook listeners (QQ OneBot, WeChat, WeCom) must reject hostile
## requests instead of allocating unbounded memory or blocking forever.
## Each test drives the real connection handler over a loopback socket.

import std/[monotimes, net, strutils, times, unittest]
import donkey/core/log
import donkey/adapters/channel/qq
import donkey/adapters/channel/wechat
import donkey/adapters/channel/wecom

type ConnHandler = proc(client: Socket) {.closure.}

proc exchange(raw: string; handler: ConnHandler): string =
  ## Sends `raw` from a loopback client, runs `handler` on the accepted
  ## server socket (which closes it) and returns whatever the client received.
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
  handler(conn)
  while true:
    let chunk = try: client.recv(4096, timeout = 2000) except CatchableError: ""
    if chunk.len == 0: break
    result.add(chunk)

const hugeBody = "POST /?signature=x&timestamp=1&nonce=2 HTTP/1.1\r\n" &
                 "Content-Length: 99999999999\r\n\r\n"
const badLength = "POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n"

proc runTests*() =
  let logger = newLogger("test.embedded_webhooks")
  let handlers: seq[(string, ConnHandler)] = @[
    ("qq", proc(c: Socket) {.closure.} =
             handleQQOneBotConn(c, logger, timeoutSec = 1)),
    ("wechat", proc(c: Socket) {.closure.} =
                 handleWeChatConn(c, "tok", logger, timeoutSec = 1)),
    ("wecom", proc(c: Socket) {.closure.} =
                handleWeComConn(c, "tok", logger, timeoutSec = 1)),
  ]

  suite "embedded webhook listeners":

    for (name, h) in handlers:
      let handler = h

      test name & ": huge Content-Length → 413, no allocation":
        check exchange(hugeBody, handler).startsWith("HTTP/1.1 413")

      test name & ": malformed Content-Length → 400":
        check exchange(badLength, handler).startsWith("HTTP/1.1 400")

      test name & ": silent client times out instead of pinning the thread":
        let t0 = getMonoTime()
        discard exchange("", handler)
        check (getMonoTime() - t0) < initDuration(seconds = 5)

  suite "wecom signature enforcement":

    let wecomHandler: ConnHandler = proc(c: Socket) {.closure.} =
      handleWeComConn(c, "tok", logger, timeoutSec = 1)

    test "POST without msg_signature is rejected (no forged messages)":
      let body = "<xml><MsgType>text</MsgType><Content>hi</Content></xml>"
      let raw = "POST /?timestamp=1&nonce=2 HTTP/1.1\r\nContent-Length: " &
                $body.len & "\r\n\r\n" & body
      check exchange(raw, wecomHandler).startsWith("HTTP/1.1 403")

    test "GET verification without msg_signature is rejected":
      check exchange("GET /?timestamp=1&nonce=2&echostr=e HTTP/1.1\r\n\r\n",
                     wecomHandler).startsWith("HTTP/1.1 403")

    test "GET verification with valid signature echoes echostr":
      let sig = wecomSignature("tok", "1", "2")
      let resp = exchange("GET /?msg_signature=" & sig &
                          "&timestamp=1&nonce=2&echostr=hello HTTP/1.1\r\n\r\n",
                          wecomHandler)
      check resp.startsWith("HTTP/1.1 200")
      check resp.endsWith("hello")

when isMainModule:
  runTests()
