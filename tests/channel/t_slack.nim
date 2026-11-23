## SlackAdapter unit tests.
## HTTP calls are not made; tests cover adapter construction, identity
## resolution, event queue routing, and parseChallenge via slack_pure.

import std/[json, options, os, unittest]
import donkey/adapters/channel/slack
import donkey/adapters/identity/identity_resolver
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/slack_pure

# ── IdentityResolver (Slack) ───────────────────────────────────────────────────

proc runTests*() =
  suite "IdentityResolver (Slack)":

    test "creates new UUID for unknown slack user":
      let path = getTempDir() / "donkey_test_ids_slack.tsv"
      removeFile(path)
      defer: removeFile(path)
      let r   = newIdentityResolver(path)
      let uid = r.resolve(ckSlack, "U123456")
      check ($uid).len == 36

    test "same slack id returns same UserId":
      let path = getTempDir() / "donkey_test_ids_slack2.tsv"
      removeFile(path)
      defer: removeFile(path)
      let r  = newIdentityResolver(path)
      let u1 = r.resolve(ckSlack, "U999")
      let u2 = r.resolve(ckSlack, "U999")
      check u1 == u2

    test "different slack ids get different UserIds":
      let path = getTempDir() / "donkey_test_ids_slack3.tsv"
      removeFile(path)
      defer: removeFile(path)
      let r  = newIdentityResolver(path)
      let u1 = r.resolve(ckSlack, "Uaaa")
      let u2 = r.resolve(ckSlack, "Ubbb")
      check u1 != u2

    test "identity persists across resolver instances":
      let path = getTempDir() / "donkey_test_ids_slack4.tsv"
      removeFile(path)
      defer: removeFile(path)
      let uid1 = newIdentityResolver(path).resolve(ckSlack, "Uccc")
      let uid2 = newIdentityResolver(path).resolve(ckSlack, "Uccc")
      check uid1 == uid2

    test "generated id looks like a UUID":
      let path = getTempDir() / "donkey_test_ids_slack5.tsv"
      removeFile(path)
      defer: removeFile(path)
      let uid = $newIdentityResolver(path).resolve(ckSlack, "U777")
      check uid.len == 36
      check uid[8]  == '-'
      check uid[13] == '-'
      check uid[18] == '-'
      check uid[23] == '-'

    test "lookup and resolve reload mappings written by another process":
      let path = getTempDir() / "donkey_test_ids_slack6.tsv"
      removeFile(path)
      defer: removeFile(path)
      let staleLookup = newIdentityResolver(path)   ## loaded before the write
      let staleResolve = newIdentityResolver(path)  ## loaded before the write
      let writer = newIdentityResolver(path)
      let uid = writer.resolve(ckSlack, "U-new")

      check staleLookup.lookup(ckSlack, "U-new").get == uid
      check staleResolve.resolve(ckSlack, "U-new") == uid  ## no new UUID minted

  # ── SlackAdapter construction ──────────────────────────────────────────────────

  suite "SlackAdapter construction":

    test "botToken is stored":
      let a = newSlackAdapter("xoxb-MY-TOKEN", "/tmp/ids_sl.tsv",
                              apiBase = "https://mock.local")
      check a.botToken == "xoxb-MY-TOKEN"

    test "apiBase override is stored":
      let a = newSlackAdapter("xoxb-TOK", "/tmp/ids_sl2.tsv",
                              apiBase = "https://test.api")
      check a.apiBase == "https://test.api"

    test "default apiBase is empty string":
      let a = newSlackAdapter("xoxb-TOK2", "/tmp/ids_sl3.tsv")
      check a.apiBase == ""

  # ── parseChallenge ─────────────────────────────────────────────────────────────

  suite "parseChallenge":

    test "url_verification returns challenge value":
      let payload = %* {"type": "url_verification", "challenge": "abc123"}
      check parseChallenge(payload) == "abc123"

    test "event_callback returns empty string":
      let payload = %* {
        "type":    "event_callback",
        "team_id": "T1",
        "event":   {"type": "message", "user": "U1", "text": "hi", "channel": "C1", "ts": "123"},
      }
      check parseChallenge(payload) == ""

    test "nil payload returns empty string":
      let payload = newJNull()
      check parseChallenge(payload) == ""

    test "slash_command payload returns empty string":
      let payload = %* {
        "type":         "slash_command",
        "user_id":      "U1",
        "command":      "/help",
        "text":         "",
        "channel_id":   "C1",
        "team_id":      "T1",
        "response_url": "https://hooks.slack.com/...",
        "trigger_id":   "tr1",
      }
      check parseChallenge(payload) == ""

  # ── pushEvent and slack_pure routing ──────────────────────────────────────────

  suite "slack_pure.parseEvent routing (used by pushEvent)":

    test "url_verification produces sekVerification":
      let r = parseEvent(%* {"type": "url_verification", "challenge": "xyz"})
      check r.kind      == sekVerification
      check r.challenge == "xyz"

    test "event_callback message produces sekMessage":
      let payload = %* {
        "type":    "event_callback",
        "team_id": "T1",
        "event": {
          "type":    "message",
          "user":    "U1",
          "text":    "hello",
          "channel": "C1",
          "ts":      "1000.0001",
        },
      }
      let r = parseEvent(payload)
      check r.kind      == sekMessage
      check r.rawId     == "U1"
      check r.text      == "hello"
      check r.channelId == "C1"
      check r.teamId    == "T1"

    test "bot message is filtered to sekUnknown":
      let payload = %* {
        "type":    "event_callback",
        "team_id": "T1",
        "event": {
          "type":    "message",
          "user":    "U2",
          "bot_id":  "B1",
          "text":    "I am a bot",
          "channel": "C1",
          "ts":      "1000.0002",
        },
      }
      let r = parseEvent(payload)
      check r.kind == sekUnknown

    test "app_mention produces sekMessage":
      let payload = %* {
        "type":    "event_callback",
        "team_id": "T1",
        "event": {
          "type":    "app_mention",
          "user":    "U3",
          "text":    "<@BAPP> help",
          "channel": "C2",
          "ts":      "1000.0003",
        },
      }
      let r = parseEvent(payload)
      check r.kind  == sekMessage
      check r.rawId == "U3"

    test "slash_command produces sekSlashCommand":
      let payload = %* {
        "type":         "slash_command",
        "user_id":      "U4",
        "command":      "/help",
        "text":         "",
        "channel_id":   "C3",
        "team_id":      "T2",
        "response_url": "https://hooks.slack.com/rsp",
        "trigger_id":   "tr1",
      }
      let r = parseEvent(payload)
      check r.kind        == sekSlashCommand
      check r.rawId       == "U4"
      check r.text        == "/help"
      check r.responseUrl == "https://hooks.slack.com/rsp"
      check r.triggerId   == "tr1"

    test "slash_command with args concatenates command and text":
      let payload = %* {
        "type":         "slash_command",
        "user_id":      "U5",
        "command":      "/models",
        "text":         "openrouter",
        "channel_id":   "C3",
        "team_id":      "T2",
        "response_url": "",
        "trigger_id":   "tr2",
      }
      let r = parseEvent(payload)
      check r.kind == sekSlashCommand
      check r.text == "/models openrouter"

    test "block_actions produces sekBlockAction":
      let payload = %* {
        "type":         "block_actions",
        "user":         {"id": "U6"},
        "actions":      [{"action_id": "btn_ok", "value": "confirm"}],
        "channel":      {"id": "C4"},
        "team_id":      "T3",
        "response_url": "https://hooks.slack.com/act",
        "trigger_id":   "tr3",
      }
      let r = parseEvent(payload)
      check r.kind        == sekBlockAction
      check r.rawId       == "U6"
      check r.text        == "btn_ok:confirm"
      check r.channelId   == "C4"
      check r.responseUrl == "https://hooks.slack.com/act"

    test "unknown type produces sekUnknown":
      let r = parseEvent(%* {"type": "reaction_added"})
      check r.kind == sekUnknown

    test "nil payload produces sekUnknown":
      let r = parseEvent(newJNull())
      check r.kind == sekUnknown

  # ── toInbound ──────────────────────────────────────────────────────────────────

  suite "slack_pure.toInbound":

    test "converts message result to InboundMessage":
      let payload = %* {
        "type":    "event_callback",
        "team_id": "T1",
        "event": {
          "type":    "message",
          "user":    "U1",
          "text":    "hello world",
          "channel": "C1",
          "ts":      "1234.5678",
        },
      }
      let r      = parseEvent(payload)
      let userId = UserId("test-uuid-0000")
      let msg    = r.toInbound(userId)
      check msg.userId  == userId
      check msg.channel == ckSlack
      check msg.text    == "hello world"

    test "isVerification is false for message":
      let payload = %* {
        "type":    "event_callback",
        "team_id": "T1",
        "event": {
          "type":    "message",
          "user":    "U1",
          "text":    "hi",
          "channel": "C1",
          "ts":      "1.0",
        },
      }
      let r = parseEvent(payload)
      check not r.isVerification

    test "isVerification is true for url_verification":
      let r = parseEvent(%* {"type": "url_verification", "challenge": "ch"})
      check r.isVerification

  suite "SlackAdapter event deduplication":

    test "same event id is rejected after the first sight":
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_dedupe1.tsv")
      let event = SlackRawEvent(eventId: "Ev123", slackUserId: "U1", text: "hi")
      check not a.isDuplicate(event, now = 1000.0)
      check a.isDuplicate(event, now = 1001.0)

    test "different event ids are accepted":
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_dedupe2.tsv")
      check not a.isDuplicate(SlackRawEvent(eventId: "Ev1"), now = 1000.0)
      check not a.isDuplicate(SlackRawEvent(eventId: "Ev2"), now = 1000.0)

    test "expired events are accepted again":
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_dedupe3.tsv")
      let event = SlackRawEvent(eventId: "Ev123")
      check not a.isDuplicate(event, now = 1000.0)
      check not a.isDuplicate(event, now = 1000.0 + SlackDedupeTtlSec + 1.0)

    test "trigger id deduplicates interactive payloads":
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_dedupe4.tsv")
      let event = SlackRawEvent(triggerId: "T1", text: "models")
      check not a.isDuplicate(event, now = 1000.0)
      check a.isDuplicate(event, now = 1000.0)

    test "a mention delivered as message and as app_mention is one turn (hermes 708f84c477)":
      ## Both events describe the same message (same channel and ts) under
      ## different event ids; answering both posted the reply twice.
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_dedupe6.tsv")
      let asMessage = SlackRawEvent(kind: srMessage, eventId: "EvA",
                                    channelId: "C1", eventTs: "1700.0001")
      let asMention = SlackRawEvent(kind: srMessage, eventId: "EvB",
                                    channelId: "C1", eventTs: "1700.0001")
      check not a.isDuplicate(asMessage, now = 1000.0)
      check a.isDuplicate(asMention, now = 1000.5)

    test "the real message and app_mention payloads of one mention dedupe":
      ## Through `pushEvent`, so the app_mention payload really is parsed as
      ## the same kind as the message one.
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_dedupe8.tsv")
      while a.tryRecvEvent()[0]: discard
      for (evType, evId) in [("message", "EvM"), ("app_mention", "EvN")]:
        pushEvent(%* {"type": "event_callback", "team_id": "T1", "event_id": evId,
          "event": {"type": evType, "user": "U1", "text": "<@B1> hi",
                    "channel": "C1", "ts": "1700.0002"}})
      let (gotFirst, first) = a.tryRecvEvent()
      let (gotSecond, second) = a.tryRecvEvent()
      check gotFirst and gotSecond
      check first.kind == srMessage and second.kind == srMessage
      check not a.isDuplicate(first, now = 1000.0)
      check a.isDuplicate(second, now = 1000.0)

    test "the same ts in another channel is another message":
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_dedupe7.tsv")
      check not a.isDuplicate(SlackRawEvent(kind: srMessage, eventId: "E1",
        channelId: "C1", eventTs: "1700.0001"), now = 1000.0)
      check not a.isDuplicate(SlackRawEvent(kind: srMessage, eventId: "E2",
        channelId: "C2", eventTs: "1700.0001"), now = 1000.0)

    test "events without ids are never deduplicated":
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_dedupe5.tsv")
      let event = SlackRawEvent(text: "hello")
      check not a.isDuplicate(event, now = 1000.0)
      check not a.isDuplicate(event, now = 1000.0)

  suite "SlackAdapter response_url":

    test "rejects empty and non-https response URLs":
      let a = newSlackAdapter("token", getTempDir() / "donkey_slack_resp.tsv")
      check a.respondToUrl("", "hi").isErr
      check a.respondToUrl("http://insecure.example", "hi").isErr

when isMainModule:
  runTests()
