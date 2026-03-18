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

import std/[json, os, strutils]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
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

proc post(a: TelegramAdapter; meth: string;
          body: JsonNode): Result[JsonNode, string] =
  let headers = @[("Content-Type", "application/json")]
  let resp = ? a.http.post(a.apiUrl(meth), $body, headers)
  try:
    let parsed = parseJson(resp.body)
    if not parsed["ok"].getBool(false):
      return err("Telegram API error [" & meth & "]: " & $parsed)
    ok(parsed)
  except CatchableError as e:
    err(e.msg)

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

proc send*(a: TelegramAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message with Markdown (plain-text fallback), split at 4096 chars.
  ## reply_to_message_id is attached only to the first chunk.
  let rawId = a.resolver.reverseChannel(msg.userId, ckTelegram)
  if rawId.len == 0:
    return err("TelegramAdapter.send: no Telegram ID for user " & $msg.userId)
  var tgId: int64
  try: tgId = parseBiggestInt(rawId).int64
  except ValueError: return err("TelegramAdapter.send: bad Telegram ID: " & rawId)
  let chunks = splitChunks(msg.text, TelegramMaxChars)
  for i, chunk in chunks:
    let r = a.sendChunk(tgId, chunk, msg.replyTo, i == 0)
    if r.isErr: return r
  ok()

proc getFileUrl*(a: TelegramAdapter; fileId: string): Result[string, string] =
  ## Resolves a Telegram file_id to a download URL via getFile API.
  let resp = ? a.post("getFile", %* {"file_id": fileId})
  try:
    let filePath = resp["result"]["file_path"].getStr()
    let base = if a.apiBase.len > 0: a.apiBase else: TelegramApiBase
    ok(base & "/file/bot" & a.token & "/" & filePath)
  except CatchableError as e:
    err(e.msg)

proc extractMediaUrl(a: TelegramAdapter; tgMsg: JsonNode): string =
  ## Returns a download URL for the best available attachment, or "".
  if tgMsg.hasKey("photo"):
    let photos = tgMsg["photo"]
    if photos.kind == JArray and photos.len > 0:
      let fileId = photos[^1].getOrDefault("file_id").getStr("")
      if fileId.len > 0:
        let r = a.getFileUrl(fileId)
        if r.isOk: return r.value
  elif tgMsg.hasKey("document"):
    let fileId = tgMsg["document"].getOrDefault("file_id").getStr("")
    if fileId.len > 0:
      let r = a.getFileUrl(fileId)
      if r.isOk: return r.value
  elif tgMsg.hasKey("voice"):
    let fileId = tgMsg["voice"].getOrDefault("file_id").getStr("")
    if fileId.len > 0:
      let r = a.getFileUrl(fileId)
      if r.isOk: return r.value
  ""

proc receive*(a: var TelegramAdapter): Result[seq[InboundMessage], string] =
  ## Long-polls getUpdates; advances a.offset on success.
  ## Handles text, photo+caption, document, and voice messages.
  let timeout = if a.pollTimeout > 0: a.pollTimeout else: DefaultPollTimeout
  let body = %* {
    "offset":  a.offset,
    "limit":   100,
    "timeout": timeout,
  }
  let parsed = ? a.post("getUpdates", body)
  try:
    let updates = parsed["result"]
    var msgs: seq[InboundMessage] = @[]
    var maxUpdateId = a.offset - 1

    for upd in updates:
      let updateId = upd["update_id"].getBiggestInt().int64
      if updateId > maxUpdateId: maxUpdateId = updateId

      ## callback_query — inline keyboard button press.
      if upd.hasKey("callback_query"):
        let cq     = upd["callback_query"]
        let fromId = cq["from"]["id"].getBiggestInt().int64
        ## Ack immediately so Telegram stops showing the loading spinner.
        discard a.post("answerCallbackQuery",
                       %* {"callback_query_id": cq["id"].getStr("")})
        msgs.add InboundMessage(
          userId:    a.resolver.resolve(ckTelegram, $fromId),
          channel:   ckTelegram,
          channelId: cq.getOrDefault("message").getOrDefault("message_id").getStr(""),
          text:      "/callback " & cq["data"].getStr(""),
          mediaUrl:  "",
        )
        continue

      if not upd.hasKey("message"): continue

      let tgMsg  = upd["message"]
      let fromId = tgMsg["from"]["id"].getBiggestInt().int64

      ## Text comes from "text" field, or "caption" for media messages.
      var text = tgMsg.getOrDefault("text").getStr("")
      if text.len == 0:
        text = tgMsg.getOrDefault("caption").getStr("")

      ## Resolve attachment to download URL.
      let mediaUrl = a.extractMediaUrl(tgMsg)

      ## Skip updates with no content to process.
      if text.len == 0 and mediaUrl.len == 0: continue

      ## P0 #3: group session keying — use chat.id for groups so all members
      ## share one session. For private chats chat.id == from.id anyway.
      let chatId   = tgMsg["chat"]["id"].getBiggestInt().int64
      let chatType = tgMsg["chat"].getOrDefault("type").getStr("private")
      let sessionRaw = if chatType in ["group", "supergroup"]: $chatId
                       else: $fromId

      msgs.add InboundMessage(
        userId:    a.resolver.resolve(ckTelegram, sessionRaw),
        channel:   ckTelegram,
        channelId: $tgMsg["message_id"].getInt(),
        text:      text,
        mediaUrl:  mediaUrl,
      )

    if maxUpdateId >= a.offset: a.offset = maxUpdateId + 1
    ok(msgs)
  except CatchableError as e:
    err(e.msg)

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
