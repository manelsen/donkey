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

import std/[json, strutils]
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
    replyToId*:     string  ## the wamid this replies to (`context.id`); Meta
                            ## sends no text for it

  RecentWaTexts* = object
    ## The texts of recent messages by wamid, bounded: Meta's reply context
    ## carries only the quoted id, so the adapter keeps what it saw and sent.
    ids:    seq[string]
    texts:  seq[string]
    stamps: seq[int64]   ## when each was last remembered: the oldest goes
    clock:  int64

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
  result = case msgType
  of "text":
    msg |>-> parseTextMsg(phoneNumberId)
  of "interactive":
    msg |>-> parseInteractiveMsg(phoneNumberId)
  of "image", "audio", "video", "document", "sticker":
    msg |>-> parseMediaMsg(phoneNumberId)
  else:
    WaParseResult(kind: wmkUnknown)
  let context = msg.getOrDefault("context")
  if context != nil and context.kind == JObject:
    result.replyToId = context.getOrDefault("id").getStr("")

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

const RecentWaTextCapacity* = 512

func remember*(r: var RecentWaTexts; id, text: string) =
  ## Keeps `text` under `id`; the oldest entry goes once the ring is full.
  if id.len == 0 or text.len == 0:
    return
  inc r.clock
  let known = r.ids.find(id)
  if known >= 0:
    ## The same id again: the newest text, and now the newest entry.
    r.texts[known] = text
    r.stamps[known] = r.clock
    return
  if r.ids.len < RecentWaTextCapacity:
    r.ids.add id
    r.texts.add text
    r.stamps.add r.clock
    return
  var oldest = 0
  for i in 1 ..< r.stamps.len:
    if r.stamps[i] < r.stamps[oldest]: oldest = i
  r.ids[oldest] = id
  r.texts[oldest] = text
  r.stamps[oldest] = r.clock

func lookup*(r: RecentWaTexts; id: string): string =
  if id.len == 0:
    return ""
  for i in 0 ..< r.ids.len:
    if r.ids[i] == id:
      return r.texts[i]
  ""


# ── Sending a file (E9, send_file) ────────────────────────────────────────────
## A local file is uploaded first (POST /{phone-number-id}/media) and the
## message carries the media by id; a link is not a local path.

func waMediaKind*(name: string): tuple[kind: string, limit: int] =
  ## The message type for a file, with WhatsApp's size limit for it.
  let n = name.toLowerAscii
  if n.endsWith(".jpg") or n.endsWith(".jpeg") or n.endsWith(".png"):
    (kind: "image", limit: 5 * 1024 * 1024)
  elif n.endsWith(".mp4") or n.endsWith(".3gp"):
    (kind: "video", limit: 16 * 1024 * 1024)
  elif n.endsWith(".ogg") or n.endsWith(".mp3") or n.endsWith(".m4a") or n.endsWith(".aac"):
    (kind: "audio", limit: 16 * 1024 * 1024)
  else:
    (kind: "document", limit: 100 * 1024 * 1024)

proc parseMediaId*(body: string): Result[string, string] =
  try:
    let id = parseJson(body){"id"}.getStr
    if id.len > 0: ok(id) else: err("WhatsApp: media upload without an id")
  except CatchableError as e:
    err("WhatsApp: media upload answer unreadable: " & e.msg)

proc mediaMessageBody*(to, kind, mediaId, filename, caption: string): JsonNode =
  var media = %* {"id": mediaId}
  if kind == "document": media["filename"] = %filename
  if kind != "audio" and caption.len > 0: media["caption"] = %caption
  result = %* {"messaging_product": "whatsapp", "to": to, "type": kind}
  result[kind] = media
