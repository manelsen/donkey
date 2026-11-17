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

import std/[json, strutils]
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
    mediaFileName*: string ## original document name, when provided
    mediaMimeType*: string ## original MIME type, when provided
    mediaGroupId*: string  ## album id, when the message belongs to one
    threadId*:    string   ## message_thread_id for forum topics
    isGroup*:     bool     ## true for group/supergroup chats
    chatId*:      string   ## source chat id (group id in groups)

# ── Internal pure helpers ─────────────────────────────────────────────────────

func idAsString(node: JsonNode; key: string): string =
  ## Telegram sends ids as numbers; some fields accept a string too.
  let value = node.getOrDefault(key)
  if value.isNil:
    return ""
  case value.kind
  of JInt: $value.getInt
  of JString: value.getStr
  else: ""

func extractTextFrom(node: JsonNode): string =
  ## Returns "text" field, or "caption" for media messages.
  let t = node.getOrDefault("text").getStr("")
  if t.len > 0: t
  else: node.getOrDefault("caption").getStr("")

func senderId(tgMsg: JsonNode): int64 =
  ## Behavior derived from hermes-agent (MIT) fix 1a9a2d7fe8; see
  ## docs/hermes-mining/telegram/CASES.md#tg-004
  ##
  ## `from` is optional: anonymous admins in groups and channel posts arrive
  ## without it. Falling back to the chat id keeps the update addressable
  ## instead of raising on a missing key.
  ## Anonymous admins carry `sender_chat` (the channel behind the admin) and a
  ## synthetic `from` (GroupAnonymousBot). `sender_chat.id` is the author, not
  ## the destination: in a discussion group the reply must go to `chat.id`.
  let senderChat = tgMsg.getOrDefault("sender_chat")
  if senderChat != nil and senderChat.kind == JObject:
    let chatNode = tgMsg.getOrDefault("chat")
    if chatNode != nil and chatNode.kind == JObject:
      let chatId = chatNode.getOrDefault("id")
      if chatId != nil and chatId.kind == JInt:
        return chatId.getBiggestInt
  let fromNode = tgMsg.getOrDefault("from")
  if fromNode != nil and fromNode.kind == JObject:
    let id = fromNode.getOrDefault("id")
    if id != nil and id.kind == JInt:
      return id.getBiggestInt
  let chatNode = tgMsg.getOrDefault("chat")
  if chatNode != nil and chatNode.kind == JObject:
    let id = chatNode.getOrDefault("id")
    if id != nil and id.kind == JInt:
      return id.getBiggestInt
  0

func extractChatKey(tgMsg: JsonNode): string =
  ## Returns the session key: chat.id for groups, from.id for private chats.
  ## Group keying lets all members of a group share one session.
  let chatType = tgMsg["chat"].getOrDefault("type").getStr("private")
  let chatId   = tgMsg["chat"]["id"].getBiggestInt()
  let fromId   = senderId(tgMsg)
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

func extractMediaFileName(tgMsg: JsonNode): string =
  ## Returns the original document name, or a synthetic name for media.
  if tgMsg.hasKey("document"):
    let name = tgMsg["document"].getOrDefault("file_name").getStr("")
    if name.len > 0:
      return name
  elif tgMsg.hasKey("photo"):
    return "photo.jpg"
  elif tgMsg.hasKey("voice"):
    return "voice.ogg"
  ""

func extractMediaMimeType(tgMsg: JsonNode): string =
  ## Returns the document MIME type, or a sensible media fallback.
  if tgMsg.hasKey("document"):
    let mime = tgMsg["document"].getOrDefault("mime_type").getStr("")
    if mime.len > 0:
      return mime
  elif tgMsg.hasKey("photo"):
    return "image/jpeg"
  elif tgMsg.hasKey("voice"):
    return "audio/ogg"
  ""

# ── Public pure API ───────────────────────────────────────────────────────────

func isBotUpdate*(upd: JsonNode): bool =
  ## Behavior derived from hermes-agent (MIT) fix fbfe294882; see
  ## docs/hermes-mining/telegram/CASES.md#tg-003
  ##
  ## getUpdates delivers messages written by other bots in groups and can
  ## re-deliver the bot's own messages. Treating them as user input creates
  ## loops and answers nobody.
  let sender =
    if upd.hasKey("message"): upd["message"].getOrDefault("from")
    elif upd.hasKey("callback_query"): upd["callback_query"].getOrDefault("from")
    else: nil
  if sender.isNil or sender.kind != JObject:
    return false
  if not sender.getOrDefault("is_bot").getBool(false):
    return false
  ## Anonymous admins arrive as a synthetic bot user (GroupAnonymousBot) but
  ## carry `sender_chat`: the message is from a human admin, not from a bot.
  let msgNode = if upd.hasKey("message"): upd.getOrDefault("message") else: nil
  if msgNode != nil and msgNode.kind == JObject and msgNode.hasKey("sender_chat"):
    return false
  true

func parseUpdate*(upd: JsonNode): TgParseResult =
  ## Parses a single Telegram update object into a TgParseResult.
  ## Returns tukUnknown for updates with no actionable content.
  ##
  ## Usage:  let r = upd |> parseUpdate
  if upd.hasKey("callback_query"):
    let cq     = upd["callback_query"]
    let fromId = cq["from"]["id"].getBiggestInt()
    let cqMsg  = cq.getOrDefault("message")
    let msgId  = cqMsg.getOrDefault("message_id").getStr("")
    let threadId = if cqMsg.isNil: "" else: cqMsg.idAsString("message_thread_id")
    return TgParseResult(
      kind:       tukCallbackQuery,
      rawId:      $fromId,
      sessionKey: $fromId,
      text:       "/callback " & cq["data"].getStr(""),
      channelId:  msgId,
      callbackId: cq["id"].getStr(""),
      threadId:   threadId,
    )

  if upd.hasKey("message"):
    let tgMsg   = upd["message"]
    if isBotUpdate(upd):
      return TgParseResult(kind: tukUnknown)
    let fromId  = senderId(tgMsg)
    let text      = tgMsg |> extractTextFrom
    let mediaId   = tgMsg |> extractMediaFileId
    let mediaName = tgMsg |> extractMediaFileName
    let mediaMime = tgMsg |> extractMediaMimeType
    let sessKey   = tgMsg |> extractChatKey
    let chanId    = $tgMsg["message_id"].getInt()
    let chatType  = tgMsg["chat"].getOrDefault("type").getStr("private")
    let threadId  = tgMsg.idAsString("message_thread_id")
    let groupId   = tgMsg.idAsString("media_group_id")
    ## Skip updates that carry neither text nor a recognisable attachment.
    if text.len == 0 and mediaId.len == 0:
      return TgParseResult(kind: tukUnknown)
    return TgParseResult(
      kind:          tukMessage,
      rawId:         $fromId,
      sessionKey:    sessKey,
      text:          text,
      channelId:     chanId,
      hasMedia:      mediaId.len > 0,
      mediaFileId:   mediaId,
      mediaFileName: mediaName,
      mediaMimeType: mediaMime,
      mediaGroupId:  groupId,
      threadId:      threadId,
      isGroup:       chatType in ["group", "supergroup"],
      chatId:        $tgMsg["chat"]["id"].getBiggestInt(),
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
    userId:       userId,
    channel:      ckTelegram,
    channelId:    r.channelId,
    rawChannelId: r.rawId,
    callbackId:   r.callbackId,
    text:         r.text,
    mediaUrl:     mediaUrl,
    mediaFileName: r.mediaFileName,
    mediaMimeType: r.mediaMimeType,
    isGroup:       r.isGroup,
    mediaGroupId:  r.mediaGroupId,
    threadId:      r.threadId,
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

func telegramReplyTarget*(messageId, threadId: string): string =
  ## Behavior derived from hermes-agent (MIT) fix 928bb16da1; see
  ## docs/hermes-mining/telegram/CASES.md#tg-025
  ##
  ## A forum topic needs both the message to reply to and the thread the reply
  ## belongs to. The pair travels as one opaque channel target, so the rest of
  ## the app keeps treating `replyTo` as a single string.
  if threadId.len == 0:
    messageId
  else:
    messageId & "#t" & threadId

func splitTelegramReplyTarget*(target: string):
    tuple[messageId, threadId: string] =
  ## Splits the composite produced by `telegramReplyTarget`.
  let at = target.find("#t")
  if at < 0:
    (target, "")
  else:
    (target[0 ..< at], target[at + 2 .. ^1])
