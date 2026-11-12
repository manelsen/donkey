## Tests for domain/channels/telegram_pure.nim — pure Telegram update parser.
## No I/O or HTTP; all input is constructed directly as JsonNode.

import std/[json, unittest]
import donkey/domain/channels/telegram_pure
import donkey/core/pipeops
import donkey/core/types

# ── Fixtures ──────────────────────────────────────────────────────────────────

func makeTextUpdate(updateId: int; fromId: int64; chatId: int64;
                    chatType, text: string): JsonNode =
  %* {
    "update_id": updateId,
    "message": {
      "message_id": 42,
      "from": {"id": fromId, "first_name": "Alice"},
      "chat": {"id": chatId, "type": chatType},
      "text": text,
    }
  }

func makeMediaUpdate(updateId: int; fromId: int64;
                     kind: string): JsonNode =
  var msg = %* {
    "message_id": 99,
    "from": {"id": fromId, "first_name": "Bob"},
    "chat": {"id": fromId, "type": "private"},
    "caption": "look at this",
  }
  case kind
  of "photo":
    msg["photo"] = %* [
      {"file_id": "small_id", "width": 90, "height": 90},
      {"file_id": "big_id",   "width": 800, "height": 600},
    ]
  of "document":
    msg["document"] = %* {"file_id": "doc_id", "file_name": "file.pdf"}
  of "voice":
    msg["voice"] = %* {"file_id": "voice_id", "duration": 3}
  else: discard
  %* {"update_id": updateId, "message": msg}

func makeCallbackUpdate(updateId: int; fromId: int64;
                        data, cbId: string): JsonNode =
  %* {
    "update_id": updateId,
    "callback_query": {
      "id": cbId,
      "from": {"id": fromId, "first_name": "Eve"},
      "data": data,
      "message": {"message_id": 77},
    }
  }

func makeEmptyMsgUpdate(updateId: int; fromId: int64): JsonNode =
  ## A message with no text, no caption, no media — should parse as tukUnknown.
  %* {
    "update_id": updateId,
    "message": {
      "message_id": 1,
      "from": {"id": fromId},
      "chat": {"id": fromId, "type": "private"},
    }
  }

func makeUnknownUpdate(updateId: int): JsonNode =
  ## An update type we don't handle (e.g. channel_post).
  %* {"update_id": updateId, "channel_post": {"text": "news"}}

# ── parseUpdate ───────────────────────────────────────────────────────────────

suite "telegram_pure.parseUpdate — text message":

  test "kind is tukMessage for a text update":
    let upd = makeTextUpdate(1, 111, 111, "private", "hello")
    let r = upd |> parseUpdate
    check r.kind == tukMessage

  test "rawId matches from.id":
    let upd = makeTextUpdate(2, 222, 222, "private", "hi")
    let r = upd |> parseUpdate
    check r.rawId == "222"

  test "sessionKey equals from.id for private chat":
    let upd = makeTextUpdate(3, 333, 333, "private", "hey")
    let r = upd |> parseUpdate
    check r.sessionKey == "333"

  test "sessionKey equals chat.id for group chat":
    let upd = makeTextUpdate(4, 444, 9001, "group", "sup")
    let r = upd |> parseUpdate
    check r.sessionKey == "9001"

  test "sessionKey equals chat.id for supergroup":
    let upd = makeTextUpdate(5, 555, 9002, "supergroup", "yo")
    let r = upd |> parseUpdate
    check r.sessionKey == "9002"

  test "text is captured":
    let upd = makeTextUpdate(6, 666, 666, "private", "I want pizza")
    let r = upd |> parseUpdate
    check r.text == "I want pizza"

  test "channelId matches message_id":
    let upd = makeTextUpdate(7, 777, 777, "private", "ok")
    let r = upd |> parseUpdate
    check r.channelId == "42"

  test "no media for plain text":
    let upd = makeTextUpdate(8, 888, 888, "private", "text only")
    let r = upd |> parseUpdate
    check not r.hasMedia
    check r.mediaFileId == ""

  test "empty-content message returns tukUnknown":
    let upd = makeEmptyMsgUpdate(9, 999)
    let r = upd |> parseUpdate
    check r.kind == tukUnknown

suite "telegram_pure.parseUpdate — media":

  test "photo: hasMedia is true, picks largest variant":
    let upd = makeMediaUpdate(10, 1001, "photo")
    let r = upd |> parseUpdate
    check r.kind == tukMessage
    check r.hasMedia
    check r.mediaFileId == "big_id"

  test "photo: caption becomes text":
    let upd = makeMediaUpdate(11, 1002, "photo")
    let r = upd |> parseUpdate
    check r.text == "look at this"

  test "document: hasMedia is true":
    let upd = makeMediaUpdate(12, 1003, "document")
    let r = upd |> parseUpdate
    check r.hasMedia
    check r.mediaFileId == "doc_id"

  test "voice: hasMedia is true":
    let upd = makeMediaUpdate(13, 1004, "voice")
    let r = upd |> parseUpdate
    check r.hasMedia
    check r.mediaFileId == "voice_id"

suite "telegram_pure.parseUpdate — callback_query":

  test "kind is tukCallbackQuery":
    let upd = makeCallbackUpdate(20, 2001, "yes", "cb-42")
    let r = upd |> parseUpdate
    check r.kind == tukCallbackQuery

  test "text is /callback <data>":
    let upd = makeCallbackUpdate(21, 2002, "no", "cb-43")
    let r = upd |> parseUpdate
    check r.text == "/callback no"

  test "callbackId is populated":
    let upd = makeCallbackUpdate(22, 2003, "ok", "cb-44")
    let r = upd |> parseUpdate
    check r.callbackId == "cb-44"

  test "hasCallbackId is true":
    let upd = makeCallbackUpdate(23, 2004, "nope", "cb-45")
    let r = upd |> parseUpdate
    check r.hasCallbackId

  test "rawId comes from from.id":
    let upd = makeCallbackUpdate(24, 2005, "x", "cb-46")
    let r = upd |> parseUpdate
    check r.rawId == "2005"

  test "unknown update returns tukUnknown":
    let upd = makeUnknownUpdate(30)
    let r = upd |> parseUpdate
    check r.kind == tukUnknown

# ── parseUpdates ──────────────────────────────────────────────────────────────

suite "telegram_pure.parseUpdates — batch":

  test "returns only actionable results":
    let arr = %* [
      makeTextUpdate(1, 100, 100, "private", "hello"),
      makeUnknownUpdate(2),
      makeCallbackUpdate(3, 200, "yes", "cb1"),
    ]
    let results = arr |> parseUpdates
    check results.len == 2
    check results[0].kind == tukMessage
    check results[1].kind == tukCallbackQuery

  test "empty array returns empty seq":
    let arr = newJArray()
    let results = arr |> parseUpdates
    check results.len == 0

  test "all unknowns returns empty seq":
    let arr = %* [makeUnknownUpdate(1), makeUnknownUpdate(2)]
    let results = arr |> parseUpdates
    check results.len == 0

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "telegram_pure.toInbound":

  test "converts TgParseResult to InboundMessage":
    let upd = makeTextUpdate(40, 4001, 4001, "private", "convert me")
    let r   = upd |> parseUpdate
    let uid = UserId("test-uuid")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckTelegram
    check msg.text == "convert me"
    check msg.channelId == "42"
    check msg.rawChannelId == "4001"
    check msg.mediaUrl == ""

  test "mediaUrl is forwarded":
    let upd = makeMediaUpdate(41, 4002, "photo")
    let r   = upd |> parseUpdate
    let uid = UserId("uuid-2")
    let msg = r.toInbound(uid, "https://cdn.example.com/photo.jpg")
    check msg.mediaUrl == "https://cdn.example.com/photo.jpg"

# ── maxNextOffset ─────────────────────────────────────────────────────────────

suite "telegram_pure.maxNextOffset":

  test "returns max update_id + 1":
    let arr = %* [
      {"update_id": 10, "message": {}},
      {"update_id": 15, "message": {}},
      {"update_id": 12, "message": {}},
    ]
    check maxNextOffset(0, arr) == 16

  test "returns currentOffset when array is empty":
    let arr = newJArray()
    check maxNextOffset(5, arr) == 5

  test "returns currentOffset when all ids are below it":
    ## Should not happen in normal operation but must be safe.
    let arr = %* [{"update_id": 3, "message": {}}]
    check maxNextOffset(10, arr) == 10

  test "pipe variant: |>-> maxNextOffset(offset)":
    let arr = %* [{"update_id": 7}, {"update_id": 9}]
    let next = arr |>-> maxNextOffset(0)
    check next == 10
