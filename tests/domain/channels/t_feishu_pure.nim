## Tests for domain/channels/feishu_pure.nim — pure Feishu/Lark event parser.
## No I/O or HTTP; all input is constructed directly as JsonNode.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/channels/feishu_pure
import donkey/core/types

# ── Fixtures ──────────────────────────────────────────────────────────────────

func makeVerificationPayload(challenge: string): JsonNode =
  %* {"type": "url_verification", "challenge": challenge, "token": "tok"}

func makeSenderNode(openId: string): JsonNode =
  %* {"sender_id": {"open_id": openId, "union_id": "uid1", "user_id": "usr1"},
      "sender_type": "user"}

func makeMessageNode(msgId, msgType, chatId, chatType,
                     content: string): JsonNode =
  %* {"message_id": msgId, "message_type": msgType, "chat_id": chatId,
      "chat_type": chatType, "content": content}

func makeReceivePayload(openId, msgId, msgType, chatId, chatType,
                        content: string): JsonNode =
  %* {
    "schema": "2.0",
    "header": {
      "event_id": "ev1",
      "event_type": "im.message.receive_v1",
      "app_id": "cli_app1",
      "tenant_key": "tenant1"
    },
    "event": {
      "sender":  makeSenderNode(openId),
      "message": makeMessageNode(msgId, msgType, chatId, chatType, content)
    }
  }

func makeOtherEventPayload(eventType: string): JsonNode =
  %* {
    "schema": "2.0",
    "header": {"event_type": eventType, "event_id": "ev2", "app_id": "cli_app1"}
  }

# ── extractJsonStr tests ───────────────────────────────────────────────────────

suite "extractJsonStr":
  test "extracts text field":
    let encoded = "{\"text\":\"hello world\"}"
    check extractJsonStr("text", encoded) == "hello world"

  test "extracts image_key field":
    let encoded = "{\"image_key\":\"img_abc123\"}"
    check extractJsonStr("image_key", encoded) == "img_abc123"

  test "extracts file_key field":
    let encoded = "{\"file_key\":\"file_xyz\",\"duration\":5000}"
    check extractJsonStr("file_key", encoded) == "file_xyz"

  test "returns empty when key absent":
    let encoded = "{\"text\":\"hi\"}"
    check extractJsonStr("image_key", encoded) == ""

  test "returns empty for empty string":
    check extractJsonStr("text", "") == ""

  test "handles escaped quotes in value":
    let encoded = "{\"text\":\"say \\\"hello\\\"\"}"
    check extractJsonStr("text", encoded) == "say \"hello\""

  test "works with |>-> syntax":
    let encoded = "{\"text\":\"piped\"}"
    let got = encoded |>-> extractJsonStr("text")
    check got == "piped"

# ── isVerification / url_verification ─────────────────────────────────────────

suite "parseEvent url_verification":
  test "parses url_verification challenge":
    let r = makeVerificationPayload("abc123") |> parseEvent
    check r.kind == fmkEvent
    check r.eventType == "url_verification"
    check r.challenge == "abc123"
    check r.isVerification

  test "isVerification returns false for non-challenge events":
    let r = makeReceivePayload("ou_x", "om_1", "text", "oc_1", "p2p",
                               "{\"text\":\"hi\"}") |> parseEvent
    check not r.isVerification

  test "nil payload returns fmkUnknown":
    let r = parseEvent(nil)
    check r.kind == fmkUnknown

  test "empty object returns fmkUnknown":
    let r = newJObject() |> parseEvent
    check r.kind == fmkUnknown

# ── parseEvent — text ──────────────────────────────────────────────────────────

suite "parseEvent text":
  test "parses text message":
    let r = makeReceivePayload("ou_alice", "om_001", "text",
                               "oc_chat1", "p2p",
                               "{\"text\":\"Hello!\"}") |> parseEvent
    check r.kind == fmkText
    check r.rawId == "ou_alice"
    check r.messageId == "om_001"
    check r.text == "Hello!"
    check r.chatId == "oc_chat1"
    check r.chatType == "p2p"
    check r.eventType == "im.message.receive_v1"
    check r.fileKey == ""

  test "text in group chat":
    let r = makeReceivePayload("ou_bob", "om_002", "text",
                               "oc_group1", "group",
                               "{\"text\":\"@all Good morning\"}") |> parseEvent
    check r.kind == fmkText
    check r.chatType == "group"
    check r.text == "@all Good morning"

  test "text with empty content":
    let r = makeReceivePayload("ou_alice", "om_003", "text",
                               "oc_chat1", "p2p", "{\"text\":\"\"}") |> parseEvent
    check r.kind == fmkText
    check r.text == ""

  test "hasMedia returns false for text":
    let r = makeReceivePayload("ou_alice", "om_004", "text",
                               "oc_chat1", "p2p",
                               "{\"text\":\"hi\"}") |> parseEvent
    check not r.hasMedia

# ── parseEvent — image ─────────────────────────────────────────────────────────

suite "parseEvent image":
  test "parses image message":
    let r = makeReceivePayload("ou_alice", "om_010", "image",
                               "oc_chat1", "p2p",
                               "{\"image_key\":\"img_abc\"}") |> parseEvent
    check r.kind == fmkImage
    check r.rawId == "ou_alice"
    check r.messageId == "om_010"
    check r.fileKey == "img_abc"
    check r.text == ""

  test "hasMedia returns true for image":
    let r = makeReceivePayload("ou_alice", "om_011", "image",
                               "oc_chat1", "p2p",
                               "{\"image_key\":\"img_xyz\"}") |> parseEvent
    check r.hasMedia

# ── parseEvent — audio ─────────────────────────────────────────────────────────

suite "parseEvent audio":
  test "parses audio message":
    let r = makeReceivePayload("ou_alice", "om_020", "audio",
                               "oc_chat1", "p2p",
                               "{\"file_key\":\"aud_123\",\"duration\":3000}") |> parseEvent
    check r.kind == fmkAudio
    check r.fileKey == "aud_123"
    check r.text == ""

  test "hasMedia returns true for audio":
    let r = makeReceivePayload("ou_alice", "om_021", "audio",
                               "oc_chat1", "p2p",
                               "{\"file_key\":\"aud_456\"}") |> parseEvent
    check r.hasMedia

# ── parseEvent — file ─────────────────────────────────────────────────────────

suite "parseEvent file":
  test "parses file message":
    let r = makeReceivePayload("ou_alice", "om_030", "file",
                               "oc_chat1", "p2p",
                               "{\"file_key\":\"fil_789\",\"file_name\":\"doc.pdf\"}") |> parseEvent
    check r.kind == fmkFile
    check r.fileKey == "fil_789"

  test "hasMedia returns true for file":
    let r = makeReceivePayload("ou_alice", "om_031", "file",
                               "oc_chat1", "p2p",
                               "{\"file_key\":\"fil_abc\"}") |> parseEvent
    check r.hasMedia

# ── parseEvent — sticker ──────────────────────────────────────────────────────

suite "parseEvent sticker":
  test "parses sticker message":
    let r = makeReceivePayload("ou_alice", "om_040", "sticker",
                               "oc_chat1", "p2p",
                               "{\"file_key\":\"stk_001\"}") |> parseEvent
    check r.kind == fmkSticker
    check r.fileKey == "stk_001"

  test "hasMedia returns true for sticker":
    let r = makeReceivePayload("ou_alice", "om_041", "sticker",
                               "oc_chat1", "p2p",
                               "{\"file_key\":\"stk_002\"}") |> parseEvent
    check r.hasMedia

# ── parseEvent — interactive ──────────────────────────────────────────────────

suite "parseEvent interactive":
  test "parses interactive (card) message":
    let r = makeReceivePayload("ou_alice", "om_050", "interactive",
                               "oc_chat1", "p2p", "{}") |> parseEvent
    check r.kind == fmkInteractive
    check r.rawId == "ou_alice"
    check r.fileKey == ""
    check r.text == ""

  test "hasMedia returns false for interactive":
    let r = makeReceivePayload("ou_alice", "om_051", "interactive",
                               "oc_chat1", "p2p", "{}") |> parseEvent
    check not r.hasMedia

# ── parseEvent — non-message events ───────────────────────────────────────────

suite "parseEvent other events":
  test "parses p2p_chat_create as fmkEvent":
    let r = makeOtherEventPayload("p2p_chat_create") |> parseEvent
    check r.kind == fmkEvent
    check r.eventType == "p2p_chat_create"
    check not r.isVerification

  test "unknown event_type returns fmkUnknown":
    let r = makeOtherEventPayload("") |> parseEvent
    check r.kind == fmkUnknown

  test "missing header returns fmkUnknown":
    let payload = %* {"schema": "2.0", "event": {}}
    check (payload |> parseEvent).kind == fmkUnknown

  test "unknown message_type returns fmkUnknown":
    let r = makeReceivePayload("ou_alice", "om_099", "location",
                               "oc_chat1", "p2p", "{}") |> parseEvent
    check r.kind == fmkUnknown

# ── toInbound ────────────────────────────────────────────────────────────────

suite "toInbound":
  test "maps text message to InboundMessage":
    let r = makeReceivePayload("ou_alice", "om_001", "text",
                               "oc_chat1", "p2p",
                               "{\"text\":\"Hello!\"}") |> parseEvent
    let msg = r.toInbound(UserId("user-42"))
    check msg.userId == UserId("user-42")
    check msg.channel == ckFeishu
    check msg.channelId == "om_001"
    check msg.text == "Hello!"
    check msg.mediaUrl == ""

  test "maps image message — fileKey goes to mediaUrl":
    let r = makeReceivePayload("ou_alice", "om_010", "image",
                               "oc_chat1", "p2p",
                               "{\"image_key\":\"img_abc\"}") |> parseEvent
    let msg = r.toInbound(UserId("user-42"))
    check msg.mediaUrl == "img_abc"
    check msg.text == ""

  test "maps file message — file_key goes to mediaUrl":
    let r = makeReceivePayload("ou_alice", "om_030", "file",
                               "oc_chat1", "p2p",
                               "{\"file_key\":\"fil_789\"}") |> parseEvent
    let msg = r.toInbound(UserId("user-42"))
    check msg.mediaUrl == "fil_789"
