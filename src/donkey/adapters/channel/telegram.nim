## TelegramAdapter — ChannelPort via Bot API long polling.
##
## Auth: BOT_TOKEN in path segment /bot{token}/
## API base: https://api.telegram.org/bot{token}/
##
## Quirks absorbed here:
##   - getUpdates long-polling: offset, limit, timeout params
##   - pollTimeout=0 → non-blocking (daemon uses this for async loop)
##   - sendMessage: parse_mode=HTML with plain-text fallback
##   - sendReturnId: returns message_id for streaming in-place edits
##   - editMessageText: updates existing message (streaming)
##   - ack is implicit via offset advancement in receive()

import std/[httpclient, json, os, strutils]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../identity/identity_resolver

export identity_resolver   ## re-export so callers get IdentityResolver type

const
  TelegramApiBase* = "https://api.telegram.org"

type
  TelegramAdapter* = object
    token*:       string
    apiBase*:     string   ## override for testing
    offset*:      int64
    pollTimeout*: int      ## seconds; 0 = non-blocking
    resolver*:    IdentityResolver

# ── API helpers ────────────────────────────────────────────────────────────────

proc apiUrl(a: TelegramAdapter; meth: string): string =
  let base = if a.apiBase.len > 0: a.apiBase else: TelegramApiBase
  base & "/bot" & a.token & "/" & meth

proc post(a: TelegramAdapter; meth: string; body: JsonNode): JsonNode =
  let client = newHttpClient()
  defer: client.close()
  client.headers = newHttpHeaders({"Content-Type": "application/json"})
  let resp = client.post(a.apiUrl(meth), body = $body)
  result = parseJson(resp.body)
  if not result["ok"].getBool(false):
    raise newException(IOError,
      "Telegram API error [" & meth & "]: " & $result)

# ── ChannelPort implementation ─────────────────────────────────────────────────

proc send*(a: TelegramAdapter; msg: OutboundMessage): Result[void, string] =
  try:
    let tgId = a.resolver.telegramId(msg.userId)
    var body = %* {"chat_id": tgId, "text": msg.text, "parse_mode": "HTML"}
    if msg.replyTo.len > 0:
      body["reply_to_message_id"] = %msg.replyTo
    discard a.post("sendMessage", body)
    ok()
  except CatchableError as e:
    ## Fallback: retry without parse_mode if HTML was rejected.
    try:
      let tgId2 = a.resolver.telegramId(msg.userId)
      var body2 = %* {"chat_id": tgId2, "text": msg.text}
      if msg.replyTo.len > 0:
        body2["reply_to_message_id"] = %msg.replyTo
      discard a.post("sendMessage", body2)
      ok()
    except CatchableError as e2:
      err(e2.msg)

proc sendReturnId*(a: TelegramAdapter;
                   msg: OutboundMessage): Result[string, string] =
  ## Sends a message and returns the Telegram message_id as string.
  ## Used for streaming: first partial creates the message; edits follow.
  try:
    let tgId = a.resolver.telegramId(msg.userId)
    var body = %* {"chat_id": tgId, "text": msg.text, "parse_mode": "HTML"}
    if msg.replyTo.len > 0:
      body["reply_to_message_id"] = %msg.replyTo
    let resp = a.post("sendMessage", body)
    let msgId = $resp["result"]["message_id"].getInt()
    ok(msgId)
  except CatchableError as e:
    err(e.msg)

proc editMessage*(a: TelegramAdapter; userId: UserId;
                  messageId, text: string): Result[void, string] =
  ## Edits an existing message in place (for streaming updates).
  try:
    let tgId = a.resolver.telegramId(userId)
    let body = %* {
      "chat_id":    tgId,
      "message_id": parseInt(messageId),
      "text":       text,
      "parse_mode": "HTML",
    }
    discard a.post("editMessageText", body)
    ok()
  except CatchableError as e:
    err(e.msg)

proc receive*(a: var TelegramAdapter): Result[seq[InboundMessage], string] =
  ## Polls getUpdates; advances a.offset on success.
  ## pollTimeout=0 returns immediately (non-blocking).
  try:
    let body = %* {
      "offset":  a.offset,
      "limit":   100,
      "timeout": a.pollTimeout,
    }
    let updates = a.post("getUpdates", body)["result"]

    var msgs: seq[InboundMessage] = @[]
    var maxUpdateId = a.offset - 1

    for upd in updates:
      let updateId = upd["update_id"].getBiggestInt().int64
      if updateId > maxUpdateId: maxUpdateId = updateId
      if not upd.hasKey("message"): continue

      let tgMsg = upd["message"]
      if not tgMsg.hasKey("text"): continue

      let fromId = tgMsg["from"]["id"].getBiggestInt().int64
      msgs.add InboundMessage(
        userId:    a.resolver.resolve(fromId),
        channel:   ckTelegram,
        channelId: $tgMsg["message_id"].getInt(),
        text:      tgMsg["text"].getStr(),
        mediaUrl:  "",
      )

    if maxUpdateId >= a.offset: a.offset = maxUpdateId + 1
    ok(msgs)
  except CatchableError as e:
    err(e.msg)

proc sendTyping*(a: TelegramAdapter; userId: UserId): Result[void, string] =
  ## Sends a "typing" chat action to show the bot is composing a reply.
  try:
    let tgId = a.resolver.telegramId(userId)
    if tgId == 0: return ok()
    let body = %* {"chat_id": tgId, "action": "typing"}
    discard a.post("sendChatAction", body)
    ok()
  except CatchableError as e:
    err(e.msg)

proc ack*(a: TelegramAdapter; channelId: string) =
  ## No-op: Telegram ack is implicit via offset advancement in receive().
  discard

# ── Constructor ────────────────────────────────────────────────────────────────

proc newTelegramAdapter*(token: string;
                         identityPath: string;
                         apiBase      = "";
                         pollTimeout  = 30): TelegramAdapter =
  TelegramAdapter(
    token:       token,
    apiBase:     apiBase,
    offset:      0,
    pollTimeout: pollTimeout,
    resolver:    newIdentityResolver(identityPath),
  )
