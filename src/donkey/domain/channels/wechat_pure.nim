## wechat_pure.nim — pure parsing of WeChat/WeCom XML webhook payloads.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## WeChat Official Account and WeCom (Enterprise WeChat) both deliver messages
## as XML, often wrapping field values in CDATA sections.
##
## Topology (pipeops):
##   |>    — unary pure transform  (xml |> parseXmlMsg)
##   |>->  — last-arg pipe         (xml |>-> extractTag("MsgType"))
##   >>=   — Result chain          (not used here; all parsing returns value types)
##
## Contract:
##   1. parseXmlMsg(xml: string)   → WcParseResult
##   2. toInbound(r, userId)       → InboundMessage
##   3. hasMedia(r)                → bool
##   4. isEvent(r)                 → bool

import std/strutils
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  WcMsgKind* = enum
    wckText    ## MsgType=text
    wckImage   ## MsgType=image (has MediaId and PicUrl)
    wckVoice   ## MsgType=voice (has MediaId)
    wckVideo   ## MsgType=video or shortvideo (has MediaId)
    wckFile    ## MsgType=file — WeCom only (has MediaId)
    wckEvent   ## MsgType=event (subscribe/unsubscribe/CLICK/SCAN/VIEW)
    wckUnknown ## parse failure or unsupported type

  WcParseResult* = object
    kind*:      WcMsgKind
    rawId*:     string  ## FromUserName (openid for OA / userid for WeCom)
    msgId*:     string  ## MsgId — unique message id for dedup (empty for events)
    text*:      string  ## Content (text), EventKey (event), empty otherwise
    mediaId*:   string  ## MediaId for image/voice/video/file
    picUrl*:    string  ## PicUrl for image
    eventType*: string  ## Event field value (subscribe, CLICK, SCAN, VIEW, …)

# ── Internal pure helpers ─────────────────────────────────────────────────────

func extractTag*(tag: string; xml: string): string =
  ## Extracts content of `<tag><![CDATA[…]]></tag>` or plain `<tag>…</tag>`.
  ## Returns "" when the tag is absent or malformed.
  ## Designed for  xml |>-> extractTag("MsgType")  (piped value is last arg).
  let cdataOpen  = "<" & tag & "><![CDATA["
  let cdataClose = "]]></" & tag & ">"
  if cdataOpen in xml and cdataClose in xml:
    let start = xml.find(cdataOpen) + cdataOpen.len
    let stop  = xml.find(cdataClose, start)
    if stop >= start:
      return xml[start ..< stop]
  let openTag  = "<" & tag & ">"
  let closeTag = "</" & tag & ">"
  if openTag in xml and closeTag in xml:
    let start = xml.find(openTag) + openTag.len
    let stop  = xml.find(closeTag, start)
    if stop >= start:
      return xml[start ..< stop]
  ""

func parseMsgKind(msgType: string): WcMsgKind =
  case msgType
  of "text":               wckText
  of "image":              wckImage
  of "voice":              wckVoice
  of "video", "shortvideo": wckVideo
  of "file":               wckFile
  of "event":              wckEvent
  else:                    wckUnknown

# ── Public pure API ───────────────────────────────────────────────────────────

func parseXmlMsg*(xml: string): WcParseResult =
  ## Parses a single WeChat/WeCom XML message envelope.
  ## Returns kind=wckUnknown when required fields are absent.
  ##
  ## Usage:  let r = xml |> parseXmlMsg
  let fromUser = xml |>-> extractTag("FromUserName")
  if fromUser.len == 0:
    return WcParseResult(kind: wckUnknown)
  let msgType = xml |>-> extractTag("MsgType")
  if msgType.len == 0:
    return WcParseResult(kind: wckUnknown)
  let kind = parseMsgKind(msgType)
  case kind
  of wckText:
    WcParseResult(
      kind:  wckText,
      rawId: fromUser,
      msgId: xml |>-> extractTag("MsgId"),
      text:  xml |>-> extractTag("Content"),
    )
  of wckImage:
    WcParseResult(
      kind:    wckImage,
      rawId:   fromUser,
      msgId:   xml |>-> extractTag("MsgId"),
      mediaId: xml |>-> extractTag("MediaId"),
      picUrl:  xml |>-> extractTag("PicUrl"),
    )
  of wckVoice:
    WcParseResult(
      kind:    wckVoice,
      rawId:   fromUser,
      msgId:   xml |>-> extractTag("MsgId"),
      mediaId: xml |>-> extractTag("MediaId"),
    )
  of wckVideo:
    WcParseResult(
      kind:    wckVideo,
      rawId:   fromUser,
      msgId:   xml |>-> extractTag("MsgId"),
      mediaId: xml |>-> extractTag("MediaId"),
    )
  of wckFile:
    WcParseResult(
      kind:    wckFile,
      rawId:   fromUser,
      msgId:   xml |>-> extractTag("MsgId"),
      mediaId: xml |>-> extractTag("MediaId"),
    )
  of wckEvent:
    WcParseResult(
      kind:      wckEvent,
      rawId:     fromUser,
      msgId:     xml |>-> extractTag("MsgId"),
      text:      xml |>-> extractTag("EventKey"),
      eventType: xml |>-> extractTag("Event"),
    )
  of wckUnknown:
    WcParseResult(kind: wckUnknown)

func toInbound*(r: WcParseResult; userId: UserId): InboundMessage =
  ## Converts a WcParseResult + resolved UserId into an InboundMessage.
  ## mediaId is placed in mediaUrl — the adapter must resolve it via Media API.
  InboundMessage(
    userId:    userId,
    channel:   ckWeChat,
    channelId: r.msgId,
    text:      r.text,
    mediaUrl:  r.mediaId,
  )

func hasMedia*(r: WcParseResult): bool =
  ## True when the message carries media that the adapter must fetch.
  r.kind in {wckImage, wckVoice, wckVideo, wckFile}

func isEvent*(r: WcParseResult): bool =
  ## True when the message is an event notification (subscribe, CLICK, SCAN…).
  r.kind == wckEvent
