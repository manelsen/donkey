## line_pure.nim — pure parsing of LINE Messaging API webhook payloads.
##
## No I/O, no side effects, no line-bot-sdk. The JSON core is `func`;
## `parseLineWebhook` is a `proc` only because stdlib `parseJson` is itself a
## proc (same precedent as `providers/ollama_pure.nim`) — it never lets an
## exception escape and returns `Result[seq[LineParseResult], string]`.
##
## Protocol facts (PRD §1; Hermes is read-only at
## `/home/micelio/git/hermes-agent`, `plugins/platforms/line/adapter.py`):
##   - payload is `{"events":[…]}` with `type`, `mode` (`active`/`standby`),
##     `webhookEventId`, `deliveryContext.isRedelivery`, `replyToken`,
##     `source{type,userId,groupId,roomId}` and `message{type,id,text}`
##     — `adapter.py:514-567,200-209`, LINE OpenAPI `webhook.yml`;
##   - `source.type` is `user` (DM), `group` (chatId = groupId) or `room`
##     (chatId = roomId); `source.userId` is always the speaker
##     — `adapter.py:200-209,548-551`;
##   - `message.type != "text"` is a non-text bubble; an event whose `type`
##     is not `"message"` carries no content at all;
##   - `mode == "standby"` means another module answers; the runtime drops it
##     (deliberate deviation: Hermes does not read `mode`);
##   - `deliveryContext.isRedelivery` is telemetry only. Dedupe is by
##     `webhookEventId` (US-002/line_policy), never by this flag.
##
## Contract:
##   1. parseWebhook(payload: JsonNode)   → seq[LineParseResult]   (pure)
##   2. parseLineWebhook(body: string)    → Result[seq[LineParseResult], string]
##   3. toInbound(r, userId)              → InboundMessage
##   4. lineTarget(rawId)                 → raw `U…`/`C…`/`R…` id

import std/[json, strutils]
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  LineSourceKind* = enum
    lskUser     ## DM: source.type == "user"
    lskGroup    ## group chat: source.type == "group", chatId = groupId
    lskRoom     ## multi-user room: source.type == "room", chatId = roomId
    lskUnknown  ## source.type missing or not one of the three above

  LineContentKind* = enum
    lckText     ## event.type == "message" and message.type == "text"
    lckNonText  ## event.type == "message" and message.type is sticker/image/…
    lckUnknown  ## event.type != "message" (postback, follow, …) or no message

  LineMode* = enum
    lmActive   ## answer this event
    lmStandby  ## another module answers; the runtime must drop it

  LineParseResult* = object
    senderId*:      string         ## source.userId — the speaker (identity key)
    chatId*:        string         ## groupId/roomId in group/room, userId in DM
    sourceKind*:    LineSourceKind
    contentKind*:   LineContentKind
    mode*:          LineMode
    isRedelivery*:  bool           ## deliveryContext.isRedelivery — telemetry only
    text*:          string         ## message.text for lckText, else ""
    messageId*:     string         ## message.id (dedupe/ack); "" for non-message events
    eventId*:       string         ## webhookEventId (replay cache key)
    replyToken*:    string         ## single-use reply token (~60 s, out of scope)

# ── Internal pure helpers ─────────────────────────────────────────────────────

func getStr(name: string; node: JsonNode): string =
  ## Returns a string field from a JsonNode by name; "" when absent or nil.
  ## Designed for  node |>-> getStr("field")  (piped value is last arg).
  if node == nil: return ""
  node.getOrDefault(name).getStr("")

func getBool(name: string; default: bool; node: JsonNode): bool =
  ## Returns a bool field; `default` when absent, nil or of another type.
  ## Designed for  node |>-> getBool("field", false)  (piped value is last arg).
  if node == nil: return default
  let v = node.getOrDefault(name)
  if v == nil or v.kind != JBool: default else: v.getBool()

func parseSourceKind(kind: string): LineSourceKind =
  case kind
  of "user":  lskUser
  of "group": lskGroup
  of "room":  lskRoom
  else:       lskUnknown

func parseContentKind(eventType, messageType: string): LineContentKind =
  ## `type` (event) and `message.type` are orthogonal to `source.type`.
  ## Unknown event types are kept as lckUnknown so the runtime can drop them;
  ## they are never silently turned into text.
  if eventType != "message":
    return lckUnknown
  if messageType == "text":
    return lckText
  if messageType.len > 0:
    return lckNonText
  lckUnknown

func chatIdFor(sourceKind: LineSourceKind; source: JsonNode): string =
  ## In DM the conversation is the speaker; in group/room it is the container id.
  case sourceKind
  of lskUser:  source |>-> getStr("userId")
  of lskGroup: source |>-> getStr("groupId")
  of lskRoom:  source |>-> getStr("roomId")
  of lskUnknown: ""

# ── Public pure API ───────────────────────────────────────────────────────────

func parseWebhook*(payload: JsonNode): seq[LineParseResult] =
  ## Parses a LINE webhook payload. Never fails: `events` empty/missing/non-array
  ## and a nil/non-object payload all yield `@[]` (the console "Verify" button
  ## posts `{"events":[]}` and only requires HTTP 200 — PRD §1).
  ## Non-object entries inside `events` are skipped.
  ##
  ## Usage:  let events = payload |> parseWebhook
  if payload == nil or payload.kind != JObject: return @[]
  let events = payload.getOrDefault("events")
  if events == nil or events.kind != JArray: return @[]

  for event in events:
    if event == nil or event.kind != JObject: continue
    let eventType   = event |>-> getStr("type")
    let source      = event.getOrDefault("source")
    let message     = event.getOrDefault("message")
    let delivery    = event.getOrDefault("deliveryContext")
    let sourceType  = source |>-> getStr("type")
    let sourceKind  = parseSourceKind(sourceType)
    let messageType = message |>-> getStr("type")
    let msgText     = message |>-> getStr("text")
    let msgId       = message |>-> getStr("id")
    let contentKind = parseContentKind(eventType, messageType)
    let modeStr     = event |>-> getStr("mode")
    let mode        = if modeStr == "standby": lmStandby else: lmActive
    let redelivery  = getBool("isRedelivery", false, delivery)
    let text = if contentKind == lckText: msgText else: ""
    let messageId = if contentKind == lckUnknown: "" else: msgId
    result.add LineParseResult(
      senderId:     source |>-> getStr("userId"),
      chatId:       chatIdFor(sourceKind, source),
      sourceKind:   sourceKind,
      contentKind:  contentKind,
      mode:         mode,
      isRedelivery: redelivery,
      text:         text,
      messageId:    messageId,
      eventId:      event |>-> getStr("webhookEventId"),
      replyToken:   event |>-> getStr("replyToken"),
    )

proc parseLineWebhook*(body: string): Result[seq[LineParseResult], string] {.raises: [].} =
  ## Raw-body variant for adapters: malformed JSON is an `err`, valid JSON with
  ## an unusable shape is `ok(@[])`. Signature verification happens upstream on
  ## the raw body (FR-1); nothing here raises.
  if body.len == 0:
    return err("LINE: empty webhook body")
  try:
    let payload = parseJson(body)
    if payload.kind != JObject:
      return err("LINE: webhook payload is not a JSON object")
    ok(parseWebhook(payload))
  except CatchableError:
    err("LINE: invalid JSON webhook payload")

func rawId*(r: LineParseResult): string =
  ## Project-wide name for the sender id (matches `rawId` in other channel
  ## parsers); identical to `senderId`.
  r.senderId

func webhookEventId*(r: LineParseResult): string =
  ## LINE OpenAPI name for the replay-cache key; identical to `eventId`.
  r.eventId

func lineTarget*(rawId: string): string =
  ## Strips internal `group:`/`room:`/`user:` prefixes so only the raw LINE id
  ## leaves the process. The push `to` is always `U…`/`C…`/`R…`, never prefixed
  ## (PRD §1, FR-5; Hermes sends `source`'s id — `adapter.py:247-248,548-551`).
  ## Already-raw ids pass through unchanged.
  for prefix in ["group:", "room:", "user:"]:
    if rawId.startsWith(prefix):
      return rawId[prefix.len .. ^1]
  rawId

func toInbound*(r: LineParseResult; userId: UserId): InboundMessage =
  ## Converts a LineParseResult + resolved UserId into an InboundMessage.
  ## The identity is the speaker (`senderId`); the reply target is the
  ## conversation (`chatId`), so group replies never go to the speaker's DM.
  ## `isGroup` is true for group/room and for an unrecognised source kind:
  ## only a `source.type == "user"` event is a DM.
  InboundMessage(
    userId:       userId,
    channel:      ckLine,
    channelId:    r.chatId,
    chatId:       r.chatId,
    rawChannelId: r.senderId,
    messageId:    r.messageId,
    text:         r.text,
    isGroup:      r.sourceKind != lskUser,
  )
