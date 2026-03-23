## Tests for domain/channels/discord_pure.nim — pure Discord dispatch parser.
## No I/O or HTTP; all input is constructed directly as JsonNode.

import std/[json, unittest]
import donkey/domain/channels/discord_pure
import donkey/core/pipeops
import donkey/core/types

# ── Fixtures ──────────────────────────────────────────────────────────────────

func makeMessageCreate(userId, channelId, messageId, content: string;
                       isBot = false): JsonNode =
  %* {
    "author": {"id": userId, "bot": isBot},
    "content": content,
    "channel_id": channelId,
    "id": messageId,
  }

func makeInteractionBase(userId, interactionId, token: string;
                         interactionType: int): JsonNode =
  %* {
    "type":  interactionType,
    "id":    interactionId,
    "token": token,
    "user":  {"id": userId},
  }

func makeSlashCommand(userId, interactionId, token, cmdName: string;
                      opts: JsonNode = nil): JsonNode =
  var data = %* {"name": cmdName}
  if opts != nil: data["options"] = opts
  result = makeInteractionBase(userId, interactionId, token, 2)
  result["data"] = data

func makeButtonClick(userId, interactionId, token, customId: string): JsonNode =
  result = makeInteractionBase(userId, interactionId, token, 3)
  result["data"] = %* {"custom_id": customId}

func makeModalSubmit(userId, interactionId, token, code: string): JsonNode =
  result = makeInteractionBase(userId, interactionId, token, 5)
  result["data"] = %* {
    "components": [{
      "type": 1,
      "components": [{
        "type":      4,
        "custom_id": "link_code",
        "value":     code,
      }],
    }],
  }

func makeMemberInteraction(memberId, interactionId, token, cmdName: string): JsonNode =
  ## Interaction with member.user instead of top-level user (guild context).
  %* {
    "type":   2,
    "id":     interactionId,
    "token":  token,
    "member": {"user": {"id": memberId}},
    "data":   {"name": cmdName},
  }

# ── parseDispatch — MESSAGE_CREATE ────────────────────────────────────────────

suite "discord_pure.parseDispatch — MESSAGE_CREATE":

  test "kind is dekMessage for valid message":
    let d = makeMessageCreate("u1", "ch1", "m1", "hello")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekMessage

  test "rawId matches author id":
    let d = makeMessageCreate("12345", "ch1", "m1", "hi")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.rawId == "12345"

  test "content is captured":
    let d = makeMessageCreate("u1", "ch1", "m1", "test content")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.content == "test content"

  test "channelId is captured":
    let d = makeMessageCreate("u1", "channel-99", "m1", "x")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.channelId == "channel-99"

  test "messageId is captured":
    let d = makeMessageCreate("u1", "ch1", "msg-42", "x")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.messageId == "msg-42"

  test "bot message returns dekUnknown":
    let d = makeMessageCreate("bot-id", "ch1", "m1", "bot text", isBot = true)
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

  test "empty content returns dekUnknown":
    let d = makeMessageCreate("u1", "ch1", "m1", "")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

  test "missing author returns dekUnknown":
    let d = %* {"content": "hi", "channel_id": "ch1", "id": "m1"}
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

  test "hasInteraction is false for plain message":
    let d = makeMessageCreate("u1", "ch1", "m1", "hello")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check not r.hasInteraction

# ── parseDispatch — INTERACTION_CREATE slash commands ─────────────────────────

suite "discord_pure.parseDispatch — INTERACTION_CREATE slash commands":

  test "simple slash command returns dekSlashCommand":
    let d = makeSlashCommand("u1", "ix1", "tok1", "help")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand

  test "slash command content has leading slash":
    let d = makeSlashCommand("u1", "ix1", "tok1", "start")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/start"

  test "rawId comes from user.id":
    let d = makeSlashCommand("user-99", "ix1", "tok1", "ping")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.rawId == "user-99"

  test "interactionId is captured":
    let d = makeSlashCommand("u1", "interact-42", "tok1", "status")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.interactionId == "interact-42"

  test "interactionToken is captured":
    let d = makeSlashCommand("u1", "ix1", "secret-token", "help")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.interactionToken == "secret-token"

  test "hasInteraction is true for slash command":
    let d = makeSlashCommand("u1", "ix1", "tok1", "help")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.hasInteraction

  test "/models with provider and model":
    let opts = %* [
      {"name": "provider", "value": "openrouter"},
      {"name": "model",    "value": "gpt-4"},
    ]
    let d = makeSlashCommand("u1", "ix1", "tok", "models", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/models openrouter gpt-4"

  test "/models with provider only":
    let opts = %* [{"name": "provider", "value": "zhipu"}]
    let d = makeSlashCommand("u1", "ix1", "tok", "models", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/models zhipu"

  test "/models without options":
    let d = makeSlashCommand("u1", "ix1", "tok", "models")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/models"

  test "/think with level":
    let opts = %* [{"name": "level", "value": "high"}]
    let d = makeSlashCommand("u1", "ix1", "tok", "think", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/think high"

  test "/think without options":
    let d = makeSlashCommand("u1", "ix1", "tok", "think")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/think"

  test "/budget with policy":
    let opts = %* [{"name": "policy", "value": "balanced"}]
    let d = makeSlashCommand("u1", "ix1", "tok", "budget", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/budget balanced"

  test "/budget without options":
    let d = makeSlashCommand("u1", "ix1", "tok", "budget")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/budget"

  test "/continue with code returns content = code":
    let opts = %* [{"name": "code", "value": "AB3X7Q"}]
    let d = makeSlashCommand("u1", "ix1", "tok", "continue", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand
    check r.content == "AB3X7Q"
    check not r.needsModal

  test "/continue without code sets needsModal":
    let d = makeSlashCommand("u1", "ix1", "tok", "continue")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand
    check r.needsModal
    check r.content == ""

  test "guild member interaction uses member.user":
    let d = makeMemberInteraction("guild-user", "ix1", "tok", "help")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.rawId == "guild-user"
    check r.content == "/help"

  test "missing user returns dekUnknown":
    let d = %* {
      "type": 2, "id": "ix1", "token": "tok",
      "data": {"name": "help"},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekUnknown

  test "missing data returns dekUnknown":
    let d = makeInteractionBase("u1", "ix1", "tok", 2)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekUnknown

# ── parseDispatch — INTERACTION_CREATE button click ───────────────────────────

suite "discord_pure.parseDispatch — INTERACTION_CREATE button click":

  test "kind is dekButtonClick":
    let d = makeButtonClick("u1", "ix1", "tok", "confirm")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekButtonClick

  test "content is the custom_id":
    let d = makeButtonClick("u1", "ix1", "tok", "my_custom_id")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "my_custom_id"

  test "rawId is userId":
    let d = makeButtonClick("btn-user", "ix1", "tok", "x")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.rawId == "btn-user"

  test "hasInteraction is true":
    let d = makeButtonClick("u1", "ix-btn", "tok", "x")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.hasInteraction

# ── parseDispatch — INTERACTION_CREATE modal submit ───────────────────────────

suite "discord_pure.parseDispatch — INTERACTION_CREATE modal submit":

  test "kind is dekModalSubmit":
    let d = makeModalSubmit("u1", "ix1", "tok", "AB3X7Q")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekModalSubmit

  test "content is the extracted link code":
    let d = makeModalSubmit("u1", "ix1", "tok", "XY99ZZ")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "XY99ZZ"

  test "rawId is userId":
    let d = makeModalSubmit("modal-user", "ix1", "tok", "code1")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.rawId == "modal-user"

  test "hasInteraction is true":
    let d = makeModalSubmit("u1", "ix-modal", "tok", "code1")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.hasInteraction

# ── parseDispatch — unknown / unhandled events ────────────────────────────────

suite "discord_pure.parseDispatch — unknown events":

  test "unknown event type returns dekUnknown":
    let d = %* {"foo": "bar"}
    let r = parseDispatch("CHANNEL_UPDATE", d)
    check r.kind == dekUnknown

  test "READY event returns dekUnknown":
    let d = %* {"session_id": "sess-1"}
    let r = parseDispatch("READY", d)
    check r.kind == dekUnknown

  test "unknown interaction type returns dekUnknown":
    let d = makeInteractionBase("u1", "ix1", "tok", 99)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekUnknown

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "discord_pure.toInbound":

  test "converts DsParseResult to InboundMessage":
    let d = makeMessageCreate("u1", "ch1", "msg-10", "hello world")
    let r = parseDispatch("MESSAGE_CREATE", d)
    let uid = UserId("test-uuid")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckDiscord
    check msg.text == "hello world"
    check msg.channelId == "msg-10"
    check msg.mediaUrl == ""

  test "converts slash command result to InboundMessage":
    let d = makeSlashCommand("u1", "ix1", "tok", "help")
    let r = parseDispatch("INTERACTION_CREATE", d)
    let uid = UserId("uid-2")
    let msg = r.toInbound(uid)
    check msg.channel == ckDiscord
    check msg.text == "/help"
