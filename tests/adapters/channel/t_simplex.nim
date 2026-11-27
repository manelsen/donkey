## SimpleX as a channel (E13.2): the connection thread against a fake
## simplex-chat WebSocket server, and the daemon's side of sending.

import std/[json, net, os, strutils, unittest]
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/infra/connection_state
import donkey/adapters/channel/simplex

proc waitFor(cond: proc(): bool; ms = 5_000): bool =
  var waited = 0
  while waited < ms:
    if cond(): return true
    sleep(20)
    waited += 20
  cond()

proc serverFrame(data: string): string =
  ## Unmasked text frame, any length a test needs.
  result.add char(0x81)
  if data.len < 126:
    result.add char(data.len)
  else:
    result.add char(126)
    result.add char((data.len shr 8) and 0xFF)
    result.add char(data.len and 0xFF)
  result.add data

proc readClientFrame(client: Socket): string =
  let head = client.recv(2, timeout = 3000)
  if head.len < 2: return ""
  var length = ord(head[1]) and 0x7F
  if length == 126:
    let ext = client.recv(2, timeout = 3000)
    length = (ord(ext[0]) shl 8) or ord(ext[1])
  let mask = client.recv(4, timeout = 3000)
  result = if length > 0: client.recv(length, timeout = 3000) else: ""
  for i in 0 ..< result.len:
    result[i] = char(ord(result[i]) xor ord(mask[i mod 4]))

const Incoming = """{"resp":{"type":"newChatItems","chatItems":[{"chatInfo":{"type":"direct","contact":{"contactId":5,"localDisplayName":"ana"}},"chatItem":{"chatDir":{"type":"directRcv"},"meta":{"itemId":41},"content":{"type":"rcvMsgContent","msgContent":{"type":"text","text":"oi, Donkey"}}}}]}}"""

proc runTests*() =
  suite "simplex adapter":
    test "connects, hands over a direct message and sends the answer":
      while tryRecvSimplex()[0]: discard
      while tryTakeSimplexOut()[0]: discard
      var server = newSocket()
      server.setSockOpt(OptReuseAddr, true)
      server.bindAddr(Port(0), "127.0.0.1")
      server.listen()
      let port = int(server.getLocalAddr()[1])
      check startSimplex(SimplexSettings(host: "127.0.0.1", port: port),
                         newLogger("test.simplex", lvlError)).isOk
      var client: Socket
      server.accept(client)
      while true:
        let line = client.recvLine(timeout = 3000)
        if line.len == 0 or line == "\r\n": break
      client.send("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n" &
                  "Connection: Upgrade\r\nSec-WebSocket-Accept: x\r\n\r\n")
      check waitFor(proc(): bool = connectionCounts(ckSimplex) == (running: 1, connected: 1))
      client.send(serverFrame(Incoming))
      var got: SimplexInbound
      check waitFor(proc(): bool =
        let (has, m) = tryRecvSimplex()
        if has: got = m
        has)
      check got.contactId == 5 and got.text == "oi, Donkey" and got.itemId == "41"
      let a = newSimplexAdapter("ws://127.0.0.1:" & $port, getTempDir() / "donkey_simplex_ids.tsv")
      check a.send(OutboundMessage(userId: UserId("u"), channel: ckSimplex, text: "olá, Ana",
                                   replyTo: "5")).isOk
      let sent = parseJson(readClientFrame(client))
      check sent["cmd"].getStr.startsWith("/_send @5 json ")
      check "olá, Ana" in sent["cmd"].getStr
      stopSimplex()
      client.close()
      server.close()

    test "a file becomes a note; no contact, no send; a remote URL is refused":
      while tryTakeSimplexOut()[0]: discard
      let a = newSimplexAdapter("", getTempDir() / "donkey_simplex_ids2.tsv")
      check a.send(OutboundMessage(userId: UserId("u"), channel: ckSimplex, text: "segue",
                                   mediaUrl: "/p/a.pdf", replyTo: "7")).isOk
      let (has, outgoing) = tryTakeSimplexOut()
      check has and outgoing.contactId == 7 and "não pôde ser enviado" in outgoing.text and "/p/a.pdf" notin outgoing.text
      check a.send(OutboundMessage(userId: UserId("nobody"), channel: ckSimplex, text: "x")).isErr
      check newSimplexAdapter("ws://10.1.1.1:5225", "").configError.len > 0

when isMainModule:
  runTests()
