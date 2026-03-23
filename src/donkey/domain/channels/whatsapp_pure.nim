## whatsapp_pure.nim — pure parsing of WhatsApp Cloud API webhook payloads.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## Topology (pipeops):
##   |>    — unary pure transform  (payload |> parseWebhook)
##   |>->  — last-arg pipe         (msg |>-> parseMessage(phoneNumberId))
##   >>=   — Result chain          (not used here; all parsing returns value types)
##
## Contract:
##   1. parseWebhook(JsonNode)        → seq[WaParseResult]   (all messages in payload)
##   2. toInbound(r, userId)          → InboundMessage
##   3. hasMedia(r)                   → bool

import std/json
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  WaMsgKind* = enum
    wmkText        ## type="text"
    wmkInteractive ## type="interactive" (button_reply or list_reply)
    wmkMedia       ## type in ["image","audio","video","document","sticker"]
    wmkUnknown     ## status updates, unsupported types, or parse failures

  WaParseResult* = object
    kind*:          WaMsgKind
    rawId*:         string  ## sender WA ID (phone number without +)
    text*:          string  ## message body, interactive id, or empty for media
    messageId*:     string  ## wamid — unique message id for dedup
    phoneNumberId*: string  ## receiving business phone number id
    mediaId*:       string  ## non-empty for wmkMedia (use to fetch via Media API)

# ── Internal pure helpers ─────────────────────────────────────────────────────

func extractStr(name: string; node: JsonNode): string =
  ## Returns a string field from a JsonNode by name.
  ## Designed for  node |>-> extractStr(name)  (piped value is last arg).
  if node == nil: return ""
  node.getOrDefault(name).getStr("")

func mediaIdFor(msgType: string; msg: JsonNode): string =
  ## Extracts the media id from a media message sub-object.
  ## Looks up the sub-object keyed by msgType (e.g. "image", "audio").
  let sub = msg.getOrDefault(msgType)
  if sub == nil: return ""
  sub.getOrDefault("id").getStr("")

func parseTextMsg(phoneNumberId: string; msg: JsonNode): WaParseResult =
  ## Parses a text message.
  ## Designed for  msg |>-> parseTextMsg(phoneNumberId)  (piped value is last arg).
  let body = msg.getOrDefault("text").getOrDefault("body").getStr("")
  if body.len == 0: return WaParseResult(kind: wmkUnknown)
  WaParseResult(
    kind:          wmkText,
    rawId:         msg |>-> extractStr("from"),
    text:          body,
    messageId:     msg |>-> extractStr("id"),
    phoneNumberId: phoneNumberId,
  )

func parseInteractiveMsg(phoneNumberId: string; msg: JsonNode): WaParseResult =
  ## Parses an interactive message (button_reply or list_reply).
  ## Designed for  msg |>-> parseInteractiveMsg(phoneNumberId).
  let inode = msg.getOrDefault("interactive")
  if inode == nil: return WaParseResult(kind: wmkUnknown)
  let itype = inode.getOrDefault("type").getStr("")
  let replyNode =
    case itype
    of "button_reply": inode.getOrDefault("button_reply")
    of "list_reply":   inode.getOrDefault("list_reply")
    else: nil
  if replyNode == nil: return WaParseResult(kind: wmkUnknown)
  let replyId = replyNode.getOrDefault("id").getStr("")
  if replyId.len == 0: return WaParseResult(kind: wmkUnknown)
  WaParseResult(
    kind:          wmkInteractive,
    rawId:         msg |>-> extractStr("from"),
    text:          replyId,
    messageId:     msg |>-> extractStr("id"),
    phoneNumberId: phoneNumberId,
  )

func parseMediaMsg(phoneNumberId: string; msg: JsonNode): WaParseResult =
  ## Parses a media message (image, audio, video, document, sticker).
  ## Designed for  msg |>-> parseMediaMsg(phoneNumberId).
  let msgType = msg |>-> extractStr("type")
  let mid = mediaIdFor(msgType, msg)
  if mid.len == 0: return WaParseResult(kind: wmkUnknown)
  WaParseResult(
    kind:          wmkMedia,
    rawId:         msg |>-> extractStr("from"),
    text:          "",
    messageId:     msg |>-> extractStr("id"),
    phoneNumberId: phoneNumberId,
    mediaId:       mid,
  )

func parseMessage(phoneNumberId: string; msg: JsonNode): WaParseResult =
  ## Dispatches a single message object to the right sub-parser.
  ## Designed for  msg |>-> parseMessage(phoneNumberId)  (piped value is last arg).
  if msg == nil: return WaParseResult(kind: wmkUnknown)
  let msgType = msg |>-> extractStr("type")
  case msgType
  of "text":
    msg |>-> parseTextMsg(phoneNumberId)
  of "interactive":
    msg |>-> parseInteractiveMsg(phoneNumberId)
  of "image", "audio", "video", "document", "sticker":
    msg |>-> parseMediaMsg(phoneNumberId)
  else:
    WaParseResult(kind: wmkUnknown)

func parseChangeValue(value: JsonNode): seq[WaParseResult] =
  ## Parses a single change.value object, extracting all messages.
  if value == nil: return @[]
  let messages = value.getOrDefault("messages")
  if messages == nil or messages.kind != JArray: return @[]
  let phoneNumberId = value.getOrDefault("metadata")
                          .getOrDefault("phone_number_id").getStr("")
  for msg in messages:
    let r = msg |>-> parseMessage(phoneNumberId)
    if r.kind != wmkUnknown:
      result.add(r)

# ── Public pure API ───────────────────────────────────────────────────────────

func parseWebhook*(payload: JsonNode): seq[WaParseResult] =
  ## Parses a WhatsApp Cloud API webhook payload.
  ## Returns all actionable messages; status updates and unknowns are filtered.
  ##
  ## Usage:  let msgs = payload |> parseWebhook
  if payload == nil: return @[]
  let entry = payload.getOrDefault("entry")
  if entry == nil or entry.kind != JArray: return @[]
  for e in entry:
    let changes = e.getOrDefault("changes")
    if changes == nil or changes.kind != JArray: continue
    for ch in changes:
      let value = ch.getOrDefault("value")
      result.add(parseChangeValue(value))

func toInbound*(r: WaParseResult; userId: UserId): InboundMessage =
  ## Converts a WaParseResult + resolved UserId into an InboundMessage.
  InboundMessage(
    userId:    userId,
    channel:   ckWhatsApp,
    channelId: r.messageId,
    text:      r.text,
    mediaUrl:  r.mediaId,   ## adapter resolves mediaId → URL via Media API
  )

func hasMedia*(r: WaParseResult): bool =
  ## True when the message carries media that the adapter must fetch.
  r.kind == wmkMedia
