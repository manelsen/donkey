## dingtalk_pure.nim — pure parsing of DingTalk Stream mode event payloads.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## DingTalk delivers messages via its Stream SDK (WebSocket). The payload
## contains:
##   msgtype         — "text", "markdown", "picture", "audio", "video", "file"
##   text.content    — text/markdown messages
##   content         — JSON-encoded string for picture/audio/video/file
##   msgId           — unique message ID
##   senderId        — sender user ID
##   senderStaffId   — staff ID (internal employee; non-empty in enterprises)
##   conversationId  — conversation ID
##   conversationType— "1" (p2p) or "2" (group)
##
## Topology (pipeops):
##   |>    — unary pure transform  (payload |> parseEvent)
##   |>->  — last-arg pipe         (node |>-> getStr("msgId"))
##   >>=   — Result chain          (not used here; parsers return value types)
##
## Contract:
##   1. parseEvent(JsonNode)   → DtParseResult
##   2. toInbound(r, userId)   → InboundMessage
##   3. hasMedia(r)            → bool

import std/[json, strutils]
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  DtMsgKind* = enum
    dtkText     ## msgtype="text" or msgtype="markdown"
    dtkImage    ## msgtype="picture"
    dtkAudio    ## msgtype="audio"
    dtkVideo    ## msgtype="video"
    dtkFile     ## msgtype="file"
    dtkUnknown  ## parse failure or unsupported type

  DtParseResult* = object
    kind*:           DtMsgKind
    rawId*:          string  ## senderId
    messageId*:      string  ## msgId
    text*:           string  ## message text (dtkText/dtkMarkdown only)
    downloadCode*:   string  ## download code for media types
    conversationId*: string  ## conversationId
    isGroup*:        bool    ## true when conversationType == "2"

# ── Internal pure helpers ─────────────────────────────────────────────────────

func getStr(name: string; node: JsonNode): string =
  ## Returns a string field from a JsonNode by name; "" when absent or nil.
  ## Designed for  node |>-> getStr("field")  (piped value is last arg).
  if node == nil: return ""
  node.getOrDefault(name).getStr("")

func extractJsonStr(key: string; encoded: string): string =
  ## Extracts a string value from a simple JSON-encoded string such as
  ## `{"downloadCode":"dc_xxx"}` without calling parseJson (proc in stdlib,
  ## incompatible with `func`).
  ##
  ## Designed for  encoded |>-> extractJsonStr("downloadCode")  (piped last).
  let needle = "\"" & key & "\":"
  let idx = encoded.find(needle)
  if idx < 0: return ""
  var i = idx + needle.len
  while i < encoded.len and encoded[i] == ' ':
    inc i
  if i >= encoded.len: return ""
  if encoded[i] != '"': return ""
  inc i
  var res = newStringOfCap(64)
  while i < encoded.len:
    let c = encoded[i]
    if c == '"': break
    if c == '\\' and i + 1 < encoded.len:
      let esc = encoded[i + 1]
      case esc
      of '"':  res.add('"');  inc i
      of '\\': res.add('\\'); inc i
      of '/':  res.add('/');  inc i
      of 'n':  res.add('\n'); inc i
      of 'r':  res.add('\r'); inc i
      of 't':  res.add('\t'); inc i
      else:    res.add(c)
    else:
      res.add(c)
    inc i
  res

func parseMsgKind(msgType: string): DtMsgKind =
  case msgType
  of "text", "markdown": dtkText
  of "picture":          dtkImage
  of "audio":            dtkAudio
  of "video":            dtkVideo
  of "file":             dtkFile
  else:                  dtkUnknown

# ── Public pure API ───────────────────────────────────────────────────────────

func parseEvent*(payload: JsonNode): DtParseResult =
  ## Parses a DingTalk Stream SDK event payload.
  ## Returns kind=dtkUnknown when parsing fails or the event is not actionable.
  ##
  ## Usage:  let r = payload |> parseEvent
  if payload == nil: return DtParseResult(kind: dtkUnknown)
  let msgType = payload |>-> getStr("msgtype")
  if msgType.len == 0: return DtParseResult(kind: dtkUnknown)
  let kind     = parseMsgKind(msgType)
  if kind == dtkUnknown: return DtParseResult(kind: dtkUnknown)
  let senderId = payload |>-> getStr("senderId")
  let msgId    = payload |>-> getStr("msgId")
  if senderId.len == 0 or msgId.len == 0:
    return DtParseResult(kind: dtkUnknown)
  let convId   = payload |>-> getStr("conversationId")
  let convType = payload |>-> getStr("conversationType")
  case kind
  of dtkText:
    DtParseResult(
      kind:           dtkText,
      rawId:          senderId,
      messageId:      msgId,
      text:           payload.getOrDefault("text") |>-> getStr("content"),
      conversationId: convId,
      isGroup:        convType == "2",
    )
  of dtkImage, dtkAudio, dtkVideo, dtkFile:
    let contentEnc = payload |>-> getStr("content")
    DtParseResult(
      kind:           kind,
      rawId:          senderId,
      messageId:      msgId,
      downloadCode:   contentEnc |>-> extractJsonStr("downloadCode"),
      conversationId: convId,
      isGroup:        convType == "2",
    )
  of dtkUnknown:
    DtParseResult(kind: dtkUnknown)

func toInbound*(r: DtParseResult; userId: UserId): InboundMessage =
  ## Converts a DtParseResult + resolved UserId into an InboundMessage.
  ## downloadCode is placed in mediaUrl — the adapter must download via DingTalk
  ## media download API.
  InboundMessage(
    userId:    userId,
    channel:   ckDingTalk,
    channelId: r.messageId,
    text:      r.text,
    mediaUrl:  r.downloadCode,
  )

func hasMedia*(r: DtParseResult): bool =
  ## True when the message carries a file/image that the adapter must download.
  r.kind in {dtkImage, dtkAudio, dtkVideo, dtkFile}
