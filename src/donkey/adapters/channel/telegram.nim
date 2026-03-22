## TelegramAdapter — ChannelPort via Bot API long polling.
##
## Auth: BOT_TOKEN in Authorization header / URL path.
## API base: https://api.telegram.org/bot{token}/
##
## Quirks absorbed here:
##   - getUpdates long-polling: offset, limit, timeout params
##   - sendMessage supports parse_mode=Markdown
##   - ack advances the offset (offset = update_id + 1)
##
## IdentityResolver is now in adapters/identity — maps telegram_user_id → UserId.

import std/[json, strutils]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/telegram_pure
import ../../ports/http
import ../http/std_http
import ../identity/identity_resolver

export identity_resolver

const
  TelegramApiBase*   = "https://api.telegram.org"
  DefaultPollTimeout = 1    ## 1 s: short enough for multi-channel fairness
  TelegramMaxChars*  = 4096 ## Telegram sendMessage hard limit

type
  TelegramAdapter* = object
    token*:       string
    apiBase*:     string        ## override for testing (e.g. mock server URL)
    offset*:      int64         ## getUpdates offset (mutable via receive)
    resolver*:    IdentityResolver
    http*:        StdHttpAdapter
    pollTimeout*: int           ## seconds; 1 for multi-channel, up to 30 for solo

# ── API helpers ───────────────────────────────────────────────────────────────

func apiUrl(a: TelegramAdapter; meth: string): string =
  let base = if a.apiBase.len > 0: a.apiBase else: TelegramApiBase
  base & "/bot" & a.token & "/" & meth

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

proc post(a: TelegramAdapter; meth: string;
          body: JsonNode): Result[JsonNode, string] =
  let headers = @[("Content-Type", "application/json")]
  a.http.post(a.apiUrl(meth), $body, headers) >>=
    proc(resp: HttpResponse): Result[JsonNode, string] {.gcsafe, raises: [].} =
      parseTgResp(meth, resp)

# ── ChannelPort implementation ────────────────────────────────────────────────

proc sendChunk(a: TelegramAdapter; chatId: int64; text, replyTo: string;
               firstChunk: bool): Result[void, string] =
  ## Sends one chunk with Markdown, falling back to plain text on parse error.
  var body = %* {"chat_id": chatId, "text": text, "parse_mode": "Markdown"}
  if firstChunk and replyTo.len > 0:
    body["reply_to_message_id"] = %replyTo
  let res = a.post("sendMessage", body)
  if res.isOk: return ok()
  ## Fallback: plain text (covers malformed markdown from LLM output).
  var plain = %* {"chat_id": chatId, "text": text}
  if firstChunk and replyTo.len > 0:
    plain["reply_to_message_id"] = %replyTo
  discard ? a.post("sendMessage", plain)
  ok()

proc sendTyping*(a: TelegramAdapter; userId: UserId): Result[void, string] =
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
  if caption.len > 0:  body["caption"] = %caption
  if replyTo.len > 0:
    try: body["reply_to_message_id"] = %parseInt(replyTo)
    except ValueError: discard
  let res = a.post(meth, body)
  if res.isOk: return ok()
  ## Fallback: send URL as text
  discard ? a.post("sendMessage", %* {"chat_id": tgId, "text": url})
  ok()

proc sendKeyboardRaw(a: TelegramAdapter; chatId: int64;
                     text: string;
                     buttons: seq[seq[(string, string)]];
                     replyTo: string): Result[void, string] =
  ## Internal helper: sends a keyboard message to a known chatId.
  var rows: seq[JsonNode]
  for row in buttons:
    var cols: seq[JsonNode]
    for (label, data) in row:
      cols.add(%* {"text": label, "callback_data": data})
    rows.add(%cols)
  var body = %* {
    "chat_id": chatId,
    "text":    text,
    "reply_markup": {"inline_keyboard": rows},
  }
  if replyTo.len > 0:
    try: body["reply_to_message_id"] = %parseInt(replyTo)
    except ValueError: discard
  discard ? a.post("sendMessage", body)
  ok()

proc send*(a: TelegramAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message with Markdown (plain-text fallback), split at 4096 chars.
  ## If msg.keyboard is non-empty, sends with an inline keyboard.
  ## If msg.mediaUrl is set, sends as photo/document (caption = msg.text).
  ## reply_to_message_id is attached only to the first chunk.
  let rawId = a.resolver.reverseChannel(msg.userId, ckTelegram)
  if rawId.len == 0:
    return err("TelegramAdapter.send: no Telegram ID for user " & $msg.userId)
  var tgId: int64
  try: tgId = parseBiggestInt(rawId).int64
  except ValueError: return err("TelegramAdapter.send: bad Telegram ID: " & rawId)
  if msg.keyboard.len > 0:
    return a.sendKeyboardRaw(tgId, msg.text, msg.keyboard, msg.replyTo)
  if msg.mediaUrl.len > 0:
    return a.sendMedia(tgId, msg.mediaUrl, msg.text, msg.replyTo)
  let chunks = splitChunks(msg.text, TelegramMaxChars)
  for i, chunk in chunks:
    let r = a.sendChunk(tgId, chunk, msg.replyTo, i == 0)
    if r.isErr: return r
  ok()

proc getFileUrl*(a: TelegramAdapter; fileId: string): Result[string, string] =
  ## Resolves a Telegram file_id to a download URL via getFile API.
  ## Uses >>= to chain post result → extract file path.
  let base  = if a.apiBase.len > 0: a.apiBase else: TelegramApiBase
  let token = a.token
  a.post("getFile", %* {"file_id": fileId}) >>=
    proc(resp: JsonNode): Result[string, string] {.gcsafe, raises: [].} =
      try:
        ok(base & "/file/bot" & token & "/" & resp["result"]["file_path"].getStr())
      except CatchableError as e:
        err(e.msg)

proc receive*(a: var TelegramAdapter): Result[seq[InboundMessage], string] =
  ## Long-polls getUpdates; advances a.offset on success.
  ## Parsing delegated to telegram_pure (|> parseUpdates).
  ## Offset advancement uses |>-> maxNextOffset(a.offset).
  let timeout = if a.pollTimeout > 0: a.pollTimeout else: DefaultPollTimeout
  let body = %* {"offset": a.offset, "limit": 100, "timeout": timeout}
  let parsed  = ? a.post("getUpdates", body)
  let updates = parsed["result"]
  let results = updates |> parseUpdates
  var msgs: seq[InboundMessage]
  for r in results:
    ## Ack callback_queries immediately (Telegram spinner).
    if r.hasCallbackId:
      discard a.post("answerCallbackQuery",
                     %* {"callback_query_id": r.callbackId})
    ## Resolve media file_id → download URL.
    let mediaUrl = if r.hasMedia: a.getFileUrl(r.mediaFileId).valueOr: ""
                   else: ""
    let userId = a.resolver.resolve(ckTelegram, r.sessionKey)
    msgs.add r.toInbound(userId, mediaUrl)
  a.offset = updates |>-> maxNextOffset(a.offset)
  ok(msgs)

proc sendReturnId*(a: TelegramAdapter; msg: OutboundMessage): Result[string, string] =
  ## Like send(), but sends only the first chunk and returns the Telegram message_id.
  ## Used by the streaming machinery to obtain the id for subsequent editMessage calls.
  let rawId = a.resolver.reverseChannel(msg.userId, ckTelegram)
  if rawId.len == 0:
    return err("TelegramAdapter.sendReturnId: no Telegram ID for " & $msg.userId)
  var tgId: int64
  try: tgId = parseBiggestInt(rawId).int64
  except ValueError: return err("TelegramAdapter.sendReturnId: bad id: " & rawId)
  let chunk = splitChunks(msg.text, TelegramMaxChars)[0]
  ## Try with Markdown, fall back to plain if Telegram rejects the formatting.
  var body = %* {"chat_id": tgId, "text": chunk, "parse_mode": "Markdown"}
  if msg.replyTo.len > 0: body["reply_to_message_id"] = %msg.replyTo
  var resp = a.post("sendMessage", body)
  if resp.isErr:
    var plain = %* {"chat_id": tgId, "text": chunk}
    if msg.replyTo.len > 0: plain["reply_to_message_id"] = %msg.replyTo
    resp = a.post("sendMessage", plain)
  try:
    ok($resp.value["result"]["message_id"].getInt())
  except CatchableError as e:
    err(e.msg)

proc editMessage*(a: TelegramAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## Edits an existing message (used to push streaming token batches).
  ## Tries Markdown first; falls back to plain on parse error. Truncates at 4096.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0:
    return err("TelegramAdapter.editMessage: no Telegram ID for " & $userId)
  var tgId: int64
  try: tgId = parseBiggestInt(rawId).int64
  except ValueError: return err("TelegramAdapter.editMessage: bad tg id: " & rawId)
  var msgIdInt: int
  try: msgIdInt = parseInt(msgId)
  except ValueError: return err("TelegramAdapter.editMessage: bad msg id: " & msgId)
  let txt = if text.len > TelegramMaxChars: text[0 ..< TelegramMaxChars] else: text
  let body = %* {"chat_id": tgId, "message_id": msgIdInt,
                 "text": txt, "parse_mode": "Markdown"}
  let res = a.post("editMessageText", body)
  if res.isOk: return ok()
  let plain = %* {"chat_id": tgId, "message_id": msgIdInt, "text": txt}
  discard ? a.post("editMessageText", plain)
  ok()

proc ack*(a: TelegramAdapter; channelId: string) =
  ## Telegram ack is implicit via offset advancement in receive().
  ## No-op for ChannelPort conformance.
  discard

proc deleteMessage*(a: TelegramAdapter; userId: UserId;
                    msgId: string): Result[void, string] =
  ## Deletes a message by id (used to remove reaction/status messages).
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("deleteMessage: no id for " & $userId)
  var chatId: int64
  try: chatId = parseBiggestInt(rawId).int64
  except ValueError: return err("deleteMessage: bad id: " & rawId)
  var msgIdInt: int
  try: msgIdInt = parseInt(msgId)
  except ValueError: return err("deleteMessage: bad msgId: " & msgId)
  discard ? a.post("deleteMessage",
                   %* {"chat_id": chatId, "message_id": msgIdInt})
  ok()

proc sendStatus*(a: TelegramAdapter; userId: UserId;
                 text: string; replyTo = ""): Result[string, string] =
  ## Sends a status/reaction message and returns its id.
  ## Used for queued🔄 / processing⚙️ / done✅ lifecycle messages.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("sendStatus: no id for " & $userId)
  var chatId: int64
  try: chatId = parseBiggestInt(rawId).int64
  except ValueError: return err("sendStatus: bad id: " & rawId)
  var body = %* {"chat_id": chatId, "text": text}
  if replyTo.len > 0:
    try: body["reply_to_message_id"] = %parseInt(replyTo)
    except ValueError: discard
  let resp = ? a.post("sendMessage", body)
  ok($resp["result"]["message_id"].getInt())

proc editStatus*(a: TelegramAdapter; userId: UserId;
                 msgId, text: string): Result[void, string] =
  ## Updates a status message in place (e.g. ⚙️ → ✅).
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("editStatus: no id for " & $userId)
  var chatId: int64
  try: chatId = parseBiggestInt(rawId).int64
  except ValueError: return err("editStatus: bad id: " & rawId)
  var msgIdInt: int
  try: msgIdInt = parseInt(msgId)
  except ValueError: return err("editStatus: bad msgId: " & msgId)
  discard ? a.post("editMessageText",
                   %* {"chat_id": chatId, "message_id": msgIdInt, "text": text})
  ok()

proc sendKeyboard*(a: TelegramAdapter; userId: UserId;
                   text: string;
                   buttons: seq[seq[(string, string)]];  ## [[("label","data"),...],...]
                   replyTo = ""): Result[string, string] =
  ## Sends a message with an inline keyboard. Returns the message id.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("sendKeyboard: no id for " & $userId)
  var chatId: int64
  try: chatId = parseBiggestInt(rawId).int64
  except ValueError: return err("sendKeyboard: bad id: " & rawId)
  var rows: seq[JsonNode]
  for row in buttons:
    var cols: seq[JsonNode]
    for (label, data) in row:
      cols.add(%* {"text": label, "callback_data": data})
    rows.add(%cols)
  var body = %* {
    "chat_id": chatId,
    "text":    text,
    "reply_markup": {"inline_keyboard": rows},
  }
  if replyTo.len > 0:
    try: body["reply_to_message_id"] = %parseInt(replyTo)
    except ValueError: discard
  let resp = ? a.post("sendMessage", body)
  ok($resp["result"]["message_id"].getInt())

proc editKeyboard*(a: TelegramAdapter; userId: UserId;
                   msgId: string;
                   buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Replaces the inline keyboard of an existing message (e.g. to remove it after selection).
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("editKeyboard: no id for " & $userId)
  var chatId: int64
  try: chatId = parseBiggestInt(rawId).int64
  except ValueError: return err("editKeyboard: bad id: " & rawId)
  var msgIdInt: int
  try: msgIdInt = parseInt(msgId)
  except ValueError: return err("editKeyboard: bad msgId: " & msgId)
  var rows: seq[JsonNode]
  for row in buttons:
    var cols: seq[JsonNode]
    for (label, data) in row:
      cols.add(%* {"text": label, "callback_data": data})
    rows.add(%cols)
  discard ? a.post("editMessageReplyMarkup", %* {
    "chat_id":      chatId,
    "message_id":   msgIdInt,
    "reply_markup": {"inline_keyboard": rows},
  })
  ok()

proc editKeyboardText*(a: TelegramAdapter; userId: UserId;
                       msgId: string;
                       text: string;
                       buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Replaces both message text and inline keyboard of an existing message.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("editKeyboardText: no id for " & $userId)
  var chatId: int64
  try: chatId = parseBiggestInt(rawId).int64
  except ValueError: return err("editKeyboardText: bad id: " & rawId)
  var msgIdInt: int
  try: msgIdInt = parseInt(msgId)
  except ValueError: return err("editKeyboardText: bad msgId: " & msgId)
  var rows: seq[JsonNode]
  for row in buttons:
    var cols: seq[JsonNode]
    for (label, data) in row:
      cols.add(%* {"text": label, "callback_data": data})
    rows.add(%cols)
  discard ? a.post("editMessageText", %* {
    "chat_id": chatId,
    "message_id": msgIdInt,
    "text": text,
    "reply_markup": {"inline_keyboard": rows},
  })
  ok()

proc setMyCommands*(a: TelegramAdapter): Result[void, string] =
  ## Registers bot commands in the Telegram menu (the / hint list).
  let cmds = %* [
    {"command": "help",    "description": "Ajuda e lista de comandos"},
    {"command": "reset",   "description": "Reinicia a conversa atual"},
    {"command": "mycode",  "description": "Gera código de linkagem cross-channel"},
    {"command": "models",  "description": "Seleciona modelo de IA"},
    {"command": "think",   "description": "Controla o nível de raciocínio"},
    {"command": "memory",  "description": "Exibe memórias salvas"},
    {"command": "forget",  "description": "Apaga as memórias salvas"},
    {"command": "status",  "description": "Snapshot da sessão atual"},
    {"command": "ping",    "description": "Testa latência do provider"},
    {"command": "debug",   "description": "Ativa/desativa modo verbose"},
    {"command": "doctor",  "description": "Diagnóstico do sistema"},
    {"command": "start",   "description": "Inicia ou recomeça a conversa"},
  ]
  discard ? a.post("setMyCommands", %* {"commands": cmds})
  ok()

# ── Constructor ───────────────────────────────────────────────────────────────

proc newTelegramAdapter*(token: string;
                         identityPath: string;
                         apiBase      = "";
                         pollTimeout  = DefaultPollTimeout): TelegramAdapter =
  TelegramAdapter(
    token:       token,
    apiBase:     apiBase,
    offset:      0,
    resolver:    newIdentityResolver(identityPath),
    http:        newStdHttpAdapter(),
    pollTimeout: pollTimeout,
  )
