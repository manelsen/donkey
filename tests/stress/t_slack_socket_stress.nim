## Stress: Slack Socket Mode envelopes and raw WebSocket frame parsing.

import std/[json, net, os, posix, strutils, unittest]
import results
import donkey/adapters/channel/slack
import donkey/adapters/channel/slack_socket
import donkey/adapters/channel/ws_client

let stressDir = getTempDir() / ("donkey_stress_slack_" & $getCurrentProcessId())
let slackStress = newSlackAdapter("tok", stressDir / "identity.tsv")
slackStress.openQueue()

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

  test "events_api, slash_commands and object interactive enqueue":
    drainAll(slackStress)

    check handleSlackSocketEnvelope(%* {
      "type": "events_api", "envelope_id": "ea1",
      "payload": {
        "type": "event_callback", "team_id": "T1", "event_id": "Ev1",
        "event": {
          "type": "message", "user": "U1", "text": "socket message",
          "channel": "C1", "ts": "1.1",
        },
      },
    })
    let (hasMessage, messageEvent) = slackStress.tryRecvEvent()
    check hasMessage
    check messageEvent.kind == srMessage
    check messageEvent.text == "socket message"
    check messageEvent.eventId == "Ev1"

    check handleSlackSocketEnvelope(%* {
      "type": "slash_commands", "envelope_id": "ea2",
      "payload": {
        "user_id": "U2", "command": "/models", "text": "openrouter",
        "channel_id": "C2", "team_id": "T2",
        "response_url": "https://hooks.slack.com/rsp", "trigger_id": "tr1",
      },
    })
    let (hasSlash, slashEvent) = slackStress.tryRecvEvent()
    check hasSlash
    check slashEvent.kind == srSlashCommand
    check slashEvent.text == "/models openrouter"

    check handleSlackSocketEnvelope(%* {
      "type": "interactive", "envelope_id": "ea3",
      "payload": {
        "type": "block_actions", "user": {"id": "U3"},
        "actions": [{"action_id": "object-action"}],
        "channel": {"id": "C3"}, "team_id": "T3",
      },
    })
    let (hasAction, actionEvent) = slackStress.tryRecvEvent()
    check hasAction
    check actionEvent.kind == srBlockAction
    check actionEvent.text == "object-action"

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

    let payload = repeat("x", 126)
    writeAll(peer, "\x81\x7e\x00\x7e" & payload)
    let frame = ws.recvFrame(100)
    check frame.opcode == WsOpcodeText
    check frame.data == payload

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
