## Tests for domain/channels/discord_pure.nim — pure Discord gateway parser.
## Uses real fixture data from tests/fixtures/discord/ for integration testing.
## No I/O or HTTP; fixture data is read as static strings and parsed.

import std/[json, os, unittest]
import donkey/domain/channels/discord_pure
import donkey/core/pipeops
import donkey/core/types

# ── Fixture Loader ────────────────────────────────────────────────────────────

const
  FixturesDir = currentSourcePath().parentDir() / ".." / ".." / "fixtures" / "discord"

proc loadGatewayPayload(name: string): JsonNode =
  let path = FixturesDir / name
  let content = readFile(path)
  let arr = parseJson(content)
  # All gateway fixtures are arrays with one payload at index 0
  arr[0]["d"]

proc loadInteractionPayload(sampleIndex: int): JsonNode =
  ## INTERACTION_CREATE fixtures have 2 samples; pick one by index.
  let arr = parseJson(readFile(FixturesDir / "gateway_interaction_create.json"))
  arr[sampleIndex]["d"]

# ── Fixtures (Synthetic) ──────────────────────────────────────────────────────

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

# ── Fixture-based Tests ───────────────────────────────────────────────────────

suite "discord_pure.parseDispatch — gateway_message_create fixture":
  ## 3 samples in fixture: regular message, reply, sticker message.

  test "sample 0: regular guild message is parsed":
    let d = loadGatewayPayload("gateway_message_create.json")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekMessage
    check r.rawId == "900000000000000002"  # author.id
    check r.content == "content_2"
    check r.channelId == "900000000000000009"
    check r.messageId == "900000000000000087"
    check r.interactionId == ""
    check r.interactionToken == ""

  test "sample 0: hasInteraction returns false":
    let d = loadGatewayPayload("gateway_message_create.json")
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.hasInteraction == false

  test "sample 1: reply message is parsed with referenced_message":
    let arr = parseJson(readFile(FixturesDir / "gateway_message_create.json"))
    let d = arr[1]["d"]
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekMessage
    check r.rawId == "900000000000000002"
    check r.content == "content_3"  # the reply content
    check r.messageId == "900000000000000089"

  test "sample 1: toInbound produces correct InboundMessage":
    let arr = parseJson(readFile(FixturesDir / "gateway_message_create.json"))
    let d = arr[1]["d"]
    let r = parseDispatch("MESSAGE_CREATE", d)
    let uid = UserId("resolved-user-uid")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckDiscord
    check msg.text == "content_3"
    check msg.channelId == "900000000000000089"

  test "sample 2: sticker message is still parsed as dekMessage":
    let arr = parseJson(readFile(FixturesDir / "gateway_message_create.json"))
    let d = arr[2]["d"]
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekMessage
    check r.rawId == "900000000000000002"
    check r.content == "content_4"
    check r.messageId == "900000000000000091"


suite "discord_pure.parseDispatch — gateway_interaction_create fixture":
  ## 2 samples: both APPLICATION_COMMAND (type 2) from guild slash commands.

  test "sample 0: application command is parsed":
    let d = loadInteractionPayload(0)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand
    check r.rawId == "900000000000000026"  # member.user.id
    check r.interactionId == "900000000000000084"
    check r.interactionToken == "token_1"
    check r.hasInteraction == true

  test "sample 0: command name is extracted":
    let d = loadInteractionPayload(0)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/name_48"  # data.name

  test "sample 1: second application command":
    let d = loadInteractionPayload(1)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand
    check r.rawId == "900000000000000026"
    check r.content == "/name_49"  # different command name
    check r.interactionId == "900000000000000087"


suite "discord_pure.parseDispatch — gateway_ready fixture":
  ## READY event should be ignored (dekUnknown).

  test "READY event returns dekUnknown":
    let d = loadGatewayPayload("gateway_ready.json")
    let r = parseDispatch("READY", d)
    check r.kind == dekUnknown

  test "READY event hasInteraction returns false":
    let d = loadGatewayPayload("gateway_ready.json")
    let r = parseDispatch("READY", d)
    check r.hasInteraction == false


suite "discord_pure.parseDispatch — gateway_guild_create fixture":
  ## Guild create should be ignored (not a message).

  test "GUILD_CREATE event returns dekUnknown":
    let d = loadGatewayPayload("gateway_guild_create.json")
    let r = parseDispatch("GUILD_CREATE", d)
    check r.kind == dekUnknown


suite "discord_pure.parseDispatch — gateway_message_delete fixture":
  ## Message deletion is not parsed as a user message.

  test "MESSAGE_DELETE event returns dekUnknown":
    let d = loadGatewayPayload("gateway_message_delete.json")
    let r = parseDispatch("MESSAGE_DELETE", d)
    check r.kind == dekUnknown


suite "discord_pure.parseDispatch — gateway_message_update fixture":
  ## Message edits are not parsed as new messages.

  test "MESSAGE_UPDATE event returns dekUnknown":
    let d = loadGatewayPayload("gateway_message_update.json")
    let r = parseDispatch("MESSAGE_UPDATE", d)
    check r.kind == dekUnknown


suite "discord_pure.parseDispatch — gateway_message_reaction_add fixture":
  ## Reactions are not parsed as user messages.

  test "MESSAGE_REACTION_ADD event returns dekUnknown":
    let d = loadGatewayPayload("gateway_message_reaction_add.json")
    let r = parseDispatch("MESSAGE_REACTION_ADD", d)
    check r.kind == dekUnknown


suite "discord_pure.parseDispatch — gateway_thread_create fixture":
  ## Thread creation is not a user message.

  test "THREAD_CREATE event returns dekUnknown":
    let d = loadGatewayPayload("gateway_thread_create.json")
    let r = parseDispatch("THREAD_CREATE", d)
    check r.kind == dekUnknown


suite "discord_pure.parseDispatch — gateway_guild_member_update fixture":
  ## Member updates are not user messages.

  test "GUILD_MEMBER_UPDATE event returns dekUnknown":
    let d = loadGatewayPayload("gateway_guild_member_update.json")
    let r = parseDispatch("GUILD_MEMBER_UPDATE", d)
    check r.kind == dekUnknown


suite "discord_pure.parseDispatch — gateway_voice_state_update fixture":
  ## Voice state changes are not user messages.

  test "VOICE_STATE_UPDATE event returns dekUnknown":
    let d = loadGatewayPayload("gateway_voice_state_update.json")
    let r = parseDispatch("VOICE_STATE_UPDATE", d)
    check r.kind == dekUnknown


suite "discord_pure.parseDispatch — gateway_voice_channel_status_update fixture":
  test "VOICE_CHANNEL_STATUS_UPDATE event returns dekUnknown":
    let d = loadGatewayPayload("gateway_voice_channel_status_update.json")
    let r = parseDispatch("VOICE_CHANNEL_STATUS_UPDATE", d)
    check r.kind == dekUnknown


suite "discord_pure.parseDispatch — gateway_voice_channel_start_time_update fixture":
  test "VOICE_CHANNEL_START_TIME_UPDATE event returns dekUnknown":
    let d = loadGatewayPayload("gateway_voice_channel_start_time_update.json")
    let r = parseDispatch("VOICE_CHANNEL_START_TIME_UPDATE", d)
    check r.kind == dekUnknown


# ── Synthetic Edge Case Tests ─────────────────────────────────────────────────

suite "discord_pure.parseDispatch — MESSAGE_CREATE (synthetic)":

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

  test "bot-authored message returns dekUnknown":
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

  test "DM channel message (no guild_id) is parsed":
    let d = %* {
      "author": {"id": "456", "bot": false},
      "content": "direct message",
      "channel_id": "dm_123",
      "id": "dm_msg_1",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekMessage
    check r.rawId == "456"
    check r.content == "direct message"
    check r.channelId == "dm_123"


suite "discord_pure.parseDispatch — INTERACTION_CREATE slash commands (synthetic)":

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
      {"name": "provider", "value": "openrouter", "type": 3},
      {"name": "model",    "value": "gpt-4", "type": 3},
    ]
    let d = makeSlashCommand("u1", "ix1", "tok", "models", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/models openrouter gpt-4"

  test "/models with provider only":
    let opts = %* [{"name": "provider", "value": "zhipu", "type": 3}]
    let d = makeSlashCommand("u1", "ix1", "tok", "models", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/models zhipu"

  test "/models without options":
    let d = makeSlashCommand("u1", "ix1", "tok", "models")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/models"

  test "/think with level":
    let opts = %* [{"name": "level", "value": "high", "type": 3}]
    let d = makeSlashCommand("u1", "ix1", "tok", "think", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/think high"

  test "/think without options":
    let d = makeSlashCommand("u1", "ix1", "tok", "think")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/think"

  test "/budget with policy":
    let opts = %* [{"name": "policy", "value": "balanced", "type": 3}]
    let d = makeSlashCommand("u1", "ix1", "tok", "budget", opts)
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/budget balanced"

  test "/budget without options":
    let d = makeSlashCommand("u1", "ix1", "tok", "budget")
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/budget"

  test "/continue with code returns content = code":
    let opts = %* [{"name": "code", "value": "AB3X7Q", "type": 3}]
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


suite "discord_pure.parseDispatch — button click (synthetic)":

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

  test "messageId is captured from the clicked message":
    var d = makeButtonClick("u1", "ix-btn", "tok", "x")
    d["message"] = %* {"id": "msg-btn-42"}
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.messageId == "msg-btn-42"


suite "discord_pure.parseDispatch — modal submit (synthetic)":

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

  test "type 4 (APPLICATION_COMMAND_AUTOCOMPLETE) returns dekUnknown":
    let d = %* {
      "type": 4,
      "id": "autocomplete_int",
      "token": "autocomplete_tok",
      "user": {"id": "user_ac"},
      "data": {"name": "models"},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekUnknown


suite "discord_pure.toInbound — conversion":

  test "message converts with correct fields":
    let d = makeMessageCreate("u1", "ch1", "msg-10", "hello world")
    let r = parseDispatch("MESSAGE_CREATE", d)
    let uid = UserId("test-uuid")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckDiscord
    check msg.text == "hello world"
    check msg.channelId == "msg-10"
    check msg.mediaUrl == ""

  test "slash command converts with interaction content":
    let d = makeSlashCommand("u1", "ix1", "tok", "help")
    let r = parseDispatch("INTERACTION_CREATE", d)
    let uid = UserId("uid-2")
    let msg = r.toInbound(uid)
    check msg.channel == ckDiscord
    check msg.text == "/help"
