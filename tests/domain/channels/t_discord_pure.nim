## Tests for domain/channels/discord_pure.nim — pure Discord gateway parser.
## Uses real fixture data from tests/fixtures/discord/ for integration testing.
## No I/O or HTTP; fixture data is read as static strings and parsed.

import std/[json, os, unittest]
import donkey/domain/channels/discord_pure
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

suite "discord_pure.parseDispatch — edge cases":

  test "bot-authored message returns dekUnknown":
    let d = %* {
      "author": {"id": "123", "bot": true},
      "content": "I am a bot",
      "channel_id": "ch1",
      "id": "m1",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

  test "empty content returns dekUnknown":
    let d = %* {
      "author": {"id": "123", "bot": false},
      "content": "",
      "channel_id": "ch1",
      "id": "m1",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

  test "missing author returns dekUnknown":
    let d = %* {
      "content": "hello",
      "channel_id": "ch1",
      "id": "m1",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

  test "missing content field returns dekUnknown":
    let d = %* {
      "author": {"id": "123", "bot": false},
      "channel_id": "ch1",
      "id": "m1",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

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

  test "DM message without author returns dekUnknown":
    ## MESSAGE_CREATE requires author field; member.user is for guilds.
    let d = %* {
      "content": "hello from guild",
      "channel_id": "guild_channel",
      "id": "guild_msg_1",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown


suite "discord_pure.parseInteractionCreate — button click (type 3)":

  test "button click extracts custom_id as content":
    let d = %* {
      "type": 3,
      "id": "int_id_1",
      "token": "tok_abc",
      "user": {"id": "user_btn"},
      "data": {"custom_id": "cbk_models_next"},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekButtonClick
    check r.rawId == "user_btn"
    check r.content == "cbk_models_next"
    check r.interactionId == "int_id_1"
    check r.interactionToken == "tok_abc"
    check r.hasInteraction == true

  test "button click with guild member.user":
    let d = %* {
      "type": 3,
      "id": "int_id_2",
      "token": "tok_def",
      "member": {"user": {"id": "guild_user_456"}},
      "data": {"custom_id": "btn_confirm"},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekButtonClick
    check r.rawId == "guild_user_456"


suite "discord_pure.parseInteractionCreate — modal submit (type 5)":

  test "modal submit extracts link_code value":
    let d = %* {
      "type": 5,
      "id": "modal_int_id",
      "token": "modal_tok",
      "user": {"id": "modal_user"},
      "data": {
        "components": [{
          "type": 1,
          "components": [{
            "custom_id": "link_code",
            "value": "XYZ789",
          }],
        }],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekModalSubmit
    check r.rawId == "modal_user"
    check r.content == "XYZ789"
    check r.interactionId == "modal_int_id"
    check r.interactionToken == "modal_tok"

  test "modal submit with empty components returns empty content":
    let d = %* {
      "type": 5,
      "id": "modal_int_id2",
      "token": "modal_tok2",
      "user": {"id": "modal_user2"},
      "data": {"components": []},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekModalSubmit
    check r.content == ""


suite "discord_pure.parseApplicationCommand — /continue command":

  test "/continue with code extracts code as content":
    let d = %* {
      "type": 2,
      "id": "continue_int_id",
      "token": "continue_tok",
      "user": {"id": "user_cont"},
      "data": {
        "name": "continue",
        "options": [{"name": "code", "value": "ABC123DEF", "type": 3}],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand
    check r.content == "ABC123DEF"
    check r.needsModal == false

  test "/continue without code sets needsModal":
    let d = %* {
      "type": 2,
      "id": "continue_int_id2",
      "token": "continue_tok2",
      "user": {"id": "user_cont2"},
      "data": {
        "name": "continue",
        "options": [],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand
    check r.content == ""
    check r.needsModal == true


suite "discord_pure.parseApplicationCommand — slash commands":

  test "/models command with provider and model":
    let d = %* {
      "type": 2,
      "id": "models_int",
      "token": "models_tok",
      "user": {"id": "user_models"},
      "data": {
        "name": "models",
        "options": [
          {"name": "provider", "value": "openai", "type": 3},
          {"name": "model", "value": "gpt-4o", "type": 3},
        ],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand
    check r.content == "/models openai gpt-4o"

  test "/models command with provider only":
    let d = %* {
      "type": 2,
      "id": "models_int2",
      "token": "models_tok2",
      "user": {"id": "user_models2"},
      "data": {
        "name": "models",
        "options": [{"name": "provider", "value": "anthropic", "type": 3}],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/models anthropic"

  test "/models command with no options":
    let d = %* {
      "type": 2,
      "id": "models_int3",
      "token": "models_tok3",
      "user": {"id": "user_models3"},
      "data": {
        "name": "models",
        "options": [],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/models"

  test "/think command with level":
    let d = %* {
      "type": 2,
      "id": "think_int",
      "token": "think_tok",
      "user": {"id": "user_think"},
      "data": {
        "name": "think",
        "options": [{"name": "level", "value": "high", "type": 3}],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/think high"

  test "/think command without level":
    let d = %* {
      "type": 2,
      "id": "think_int2",
      "token": "think_tok2",
      "user": {"id": "user_think2"},
      "data": {
        "name": "think",
        "options": [],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/think"

  test "/budget command":
    let d = %* {
      "type": 2,
      "id": "budget_int",
      "token": "budget_tok",
      "user": {"id": "user_budget"},
      "data": {
        "name": "budget",
        "options": [{"name": "policy", "value": "balanced", "type": 3}],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.content == "/budget balanced"

  test "unknown slash command falls back to /commandname":
    let d = %* {
      "type": 2,
      "id": "unknown_int",
      "token": "unknown_tok",
      "user": {"id": "user_unknown"},
      "data": {
        "name": "random_command",
        "options": [],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekSlashCommand
    check r.content == "/random_command"


suite "discord_pure.parseInteractionCreate — unsupported types":

  test "type 1 (PING) returns dekUnknown":
    let d = %* {
      "type": 1,
      "id": "ping_int",
      "token": "ping_tok",
      "user": {"id": "user_ping"},
    }
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

  test "type 6 (APPLICATION_COMMAND_MODAL_SUBMIT) returns dekUnknown":
    ## Type 6 is APPLICATION_COMMAND_MODAL_SUBMIT (Discord API) — not handled.
    let d = %* {
      "type": 6,
      "id": "form_int",
      "token": "form_tok",
      "user": {"id": "user_form"},
      "data": {
        "components": [{
          "type": 1,
          "components": [{"custom_id": "answer", "value": "test"}],
        }],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)

  test "missing user and member returns dekUnknown":
    let d = %* {
      "type": 2,
      "id": "no_user_int",
      "token": "no_user_tok",
      "data": {"name": "ping"},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind == dekUnknown


suite "discord_pure.toInbound — conversion":

  test "message converts with correct fields":
    let d = %* {
      "author": {"id": "msg_user", "bot": false},
      "content": "hello inbox",
      "channel_id": "ch_msg",
      "id": "msg_123",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    let uid = UserId("inbox-uid-xyz")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckDiscord
    check msg.text == "hello inbox"
    check msg.channelId == "msg_123"
    check msg.mediaUrl == ""

  test "slash command converts with interaction content":
    let d = %* {
      "type": 2,
      "id": "slash_int",
      "token": "slash_tok",
      "user": {"id": "slash_user"},
      "data": {
        "name": "help",
        "options": [],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    let uid = UserId("slash-uid")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckDiscord
    check msg.text == "/help"