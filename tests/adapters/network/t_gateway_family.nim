## The Discord-family gateway protocol (Discord, QQ official): hello and the
## first heartbeat, identify or resume, heartbeats and dead links, opcodes
## 1/7/9/11 and close codes. A loopback socket pair stands in for the
## gateway: what the client sends is read back on the server side.

import std/[json, net, strutils, unittest]
import donkey/adapters/network/gateway_family
import donkey/adapters/network/persistent_socket
import donkey/adapters/channel/ws_client
import donkey/core/log
import donkey/core/pipeops
import donkey/domain/channels/discord_pure

type Pair = object
  listener, server: Socket
  ws: WsClient

proc pair(): Pair =
  result.listener = newSocket()
  result.listener.setSockOpt(OptReuseAddr, true)
  result.listener.bindAddr(Port(0), "127.0.0.1")
  result.listener.listen()
  let client = newSocket(buffered = false)
  client.connect("127.0.0.1", result.listener.getLocalAddr()[1])
  result.listener.accept(result.server)
  result.ws = WsClient(sock: client)

proc close(p: Pair) =
  p.ws.sock.close()
  p.server.close()
  p.listener.close()

proc serverSends(p: Pair; data: string; opcode = 0x1) =
  var frame = ""
  frame.add char(0x80 or opcode)
  if data.len < 126:
    frame.add char(data.len)
  else:
    frame.add char(126)
    frame.add char(data.len shr 8)
    frame.add char(data.len and 0xFF)
  frame.add data
  p.server.send(frame)

proc serverReads(p: Pair): JsonNode =
  ## One masked text frame from the client, decoded.
  let head = p.server.recv(2, timeout = 2000)
  var length = ord(head[1]) and 0x7F
  if length == 126:
    let ext = p.server.recv(2, timeout = 2000)
    length = (ord(ext[0]) shl 8) or ord(ext[1])
  let mask = p.server.recv(4, timeout = 2000)
  var payload = p.server.recv(length, timeout = 2000)
  for i in 0 ..< payload.len:
    payload[i] = char(ord(payload[i]) xor ord(mask[i mod 4]))
  parseJson(payload)

let tlog = newLogger("test.gateway_family", lvlError)

proc frameOf(data: string; opcode = WsOpcodeText): WsFrame =
  WsFrame(opcode: opcode, data: data)

proc runTests*() =
  suite "Discord-family gateway":

    test "hello sets the interval and schedules the first beat within the jitter":
      for _ in 0 ..< 20:
        var p = pair()
        var state = FamilyState()
        p.serverSends($ %* {"op": 10, "d": {"heartbeat_interval": 41250}})
        check familyHello(p.ws, state, nowMs = 100_000, jitterCapMs = 3000).isOk
        check state.heartbeatMs == 41250
        check not state.awaitingAck
        ## Due within the cap: no sleep on the connection thread.
        check heartbeatStep(100_000 + 3000, state.lastBeatMs, state.heartbeatMs, false) == hbSend
        p.close()

    test "without a jitter cap the first beat is due at once":
      var p = pair()
      defer: p.close()
      var state = FamilyState()
      p.serverSends($ %* {"op": 10, "d": {"heartbeat_interval": 45000}})
      check familyHello(p.ws, state, nowMs = 5_000, jitterCapMs = 0).isOk
      check heartbeatStep(5_000, state.lastBeatMs, state.heartbeatMs, false) == hbSend

    test "the gateways wait at least 1 s before identifying again (op 9)":
      ## Discord and QQ ask for 1-5 s; the socket's shortest pause gives it.
      check defaultSocketPolicy().reconnectMinMs >= 1_000

    test "a fresh session identifies; a known one resumes from its sequence":
      var p = pair()
      defer: p.close()
      var state = FamilyState()
      familyIdentify(p.ws, state, %* {"token": "t"}, resumeToken = "t")
      let identify = p.serverReads()
      check identify["op"].getInt == 2
      state.sessionId = "s1"
      state.lastSeq = 42
      familyIdentify(p.ws, state, %* {"token": "t"}, resumeToken = "t")
      let resume = p.serverReads()
      check resume["op"].getInt == 6
      check resume["d"]["session_id"].getStr == "s1"
      check resume["d"]["seq"].getInt == 42

    test "a due heartbeat is sent with the last sequence; an unacked one is a dead link":
      var p = pair()
      defer: p.close()
      var state = FamilyState(heartbeatMs: 1000, lastBeatMs: 0, lastSeq: 7)
      check familyTick(p.ws, state, nowMs = 1500, tlog, "test") == ssKeep
      let beat = p.serverReads()
      check beat["op"].getInt == 1
      check beat["d"].getInt == 7
      check state.awaitingAck
      check familyTick(p.ws, state, nowMs = 2600, tlog, "test") == ssReconnect

    test "READY keeps the session; dispatches carry their sequence":
      var p = pair()
      defer: p.close()
      var state = FamilyState()
      let ready = familyFrame(p.ws, state, frameOf($ %* {"op": 0, "s": 1, "t": "READY",
        "d": {"session_id": "abc", "resume_gateway_url": "wss://resume.example"}}),
        closeAction, tlog, "test")
      check ready.kind == fkReady
      check state.sessionId == "abc"
      check state.resumeUrl == "wss://resume.example"
      let msg = familyFrame(p.ws, state, frameOf($ %* {"op": 0, "s": 5, "t": "MESSAGE_CREATE",
        "d": {"content": "oi"}}), closeAction, tlog, "test")
      check msg.kind == fkDispatch
      check msg.name == "MESSAGE_CREATE"
      check msg.data["content"].getStr == "oi"
      check state.lastSeq == 5

    test "op 11 acknowledges; op 1 asks for a beat now":
      var p = pair()
      defer: p.close()
      var state = FamilyState(awaitingAck: true, lastSeq: 3)
      check familyFrame(p.ws, state, frameOf("""{"op":11}"""), closeAction, tlog, "t").kind == fkNone
      check not state.awaitingAck
      check familyFrame(p.ws, state, frameOf("""{"op":1}"""), closeAction, tlog, "t").kind == fkNone
      check p.serverReads()["op"].getInt == 1

    test "op 7 reconnects and resumes; op 9 without resume drops the session":
      var p = pair()
      defer: p.close()
      var state = FamilyState(sessionId: "s", lastSeq: 9, resumeUrl: "wss://r")
      let seven = familyFrame(p.ws, state, frameOf("""{"op":7}"""), closeAction, tlog, "t")
      check seven.kind == fkStep and seven.step == ssReconnect
      check state.sessionId == "s"
      let nine = familyFrame(p.ws, state, frameOf("""{"op":9,"d":false}"""), closeAction, tlog, "t")
      check nine.kind == fkStep and nine.step == ssReconnect
      check state.sessionId == "" and state.lastSeq == 0 and state.resumeUrl == ""

    test "close codes: a bad token stops, a lost session starts over, others resume":
      var p = pair()
      defer: p.close()
      var state = FamilyState(sessionId: "s", lastSeq: 9)
      let fatal = familyFrame(p.ws, state, frameOf("\x0F\xA4", WsOpcodeClose), closeAction, tlog, "t")
      check fatal.kind == fkStep and fatal.step == ssStop
      let lost = familyFrame(p.ws, state, frameOf("\x0F\xA7", WsOpcodeClose), closeAction, tlog, "t")
      check lost.step == ssReconnect and state.sessionId == ""
      state.sessionId = "s2"
      let drop = familyFrame(p.ws, state, frameOf("\x03\xE8", WsOpcodeClose), closeAction, tlog, "t")
      check drop.step == ssReconnect and state.sessionId == "s2"

when isMainModule:
  runTests()
