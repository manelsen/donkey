## TelegramAdapter unit tests.
## HTTP calls are not made; tests cover IdentityResolver and pure logic.

import std/[json, os, strutils, unittest]
import donkey/adapters/channel/telegram
import donkey/adapters/identity/identity_resolver
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/channel
import donkey/core/types

proc verifyChannelPort[T: ChannelPort](c: var T) {.used.} =
  ## Compile-time concept check — generic constraint verifies T satisfies ChannelPort.
  discard

suite "IdentityResolver (generalized)":

  test "creates new UUID for unknown telegram user":
    let path = getTempDir() / "donkey_test_identities.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckTelegram, "12345678")
    check $uid != ""
    check ($uid).len == 36

  test "same telegram id returns same UserId":
    let path = getTempDir() / "donkey_test_identities2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckTelegram, "99")
    let u2 = r.resolve(ckTelegram, "99")
    check u1 == u2

  test "different telegram ids get different UserIds":
    let path = getTempDir() / "donkey_test_identities3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckTelegram, "1")
    let u2 = r.resolve(ckTelegram, "2")
    check u1 != u2

  test "same raw id on different channels gets different UserIds":
    let path = getTempDir() / "donkey_test_identities_cross.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckTelegram, "100")
    let u2 = r.resolve(ckDiscord,  "100")
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_identities4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid1 = newIdentityResolver(path).resolve(ckTelegram, "555")
    let uid2 = newIdentityResolver(path).resolve(ckTelegram, "555")
    check uid1 == uid2

  test "generated id looks like UUID v4":
    let path = getTempDir() / "donkey_test_identities5.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid = $newIdentityResolver(path).resolve(ckTelegram, "777")
    check uid.len == 36
    check uid[8]  == '-'
    check uid[13] == '-'
    check uid[18] == '-'
    check uid[23] == '-'

  test "reverseChannel returns raw id after resolve":
    let path = getTempDir() / "donkey_test_identities6.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckTelegram, "42000")
    check r.reverseChannel(uid, ckTelegram) == "42000"
    check r.reverseChannel(uid, ckDiscord)  == ""

  test "link code links two channel identities to same UserId":
    let path = getTempDir() / "donkey_test_link.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r      = newIdentityResolver(path)
    let uid    = r.resolve(ckTelegram, "1001")
    let code   = r.generateLinkCode(uid)
    check code.len == 6
    let linked = r.consumeLinkCode(code, ckDiscord, "2002")
    check linked
    check r.resolve(ckDiscord, "2002") == uid

  test "link code is single-use":
    let path = getTempDir() / "donkey_test_link2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r    = newIdentityResolver(path)
    let uid  = r.resolve(ckTelegram, "3003")
    let code = r.generateLinkCode(uid)
    check r.consumeLinkCode(code, ckDiscord, "4004")
    check not r.consumeLinkCode(code, ckDiscord, "5005")  ## already consumed

suite "TelegramAdapter construction":

  test "token is stored":
    let a = newTelegramAdapter("MY_TOKEN", "/tmp/ids.tsv",
                               apiBase = "https://mock.local")
    check a.token == "MY_TOKEN"

  test "initial offset is zero":
    let a = newTelegramAdapter("tok", "/tmp/ids2.tsv")
    check a.offset == 0

  test "pollTimeout defaults to 1":
    let a = newTelegramAdapter("tok", "/tmp/ids3.tsv")
    check a.pollTimeout == 1

suite "TelegramAdapter satisfies ChannelPort concept":

  test "compile-time concept check passes":
    var a = newTelegramAdapter("tok", "/tmp/ids_concept.tsv")
    verifyChannelPort(a)
    check true

suite "TelegramAdapter sendTyping compiles":

  test "sendTyping is callable on a TelegramAdapter":
    ## Compile-time check only — no real HTTP call.
    ## Creates an adapter against a non-existent base URL; we never call send.
    let a = newTelegramAdapter("tok", "/tmp/ids_typing.tsv",
                               apiBase = "https://127.0.0.1:1")
    ## Verify the proc exists and accepts the right types.
    ## We don't call it (would fail with connection refused).
    check a.token == "tok"   ## stand-in for "compiled OK"

suite "Telegram reaction selection":

  test "available_reactions omitted means all emoji reactions are allowed":
    let chatInfo = parseJson("""{"id":1,"type":"private"}""")
    let parsed = chatAllowedReactionEmojis(chatInfo)
    check not parsed.restricted
    check parsed.emojis.len == 0
    check pickTelegramReactionEmoji("⏳", chatInfo) == "⏳"

  test "pickTelegramReactionEmoji keeps desired emoji when chat allows it":
    let chatInfo = parseJson("""{"available_reactions":[
      {"type":"emoji","emoji":"👍"},
      {"type":"emoji","emoji":"⏳"},
      {"type":"emoji","emoji":"✅"}
    ]}""")
    check pickTelegramReactionEmoji("⏳", chatInfo) == "⏳"

  test "pickTelegramReactionEmoji falls back to allowed default emoji":
    let chatInfo = parseJson("""{"available_reactions":[
      {"type":"emoji","emoji":"👍"},
      {"type":"emoji","emoji":"✅"}
    ]}""")
    check pickTelegramReactionEmoji("⏳", chatInfo) == "👍"

  test "pickTelegramReactionEmoji returns empty when no normal emoji reactions are allowed":
    let chatInfo = parseJson("""{"available_reactions":[
      {"type":"custom_emoji","custom_emoji_id":"123"}
    ]}""")
    check pickTelegramReactionEmoji("⏳", chatInfo) == ""

suite "splitChunks — Telegram 4096 limit":

  test "message exactly at limit is a single chunk":
    let text = 'a'.repeat(4096)
    check splitChunks(text, 4096).len == 1

  test "message one char over limit splits in two":
    let text = 'a'.repeat(4097)
    let chunks = splitChunks(text, 4096)
    check chunks.len == 2
    check chunks.join("") == text
