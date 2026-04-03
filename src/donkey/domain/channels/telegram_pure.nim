## telegram_pure.nim — pure parsing of Telegram Bot API update objects.
##
## No I/O, no side effects. All parsing functions are `func`.
##
## Topology (pipeops):
##   |>    — unary pure transform  (upd |> parseUpdate)
##   |>->  — last-arg pipe         (tgMsg |>-> extractTextFrom)
##   >>=   — Result chain          (parseResult >>= validateContent)
##
## Contract:
##   1. parseUpdate(JsonNode) → TgParseResult        (single update)
##   2. parseUpdates(JsonNode) → seq[TgParseResult]  (batch, filters unknowns)
##   3. toInbound(r, userId, mediaUrl) → InboundMessage
##   4. maxNextOffset(JsonNode, int64) → int64        (next polling offset)

import std/json
import ../../core/pipeops
import ../../domain/message

# ── Domain types ──────────────────────────────────────────────────────────────

type
  TgUpdateKind* = enum
    tukMessage        ## regular text / caption message
    tukCallbackQuery  ## inline keyboard button press
    tukUnknown        ## unsupported / no actionable content

  TgParseResult* = object
    kind*:        TgUpdateKind
    rawId*:       string   ## channel_user_id (before identity resolution)
    sessionKey*:  string   ## group: chat.id; private: from.id
    text*:        string   ## message text or /callback <data>
    channelId*:   string   ## message_id for ack / dedup
    callbackId*:  string   ## callback_query.id (non-empty → must ack)
    hasMedia*:    bool     ## true when a photo/document/voice is attached
    mediaFileId*: string   ## Telegram file_id for download (if hasMedia)

# ── Internal pure helpers ─────────────────────────────────────────────────────

func extractTextFrom(node: JsonNode): string =
  ## Returns "text" field, or "caption" for media messages.
  let t = node.getOrDefault("text").getStr("")
  if t.len > 0: t
  else: node.getOrDefault("caption").getStr("")

func extractChatKey(tgMsg: JsonNode): string =
  ## Returns the session key: chat.id for groups, from.id for private chats.
  ## Group keying lets all members of a group share one session.
  let chatType = tgMsg["chat"].getOrDefault("type").getStr("private")
  let chatId   = tgMsg["chat"]["id"].getBiggestInt()
  let fromId   = tgMsg["from"]["id"].getBiggestInt()
  if chatType in ["group", "supergroup"]: $chatId else: $fromId

func extractMediaFileId(tgMsg: JsonNode): string =
  ## Returns the best file_id for photos, documents, or voice clips.
  ## Picks the largest photo variant (last in the array).
  if tgMsg.hasKey("photo"):
    let photos = tgMsg["photo"]
    if photos.kind == JArray and photos.len > 0:
      return photos[^1].getOrDefault("file_id").getStr("")
  elif tgMsg.hasKey("document"):
    return tgMsg["document"].getOrDefault("file_id").getStr("")
  elif tgMsg.hasKey("voice"):
    return tgMsg["voice"].getOrDefault("file_id").getStr("")
  ""

# ── Public pure API ───────────────────────────────────────────────────────────

func parseUpdate*(upd: JsonNode): TgParseResult =
  ## Parses a single Telegram update object into a TgParseResult.
  ## Returns tukUnknown for updates with no actionable content.
  ##
  ## Usage:  let r = upd |> parseUpdate
  if upd.hasKey("callback_query"):
    let cq     = upd["callback_query"]
    let fromId = cq["from"]["id"].getBiggestInt()
    let msgId  = cq.getOrDefault("message").getOrDefault("message_id").getStr("")
    return TgParseResult(
      kind:       tukCallbackQuery,
      rawId:      $fromId,
      sessionKey: $fromId,
      text:       "/callback " & cq["data"].getStr(""),
      channelId:  msgId,
      callbackId: cq["id"].getStr(""),
    )

  if upd.hasKey("message"):
    let tgMsg   = upd["message"]
    let fromId  = tgMsg["from"]["id"].getBiggestInt()
    let text    = tgMsg |> extractTextFrom
    let mediaId = tgMsg |> extractMediaFileId
    let sessKey = tgMsg |> extractChatKey
    let chanId  = $tgMsg["message_id"].getInt()
    ## Skip updates that carry neither text nor a recognisable attachment.
    if text.len == 0 and mediaId.len == 0:
      return TgParseResult(kind: tukUnknown)
    return TgParseResult(
      kind:        tukMessage,
      rawId:       $fromId,
      sessionKey:  sessKey,
      text:        text,
      channelId:   chanId,
      hasMedia:    mediaId.len > 0,
      mediaFileId: mediaId,
    )

  TgParseResult(kind: tukUnknown)

func parseUpdates*(updates: JsonNode): seq[TgParseResult] =
  ## Parses a getUpdates "result" array.
  ## Filters out tukUnknown entries; only actionable updates are returned.
  ##
  ## Usage:  let results = parsed["result"] |> parseUpdates
  for upd in updates:
    let r = upd |> parseUpdate
    if r.kind != tukUnknown:
      result.add(r)

func toInbound*(r: TgParseResult; userId: UserId;
                mediaUrl = ""): InboundMessage =
  ## Converts a TgParseResult + resolved UserId into an InboundMessage.
  ## `mediaUrl` is the resolved download URL (empty when no attachment).
  InboundMessage(
    userId:     userId,
    channel:    ckTelegram,
    channelId:  r.channelId,
    callbackId: r.callbackId,
    text:       r.text,
    mediaUrl:   mediaUrl,
  )

func maxNextOffset*(currentOffset: int64; updates: JsonNode): int64 =
  ## Returns the next polling offset (max update_id + 1).
  ## Returns currentOffset unchanged when the result array is empty.
  ##
  ## Usage:  a.offset = parsed["result"] |>-> maxNextOffset(a.offset)
  var maxId = currentOffset - 1
  for upd in updates:
    let uid = upd["update_id"].getBiggestInt()
    if uid > maxId: maxId = uid
  if maxId >= currentOffset: maxId + 1 else: currentOffset

func hasCallbackId*(r: TgParseResult): bool =
  ## True when the update is a callback_query that requires an ack.
  r.kind == tukCallbackQuery and r.callbackId.len > 0
