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

import std/[json, sequtils, strutils]
import ../../core/types
import ../../core/pipeops
import ../../core/telegram_format
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
          body: JsonNode): Result[JsonNode, string] {.gcsafe, raises: [].} =
  try:
    let headers = @[("Content-Type", "application/json")]
    a.http.post(a.apiUrl(meth), $body, headers) >>=
      proc(resp: HttpResponse): Result[JsonNode, string] {.gcsafe, raises: [].} =
        parseTgResp(meth, resp)
  except Exception as e:
    err(e.msg)

# ── ChannelPort implementation ────────────────────────────────────────────────

proc sendChunk(a: TelegramAdapter; chatId: int64; text, replyTo: string;
               firstChunk: bool): Result[void, string] =
  ## Sends one chunk with HTML (converted from MD), falling back to plain text.
  let html = markdownToTelegramHtml(text)
  var body = %* {"chat_id": chatId, "text": html, "parse_mode": "HTML"}
  if firstChunk and replyTo.len > 0:
    body["reply_to_message_id"] = %replyTo
  let res = a.post("sendMessage", body)
  if res.isOk: return ok()
  ## Fallback: plain text
  var plain = %* {"chat_id": chatId, "text": text}
  if firstChunk and replyTo.len > 0:
    plain["reply_to_message_id"] = %replyTo
  discard ? a.post("sendMessage", plain)
  ok()

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
                     replyTo: string): Result[string, string] =
  ## Internal helper: sends a keyboard message to a known chatId.
  ## Returns the Telegram message_id of the sent message.
  var rows: seq[JsonNode]
  for row in buttons:
    var cols: seq[JsonNode]
    for (label, data) in row:
      cols.add(%* {"text": label, "callback_data": data})
    rows.add(%cols)
  let html = markdownToTelegramHtml(text)
  var body = %* {
    "chat_id":    chatId,
    "text":       html,
    "parse_mode": "HTML",
    "reply_markup": {"inline_keyboard": rows},
  }
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

  if msg.keyboard.len > 0:
    discard ? a.sendKeyboardRaw(chatId, msg.text, msg.keyboard, msg.replyTo)
    return ok()

  if msg.mediaUrl.len > 0:
    return a.sendMedia(chatId, msg.mediaUrl, msg.text, msg.replyTo)

  for i, chunk in splitChunks(msg.text, TelegramMaxChars):
    ? a.sendChunk(chatId, chunk, msg.replyTo, i == 0)
  ok()

proc sendReturnId*(a: TelegramAdapter; msg: OutboundMessage): Result[string, string] =
  ## Sends and returns the message_id.
  let rawId = a.resolver.reverseChannel(msg.userId, ckTelegram)
  if rawId.len == 0: return err("TelegramAdapter.sendReturnId: no id for " & $msg.userId)
  let chatId = parseBiggestInt(rawId).int64

  if msg.keyboard.len > 0:
    return a.sendKeyboardRaw(chatId, msg.text, msg.keyboard, msg.replyTo)

  if msg.mediaUrl.len > 0:
    ? a.sendMedia(chatId, msg.mediaUrl, msg.text, msg.replyTo)
    return ok("")

  var lastId = ""
  for i, chunk in splitChunks(msg.text, TelegramMaxChars):
    let html = markdownToTelegramHtml(chunk)
    var body = %* {"chat_id": chatId, "text": html, "parse_mode": "HTML"}
    if i == 0 and msg.replyTo.len > 0:
      body["reply_to_message_id"] = %msg.replyTo
    let res = a.post("sendMessage", body)
    if res.isOk:
      lastId = $res.value["result"]["message_id"].getInt()
    else:
      # Fallback
      body.delete("parse_mode")
      body["text"] = %chunk
      let res2 = ? a.post("sendMessage", body)
      lastId = $res2["result"]["message_id"].getInt()
  ok(lastId)

proc editMessage*(a: TelegramAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## Edits an existing message's text.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("editMessage: no id for " & $userId)
  let chatId = parseBiggestInt(rawId).int64
  let html = markdownToTelegramHtml(text)
  var body = %* {"chat_id": chatId, "message_id": parseBiggestInt(msgId), "text": html, "parse_mode": "HTML"}
  let res = a.post("editMessageText", body)
  if res.isOk: return ok()
  # Fallback
  body.delete("parse_mode")
  body["text"] = %text
  discard ? a.post("editMessageText", body)
  ok()

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
  let markup = %* {"inline_keyboard": buttons.mapIt(it.mapIt(%* {"text": it[0], "callback_data": it[1]}))}
  discard ? a.post("editMessageReplyMarkup",
                   %* {"chat_id": chatId, "message_id": parseBiggestInt(msgId),
                       "reply_markup": markup})
  ok()

proc editKeyboardText*(a: TelegramAdapter; userId: UserId;
                       msgId, text: string;
                       buttons: seq[seq[(string, string)]]): Result[void, string] =
  ## Edits both text AND keyboard.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("editKeyboardText: no id for " & $userId)
  let chatId = parseBiggestInt(rawId).int64
  let markup = %* {"inline_keyboard": buttons.mapIt(it.mapIt(%* {"text": it[0], "callback_data": it[1]}))}
  let html = markdownToTelegramHtml(text)
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
  body["text"] = %text
  discard ? a.post("editMessageText", body)
  ok()

proc setMessageReaction*(a: TelegramAdapter; userId: UserId;
                          msgId, emoji: string): Result[void, string] =
  ## Sets a reaction (emoji) on a message.
  let rawId = a.resolver.reverseChannel(userId, ckTelegram)
  if rawId.len == 0: return err("setMessageReaction: no id for " & $userId)
  try:
    let chatId = parseBiggestInt(rawId).int64
    let msgIdInt = parseBiggestInt(msgId).int64
    var reaction = newJArray()
    if emoji.len > 0:
      reaction.add(%* {"type": "emoji", "emoji": emoji})

    discard ? a.post("setMessageReaction",
                     %* {"chat_id": chatId, "message_id": msgIdInt,
                         "reaction": reaction})
    ok()
  except CatchableError as e:
    err(e.msg)

proc registerBotCommands*(a: TelegramAdapter): Result[void, string] =
  ## Registers bot commands in the Telegram menu (the / hint list).
  let cmds = %* [
    {"command": "help",    "description": "Ajuda e lista de comandos"},
    {"command": "reset",   "description": "Reinicia a conversa atual"},
    {"command": "mycode",  "description": "Gera código de linkagem cross-channel"},
    {"command": "models",  "description": "Seleciona modelo de IA"},
    {"command": "think",   "description": "Controla o nível de raciocínio"},
    {"command": "reasoning", "description": "Exibe o pensamento do modelo (blockquote)"},
    {"command": "memory",  "description": "Exibe memórias salvas"},
    {"command": "forget",  "description": "Apaga as memórias salvas"},
    {"command": "status",  "description": "Snapshot da sessão atual"},
    {"command": "ping",    "description": "Testa latência do provider"},
    {"command": "debug",    "description": "Ativa/desativa modo verbose"},
    {"command": "doctor",  "description": "Diagnóstico do sistema"},
    {"command": "continue", "description": "Continua sessão de outro canal"},
    {"command": "start",   "description": "Inicia ou recomeça a conversa"},
  ]
  discard ? a.post("setMyCommands", %* {"commands": cmds})
  ok()

proc receive*(a: var TelegramAdapter): Result[seq[InboundMessage], string] =
  ## Long-polls getUpdates and returns new user messages.
  ## Advances update offset.
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
      msgs.add(parsed.toInbound(uid))
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

proc newTelegramAdapter*(token: string; identityPath: string;
                         apiBase = ""; pollTimeout = DefaultPollTimeout): TelegramAdapter =
  TelegramAdapter(
    token:       token,
    apiBase:     apiBase,
    offset:      0,
    resolver:    newIdentityResolver(identityPath),
    http:        newStdHttpAdapter(),
    pollTimeout: pollTimeout,
  )
