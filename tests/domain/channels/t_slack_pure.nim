## Tests for domain/channels/slack_pure.nim — pure Slack Events API parser.
## No I/O or HTTP; all input is constructed directly as JsonNode.

import std/[json, unittest]
import donkey/domain/channels/slack_pure
import donkey/core/types

# ── Fixtures ──────────────────────────────────────────────────────────────────

func makeEventCallback(teamId: string; event: JsonNode): JsonNode =
  %* {
    "type":     "event_callback",
    "team_id":  teamId,
    "event":    event,
  }

func makeMessageEvent(userId, channel, text, ts: string;
                      botId = ""; subtype = ""): JsonNode =
  var n = %* {
    "type":    "message",
    "user":    userId,
    "channel": channel,
    "text":    text,
    "ts":      ts,
  }
  if botId.len > 0:   n["bot_id"]  = %botId
  if subtype.len > 0: n["subtype"] = %subtype
  n

func makeAppMentionEvent(userId, channel, text, ts: string): JsonNode =
  %* {
    "type":    "app_mention",
    "user":    userId,
    "channel": channel,
    "text":    text,
    "ts":      ts,
  }

func makeSlashCommand(userId, command, args, channelId, teamId,
                      responseUrl, triggerId: string): JsonNode =
  %* {
    "type":         "slash_command",
    "user_id":      userId,
    "command":      command,
    "text":         args,
    "channel_id":   channelId,
    "team_id":      teamId,
    "response_url": responseUrl,
    "trigger_id":   triggerId,
  }

func makeBlockActions(userId, actionId, actionValue,
                      channelId, teamId, responseUrl, triggerId: string): JsonNode =
  %* {
    "type":         "block_actions",
    "user":         {"id": userId},
    "actions":      [{"action_id": actionId, "value": actionValue}],
    "channel":      {"id": channelId},
    "team_id":      teamId,
    "response_url": responseUrl,
    "trigger_id":   triggerId,
  }

func makeVerification(challenge: string): JsonNode =
  %* {
    "type":      "url_verification",
    "challenge": challenge,
  }

# ── parseEvent — url_verification ─────────────────────────────────────────────

suite "slack_pure.parseEvent — url_verification":

  test "kind is sekVerification":
    let r = parseEvent(makeVerification("my-challenge"))
    check r.kind == sekVerification

  test "challenge value is captured":
    let r = parseEvent(makeVerification("abc123"))
    check r.challenge == "abc123"

  test "isVerification returns true":
    let r = parseEvent(makeVerification("token"))
    check r.isVerification

  test "isVerification returns false for message":
    let ev = makeMessageEvent("U1", "C1", "hi", "1.0")
    let r  = parseEvent(makeEventCallback("T1", ev))
    check not r.isVerification

# ── parseEvent — message events ───────────────────────────────────────────────

suite "slack_pure.parseEvent — message events":

  test "kind is sekMessage for valid message":
    let ev = makeMessageEvent("U001", "C001", "hello", "1.0")
    let r  = parseEvent(makeEventCallback("T001", ev))
    check r.kind == sekMessage

  test "rawId matches user field":
    let ev = makeMessageEvent("U999", "C001", "hi", "1.0")
    let r  = parseEvent(makeEventCallback("T001", ev))
    check r.rawId == "U999"

  test "text is captured":
    let ev = makeMessageEvent("U1", "C1", "test content", "1.0")
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.text == "test content"

  test "channelId and eventTs are captured":
    let ev = makeMessageEvent("U1", "C-special", "hi", "1.0")
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.channelId == "C-special"
    check r.eventTs == "1.0"

  test "teamId is captured":
    let ev = makeMessageEvent("U1", "C1", "hi", "1.0")
    let r  = parseEvent(makeEventCallback("TEAM-X", ev))
    check r.teamId == "TEAM-X"

  test "eventTs is captured":
    let ev = makeMessageEvent("U1", "C1", "hi", "1234567890.000001")
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.eventTs == "1234567890.000001"

  test "eventId is captured from the envelope":
    let ev = makeMessageEvent("U1", "C1", "hi", "1.0")
    let payload = %* {
      "type":     "event_callback",
      "team_id":  "T1",
      "event_id": "Ev123",
      "event":    ev,
    }
    let r = parseEvent(payload)
    check r.eventId == "Ev123"

  test "bot message with bot_id returns sekUnknown":
    let ev = makeMessageEvent("B001", "C1", "bot reply", "1.0", botId = "B001")
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.kind == sekUnknown

  test "bot_message subtype returns sekUnknown":
    let ev = makeMessageEvent("U1", "C1", "auto reply", "1.0", subtype = "bot_message")
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.kind == sekUnknown

  test "empty text returns sekUnknown":
    let ev = makeMessageEvent("U1", "C1", "", "1.0")
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.kind == sekUnknown

  test "missing user returns sekUnknown":
    let ev = %* {"type": "message", "channel": "C1", "text": "hi", "ts": "1.0"}
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.kind == sekUnknown

  test "app_mention is parsed as sekMessage":
    let ev = makeAppMentionEvent("U1", "C1", "<@BOT> hello", "2.0")
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.kind == sekMessage
    check r.text == "<@BOT> hello"

  test "unsupported event type returns sekUnknown":
    let ev = %* {"type": "reaction_added", "user": "U1"}
    let r  = parseEvent(makeEventCallback("T1", ev))
    check r.kind == sekUnknown

  test "missing event in event_callback returns sekUnknown":
    let payload = %* {"type": "event_callback", "team_id": "T1"}
    let r = parseEvent(payload)
    check r.kind == sekUnknown

# ── parseEvent — slash commands ───────────────────────────────────────────────

suite "slack_pure.parseEvent — slash commands":

  test "kind is sekSlashCommand":
    let p = makeSlashCommand("U1", "/help", "", "C1", "T1", "https://slack.com/...", "t1")
    let r = parseEvent(p)
    check r.kind == sekSlashCommand

  test "rawId matches user_id":
    let p = makeSlashCommand("U777", "/ping", "", "C1", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.rawId == "U777"

  test "text includes command with args":
    let p = makeSlashCommand("U1", "/deploy", "staging v2", "C1", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.text == "/deploy staging v2"

  test "text is just command when no args":
    let p = makeSlashCommand("U1", "/status", "", "C1", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.text == "/status"

  test "channelId is captured":
    let p = makeSlashCommand("U1", "/x", "", "C-cmd", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.channelId == "C-cmd"

  test "teamId is captured":
    let p = makeSlashCommand("U1", "/x", "", "C1", "TEAM-Z", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.teamId == "TEAM-Z"

  test "responseUrl is captured":
    let p = makeSlashCommand("U1", "/x", "", "C1", "T1", "https://hooks.slack.com/r", "t1")
    let r = parseEvent(p)
    check r.responseUrl == "https://hooks.slack.com/r"

  test "triggerId is captured":
    let p = makeSlashCommand("U1", "/x", "", "C1", "T1", "https://r.com", "trigger-42")
    let r = parseEvent(p)
    check r.triggerId == "trigger-42"

  test "missing user_id returns sekUnknown":
    let p = %* {"type": "slash_command", "command": "/x", "text": ""}
    let r = parseEvent(p)
    check r.kind == sekUnknown

# ── parseEvent — block actions ────────────────────────────────────────────────

suite "slack_pure.parseEvent — block actions":

  test "kind is sekBlockAction":
    let p = makeBlockActions("U1", "btn_ok", "yes", "C1", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.kind == sekBlockAction

  test "rawId comes from user.id":
    let p = makeBlockActions("U-btn-user", "a1", "v", "C1", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.rawId == "U-btn-user"

  test "text is action_id:value":
    let p = makeBlockActions("U1", "confirm_delete", "row-5", "C1", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.text == "confirm_delete:row-5"

  test "text is just action_id when no value":
    let p = %* {
      "type":    "block_actions",
      "user":    {"id": "U1"},
      "actions": [{"action_id": "dismiss"}],
      "channel": {"id": "C1"},
    }
    let r = parseEvent(p)
    check r.text == "dismiss"

  test "action_id == value is not duplicated":
    let p = makeBlockActions("U1", "models", "models", "C1", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.text == "models"

  test "channelId comes from channel.id":
    let p = makeBlockActions("U1", "a1", "v", "C-action", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    check r.channelId == "C-action"

  test "responseUrl is captured":
    let p = makeBlockActions("U1", "a1", "v", "C1", "T1", "https://hooks.slack.com/ia", "t1")
    let r = parseEvent(p)
    check r.responseUrl == "https://hooks.slack.com/ia"

  test "triggerId is captured":
    let p = makeBlockActions("U1", "a1", "v", "C1", "T1", "https://r.com", "trig-99")
    let r = parseEvent(p)
    check r.triggerId == "trig-99"

  test "missing user returns sekUnknown":
    let p = %* {"type": "block_actions", "actions": [{"action_id": "x"}]}
    let r = parseEvent(p)
    check r.kind == sekUnknown

# ── parseEvent — unknown / unhandled payloads ─────────────────────────────────

suite "slack_pure.parseEvent — unknown payloads":

  test "unknown type returns sekUnknown":
    let r = parseEvent(%* {"type": "oauth_access"})
    check r.kind == sekUnknown

  test "nil payload returns sekUnknown":
    let r = parseEvent(nil)
    check r.kind == sekUnknown

  test "empty object returns sekUnknown":
    let r = parseEvent(%* {})
    check r.kind == sekUnknown

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "slack_pure.toInbound":

  test "converts SlkParseResult to InboundMessage":
    let ev = makeMessageEvent("U1", "C1", "hello world", "1234.5678")
    let r  = parseEvent(makeEventCallback("T1", ev))
    let uid = UserId("uuid-1")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckSlack
    check msg.text == "hello world"
    check msg.channelId == "1234.5678"
    check msg.mediaUrl == ""

  test "slash command result converts to InboundMessage":
    let p = makeSlashCommand("U1", "/help", "all", "C1", "T1", "https://r.com", "t1")
    let r = parseEvent(p)
    let uid = UserId("uuid-2")
    let msg = r.toInbound(uid)
    check msg.channel == ckSlack
    check msg.text == "/help all"

suite "slack_pure.blockActionCommand":

  test "simple menu buttons map to their command":
    check blockActionCommand("models") == "/models"
    check blockActionCommand("reasoning") == "/reasoning"
    check blockActionCommand("menu") == "/menu"

  test "model provider selection maps to /models <provider>":
    check blockActionCommand("models:provider:openrouter") == "/models openrouter"

  test "model selection maps to /models <provider> <model>":
    check blockActionCommand("models:set:openai:gpt-4.1") == "/models openai gpt-4.1"

  test "model identifiers with colons are preserved":
    check blockActionCommand("models:set:openrouter:org/model:free") ==
      "/models openrouter org/model:free"

  test "model pagination keeps the provider and drops the page":
    check blockActionCommand("models:page:anthropic:2") == "/models anthropic"

  test "think presets map to /think <level>":
    check blockActionCommand("think:set:high") == "/think high"

  test "unknown actions return an empty command":
    check blockActionCommand("personality:pirate") == ""
    check blockActionCommand("") == ""
