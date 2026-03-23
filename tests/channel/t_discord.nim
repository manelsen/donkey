## DiscordAdapter unit tests.
## HTTP calls are not made; tests cover adapter construction, identity
## resolution, and the handleDispatch routing via discord_pure.

import std/[json, os, unittest]
import donkey/adapters/channel/discord
import donkey/adapters/identity/identity_resolver
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/discord_pure

suite "IdentityResolver (Discord)":

  test "creates new UUID for unknown discord user":
    let path = getTempDir() / "donkey_test_ids_discord.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckDiscord, "123456789")
    check ($uid).len == 36

  test "same discord id returns same UserId":
    let path = getTempDir() / "donkey_test_ids_discord2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckDiscord, "999")
    let u2 = r.resolve(ckDiscord, "999")
    check u1 == u2

  test "different discord ids get different UserIds":
    let path = getTempDir() / "donkey_test_ids_discord3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckDiscord, "aaa")
    let u2 = r.resolve(ckDiscord, "bbb")
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_ids_discord4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid1 = newIdentityResolver(path).resolve(ckDiscord, "ccc")
    let uid2 = newIdentityResolver(path).resolve(ckDiscord, "ccc")
    check uid1 == uid2

  test "generated id looks like a UUID":
    let path = getTempDir() / "donkey_test_ids_discord5.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid = $newIdentityResolver(path).resolve(ckDiscord, "777")
    check uid.len == 36
    check uid[8]  == '-'
    check uid[13] == '-'
    check uid[18] == '-'
    check uid[23] == '-'

suite "DiscordAdapter construction":

  test "token is stored":
    let a = newDiscordAdapter("MY_TOKEN", "/tmp/ids_ds.tsv",
                              apiBase = "https://mock.local")
    check a.token == "MY_TOKEN"

  test "apiBase override is stored":
    let a = newDiscordAdapter("TOK", "/tmp/ids_ds2.tsv",
                              apiBase = "https://test.api")
    check a.apiBase == "https://test.api"

  test "default apiBase is empty string":
    let a = newDiscordAdapter("TOK2", "/tmp/ids_ds3.tsv")
    check a.apiBase == ""

suite "discord_pure dispatch routing (used by handleDispatch)":

  test "MESSAGE_CREATE produces dekMessage":
    let d = %* {
      "author":     {"id": "u1", "bot": false},
      "content":    "hello",
      "channel_id": "ch1",
      "id":         "m1",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind    == dekMessage
    check r.rawId   == "u1"
    check r.content == "hello"

  test "bot MESSAGE_CREATE produces dekUnknown":
    let d = %* {
      "author":     {"id": "bot1", "bot": true},
      "content":    "I am a bot",
      "channel_id": "ch1",
      "id":         "m2",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

  test "empty-content MESSAGE_CREATE produces dekUnknown":
    let d = %* {
      "author":     {"id": "u2", "bot": false},
      "content":    "",
      "channel_id": "ch1",
      "id":         "m3",
    }
    let r = parseDispatch("MESSAGE_CREATE", d)
    check r.kind == dekUnknown

  test "slash command without code sets needsModal false":
    let d = %* {
      "type":  2,
      "id":    "i1",
      "token": "t1",
      "user":  {"id": "u3"},
      "data":  {"name": "help", "options": []},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind      == dekSlashCommand
    check r.content   == "/help"
    check r.needsModal == false

  test "/continue with code produces dekSlashCommand content=code":
    let d = %* {
      "type":  2,
      "id":    "i2",
      "token": "t2",
      "user":  {"id": "u4"},
      "data":  {
        "name":    "continue",
        "options": [{"name": "code", "value": "AB3X7Q", "type": 3}],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind         == dekSlashCommand
    check r.content      == "AB3X7Q"
    check r.needsModal   == false
    check r.interactionId == "i2"

  test "/continue without code sets needsModal":
    let d = %* {
      "type":  2,
      "id":    "i3",
      "token": "t3",
      "user":  {"id": "u5"},
      "data":  {"name": "continue", "options": []},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind      == dekSlashCommand
    check r.needsModal == true

  test "button click produces dekButtonClick":
    let d = %* {
      "type":  3,
      "id":    "i4",
      "token": "t4",
      "user":  {"id": "u6"},
      "data":  {"custom_id": "btn_ok"},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind    == dekButtonClick
    check r.content == "btn_ok"

  test "modal submit produces dekModalSubmit":
    let d = %* {
      "type":  5,
      "id":    "i5",
      "token": "t5",
      "user":  {"id": "u7"},
      "data":  {
        "components": [{
          "type": 1,
          "components": [{
            "custom_id": "link_code",
            "value":     "XY99ZZ",
          }],
        }],
      },
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.kind    == dekModalSubmit
    check r.content == "XY99ZZ"

  test "unknown event type produces dekUnknown":
    let r = parseDispatch("TYPING_START", %* {})
    check r.kind == dekUnknown

  test "guild interaction uses member.user for userId":
    let d = %* {
      "type":   2,
      "id":     "i6",
      "token":  "t6",
      "member": {"user": {"id": "guild_user"}},
      "data":   {"name": "ping"},
    }
    let r = parseDispatch("INTERACTION_CREATE", d)
    check r.rawId == "guild_user"
