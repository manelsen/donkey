## Stress: Slack Socket Mode envelopes and raw WebSocket frame parsing.

import std/[json, net, os, posix, strutils, unittest]
import results
import donkey/adapters/channel/slack
import donkey/adapters/channel/slack_socket
import donkey/adapters/channel/ws_client

const StressDir = "/tmp/donkey_stress_slack"
let slackStress = newSlackAdapter("tok", StressDir / "identity.tsv")

proc makePair(): tuple[ws: WsClient, peer: cint] =
  var fds: array[2, cint]
  doAssert posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, fds) == 0
  let sock = newSocket(SocketHandle(fds[0]), domain = AF_UNIX,
                       sockType = SOCK_STREAM, protocol = IPPROTO_NONE,
                       buffered = false)
  (WsClient(sock: sock), cint(fds[1]))

proc writeAll(fd: cint; data: string) =
  var pos = 0
  while pos < data.len:
    let n = posix.write(fd, unsafeAddr data[pos], data.len - pos)
    if n <= 0:
      break
    pos += n

proc drainAll(sl: SlackAdapter) =
  while sl.tryRecvEvent()[0]:
    discard

suite "Slack Socket Mode stress":

  test "malformed and unknown envelopes do not raise":
    slackStress.openQueue()
    drainAll(slackStress)

    let envelopes = @[
      newJNull(),
      %*[],
      %"string-envelope",
      %*{},
      %*{"type": "events_api"},
      %*{"type": "events_api", "payload": "not-an-object"},
      %*{"type": "slash_commands", "payload": %*{}},
      %*{"type": "interactive", "payload": "not-json"},
      %*{"type": "interactive", "payload": newJNull()},
      %*{"type": "unknown", "envelope_id": "e"},
      %*{"type": "hello"},
    ]
    for envelope in envelopes:
      check handleSlackSocketEnvelope(envelope)
    check not slackStress.tryRecvEvent()[0]

  test "disconnect asks for reconnect":
    check not handleSlackSocketEnvelope(%* {
      "type": "disconnect", "reason": "refresh_requested"})

  test "interactive payload as a JSON string is accepted":
    drainAll(slackStress)
    let payload = $ %* {
      "type": "block_actions",
      "user": {"id": "U9"},
      "actions": [{"action_id": "stress-action"}],
      "channel": {"id": "C9"},
    }
    check handleSlackSocketEnvelope(%* {
      "type": "interactive", "envelope_id": "e9", "payload": payload})
    let (hasEvent, event) = slackStress.tryRecvEvent()
    check hasEvent
    check event.kind == srBlockAction
    check event.slackUserId == "U9"
    check event.text == "stress-action"

  test "valid WebSocket text and ping frames parse":
    let (ws, peer) = makePair()
    defer:
      try: ws.sock.close() except CatchableError: discard
      discard posix.close(peer)

    writeAll(peer, "\x81\x05hello")
    let text = ws.recvFrame(100)
    check text.opcode == WsOpcodeText
    check text.data == "hello"

    writeAll(peer, "\x89\x00")
    let ping = ws.recvFrame(100)
    check ping.opcode == WsOpcodePing
    check ping.data.len == 0

  test "extended-length frames parse":
    let (ws, peer) = makePair()
    defer:
      try: ws.sock.close() except CatchableError: discard
      discard posix.close(peer)

    writeAll(peer, "\x81\x7e\x00\x05hello")
    let frame = ws.recvFrame(100)
    check frame.opcode == WsOpcodeText
    check frame.data == "hello"

  test "a truncated frame raises protocol error, not idle timeout":
    let (ws, peer) = makePair()
    defer:
      try: ws.sock.close() except CatchableError: discard
      discard posix.close(peer)

    writeAll(peer, "\x81\x05he")  # header promises 5 bytes, only 2 arrive
    var raisedIo = false
    try:
      discard ws.recvFrame(100, 100)
    except TimeoutError:
      check false
    except IOError:
      raisedIo = true
    check raisedIo
