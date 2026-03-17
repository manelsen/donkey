## TelegramAdapter — ChannelPort via Bot API long polling.
##
## Auth: BOT_TOKEN in Authorization header / URL path.
## API base: https://api.telegram.org/bot{token}/
##
## Quirks absorbed here:
##   - getUpdates long-polling: offset, limit, timeout params
##   - IdentityResolver: maps telegram_user_id (int) → UserId (UUID string)
##   - sendMessage supports parse_mode=Markdown
##   - ack advances the offset (offset = update_id + 1)

import std/[httpclient, json, os, random, strutils, tables]
import ../../core/types
import ../../domain/message

const
  TelegramApiBase* = "https://api.telegram.org"
  DefaultPollTimeout = 30   ## seconds for long-polling getUpdates

type
  IdentityResolver* = ref object
    ## Maps Telegram numeric user ids to stable UUIDs.
    ## Persistence: simple tab-separated file (data/identities.tsv).
    ## On first contact a new UUID is generated and saved.
    store: Table[int64, UserId]
    path: string

  TelegramAdapter* = object
    token*:    string
    apiBase*:  string        ## override for testing (e.g. mock server URL)
    offset*:   int64         ## getUpdates offset (mutable via nextOffset)
    resolver*: IdentityResolver

# ── IdentityResolver ──────────────────────────────────────────────────────────

proc newIdentityResolver*(path: string): IdentityResolver =
  result = IdentityResolver(path: path)
  result.store = initTable[int64, UserId]()
  if fileExists(path):
    for line in lines(path):
      let parts = line.split('\t')
      if parts.len == 2:
        try:
          result.store[parseBiggestInt(parts[0]).int64] = UserId(parts[1])
        except ValueError:
          discard

proc save(r: IdentityResolver) =
  var content = ""
  for tgId, uid in r.store:
    content.add $tgId & '\t' & $uid & '\n'
  writeFile(r.path, content)

proc generateUUID(): string =
  ## Generates a random UUID v4 (hex, no dashes removed for simplicity).
  ## For production use a proper UUID library; this is sufficient for F1.
  randomize()
  let hex = "0123456789abcdef"
  result = newStringOfCap(36)
  for i in 0..<36:
    if i in [8, 13, 18, 23]:
      result.add '-'
    elif i == 14:
      result.add '4'
    elif i == 19:
      result.add hex[(rand(3) + 8)]
    else:
      result.add hex[rand(15)]

proc resolve*(r: IdentityResolver; telegramUserId: int64): UserId =
  ## Returns the stable UserId for a Telegram user, creating one if absent.
  if telegramUserId notin r.store:
    r.store[telegramUserId] = UserId(generateUUID())
    r.save()
  r.store[telegramUserId]

# ── API helpers ───────────────────────────────────────────────────────────────

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

# ── ChannelPort implementation ────────────────────────────────────────────────

proc send*(a: TelegramAdapter; msg: OutboundMessage) =
  var body = %* {
    "chat_id":    msg.userId.`$`(),
    "text":       msg.text,
    "parse_mode": "Markdown",
  }
  if msg.replyTo.len > 0:
    body["reply_to_message_id"] = %msg.replyTo
  discard a.post("sendMessage", body)

proc receive*(a: var TelegramAdapter): seq[InboundMessage] =
  ## Long-polls getUpdates; advances a.offset on success.
  let body = %* {
    "offset":  a.offset,
    "limit":   100,
    "timeout": DefaultPollTimeout,
  }
  let resp = a.post("getUpdates", body)
  let updates = resp["result"]

  result = @[]
  var maxUpdateId: int64 = a.offset - 1

  for upd in updates:
    let updateId = upd["update_id"].getBiggestInt().int64
    if updateId > maxUpdateId:
      maxUpdateId = updateId

    if not upd.hasKey("message"):
      continue

    let tgMsg  = upd["message"]
    if not tgMsg.hasKey("text"):
      continue

    let fromId = tgMsg["from"]["id"].getBiggestInt().int64
    let uid    = a.resolver.resolve(fromId)
    let msgId  = $tgMsg["message_id"].getInt()
    let text   = tgMsg["text"].getStr()

    var mediaUrl = ""
    if tgMsg.hasKey("photo"):
      mediaUrl = "tg://photo/" & msgId

    result.add InboundMessage(
      userId:    uid,
      channelId: msgId,
      text:      text,
      mediaUrl:  mediaUrl,
    )

  if maxUpdateId >= a.offset:
    a.offset = maxUpdateId + 1

proc ack*(a: TelegramAdapter; channelId: string) =
  ## Telegram ack is implicit via offset advancement in receive().
  ## This is a no-op kept for ChannelPort conformance.
  discard

# ── Constructor ───────────────────────────────────────────────────────────────

proc newTelegramAdapter*(token: string;
                         identityPath: string;
                         apiBase = ""): TelegramAdapter =
  TelegramAdapter(
    token:    token,
    apiBase:  apiBase,
    offset:   0,
    resolver: newIdentityResolver(identityPath),
  )
