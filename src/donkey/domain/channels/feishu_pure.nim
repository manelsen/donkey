## feishu_pure.nim — pure parsing of Feishu/Lark webhook event payloads.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## Feishu (Lark) delivers events as JSON (schema 2.0). Messages arrive under
## event_type "im.message.receive_v1". The `message.content` field is itself a
## JSON-encoded string (double-encoded) containing type-specific fields such as
## `{"text":"hello"}` for text or `{"image_key":"img_xxx"}` for images.
##
## URL-verification challenges arrive at the top level:
##   {"type":"url_verification","challenge":"xxx","token":"xxx"}
##
## Topology (pipeops):
##   |>    — unary pure transform  (payload |> parseEvent)
##   |>->  — last-arg pipe         (node |>-> getField("open_id"))
##   >>=   — Result chain          (not used here; all parsing returns value types)
##
## Contract:
##   1. parseEvent(JsonNode)   → FsParseResult
##   2. toInbound(r, userId)   → InboundMessage
##   3. hasMedia(r)            → bool
##   4. isVerification(r)      → bool

import std/[json, strutils]
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  FsMsgKind* = enum
    fmkText        ## message_type="text"
    fmkImage       ## message_type="image"  (has image_key)
    fmkAudio       ## message_type="audio"  (has file_key)
    fmkFile        ## message_type="file"   (has file_key)
    fmkSticker     ## message_type="sticker" (has file_key)
    fmkInteractive ## message_type="interactive" (card, no media to fetch)
    fmkEvent       ## non-message event (p2p_chat_create, url_verification, …)
    fmkUnknown     ## parse failure or unsupported type

  FsParseResult* = object
    kind*:      FsMsgKind
    rawId*:     string  ## sender open_id
    messageId*: string  ## Feishu message_id (om_xxx) — for dedup / ack
    text*:      string  ## message text or empty
    fileKey*:   string  ## image_key (image) or file_key (audio/file/sticker)
    chatId*:    string  ## chat_id the message was sent to
    chatType*:  string  ## "p2p" or "group"
    eventType*: string  ## raw event_type from header (non-message events)
    challenge*: string  ## non-empty for url_verification events

# ── Internal pure helpers ─────────────────────────────────────────────────────

func getField(name: string; node: JsonNode): string =
  ## Returns a string field from a JsonNode by name; "" when absent or nil.
  ## Designed for  node |>-> getField("open_id")  (piped value is last arg).
  if node == nil: return ""
  node.getOrDefault(name).getStr("")

func extractJsonStr*(key: string; encoded: string): string =
  ## Extracts a string value from a simple JSON-encoded string such as
  ## `{"text":"hello"}` or `{"image_key":"img_xxx"}` without calling
  ## parseJson (which is a proc in stdlib and cannot be called from `func`).
  ##
  ## Matches the pattern:  "key":"value"  handling optional whitespace.
  ## Returns "" when the key is absent or the value cannot be determined.
  ##
  ## Designed for  encoded |>-> extractJsonStr("text")  (piped value is last).
  let needle = "\"" & key & "\":"
  let idx = encoded.find(needle)
  if idx < 0: return ""
  var i = idx + needle.len
  # skip optional whitespace
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
      # handle common JSON escapes
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

func parseMsgKind(msgType: string): FsMsgKind =
  case msgType
  of "text":        fmkText
  of "image":       fmkImage
  of "audio":       fmkAudio
  of "file":        fmkFile
  of "sticker":     fmkSticker
  of "interactive": fmkInteractive
  else:             fmkUnknown

func parseSenderId(sender: JsonNode): string =
  ## Extracts the sender open_id from the sender sub-object.
  if sender == nil: return ""
  sender.getOrDefault("sender_id").getOrDefault("open_id").getStr("")

func parseMessage(event: JsonNode): FsParseResult =
  ## Parses the inner `event` object for im.message.receive_v1 events.
  if event == nil: return FsParseResult(kind: fmkUnknown)
  let msgNode  = event.getOrDefault("message")
  let sender   = event.getOrDefault("sender")
  if msgNode == nil: return FsParseResult(kind: fmkUnknown)
  let msgType    = msgNode |>-> getField("message_type")
  let kind       = parseMsgKind(msgType)
  let rawId      = parseSenderId(sender)
  let msgId      = msgNode |>-> getField("message_id")
  let chatId     = msgNode |>-> getField("chat_id")
  let chatType   = msgNode |>-> getField("chat_type")
  let contentEnc = msgNode |>-> getField("content")  ## JSON-encoded string
  case kind
  of fmkText:
    FsParseResult(
      kind:      fmkText,
      rawId:     rawId,
      messageId: msgId,
      text:      contentEnc |>-> extractJsonStr("text"),
      chatId:    chatId,
      chatType:  chatType,
    )
  of fmkImage:
    FsParseResult(
      kind:      fmkImage,
      rawId:     rawId,
      messageId: msgId,
      fileKey:   contentEnc |>-> extractJsonStr("image_key"),
      chatId:    chatId,
      chatType:  chatType,
    )
  of fmkAudio, fmkFile, fmkSticker:
    FsParseResult(
      kind:      kind,
      rawId:     rawId,
      messageId: msgId,
      fileKey:   contentEnc |>-> extractJsonStr("file_key"),
      chatId:    chatId,
      chatType:  chatType,
    )
  of fmkInteractive:
    FsParseResult(
      kind:      fmkInteractive,
      rawId:     rawId,
      messageId: msgId,
      chatId:    chatId,
      chatType:  chatType,
    )
  of fmkEvent, fmkUnknown:
    FsParseResult(kind: fmkUnknown)

# ── Public pure API ───────────────────────────────────────────────────────────

func parseEvent*(payload: JsonNode): FsParseResult =
  ## Parses a Feishu/Lark webhook payload (schema 2.0 or url_verification).
  ## Returns kind=fmkUnknown when parsing fails or the event is not actionable.
  ##
  ## Usage:  let r = payload |> parseEvent
  if payload == nil: return FsParseResult(kind: fmkUnknown)
  # url_verification challenge (no schema/header — top-level type field)
  let topType = payload.getOrDefault("type").getStr("")
  if topType == "url_verification":
    let ch = payload.getOrDefault("challenge").getStr("")
    return FsParseResult(kind: fmkEvent, challenge: ch,
                         eventType: "url_verification")
  # schema 2.0 events: {schema, header, event}
  let header    = payload.getOrDefault("header")
  let eventNode = payload.getOrDefault("event")
  if header == nil: return FsParseResult(kind: fmkUnknown)
  let eventType = header |>-> getField("event_type")
  if eventType == "im.message.receive_v1":
    var r = parseMessage(eventNode)
    r.eventType = eventType
    return r
  # other recognised event types (membership changes, etc.)
  if eventType.len > 0:
    return FsParseResult(kind: fmkEvent, eventType: eventType)
  FsParseResult(kind: fmkUnknown)

func toInbound*(r: FsParseResult; userId: UserId): InboundMessage =
  ## Converts a FsParseResult + resolved UserId into an InboundMessage.
  ## fileKey is placed in mediaUrl — the adapter must download via Feishu File API.
  InboundMessage(
    userId:    userId,
    channel:   ckFeishu,
    channelId: r.messageId,
    text:      r.text,
    mediaUrl:  r.fileKey,
  )

func hasMedia*(r: FsParseResult): bool =
  ## True when the message carries a file/image that the adapter must fetch.
  r.kind in {fmkImage, fmkAudio, fmkFile, fmkSticker}

func isVerification*(r: FsParseResult): bool =
  ## True when this is a url_verification challenge that must be echoed back.
  r.kind == fmkEvent and r.eventType == "url_verification" and r.challenge.len > 0
