## Tests for domain/channels/wechat_pure.nim — pure WeChat/WeCom XML parser.
## No I/O or HTTP; all input is constructed directly as XML strings.

import std/[strutils, unittest]
import donkey/core/pipeops
import donkey/domain/channels/wechat_pure
import donkey/core/types

# ── Fixtures ──────────────────────────────────────────────────────────────────

func makeTextXml(fromUser, msgId, content: string): string =
  "<xml>" &
  "<ToUserName><![CDATA[toUser]]></ToUserName>" &
  "<FromUserName><![CDATA[" & fromUser & "]]></FromUserName>" &
  "<CreateTime>1348831860</CreateTime>" &
  "<MsgType><![CDATA[text]]></MsgType>" &
  "<Content><![CDATA[" & content & "]]></Content>" &
  "<MsgId>" & msgId & "</MsgId>" &
  "</xml>"

func makeImageXml(fromUser, msgId, mediaId, picUrl: string): string =
  "<xml>" &
  "<ToUserName><![CDATA[toUser]]></ToUserName>" &
  "<FromUserName><![CDATA[" & fromUser & "]]></FromUserName>" &
  "<CreateTime>1348831861</CreateTime>" &
  "<MsgType><![CDATA[image]]></MsgType>" &
  "<PicUrl><![CDATA[" & picUrl & "]]></PicUrl>" &
  "<MediaId><![CDATA[" & mediaId & "]]></MediaId>" &
  "<MsgId>" & msgId & "</MsgId>" &
  "</xml>"

func makeVoiceXml(fromUser, msgId, mediaId: string): string =
  "<xml>" &
  "<ToUserName><![CDATA[toUser]]></ToUserName>" &
  "<FromUserName><![CDATA[" & fromUser & "]]></FromUserName>" &
  "<CreateTime>1348831862</CreateTime>" &
  "<MsgType><![CDATA[voice]]></MsgType>" &
  "<MediaId><![CDATA[" & mediaId & "]]></MediaId>" &
  "<Format><![CDATA[amr]]></Format>" &
  "<MsgId>" & msgId & "</MsgId>" &
  "</xml>"

func makeVideoXml(fromUser, msgId, mediaId: string): string =
  "<xml>" &
  "<ToUserName><![CDATA[toUser]]></ToUserName>" &
  "<FromUserName><![CDATA[" & fromUser & "]]></FromUserName>" &
  "<CreateTime>1348831863</CreateTime>" &
  "<MsgType><![CDATA[video]]></MsgType>" &
  "<MediaId><![CDATA[" & mediaId & "]]></MediaId>" &
  "<ThumbMediaId><![CDATA[thumb123]]></ThumbMediaId>" &
  "<MsgId>" & msgId & "</MsgId>" &
  "</xml>"

func makeShortVideoXml(fromUser, msgId, mediaId: string): string =
  "<xml>" &
  "<ToUserName><![CDATA[toUser]]></ToUserName>" &
  "<FromUserName><![CDATA[" & fromUser & "]]></FromUserName>" &
  "<CreateTime>1348831864</CreateTime>" &
  "<MsgType><![CDATA[shortvideo]]></MsgType>" &
  "<MediaId><![CDATA[" & mediaId & "]]></MediaId>" &
  "<ThumbMediaId><![CDATA[thumb456]]></ThumbMediaId>" &
  "<MsgId>" & msgId & "</MsgId>" &
  "</xml>"

func makeFileXml(fromUser, msgId, mediaId: string): string =
  ## WeCom-style file message
  "<xml>" &
  "<ToUserName><![CDATA[toUser]]></ToUserName>" &
  "<FromUserName><![CDATA[" & fromUser & "]]></FromUserName>" &
  "<CreateTime>1409735669</CreateTime>" &
  "<MsgType><![CDATA[file]]></MsgType>" &
  "<MediaId><![CDATA[" & mediaId & "]]></MediaId>" &
  "<FileName><![CDATA[report.pdf]]></FileName>" &
  "<FileSize>98765</FileSize>" &
  "<MsgId>" & msgId & "</MsgId>" &
  "<AgentID>218</AgentID>" &
  "</xml>"

func makeEventXml(fromUser, event, eventKey: string): string =
  "<xml>" &
  "<ToUserName><![CDATA[toUser]]></ToUserName>" &
  "<FromUserName><![CDATA[" & fromUser & "]]></FromUserName>" &
  "<CreateTime>1348831865</CreateTime>" &
  "<MsgType><![CDATA[event]]></MsgType>" &
  "<Event><![CDATA[" & event & "]]></Event>" &
  "<EventKey><![CDATA[" & eventKey & "]]></EventKey>" &
  "</xml>"

func makePlainTagXml(fromUser, msgId, content: string): string =
  ## Plain tags without CDATA
  "<xml>" &
  "<ToUserName>toUser</ToUserName>" &
  "<FromUserName>" & fromUser & "</FromUserName>" &
  "<CreateTime>1348831860</CreateTime>" &
  "<MsgType>text</MsgType>" &
  "<Content>" & content & "</Content>" &
  "<MsgId>" & msgId & "</MsgId>" &
  "</xml>"

# ── extractTag tests ──────────────────────────────────────────────────────────

suite "extractTag":
  test "extracts CDATA-wrapped value":
    let xml = "<xml><MsgType><![CDATA[text]]></MsgType></xml>"
    check extractTag("MsgType", xml) == "text"

  test "extracts plain (no CDATA) value":
    let xml = "<xml><MsgType>text</MsgType></xml>"
    check extractTag("MsgType", xml) == "text"

  test "returns empty string when tag absent":
    let xml = "<xml><Content><![CDATA[hello]]></Content></xml>"
    check extractTag("MsgType", xml) == ""

  test "returns empty string for empty xml":
    check extractTag("MsgType", "") == ""

  test "works with |>-> syntax":
    let xml = "<xml><FromUserName><![CDATA[alice]]></FromUserName></xml>"
    let got = xml |>-> extractTag("FromUserName")
    check got == "alice"

  test "MsgId is plain (no CDATA)":
    let xml = "<xml><MsgId>9876543210</MsgId></xml>"
    check extractTag("MsgId", xml) == "9876543210"

# ── parseXmlMsg — text ────────────────────────────────────────────────────────

suite "parseXmlMsg text":
  test "parses text message":
    let r = makeTextXml("alice", "1001", "Hello!") |> parseXmlMsg
    check r.kind == wckText
    check r.rawId == "alice"
    check r.msgId == "1001"
    check r.text == "Hello!"
    check r.mediaId == ""
    check r.picUrl == ""

  test "text with plain tags (no CDATA)":
    let r = makePlainTagXml("bob", "2002", "Hi") |> parseXmlMsg
    check r.kind == wckText
    check r.rawId == "bob"
    check r.text == "Hi"

  test "text with empty content":
    let r = makeTextXml("alice", "1002", "") |> parseXmlMsg
    check r.kind == wckText
    check r.text == ""

# ── parseXmlMsg — image ───────────────────────────────────────────────────────

suite "parseXmlMsg image":
  test "parses image message":
    let r = makeImageXml("alice", "2001", "MEDIA-1", "http://pic.example.com/1.jpg") |> parseXmlMsg
    check r.kind == wckImage
    check r.rawId == "alice"
    check r.msgId == "2001"
    check r.mediaId == "MEDIA-1"
    check r.picUrl == "http://pic.example.com/1.jpg"

  test "hasMedia returns true for image":
    let r = makeImageXml("alice", "2001", "MEDIA-1", "http://pic.example.com/1.jpg") |> parseXmlMsg
    check r.hasMedia

# ── parseXmlMsg — voice ───────────────────────────────────────────────────────

suite "parseXmlMsg voice":
  test "parses voice message":
    let r = makeVoiceXml("alice", "3001", "VOICE-1") |> parseXmlMsg
    check r.kind == wckVoice
    check r.rawId == "alice"
    check r.mediaId == "VOICE-1"
    check r.text == ""

  test "hasMedia returns true for voice":
    let r = makeVoiceXml("alice", "3001", "VOICE-1") |> parseXmlMsg
    check r.hasMedia

# ── parseXmlMsg — video ───────────────────────────────────────────────────────

suite "parseXmlMsg video":
  test "parses video message":
    let r = makeVideoXml("alice", "4001", "VIDEO-1") |> parseXmlMsg
    check r.kind == wckVideo
    check r.rawId == "alice"
    check r.mediaId == "VIDEO-1"

  test "parses shortvideo as wckVideo":
    let r = makeShortVideoXml("alice", "4002", "SHORT-1") |> parseXmlMsg
    check r.kind == wckVideo
    check r.mediaId == "SHORT-1"

  test "hasMedia returns true for video":
    let r = makeVideoXml("alice", "4001", "VIDEO-1") |> parseXmlMsg
    check r.hasMedia

# ── parseXmlMsg — file (WeCom) ────────────────────────────────────────────────

suite "parseXmlMsg file":
  test "parses WeCom file message":
    let r = makeFileXml("alice", "5001", "FILE-1") |> parseXmlMsg
    check r.kind == wckFile
    check r.rawId == "alice"
    check r.msgId == "5001"
    check r.mediaId == "FILE-1"

  test "hasMedia returns true for file":
    let r = makeFileXml("alice", "5001", "FILE-1") |> parseXmlMsg
    check r.hasMedia

# ── parseXmlMsg — event ───────────────────────────────────────────────────────

suite "parseXmlMsg event":
  test "parses subscribe event":
    let r = makeEventXml("alice", "subscribe", "") |> parseXmlMsg
    check r.kind == wckEvent
    check r.rawId == "alice"
    check r.eventType == "subscribe"
    check r.text == ""
    check r.msgId == ""

  test "parses CLICK event with EventKey":
    let r = makeEventXml("alice", "CLICK", "BTN_BUY") |> parseXmlMsg
    check r.kind == wckEvent
    check r.eventType == "CLICK"
    check r.text == "BTN_BUY"

  test "parses SCAN event":
    let r = makeEventXml("alice", "SCAN", "SCENE_123") |> parseXmlMsg
    check r.kind == wckEvent
    check r.eventType == "SCAN"

  test "isEvent returns true for event":
    let r = makeEventXml("alice", "subscribe", "") |> parseXmlMsg
    check r.isEvent

  test "hasMedia returns false for event":
    let r = makeEventXml("alice", "subscribe", "") |> parseXmlMsg
    check not r.hasMedia

# ── parseXmlMsg — unknown / edge cases ───────────────────────────────────────

suite "parseXmlMsg edge cases":
  test "unknown MsgType returns wckUnknown":
    let xml = makeTextXml("alice", "9001", "hi")
      .replace("<![CDATA[text]]>", "<![CDATA[location]]>")
    let r = xml |> parseXmlMsg
    check r.kind == wckUnknown

  test "missing FromUserName returns wckUnknown":
    let xml = "<xml><MsgType><![CDATA[text]]></MsgType></xml>"
    check (xml |> parseXmlMsg).kind == wckUnknown

  test "missing MsgType returns wckUnknown":
    let xml = "<xml><FromUserName><![CDATA[alice]]></FromUserName></xml>"
    check (xml |> parseXmlMsg).kind == wckUnknown

  test "empty xml returns wckUnknown":
    check ("" |> parseXmlMsg).kind == wckUnknown

  test "isEvent returns false for non-event":
    let r = makeTextXml("alice", "1001", "Hello") |> parseXmlMsg
    check not r.isEvent

# ── toInbound ────────────────────────────────────────────────────────────────

suite "toInbound":
  test "maps text message to InboundMessage":
    let r = makeTextXml("alice", "1001", "Hello!") |> parseXmlMsg
    let msg = r.toInbound(UserId("user-42"))
    check msg.userId == UserId("user-42")
    check msg.channel == ckWeChat
    check msg.channelId == "1001"
    check msg.text == "Hello!"
    check msg.mediaUrl == ""

  test "maps image message — mediaId goes to mediaUrl":
    let r = makeImageXml("alice", "2001", "MEDIA-1", "http://pic.example.com/1.jpg") |> parseXmlMsg
    let msg = r.toInbound(UserId("user-42"))
    check msg.mediaUrl == "MEDIA-1"
    check msg.text == ""

  test "maps event to InboundMessage with eventKey as text":
    let r = makeEventXml("alice", "CLICK", "BTN_BUY") |> parseXmlMsg
    let msg = r.toInbound(UserId("user-42"))
    check msg.text == "BTN_BUY"
    check msg.channelId == ""
