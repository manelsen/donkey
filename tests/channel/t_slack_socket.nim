## Slack Socket Mode envelope routing (no network).

import std/[json, os, unittest]
import donkey/adapters/channel/slack
import donkey/adapters/channel/slack_socket

const SocketTmp = "/tmp/donkey_slack_socket_tests"

let socketSlack = newSlackAdapter("tok", SocketTmp / "identity.tsv")

proc drainAll(sl: SlackAdapter) =
  while sl.tryRecvEvent()[0]:
    discard

suite "Slack Socket Mode envelopes":

  test "events_api envelope enqueues a message":
    socketSlack.openQueue()
    drainAll(socketSlack)

    let envelope = %* {
      "type": "events_api",
      "envelope_id": "e1",
      "payload": {
        "type": "event_callback",
        "team_id": "T1",
        "event_id": "Ev1",
        "event": {
          "type": "message",
          "user": "U1",
          "text": "hello socket",
          "channel": "C1",
          "ts": "1.1",
        },
      },
    }
    check handleSlackSocketEnvelope(envelope)

    let (hasEvent, event) = socketSlack.tryRecvEvent()
    check hasEvent
    check event.kind == srMessage
    check event.slackUserId == "U1"
    check event.text == "hello socket"
    check event.channelId == "C1"
    check event.eventId == "Ev1"

  test "slash_commands envelope is normalized":
    drainAll(socketSlack)

    let envelope = %* {
      "type": "slash_commands",
      "envelope_id": "e2",
      "payload": {
        "user_id": "U2",
        "command": "/models",
        "text": "openrouter",
        "channel_id": "C2",
        "team_id": "T2",
        "response_url": "https://hooks.slack.com/rsp",
        "trigger_id": "tr1",
      },
    }
    check handleSlackSocketEnvelope(envelope)

    let (hasEvent, event) = socketSlack.tryRecvEvent()
    check hasEvent
    check event.kind == srSlashCommand
    check event.slackUserId == "U2"
    check event.text == "/models openrouter"
    check event.responseUrl == "https://hooks.slack.com/rsp"
    check event.triggerId == "tr1"

  test "interactive envelope routes block actions":
    drainAll(socketSlack)

    let envelope = %* {
      "type": "interactive",
      "envelope_id": "e3",
      "payload": {
        "type": "block_actions",
        "user": {"id": "U3"},
        "actions": [{"action_id": "approval:abcdefgh:allow"}],
        "channel": {"id": "C3"},
        "team_id": "T3",
        "response_url": "https://hooks.slack.com/act",
        "trigger_id": "tr2",
      },
    }
    check handleSlackSocketEnvelope(envelope)

    let (hasEvent, event) = socketSlack.tryRecvEvent()
    check hasEvent
    check event.kind == srBlockAction
    check event.slackUserId == "U3"
    check event.text == "approval:abcdefgh:allow"
    check event.channelId == "C3"

  test "disconnect asks the reader to reconnect":
    check not handleSlackSocketEnvelope(%* {
      "type": "disconnect",
      "reason": "refresh_requested",
    })

  test "hello and unknown envelopes are ignored":
    drainAll(socketSlack)
    check handleSlackSocketEnvelope(%* {"type": "hello"})
    check handleSlackSocketEnvelope(%* {"type": "unknown"})
    check not socketSlack.tryRecvEvent()[0]
