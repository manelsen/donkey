## Tests for domain/channels/dingtalk_pure.nim — pure DingTalk Stream event parser.
## No I/O or HTTP; all input is constructed directly as JsonNode.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/channels/dingtalk_pure
import donkey/core/types

# ── Fixtures ──────────────────────────────────────────────────────────────────

func makeTextPayload(senderId, msgId, content: string;
                     convType = "1"; convId = "cid_xxx"): JsonNode =
  %* {
    "msgtype": "text",
    "text": {"content": content},
    "msgId": msgId,
    "senderId": senderId,
    "senderNick": "TestUser",
    "senderStaffId": "staff_001",
    "conversationId": convId,
    "conversationType": convType,
    "robotCode": "robot_xxx"
  }

func makeMarkdownPayload(senderId, msgId, content: string): JsonNode =
  %* {
    "msgtype": "markdown",
    "text": {"content": content},
    "msgId": msgId,
    "senderId": senderId,
    "conversationId": "cid_xxx",
    "conversationType": "1"
  }

func makeMediaPayload(msgType, senderId, msgId, contentJson: string;
                      convType = "1"): JsonNode =
  %* {
    "msgtype": msgType,
    "content": contentJson,
    "msgId": msgId,
    "senderId": senderId,
    "conversationId": "cid_xxx",
    "conversationType": convType
  }

# ── parseEvent — text ─────────────────────────────────────────────────────────

suite "parseEvent text":
  test "parses private text message":
    let r = makeTextPayload("sender_001", "msg_001", "hello") |> parseEvent
    check r.kind == dtkText
    check r.rawId == "sender_001"
    check r.messageId == "msg_001"
    check r.text == "hello"
    check not r.isGroup

  test "parses group text message":
    let r = makeTextPayload("sender_002", "msg_002", "hi group",
                            convType = "2", convId = "cid_group_x") |> parseEvent
    check r.kind == dtkText
    check r.rawId == "sender_002"
    check r.text == "hi group"
    check r.isGroup
    check r.conversationId == "cid_group_x"

  test "text with empty content":
    let r = makeTextPayload("sender_003", "msg_003", "") |> parseEvent
    check r.kind == dtkText
    check r.text == ""

  test "text hasMedia returns false":
    let r = makeTextPayload("sender_001", "msg_001", "hi") |> parseEvent
    check not r.hasMedia

# ── parseEvent — markdown ─────────────────────────────────────────────────────

suite "parseEvent markdown":
  test "parses markdown message as dtkText":
    let r = makeMarkdownPayload("sender_010", "msg_010", "# Header") |> parseEvent
    check r.kind == dtkText
    check r.rawId == "sender_010"
    check r.text == "# Header"

# ── parseEvent — picture ──────────────────────────────────────────────────────

suite "parseEvent picture":
  test "parses picture message":
    let r = makeMediaPayload("picture", "sender_020", "msg_020",
                             "{\"downloadCode\":\"dlcode_img\",\"type\":\"jpeg\"}") |> parseEvent
    check r.kind == dtkImage
    check r.rawId == "sender_020"
    check r.messageId == "msg_020"
    check r.downloadCode == "dlcode_img"
    check r.hasMedia

  test "hasMedia returns true for picture":
    let r = makeMediaPayload("picture", "s", "m",
                             "{\"downloadCode\":\"dc\"}") |> parseEvent
    check r.hasMedia

# ── parseEvent — audio ────────────────────────────────────────────────────────

suite "parseEvent audio":
  test "parses audio message":
    let r = makeMediaPayload("audio", "sender_030", "msg_030",
                             "{\"downloadCode\":\"dlcode_audio\",\"duration\":5000}") |> parseEvent
    check r.kind == dtkAudio
    check r.downloadCode == "dlcode_audio"
    check r.hasMedia

# ── parseEvent — video ────────────────────────────────────────────────────────

suite "parseEvent video":
  test "parses video message":
    let r = makeMediaPayload("video", "sender_040", "msg_040",
                             "{\"downloadCode\":\"dlcode_video\",\"videoType\":\"mp4\"}") |> parseEvent
    check r.kind == dtkVideo
    check r.downloadCode == "dlcode_video"
    check r.hasMedia

# ── parseEvent — file ─────────────────────────────────────────────────────────

suite "parseEvent file":
  test "parses file message":
    let r = makeMediaPayload("file", "sender_050", "msg_050",
                             "{\"downloadCode\":\"dlcode_file\",\"fileName\":\"doc.pdf\"}") |> parseEvent
    check r.kind == dtkFile
    check r.downloadCode == "dlcode_file"
    check r.hasMedia

# ── parseEvent — edge cases ───────────────────────────────────────────────────

suite "parseEvent edge cases":
  test "nil payload returns dtkUnknown":
    let r = parseEvent(nil)
    check r.kind == dtkUnknown

  test "empty object returns dtkUnknown":
    let r = newJObject() |> parseEvent
    check r.kind == dtkUnknown

  test "missing senderId returns dtkUnknown":
    let payload = %* {"msgtype": "text", "text": {"content": "hi"},
                      "msgId": "m1", "conversationId": "c1",
                      "conversationType": "1"}
    check (payload |> parseEvent).kind == dtkUnknown

  test "missing msgId returns dtkUnknown":
    let payload = %* {"msgtype": "text", "text": {"content": "hi"},
                      "senderId": "s1", "conversationId": "c1",
                      "conversationType": "1"}
    check (payload |> parseEvent).kind == dtkUnknown

  test "unknown msgtype returns dtkUnknown":
    let payload = %* {"msgtype": "location", "senderId": "s1",
                      "msgId": "m1", "conversationId": "c1",
                      "conversationType": "1"}
    check (payload |> parseEvent).kind == dtkUnknown

  test "picture missing downloadCode yields empty downloadCode":
    let r = makeMediaPayload("picture", "s", "m", "{}") |> parseEvent
    check r.kind == dtkImage
    check r.downloadCode == ""

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "toInbound":
  test "maps text message to InboundMessage":
    let r = makeTextPayload("sender_001", "msg_001", "Hello!") |> parseEvent
    let msg = r.toInbound(UserId("user-42"))
    check msg.userId == UserId("user-42")
    check msg.channel == ckDingTalk
    check msg.channelId == "msg_001"
    check msg.text == "Hello!"
    check msg.mediaUrl == ""

  test "maps picture message — downloadCode goes to mediaUrl":
    let r = makeMediaPayload("picture", "s", "msg_020",
                             "{\"downloadCode\":\"dc_img\"}") |> parseEvent
    let msg = r.toInbound(UserId("user-42"))
    check msg.mediaUrl == "dc_img"
    check msg.text == ""

  test "maps file message — downloadCode goes to mediaUrl":
    let r = makeMediaPayload("file", "s", "msg_050",
                             "{\"downloadCode\":\"dc_file\"}") |> parseEvent
    let msg = r.toInbound(UserId("user-42"))
    check msg.mediaUrl == "dc_file"

  test "maps group text — channelId is msgId":
    let r = makeTextPayload("sender_002", "msg_grp", "greet",
                            convType = "2") |> parseEvent
    let msg = r.toInbound(UserId("user-99"))
    check msg.channelId == "msg_grp"
    check msg.channel == ckDingTalk
