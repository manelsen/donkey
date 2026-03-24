## Tests for domain/channels/matrix_pure — pure Matrix event parsing.
##
## All tests are deterministic: no I/O, no filesystem, no network.
## Covers: parseEvent (all msgtypes), toInbound, hasMedia.
##
## Topology exercised:
##   |>    — payload |> parseEvent
##   |>->  — node |>-> getStr (via parseEvent internals)

import std/[json, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/matrix_pure
import donkey/domain/message

# ── helpers ───────────────────────────────────────────────────────────────────

proc msgEvent(msgtype, body, roomId, sender, eventId: string;
              url: string = ""): JsonNode =
  result = %* {
    "type":     "m.room.message",
    "room_id":  roomId,
    "event_id": eventId,
    "sender":   sender,
    "content": {
      "msgtype": msgtype,
      "body":    body,
    }
  }
  if url.len > 0:
    result["content"]["url"] = %url

proc textEvent(body: string = "hello"; room: string = "!room:server";
               sender: string = "@user:server"; evId: string = "$ev1:server"): JsonNode =
  msgEvent("m.text", body, room, sender, evId)

# ── parseEvent — text variants ────────────────────────────────────────────────

suite "matrix_pure — parseEvent text":

  test "parses m.text event":
    let r = textEvent("Hello, Matrix!") |> parseEvent
    check r.kind == mxkText
    check r.text == "Hello, Matrix!"
    check r.roomId == "!room:server"
    check r.senderId == "@user:server"
    check r.eventId == "$ev1:server"
    check r.mediaUrl == ""

  test "parses m.notice event as text":
    let n = msgEvent("m.notice", "A notice", "!r:s", "@bot:s", "$n1:s")
    let r = n |> parseEvent
    check r.kind == mxkText
    check r.text == "A notice"

  test "parses m.emote event as text":
    let n = msgEvent("m.emote", "*waves*", "!r:s", "@u:s", "$e1:s")
    let r = n |> parseEvent
    check r.kind == mxkText
    check r.text == "*waves*"

  test "pipeops |> parseEvent works":
    let r = textEvent("pipeline test") |> parseEvent
    check r.kind == mxkText
    check r.text == "pipeline test"

# ── parseEvent — media variants ───────────────────────────────────────────────

suite "matrix_pure — parseEvent media":

  test "parses m.image event":
    let n = msgEvent("m.image", "photo.jpg", "!r:s", "@u:s", "$img1:s",
                     url = "mxc://server/abc123")
    let r = n |> parseEvent
    check r.kind == mxkImage
    check r.mediaUrl == "mxc://server/abc123"
    check r.text == ""

  test "parses m.audio event":
    let n = msgEvent("m.audio", "clip.ogg", "!r:s", "@u:s", "$aud1:s",
                     url = "mxc://server/audio1")
    let r = n |> parseEvent
    check r.kind == mxkAudio
    check r.mediaUrl == "mxc://server/audio1"

  test "parses m.video event":
    let n = msgEvent("m.video", "video.mp4", "!r:s", "@u:s", "$vid1:s",
                     url = "mxc://server/vid1")
    let r = n |> parseEvent
    check r.kind == mxkVideo

  test "parses m.file event":
    let n = msgEvent("m.file", "doc.pdf", "!r:s", "@u:s", "$f1:s",
                     url = "mxc://server/file1")
    let r = n |> parseEvent
    check r.kind == mxkFile
    check r.mediaUrl == "mxc://server/file1"

# ── parseEvent — rejection cases ─────────────────────────────────────────────

suite "matrix_pure — parseEvent rejections":

  test "nil payload returns mxkUnknown":
    let r = parseEvent(nil)
    check r.kind == mxkUnknown

  test "non-message event type returns mxkUnknown":
    let n = %* {"type": "m.room.member", "room_id": "!r:s",
                "event_id": "$e:s", "sender": "@u:s"}
    let r = n |> parseEvent
    check r.kind == mxkUnknown

  test "missing room_id returns mxkUnknown":
    let n = %* {"type": "m.room.message", "event_id": "$e:s",
                "sender": "@u:s",
                "content": {"msgtype": "m.text", "body": "hi"}}
    let r = n |> parseEvent
    check r.kind == mxkUnknown

  test "missing sender returns mxkUnknown":
    let n = %* {"type": "m.room.message", "room_id": "!r:s",
                "event_id": "$e:s",
                "content": {"msgtype": "m.text", "body": "hi"}}
    let r = n |> parseEvent
    check r.kind == mxkUnknown

  test "unknown msgtype returns mxkUnknown":
    let n = msgEvent("m.sticker", "sticker", "!r:s", "@u:s", "$s1:s")
    let r = n |> parseEvent
    check r.kind == mxkUnknown

  test "empty JSON object returns mxkUnknown":
    let r = (%* {}) |> parseEvent
    check r.kind == mxkUnknown

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "matrix_pure — toInbound":

  test "maps text event to InboundMessage":
    let r = MxParseResult(
      kind:     mxkText,
      roomId:   "!myroom:server",
      senderId: "@alice:server",
      eventId:  "$ev42:server",
      text:     "Hello world",
    )
    let uid = UserId("uuid-alice")
    let msg = r.toInbound(uid)
    check msg.userId == uid
    check msg.channel == ckMatrix
    check msg.channelId == "$ev42:server"
    check msg.text == "Hello world"
    check msg.mediaUrl == ""

  test "maps image event with mxc URL":
    let r = MxParseResult(
      kind:     mxkImage,
      eventId:  "$imgev:server",
      mediaUrl: "mxc://server/xyz",
    )
    let msg = r.toInbound(UserId("u"))
    check msg.channelId == "$imgev:server"
    check msg.mediaUrl == "mxc://server/xyz"
    check msg.text == ""

  test "channelId is event_id (unique per event)":
    let r = MxParseResult(kind: mxkText, eventId: "$uniq1:s")
    let msg = r.toInbound(UserId("u"))
    check msg.channelId == "$uniq1:s"

# ── hasMedia ──────────────────────────────────────────────────────────────────

suite "matrix_pure — hasMedia":

  test "false for text":
    check not MxParseResult(kind: mxkText).hasMedia

  test "false for unknown":
    check not MxParseResult(kind: mxkUnknown).hasMedia

  test "true for image":
    check MxParseResult(kind: mxkImage).hasMedia

  test "true for audio":
    check MxParseResult(kind: mxkAudio).hasMedia

  test "true for video":
    check MxParseResult(kind: mxkVideo).hasMedia

  test "true for file":
    check MxParseResult(kind: mxkFile).hasMedia

# ── integration — round-trip ──────────────────────────────────────────────────

suite "matrix_pure — integration round-trip":

  test "full pipeline: JSON → parseEvent → toInbound":
    let payload = textEvent("integration test", "!chatroom:matrix.org",
                            "@bot:matrix.org", "$event99:matrix.org")
    let uid = UserId("user-id-99")
    let r   = payload |> parseEvent
    let msg = r.toInbound(uid)
    check r.kind == mxkText
    check r.text == "integration test"
    check msg.channel == ckMatrix
    check msg.text == "integration test"
    check msg.userId == uid

  test "media pipeline: image event → hasMedia check":
    let payload = msgEvent("m.image", "photo.jpg", "!r:s", "@u:s", "$i:s",
                           url = "mxc://matrix.org/img1")
    let r = payload |> parseEvent
    check r.hasMedia
    check r.mediaUrl == "mxc://matrix.org/img1"
