## matrix_pure.nim — pure parsing of Matrix Client-Server API event payloads.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## Matrix delivers messages as JSON events with this shape:
##   type            — "m.room.message" for messages
##   room_id         — "!opaque:server" (used as routing key)
##   event_id        — "$eventid:server" (unique event identifier)
##   sender          — "@user:server" (sender MXID)
##   content.msgtype — "m.text", "m.notice", "m.emote", "m.image", "m.audio",
##                     "m.video", "m.file"
##   content.body    — text body (all msgtypes carry a fallback body)
##   content.url     — mxc:// URI (media msgtypes only)
##
## Routing convention:
##   rawId = room_id for all events (adapter identity key is the room)
##
## Topology (pipeops):
##   |>    — unary pure transform  (payload |> parseEvent)
##   |>->  — last-arg pipe         (node |>-> getStr("room_id"))
##   >>=   — Result chain          (not used here; parsers return value types)
##
## Contract:
##   1. parseEvent(JsonNode)  → MxParseResult
##   2. toInbound(r, userId)  → InboundMessage
##   3. hasMedia(r)           → bool

import std/json
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  MxMsgKind* = enum
    mxkText     ## msgtype=m.text, m.notice, or m.emote
    mxkImage    ## msgtype=m.image
    mxkAudio    ## msgtype=m.audio
    mxkVideo    ## msgtype=m.video
    mxkFile     ## msgtype=m.file
    mxkUnknown  ## non-message event type or unsupported msgtype

  MxParseResult* = object
    kind*:     MxMsgKind
    roomId*:   string  ## room_id — routing key used as rawId
    senderId*: string  ## sender MXID (@user:server)
    eventId*:  string  ## $event:server — unique event id
    text*:     string  ## body text (mxkText only)
    mediaUrl*: string  ## mxc:// URL (mxkImage/Audio/Video/File only)

# ── Internal pure helpers ─────────────────────────────────────────────────────

func getStr(name: string; node: JsonNode): string =
  ## Returns a string field from a JsonNode by name; "" when absent or nil.
  ## Designed for  node |>-> getStr("field")  (piped value is last arg).
  if node == nil: return ""
  node.getOrDefault(name).getStr("")

func parseMsgKind(msgtype: string): MxMsgKind =
  case msgtype
  of "m.text", "m.notice", "m.emote": mxkText
  of "m.image":                        mxkImage
  of "m.audio":                        mxkAudio
  of "m.video":                        mxkVideo
  of "m.file":                         mxkFile
  else:                                mxkUnknown

# ── Public pure API ───────────────────────────────────────────────────────────

func parseEvent*(payload: JsonNode): MxParseResult =
  ## Parses a Matrix Client-Server API event.
  ## Returns kind=mxkUnknown when parsing fails, the event is not
  ## "m.room.message", or the msgtype is unsupported.
  ##
  ## Usage:  let r = payload |> parseEvent
  if payload == nil: return MxParseResult(kind: mxkUnknown)
  let evType = payload |>-> getStr("type")
  if evType != "m.room.message": return MxParseResult(kind: mxkUnknown)
  let roomId   = payload |>-> getStr("room_id")
  let eventId  = payload |>-> getStr("event_id")
  let senderId = payload |>-> getStr("sender")
  if roomId.len == 0 or eventId.len == 0 or senderId.len == 0:
    return MxParseResult(kind: mxkUnknown)
  let content = payload.getOrDefault("content")
  let msgtype = content |>-> getStr("msgtype")
  let kind    = parseMsgKind(msgtype)
  if kind == mxkUnknown: return MxParseResult(kind: mxkUnknown)
  case kind
  of mxkText:
    MxParseResult(
      kind:     mxkText,
      roomId:   roomId,
      senderId: senderId,
      eventId:  eventId,
      text:     content |>-> getStr("body"),
    )
  of mxkImage, mxkAudio, mxkVideo, mxkFile:
    MxParseResult(
      kind:     kind,
      roomId:   roomId,
      senderId: senderId,
      eventId:  eventId,
      mediaUrl: content |>-> getStr("url"),
    )
  of mxkUnknown:
    MxParseResult(kind: mxkUnknown)

func toInbound*(r: MxParseResult; userId: UserId): InboundMessage =
  ## Converts an MxParseResult + resolved UserId into an InboundMessage.
  ## mediaUrl carries the mxc:// URL — the adapter must download via the
  ## Matrix media download endpoint.
  InboundMessage(
    userId:    userId,
    channel:   ckMatrix,
    channelId: r.eventId,
    text:      r.text,
    mediaUrl:  r.mediaUrl,
  )

func hasMedia*(r: MxParseResult): bool =
  ## True when the event carries a media attachment the adapter must download.
  r.kind in {mxkImage, mxkAudio, mxkVideo, mxkFile}
