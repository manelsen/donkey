## TelegramAdapter — ChannelPort via Bot API long polling.
##
## Auth: BOT_TOKEN in Authorization header / URL path.
## API base: https://api.telegram.org/bot{token}/
##
## Quirks absorbed here:
##   - getUpdates long-polling: offset, limit, timeout params
##   - sendMessage supports parse_mode=HTML (converted from Markdown)
##   - ack advances the offset (offset = update_id + 1)
##
## IdentityResolver is now in adapters/identity — maps telegram_user_id → UserId.

import std/[json, os, sequtils, strutils]
import ../../core/types
import ../../core/pipeops
import ../../core/commands/command_catalog
import ../../core/telegram_format
import ../../core/channels/flood_gate
import ../../core/media_download
import ../../domain/message
import ../../domain/channels/telegram_pure
import ../../domain/channels/telegram_split
import ../../domain/channels/telegram_policy
import ../../ports/http
import ../../ports/channel
import ../http/std_http
import ../identity/identity_resolver

export identity_resolver
export sanitizeForTelegram
export FileDownload

const
  TelegramApiBase*   = "https://api.telegram.org"
  DefaultPollTimeout = 1    ## 1 s: short enough for multi-channel fairness
  TelegramMaxChars*  = 4096 ## Telegram sendMessage hard limit
  TelegramCaptionLimit* = 1024 ## media caption limit

const TelegramReactionFallbacks* = ["👍", "👌", "✅", "🔥", "👏"]

type
  TelegramAdapter* = object
    token*:       string
    apiBase*:     string        ## override for testing (e.g. mock server URL)
    offset*:      int64         ## getUpdates offset (mutable via receive)
    resolver*:    IdentityResolver
    http*:        StdHttpAdapter
    flood*:       FloodGate      ## per-chat penalty windows
    pollTimeout*: int           ## seconds; 1 for multi-channel, up to 30 for solo

# ── API helpers ───────────────────────────────────────────────────────────────

func apiBaseValue*(a: TelegramAdapter): string =
  ## Base used for Bot API calls. Empty keeps the official endpoint; a proxy
  ## can be supplied through DONKEY_TELEGRAM_API_BASE.
  if a.apiBase.len > 0: a.apiBase else: TelegramApiBase

func apiUrl(a: TelegramAdapter; meth: string): string =
  a.apiBaseValue & "/bot" & a.token & "/" & meth

func telegramLinkPreviewsEnabled*(): bool =
  linkPreviewsFromEnv(getEnv("DONKEY_TELEGRAM_LINK_PREVIEW"))

func telegramMediaTimeoutSec*(): int =
  ## Behavior derived from hermes-agent (MIT) fix 85e673b4a5; see
  ## docs/hermes-mining/telegram/CASES.md#tg-030
  ##
  ## Uploads get a larger deadline than text calls.
  let raw = getEnv("DONKEY_TELEGRAM_MEDIA_TIMEOUT_SEC").strip
  if raw.len == 0:
    return 300
  let parsed = try:
    raw.parseInt
  except ValueError:
    return 300
  if parsed <= 0: 300 else: parsed



proc parseTgResp(meth: string; resp: HttpResponse): Result[JsonNode, string]
                 {.gcsafe, raises: [].} =
  ## Validates a Telegram API HTTP response; designed for >>= chaining.
  try:
    let parsed = parseJson(resp.body)
    if not parsed["ok"].getBool(false):
      return err("Telegram API error [" & meth & "]: " & $parsed)
    ok(parsed)
  except CatchableError as e:
    err(e.msg)

proc postWith(a: TelegramAdapter; meth: string; body: JsonNode;
              timeoutSec: int): Result[JsonNode, string] {.gcsafe, raises: [].} =
  try:
    let headers = @[("Content-Type", "application/json")]
    let sent =
      if timeoutSec > 0:
        a.http.postWithTimeout(a.apiUrl(meth), $body, headers, timeoutSec)
      else:
        a.http.post(a.apiUrl(meth), $body, headers)
    sent >>=
      proc(resp: HttpResponse): Result[JsonNode, string] {.gcsafe, raises: [].} =
        parseTgResp(meth, resp)
  except Exception as e:
    err(e.msg)

proc post(a: TelegramAdapter; meth: string;
          body: JsonNode): Result[JsonNode, string] {.gcsafe, raises: [].} =
  a.postWith(meth, body, 0)

func chatAllowedReactionEmojis*(chatInfo: JsonNode): tuple[restricted: bool, emojis: seq[string]]
                               {.gcsafe, raises: [].} =
  let available = chatInfo{"available_reactions"}
  if available.isNil or available.kind != JArray:
    return (false, @[])
  result.restricted = true
  for item in available:
    if item.getOrDefault("type").getStr("") != "emoji":
      continue
    let emoji = item.getOrDefault("emoji").getStr("")
    if emoji.len > 0:
      result.emojis.add(emoji)

func pickTelegramReactionEmoji*(desired: string; chatInfo: JsonNode): string
                               {.gcsafe, raises: [].} =
  if desired.len == 0:
    return ""
  let (restricted, emojis) = chatAllowedReactionEmojis(chatInfo)
  if not restricted:
    return desired
  if desired in emojis:
    return desired
  for fallback in TelegramReactionFallbacks:
    if fallback in emojis:
      return fallback
  if emojis.len > 0:
    return emojis[0]
  ""

func renderTelegramHtml*(text: string; isHtml = false): string =
  let sanitized = sanitizeForTelegram(text)
  if isHtml: sanitized
  else: markdownToTelegramHtml(sanitized)

# ── ChannelPort implementation ────────────────────────────────────────────────

proc sendMessageBody(a: TelegramAdapter; body: JsonNode; replyTo: string;
                     firstChunk: bool): Result[JsonNode, string] {.gcsafe.} =
  ## Posts a sendMessage payload. When the reply anchor no longer exists, the
  ## API refuses the whole message; retry once without the anchor so the text
  ## still arrives. A per-chat flood window is respected before the call.
  let chatId = body.getOrDefault("chat_id").getBiggestInt(0)
  let waitMs = a.flood.remainingMs(chatId, epochMs())
  if waitMs > 0:
    sleep(int(min(waitMs, FloodMaxWaitMs)))
  let res = a.post("sendMessage", body)
  if res.isErr:
    let retryAfter = parseRetryAfterMs(res.error)
    if retryAfter > 0:
      a.flood.noteRetryAfter(chatId, retryAfter, epochMs())
  if res.isOk: return res
  if firstChunk and replyTo.len > 0 and isMissingReplyAnchorError(res.error):
    var retry = body
    retry.delete("reply_to_message_id")
    return a.post("sendMessage", retry)
  res

proc sendChunkOnce(a: TelegramAdapter; chatId: int64; text, replyTo: string;
                   firstChunk: bool;
                   isHtml = false): Result[void, string] =
  ## Sends one chunk with HTML (converted from MD), falling back to plain text.
  let html = renderTelegramHtml(text, isHtml)
  var body = %* {"chat_id": chatId, "text": html, "parse_mode": "HTML"}
  if firstChunk and replyTo.len > 0:
    body["reply_to_message_id"] = %replyTo
  body = withLinkPreviewPolicy(body, telegramLinkPreviewsEnabled())
  let res = a.sendMessageBody(body, replyTo, firstChunk)
  if res.isOk: return ok()
  ## Fallback: plain text
  var plain = %* {"chat_id": chatId, "text": text}
  if firstChunk and replyTo.len > 0:
    plain["reply_to_message_id"] = %replyTo
  plain = withLinkPreviewPolicy(plain, telegramLinkPreviewsEnabled())
  discard ? a.sendMessageBody(plain, replyTo, firstChunk)
  ok()

proc sendChunk(a: TelegramAdapter; chatId: int64; text, replyTo: string;
               firstChunk: bool;
               isHtml = false): Result[void, string] =
  ## Sends one chunk, retrying once when flood control refused it. The chunks
  ## already delivered are not resent: the retry starts at the refused chunk.
  var retried = false
  while true:
    let sent = a.sendChunkOnce(chatId, text, replyTo, firstChunk, isHtml)
    if sent.isOk:
      return ok()
    if not shouldRetryChunk(sent.error, retried):
      return sent
    retried = true

proc sendTyping*(a: TelegramAdapter; userId: UserId): Result[void, string] {.gcsafe.} =
  ## Sends a "typing…" indicator to the user's chat.
  ## For DM bots the chat_id equals the Telegram user ID.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("TelegramAdapter.sendTyping: no id for " & $userId)
  try:
    let tgId = parseBiggestInt(rawId).int64
    discard ? a.post("sendChatAction", %* {"chat_id": tgId, "action": "typing"})
    ok()
  except ValueError:
    err("TelegramAdapter.sendTyping: bad id: " & rawId)

proc sendMedia*(a: TelegramAdapter; tgId: int64;
                url, caption, replyTo: string): Result[void, string] =
  ## Sends a photo (if URL looks like an image) or a document otherwise.
  ## Falls back to sending a plain URL as text if the API call fails.
  let isImage = url.endsWith(".jpg") or url.endsWith(".jpeg") or
                url.endsWith(".png") or url.endsWith(".gif") or
                url.endsWith(".webp")
  let meth    = if isImage: "sendPhoto" else: "sendDocument"
  let fileKey = if isImage: "photo"     else: "document"
  var body = %* {"chat_id": tgId, fileKey: url}
  if caption.len > 0:
    body["caption"] = %clipCaption(caption, TelegramCaptionLimit)
  if replyTo.len > 0:
    try: body["reply_to_message_id"] = %parseInt(replyTo)
    except ValueError: discard
  let mediaTimeout = telegramMediaTimeoutSec()
  let res = a.postWith(meth, body, mediaTimeout)
  if res.isOk: return ok()
  if meth == "sendPhoto":
    ## A photo outside the dimension/size limits is still a valid document.
    let docRes = a.postWith("sendDocument", asDocumentBody(body), mediaTimeout)
    if docRes.isOk: return ok()
  ## Fallback: send URL as text
  discard ? a.post("sendMessage", %* {"chat_id": tgId, "text": url})
  ok()

proc validateButtons(buttons: seq[seq[(string, string)]]): Result[void, string] =
  for row in buttons:
    for (_, data) in row:
      let reason = callbackDataError(data)
      if reason.len > 0:
        return err(reason)
  ok()

proc sendKeyboardRaw(a: TelegramAdapter; chatId: int64;
                     text: string;
                     buttons: seq[seq[(string, string)]];
                     replyTo: string;
                     isHtml = false): Result[string, string] =
  ## Internal helper: sends a keyboard message to a known chatId.
  ## Returns the Telegram message_id of the sent message.
  ? validateButtons(buttons)
  var rows: seq[JsonNode]
  for row in buttons:
    var cols: seq[JsonNode]
    for (label, data) in row:
      cols.add(%* {"text": label, "callback_data": data})
    rows.add(%cols)
  let html = renderTelegramHtml(text, isHtml)
  var body = %* {
    "chat_id":    chatId,
    "text":       html,
    "parse_mode": "HTML",
    "reply_markup": {"inline_keyboard": rows},
  }
  body = withLinkPreviewPolicy(body, telegramLinkPreviewsEnabled())
  if replyTo.len > 0:
    try: body["reply_to_message_id"] = %parseInt(replyTo)
    except ValueError: discard
  let res = a.post("sendMessage", body)
  if res.isOk:
    return ok($res.value["result"]["message_id"].getInt())
  body.delete("parse_mode")
  body["text"] = %text
  let plain = ? a.post("sendMessage", body)
  ok($plain["result"]["message_id"].getInt())

proc send*(a: TelegramAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message with Markdown (plain-text fallback), split at 4096 chars.
  ## If msg.keyboard is non-empty, sends with an inline keyboard.
  ## If msg.mediaUrl is set, sends as photo/document (caption = msg.text).
  let rawId = a.resolver.reverseChannel(msg.userId, ckTelegram)
  if rawId.len == 0: return err("TelegramAdapter.send: no id for " & $msg.userId)
  let chatId = parseBiggestInt(rawId).int64

  if shouldSkipOutboundText(msg.text) and msg.mediaUrl.len == 0:
    return ok()   ## the API refuses empty text; nothing to deliver

  if msg.keyboard.len > 0:
    discard ? a.sendKeyboardRaw(chatId, msg.text, msg.keyboard, msg.replyTo, msg.isHtml)
    return ok()

  if msg.mediaUrl.len > 0:
    let (head, tail) = splitCaption(msg.text, TelegramCaptionLimit)
    ? a.sendMedia(chatId, msg.mediaUrl, head, msg.replyTo)
    if tail.strip.len > 0:
      for i, chunk in splitForTelegram(tail, TelegramMaxChars):
        ? a.sendChunk(chatId, chunk, "", i == 0, msg.isHtml)
    return ok()

  for i, chunk in splitForTelegram(msg.text, TelegramMaxChars):
    ? a.sendChunk(chatId, chunk, msg.replyTo, i == 0, msg.isHtml)
  ok()

proc sendReturnId*(a: TelegramAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends and returns the message_id.
  let rawId = a.resolver.reverseChannel(msg.userId, ckTelegram)
  if rawId.len == 0: return err("TelegramAdapter.sendReturnId: no id for " & $msg.userId)
  let chatId = parseBiggestInt(rawId).int64

  if msg.keyboard.len > 0:
    return a.sendKeyboardRaw(chatId, msg.text, msg.keyboard, msg.replyTo, msg.isHtml)

  if msg.mediaUrl.len > 0:
    let (head, tail) = splitCaption(msg.text, TelegramCaptionLimit)
    ? a.sendMedia(chatId, msg.mediaUrl, head, msg.replyTo)
    if tail.strip.len > 0:
      for i, chunk in splitForTelegram(tail, TelegramMaxChars):
        ? a.sendChunk(chatId, chunk, "", i == 0, msg.isHtml)
    return ok("")

  if shouldSkipOutboundText(msg.text):
    return ok("")   ## the API refuses empty text; nothing to deliver

  var lastId = ""
  for i, chunk in splitForTelegram(msg.text, TelegramMaxChars):
    let html = renderTelegramHtml(chunk, msg.isHtml)
    var body = %* {"chat_id": chatId, "text": html, "parse_mode": "HTML"}
    body = withLinkPreviewPolicy(body, telegramLinkPreviewsEnabled())
    if i == 0 and msg.replyTo.len > 0:
      body["reply_to_message_id"] = %msg.replyTo
    let res = a.sendMessageBody(body, msg.replyTo, i == 0)
    if res.isOk:
      lastId = $res.value["result"]["message_id"].getInt()
    else:
      # Fallback
      body.delete("parse_mode")
      body["text"] = %chunk
      let res2 = ? a.sendMessageBody(body, msg.replyTo, i == 0)
      lastId = $res2["result"]["message_id"].getInt()
  ok(lastId)

proc editMessage*(a: TelegramAdapter; userId: UserId;
                  msgId, text: string;
                  isHtml = false): Result[void, string] =
  ## Edits an existing message's text.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("editMessage: no id for " & $userId)
  let chatId = parseBiggestInt(rawId).int64
  let sanitizedText = sanitizeForTelegram(text)
  let chunks = planEditChunks(sanitizedText, TelegramMaxChars)
  let html = renderTelegramHtml(chunks[0], isHtml)
  var body = %* {"chat_id": chatId, "message_id": parseBiggestInt(msgId), "text": html, "parse_mode": "HTML"}
  let res = a.post("editMessageText", body)
  if res.isOk or isEditNoopError(res.error):
    ## The tail of an oversized edit cannot fit in the edited message, and a
    ## no-op edit still leaves the tail to deliver.
    for i in 1 ..< chunks.len:
      ? a.sendChunk(chatId, chunks[i], "", false, isHtml)
    return ok()
  # Fallback
  body.delete("parse_mode")
  body["text"] = %chunks[0]
  let plain = a.post("editMessageText", body)
  if plain.isOk or isEditNoopError(plain.error):
    for i in 1 ..< chunks.len:
      ? a.sendChunk(chatId, chunks[i], "", false, isHtml)
    return ok()
  err(plain.error)

proc sendKeyboard*(a: TelegramAdapter; userId: UserId;
                   text: string;
                   buttons: seq[seq[(string, string)]];  ## [[("label","data"),...],...]
                   replyTo = ""): Result[string, string] =
  ## Sends a message with an inline keyboard.
  ## Returns the Telegram message_id so the caller can later edit the message.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("sendKeyboard: no id for " & $userId)
  var chatId: int64
  try: chatId = parseBiggestInt(rawId).int64
  except ValueError: return err("sendKeyboard: bad id: " & rawId)
  a.sendKeyboardRaw(chatId, text, buttons, replyTo)

proc editKeyboard*(a: TelegramAdapter; userId: UserId;
                   msgId: string;
                   buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Replaces the inline keyboard of an existing message (e.g. to remove it after selection).
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("editKeyboard: no id for " & $userId)
  let chatId = parseBiggestInt(rawId).int64
  ? validateButtons(buttons)
  let markup = %* {"inline_keyboard": buttons.mapIt(it.mapIt(%* {"text": it[0], "callback_data": it[1]}))}
  discard ? a.post("editMessageReplyMarkup",
                   %* {"chat_id": chatId, "message_id": parseBiggestInt(msgId),
                       "reply_markup": markup})
  ok()

proc editKeyboardText*(a: TelegramAdapter; userId: UserId;
                       msgId, text: string;
                       buttons: seq[seq[(string, string)]];
                       isHtml = false): Result[void, string] =
  ## Edits both text AND keyboard.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("editKeyboardText: no id for " & $userId)
  let chatId = parseBiggestInt(rawId).int64
  ? validateButtons(buttons)
  let markup = %* {"inline_keyboard": buttons.mapIt(it.mapIt(%* {"text": it[0], "callback_data": it[1]}))}
  let sanitizedText = sanitizeForTelegram(text)
  let html = renderTelegramHtml(sanitizedText, isHtml)
  var body = %* {
    "chat_id":    chatId,
    "message_id": parseBiggestInt(msgId),
    "text":       html,
    "parse_mode": "HTML",
    "reply_markup": markup
  }
  let res = a.post("editMessageText", body)
  if res.isOk: return ok()
  # Fallback
  body.delete("parse_mode")
  body["text"] = %sanitizedText
  discard ? a.post("editMessageText", body)
  ok()

proc setMessageReaction*(a: TelegramAdapter; userId: UserId;
                          channelId, msgId, emoji: string): Result[void, string] =
  ## Sets a reaction (emoji) on a message.
  discard channelId
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("setMessageReaction: no id for " & $userId)

  try:
    let chatId = parseBiggestInt(rawId).int64
    let msgIdInt = parseBiggestInt(msgId).int64
    var selectedEmoji = emoji
    if emoji.len > 0:
      let chatRes = a.post("getChat", %* {"chat_id": chatId})
      if chatRes.isOk:
        selectedEmoji = pickTelegramReactionEmoji(emoji, chatRes.value.getOrDefault("result"))
        if selectedEmoji.len == 0:
          return ok()
    var reaction = newJArray()
    if selectedEmoji.len > 0:
      reaction.add(%* {"type": "emoji", "emoji": selectedEmoji})

    let res = a.post("setMessageReaction",
                     %* {"chat_id": chatId, "message_id": msgIdInt,
                         "reaction": reaction})
    if res.isErr:
      let errMsg = res.error
      let lowerErr = errMsg.toLowerAscii()
      if "reaction_invalid" in lowerErr or
         "message can't be reacted" in lowerErr or
         "reactions are unavailable" in lowerErr or
         "message reactions are not supported" in lowerErr:
        return ok()
      return err(errMsg)
    ok()
  except CatchableError as e:
    err(e.msg)

proc getFile*(a: TelegramAdapter; fileId: string): Result[string, string] =
  ## Gets file path from Telegram API using file_id.
  ## Returns the file_path that can be used to download the file.
  let res = a.post("getFile", %* {"file_id": fileId})
  if res.isOk:
    let resultNode = res.value["result"]
    let filePath = resultNode.getOrDefault("file_path").getStr("")
    if filePath.len == 0:
      return err("getFile: empty file_path for id=" & fileId)
    ok(filePath)
  else:
    err(res.error)

proc downloadFileBytes*(a: TelegramAdapter; filePath: string): Result[seq[byte], string] =
  ## Downloads file content from Telegram servers.
  ## filePath should be obtained from getFile() first.
  try:
    let url = a.apiBaseValue & "/file/bot" & a.token & "/" & filePath
    let headers: seq[(string, string)] = @[]
    let resp = ? a.http.get(url, headers)
    
    # Convert string body to seq[byte]
    var data = newSeq[byte](resp.body.len)
    for i in 0 ..< resp.body.len:
      data[i] = cast[byte](resp.body[i])
    ok(data)
  except CatchableError as e:
    err(e.msg)

proc downloadFile*(a: TelegramAdapter; fileId: string): Result[FileDownload, string] =
  ## Complete file download: gets file info and downloads content.
  ## Returns FileDownload with path, name, size and data.
  let filePath =
    if fileId.startsWith("tg://"):
      fileId["tg://".len .. ^1]
    else:
      ? a.getFile(fileId)
  let data = ? a.downloadFileBytes(filePath)
  
  # Extract file name from path
  let fileName = filePath.split('/')[^1]
  
  ok(FileDownload(
    fileName: fileName,
    fileSize: data.len.int64,
    mimeType: extractMimeType(filePath),
    localPath: "",
    data: data
  ))

proc registerBotCommands*(a: TelegramAdapter): Result[void, string] =
  ## Registers bot commands in the Telegram menu (the / hint list).
  let cmds = newCommandCatalog().toTelegramCommandsJson()
  discard ? a.post("setMyCommands", %* {"commands": cmds})
  ok()

proc receive*(a: var TelegramAdapter): Result[seq[InboundMessage], string] =
  ## Long-polls getUpdates and returns new user messages.
  ## Advances update offset.
  ## Preserves Telegram file_id for later download via getFile.
  try:
    let url = a.apiUrl("getUpdates") & "?offset=" & $a.offset &
              "&timeout=" & $a.pollTimeout &
              "&allowed_updates=[\"message\",\"callback_query\"]"
    let resp = ? a.http.get(url)
    let j = ? parseTgResp("getUpdates", resp)
    let updates = j["result"]
    var msgs: seq[InboundMessage]
    for u in updates:
      let updateId = u["update_id"].getBiggestInt()
      a.offset = updateId + 1
      let parsed = parseUpdate(u)
      if parsed.kind == tukUnknown: continue
      let uid = a.resolver.resolve(ckTelegram, parsed.rawId)
      if ($uid).len == 0:
        ## Identity storage is unreadable; drop rather than create an empty user.
        continue
      
      var msg = parsed.toInbound(uid)
      if parsed.hasMedia and parsed.mediaFileId.len > 0:
        msg.mediaUrl = parsed.mediaFileId
      msgs.add(msg)
    ok(msgs)
  except CatchableError as e:
    err("TelegramAdapter.receive: " & e.msg)

proc ack*(a: TelegramAdapter; msgId: string) =
  ## No-op: Telegram offset is advanced during receive().
  discard

proc answerCallback*(a: TelegramAdapter; callbackId: string): Result[void, string] =
  ## Acknowledges a callback query to remove the loading state in the client.
  if callbackId.len == 0: return ok()
  discard ? a.post("answerCallbackQuery", %* {"callback_id": callbackId})
  ok()

func telegramHttpTimeoutSec*(): int =
  ## Behavior derived from hermes-agent (MIT) fix 04057250a3; see
  ## docs/hermes-mining/telegram/CASES.md#tg-030
  ##
  ## Bot API calls are bounded by a wall-clock deadline; media uploads get a
  ## larger one because the transfer itself is slower.
  let raw = getEnv("DONKEY_TELEGRAM_TIMEOUT_SEC").strip
  if raw.len == 0:
    return 60
  let parsed = try:
    raw.parseInt
  except ValueError:
    return 60
  if parsed <= 0: 60 else: parsed

func telegramProxyUrl*(): string =
  ## Behavior derived from hermes-agent (MIT) fix d7c41f3cef; see
  ## docs/hermes-mining/telegram/CASES.md#tg-022
  ##
  ## The Bot API may only be reachable through a proxy. The Telegram-specific
  ## variable wins over the generic web proxy.
  let specific = getEnv("DONKEY_TELEGRAM_PROXY").strip
  if specific.len > 0:
    return specific
  getEnv("DONKEY_WEB_PROXY").strip

proc newTelegramAdapter*(token: string; identityPath: string;
                         apiBase = ""; pollTimeout = DefaultPollTimeout): TelegramAdapter =
  TelegramAdapter(
    token:       token,
    apiBase:     apiBase,
    offset:      0,
    resolver:    newIdentityResolver(identityPath),
    flood:       newFloodGate(),
    http:        newStdHttpAdapter(
                   timeout = telegramHttpTimeoutSec(),
                   proxy = telegramProxyUrl(),
                   allowlist = @["api.telegram.org"],
                   retryNonIdempotent = false),
    pollTimeout: pollTimeout,
  )
