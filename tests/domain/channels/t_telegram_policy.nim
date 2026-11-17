## Tests for outbound Telegram policies extracted from the hermes history.
##
## Each test starts with the case id from docs/hermes-mining/telegram/CASES.md.

import std/[json, strutils, unicode, unittest]
import donkey/domain/channels/telegram_policy
import donkey/domain/channels/telegram_pure

suite "telegram_policy — edit errors":

  test "TG-002: \"message is not modified\" is treated as success":
    check isEditNoopError(
      "Telegram API error [editMessageText]: bad request: message is not modified")
    check isEditNoopError("MESSAGE IS NOT MODIFIED")

  test "TG-002: other edit errors are not swallowed":
    check not isEditNoopError("")
    check not isEditNoopError("chat not found")
    check not isEditNoopError(
      "Telegram API error [editMessageText]: message to edit not found")


suite "telegram_policy — reply anchors":

  test "TG-005: a missing reply anchor is recognised":
    check isMissingReplyAnchorError(
      "Telegram API error [sendMessage]: Bad Request: message to be replied not found")
    check isMissingReplyAnchorError("reply message not found")

  test "TG-005: unrelated errors are not treated as a missing anchor":
    check not isMissingReplyAnchorError("chat not found")
    check not isMissingReplyAnchorError("")


suite "telegram_policy — outbound text":

  test "TG-006: empty and whitespace-only text is not sent":
    check shouldSkipOutboundText("")
    check shouldSkipOutboundText("   \n\t ")
    check not shouldSkipOutboundText("oi")


func runeCount(s: string): int =
  for _ in s.runes: inc result

suite "telegram_policy — captions":

  test "TG-007: a long caption is clipped to the 1024 limit":
    let long = strutils.repeat("a", 1500)
    let clipped = clipCaption(long, 1024)
    check runeCount(clipped) <= 1024
    check clipped.endsWith("…")

  test "TG-007: a caption under the limit is unchanged":
    check clipCaption("legenda", 1024) == "legenda"

  test "TG-007: clipping respects character boundaries":
    var text = strutils.repeat("a", 1022)
    text.add("😀😀😀😀")
    let clipped = clipCaption(text, 1024)
    check runeCount(clipped) <= 1024
    check clipped.endsWith("…")


suite "telegram_policy — oversized edits":

  test "TG-008: an oversized edit becomes an edit plus follow-ups":
    let text = strutils.repeat("x", 5000)
    let plan = planEditChunks(text, 4096)
    check plan.len == 2
    check plan[0].len == 4096
    check plan.join("") == text

  test "TG-008: an edit under the limit stays a single chunk":
    check planEditChunks("curto", 4096) == @["curto"]


suite "telegram_policy — callback data":

  test "TG-009: callback data from 1 to 64 bytes is accepted":
    check callbackDataError("models:set:openrouter:abc").len == 0
    check callbackDataError(strutils.repeat("a", 64)).len == 0

  test "TG-009: empty callback data is rejected":
    check callbackDataError("").len > 0

  test "TG-009: callback data above 64 bytes is rejected":
    let reason = callbackDataError(strutils.repeat("a", 65))
    check reason.len > 0
    check "64" in reason


suite "telegram_policy — caption tail":

  test "TG-007: a caption under the limit has no tail":
    let (head, tail) = splitCaption("legenda", 1024)
    check head == "legenda"
    check tail == ""

  test "TG-007: the overflow becomes a tail":
    let text = strutils.repeat("a", 1500)
    let (head, tail) = splitCaption(text, 1024)
    check head.len == 1024
    check head & tail == text

suite "telegram_policy — link previews":

  test "TG-035: previews are disabled by default":
    let body = withLinkPreviewPolicy(%*{"chat_id": 1, "text": "https://x.test"}, false)
    check body["link_preview_options"]["is_disabled"].getBool()

  test "TG-035: the opt-in keeps previews enabled":
    let body = withLinkPreviewPolicy(%*{"chat_id": 1, "text": "https://x.test"}, true)
    check not body.hasKey("link_preview_options")

  test "TG-035: the env flag only accepts an explicit yes":
    for value in ["1", "true", "YES", "on"]:
      check linkPreviewsFromEnv(value)
    for value in ["0", "false", "", "off", "no"]:
      check not linkPreviewsFromEnv(value)

suite "telegram_policy — media fallback":

  test "TG-027: a photo body becomes a document body":
    let body = %*{"chat_id": 1, "photo": "https://x.test/a.jpg", "caption": "oi"}
    let doc = asDocumentBody(body)
    check doc["document"].getStr() == "https://x.test/a.jpg"
    check not doc.hasKey("photo")
    check doc["caption"].getStr() == "oi"

  test "TG-027: a document body is unchanged":
    let body = %*{"chat_id": 1, "document": "https://x.test/a.pdf"}
    check asDocumentBody(body) == body

suite "telegram_policy — audio method":

  test "TG-029: voice notes go through sendVoice":
    check audioMethodFor("https://x.test/a.ogg") == "sendVoice"
    check audioMethodFor("https://x.test/a.opus") == "sendVoice"

  test "TG-029: music goes through sendAudio":
    check audioMethodFor("https://x.test/a.mp3") == "sendAudio"
    check audioMethodFor("https://x.test/a.m4a") == "sendAudio"

  test "TG-029: other media keeps the photo/document path":
    check audioMethodFor("https://x.test/a.jpg") == ""
    check audioMethodFor("https://x.test/a.pdf") == ""
    check audioMethodFor("https://x.test/noext") == ""

suite "telegram_policy — group mentions":

  test "TG-015: an exact mention addresses the bot":
    check isAddressedToBot("hey @donkeybot help", "donkeybot")
    check isAddressedToBot("@DonkeyBot", "donkeybot")

  test "TG-015: a longer handle does not match":
    check not isAddressedToBot("@donkeybot2 help", "donkeybot")
    check not isAddressedToBot("@donkeybot_x", "donkeybot")

  test "TG-015: a message without the mention is not addressed":
    check not isAddressedToBot("bom dia", "donkeybot")
    check not isAddressedToBot("email a@b.com", "donkeybot")

  test "TG-015: an unknown username disables the gate":
    check not isAddressedToBot("@donkeybot", "")

  test "TG-015: the gate is opt-in":
    for value in ["1", "true", "YES", "on"]:
      check mentionRequiredFromEnv(value)
    for value in ["0", "false", "", "off"]:
      check not mentionRequiredFromEnv(value)

suite "telegram_policy — forum threads":

  test "TG-025: the reply target carries the thread":
    check telegramReplyTarget("42", "") == "42"
    check telegramReplyTarget("42", "7") == "42#t7"
    check splitTelegramReplyTarget("42#t7") == ("42", "7")
    check splitTelegramReplyTarget("42") == ("42", "")

  test "TG-026: a missing thread is recognised":
    check isMissingThreadError("Bad Request: message thread not found")
    check isMissingThreadError("MESSAGE THREAD NOT FOUND")
    check not isMissingThreadError("message to be replied not found")

  test "TG-029: a query string does not confuse the extension":
    check audioMethodFor("https://x.test/a.ogg?token=1") == "sendVoice"
    check audioMethodFor("https://x.test/a.mp3#t=3") == "sendAudio"

  test "TG-029: other audio formats stay documents":
    check audioMethodFor("https://x.test/a.flac") == ""
    check audioMethodFor("https://x.test/a.wav") == ""

  test "TG-015: an email address is not a mention":
    check not isAddressedToBot("escreva para contato@donkeybot.com", "donkeybot")
    check isAddressedToBot("/status@donkeybot", "donkeybot")

suite "telegram_policy — album mention gate":

  test "TG-028: an addressed album admits its siblings":
    let gate = newAlbumMentionGate()
    let key = albumKey("u1", "g1")
    gate.rememberAddressedAlbum(key, 1_000)
    check gate.albumAddressed(key, 1_500)
    check not gate.albumAddressed(albumKey("u1", "g2"), 1_500)
    check not gate.albumAddressed(albumKey("u2", "g1"), 1_500)

  test "TG-028: the window expires":
    let gate = newAlbumMentionGate()
    let key = albumKey("u1", "g1")
    gate.rememberAddressedAlbum(key, 1_000, ttlMs = 500)
    check not gate.albumAddressed(key, 1_600)

  test "TG-028: a message without a group is never admitted":
    let gate = newAlbumMentionGate()
    gate.rememberAddressedAlbum(albumKey("u1", ""), 1_000)
    check not gate.albumAddressed("", 1_000)
