## qq_pure.nim — pure parsing of QQ official bot event payloads.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## QQ official bot delivers events via WebSocket gateway (op=0 dispatches)
## and optionally via webhook (flat JSON). Message types handled:
##   C2C_MESSAGE_CREATE          — private (DM) message
##   GROUP_AT_MESSAGE_CREATE     — group message (bot @-mentioned)
##   GROUP_MSG_RECEIVE           — group message (subscription)
##   INTERACTION_CREATE          — button click / inline callback
##
## Gateway dispatch format:
##   {"op":0,"t":"C2C_MESSAGE_CREATE","s":42,"d":{...}}
##
## Flat webhook format (some integrations):
##   {"group_openid":"...","author":{"member_openid":"..."},...}
##
## Topology (pipeops):
##   |>    — unary pure transform  (payload |> parseEvent)
##   |>->  — last-arg pipe         (node |>-> getStr("content"))
##   >>=   — Result chain          (not used here; parsers return value types)
##
## Contract:
##   1. parseDispatch(t, d)  → QqParseResult        (gateway op=0 events)
##   2. parseEvent(payload)  → QqParseResult         (any payload format)
##   3. toInbound(r, userId) → InboundMessage
##   4. qqRawIdentity(r)     → string               ("group:<id>" or userId)
##   5. isInteraction(r)     → bool
##   6. hasMedia(r)          → bool

import std/json
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  QqMsgKind* = enum
    qqkPrivate     ## C2C_MESSAGE_CREATE — direct message
    qqkGroup       ## GROUP_AT_MESSAGE_CREATE / GROUP_MSG_RECEIVE
    qqkInteraction ## INTERACTION_CREATE — button click / callback
    qqkUnknown     ## parse failure or unsupported event type

  QqParseResult* = object
    kind*:      QqMsgKind
    rawId*:     string  ## user_openid (private) or member_openid (group)
    groupId*:   string  ## group_openid; non-empty for group events
    messageId*: string  ## "msg:<id>" for messages, "event:<id>" for interactions
    text*:      string  ## message content or "/callback <data>" for interactions

# ── Internal pure helpers ─────────────────────────────────────────────────────

func getStr(name: string; node: JsonNode): string =
  ## Returns a string field from a JsonNode by name; "" when absent or nil.
  ## Designed for  node |>-> getStr("content")  (piped value is last arg).
  if node == nil: return ""
  node.getOrDefault(name).getStr("")

func getAuthorId(authorNode: JsonNode): string =
  ## Extracts the best available user id from an author sub-object.
  ## Prefers member_openid (group context), falls back to user_openid.
  if authorNode == nil: return ""
  let memberId = authorNode.getOrDefault("member_openid").getStr("")
  if memberId.len > 0: return memberId
  authorNode.getOrDefault("user_openid").getStr("")

func parseC2cEvent(data: JsonNode): QqParseResult =
  ## Parses a C2C_MESSAGE_CREATE event node into QqParseResult.
  if data == nil: return QqParseResult(kind: qqkUnknown)
  let userId    = data.getOrDefault("author") |>-> getStr("user_openid")
  let messageId = data |>-> getStr("id")
  if userId.len == 0 or messageId.len == 0:
    return QqParseResult(kind: qqkUnknown)
  QqParseResult(
    kind:      qqkPrivate,
    rawId:     userId,
    messageId: "msg:" & messageId,
    text:      data |>-> getStr("content"),
  )

func parseGroupEvent(data: JsonNode): QqParseResult =
  ## Parses GROUP_AT_MESSAGE_CREATE or GROUP_MSG_RECEIVE event node.
  if data == nil: return QqParseResult(kind: qqkUnknown)
  let groupId   = data |>-> getStr("group_openid")
  let userId    = getAuthorId(data.getOrDefault("author"))
  let messageId = data |>-> getStr("id")
  if groupId.len == 0 or userId.len == 0 or messageId.len == 0:
    return QqParseResult(kind: qqkUnknown)
  QqParseResult(
    kind:      qqkGroup,
    rawId:     userId,
    groupId:   groupId,
    messageId: "msg:" & messageId,
    text:      data |>-> getStr("content"),
  )

func parseInteractionEvent(data: JsonNode): QqParseResult =
  ## Parses an INTERACTION_CREATE event node (button click / callback).
  ## The callback data is placed in text as "/callback <data>".
  if data == nil: return QqParseResult(kind: qqkUnknown)
  let buttonData = data.getOrDefault("data")
                      .getOrDefault("resolved")
                      .getOrDefault("button_data").getStr("")
  let eventId    = data |>-> getStr("id")
  let scene      = data |>-> getStr("scene")
  let userId =
    if scene == "group":
      data.getOrDefault("group_member_openid").getStr("")
    else:
      data.getOrDefault("user_openid").getStr("")
  if eventId.len == 0 or userId.len == 0 or buttonData.len == 0:
    return QqParseResult(kind: qqkUnknown)
  QqParseResult(
    kind:      qqkInteraction,
    rawId:     userId,
    groupId:   if scene == "group": data |>-> getStr("group_openid") else: "",
    messageId: "event:" & eventId,
    text:      "/callback " & buttonData,
  )

func detectFlatEventType(data: JsonNode): string =
  ## Infers the event type from a flat webhook payload (no "t" field).
  if data == nil: return ""
  if data.getOrDefault("group_openid").getStr("").len > 0:
    return "GROUP_AT_MESSAGE_CREATE"
  if data.getOrDefault("author").getOrDefault("user_openid").getStr("").len > 0:
    return "C2C_MESSAGE_CREATE"
  ""

# ── Public pure API ───────────────────────────────────────────────────────────

func parseDispatch*(t: string; d: JsonNode): QqParseResult =
  ## Parses a gateway op=0 dispatch: t is the event type string, d is the data node.
  ## Usage:  let r = parseDispatch(eventType, dataNode)
  case t
  of "C2C_MESSAGE_CREATE":
    parseC2cEvent(d)
  of "GROUP_AT_MESSAGE_CREATE", "GROUP_MSG_RECEIVE":
    parseGroupEvent(d)
  of "INTERACTION_CREATE":
    parseInteractionEvent(d)
  else:
    QqParseResult(kind: qqkUnknown)

func parseEvent*(payload: JsonNode): QqParseResult =
  ## Parses any QQ official bot payload — gateway dispatch (op=0 with t+d) or flat webhook.
  ## Usage:  let r = payload |> parseEvent
  if payload == nil: return QqParseResult(kind: qqkUnknown)
  # Gateway dispatch format: {"op":0,"t":"TYPE","d":{...}}
  let t = payload.getOrDefault("t").getStr("")
  if t.len > 0:
    let d = payload.getOrDefault("d")
    return parseDispatch(t, d)
  # Flat webhook format: detect event type from payload fields
  let flatType = detectFlatEventType(payload)
  if flatType.len == 0:
    return QqParseResult(kind: qqkUnknown)
  parseDispatch(flatType, payload)

func toInbound*(r: QqParseResult; userId: UserId): InboundMessage =
  ## Converts a QqParseResult + resolved UserId into an InboundMessage.
  InboundMessage(
    userId:    userId,
    channel:   ckQQ,
    channelId: r.messageId,
    text:      r.text,
  )

func qqRawIdentity*(r: QqParseResult): string =
  ## Returns the routing key for identity resolution.
  ## Any event with a non-empty groupId returns "group:<group_openid>"; otherwise the userId.
  if r.groupId.len > 0:
    "group:" & r.groupId
  else:
    r.rawId

func isInteraction*(r: QqParseResult): bool =
  ## True when this is an INTERACTION_CREATE event that may require an ack.
  r.kind == qqkInteraction

func hasMedia*(r: QqParseResult): bool =
  ## QQ official bot v1 does not support media inbound; always false.
  false
