## teams_pure — Microsoft Teams through the Bot Framework REST API, the pure
## half (PRD-roadmap E2.2–E2.3).
##
## Sources (learn.microsoft.com, checked 25/11/2026): "Send and receive
## messages with the Bot Connector API" (activity fields, reply and send
## addresses) and "Authenticate requests with the Bot Connector API" (app
## token: client credentials at the tenant's endpoint, scope
## https://api.botframework.com/.default; single-tenant is the default for
## bots created since July 2025, `botframework.com` stays for older
## multi-tenant ones). Teams accepts messages up to 100 KB and recommends
## staying under 80 KB; a piece here is far below that.
##
## `proc` where JSON is built or parsed (ADR-007 allows it).

import std/[json, strutils, uri]
import ../../core/pipeops

const
  TeamsChunkChars* = 20_000
  TokenRenewMarginSec* = 300
    ## The app token is renewed five minutes before it expires.
  BotFrameworkScope* = "https://api.botframework.com/.default"

type
  TeamsActivity* = object
    kind*:             string   ## message, conversationUpdate, typing, …
    id*:               string
    serviceUrl*:       string
    channelId*:        string
    conversationId*:   string
    conversationType*: string   ## personal, groupChat, channel
    isGroup*:          bool
    tenantId*:         string
    fromId*:           string
    fromName*:         string
    aadObjectId*:      string
    recipientId*:      string
    recipientName*:    string
    text*:             string   ## the bot's mention taken out
    replyToId*:        string
    bot*:              string   ## the `[[bots]]` app it was sent to; "" = default

  ReplyTarget* = object
    serviceUrl*:     string
    conversationId*: string
    activityId*:     string   ## "" sends to the conversation, not a thread

  AppToken* = object
    token*:     string
    renewAtMs*: int64

func senderKey*(a: TeamsActivity): string =
  ## Who wrote: the Entra object id when Teams gives it (stable across bots
  ## and tenants' apps), the channel account id otherwise.
  if a.aadObjectId.len > 0: a.aadObjectId else: a.fromId

func unescapeEntities(s: string): string =
  s.multiReplace(("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
                 ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&"))

func withoutMentions(text, botName: string): string =
  ## `<at>Name</at>`: the bot's own mention goes, anyone else's stays as the
  ## name.
  var rest = text
  while true:
    let start = rest.find("<at>")
    if start < 0:
      break
    let stop = rest.find("</at>", start)
    if stop < 0:
      break
    let name = rest[start + 4 ..< stop]
    let keep = if botName.len > 0 and name.strip == botName.strip: "" else: name
    rest = rest[0 ..< start] & keep & rest[stop + 5 .. ^1]
  rest

func collapseSpaces(s: string): string =
  var lastSpace = false
  for c in s:
    if c in {' ', '\t'}:
      if not lastSpace:
        result.add ' '
      lastSpace = true
    else:
      result.add c
      lastSpace = false
  result = result.strip

proc parseActivity*(payload: JsonNode): Result[TeamsActivity, string] =
  if payload.kind != JObject:
    return err("activity is not an object")
  let conv = payload{"conversation"}
  let sender = payload{"from"}
  let recipient = payload{"recipient"}
  var a = TeamsActivity(
    kind: payload{"type"}.getStr, id: payload{"id"}.getStr,
    serviceUrl: payload{"serviceUrl"}.getStr,
    channelId: payload{"channelId"}.getStr,
    replyToId: payload{"replyToId"}.getStr)
  if a.kind.len == 0 or a.serviceUrl.len == 0 or conv.isNil or conv.kind != JObject:
    return err("activity lacks type, serviceUrl or conversation")
  a.conversationId = conv{"id"}.getStr
  a.conversationType = conv{"conversationType"}.getStr
  a.isGroup = conv{"isGroup"}.getBool or
              a.conversationType in ["groupChat", "channel"]
  a.tenantId = conv{"tenantId"}.getStr
  if a.tenantId.len == 0:
    a.tenantId = payload{"channelData"}{"tenant"}{"id"}.getStr
  if not sender.isNil and sender.kind == JObject:
    a.fromId = sender{"id"}.getStr
    a.fromName = sender{"name"}.getStr
    a.aadObjectId = sender{"aadObjectId"}.getStr
  if not recipient.isNil and recipient.kind == JObject:
    a.recipientId = recipient{"id"}.getStr
    a.recipientName = recipient{"name"}.getStr
  if a.conversationId.len == 0:
    return err("activity has no conversation id")
  a.text = payload{"text"}.getStr
    .withoutMentions(a.recipientName)
    .unescapeEntities
    .collapseSpaces
  ok(a)

# ── Reply target ──────────────────────────────────────────────────────────────

const TargetSep = '|'
  ## Conversation ids hold ':', ';' and '@', never '|'; service URLs neither.

func replyTarget*(serviceUrl, conversationId, activityId: string): string =
  serviceUrl & TargetSep & conversationId & TargetSep & activityId

proc parseReplyTarget*(target: string): Result[ReplyTarget, string] =
  let parts = target.split(TargetSep)
  if parts.len != 3 or parts[0].len == 0 or parts[1].len == 0:
    return err("not a Teams reply target")
  ok(ReplyTarget(serviceUrl: parts[0], conversationId: parts[1],
                 activityId: parts[2]))

func serviceHostOf*(serviceUrl: string): string =
  if not serviceUrl.startsWith("https://"):
    return ""
  let rest = serviceUrl["https://".len .. ^1]
  var stop = rest.len
  for i, c in rest:
    if c in {'/', ':', '?', '#'}:
      stop = i
      break
  rest[0 ..< stop].toLowerAscii

func serviceHostAllowed*(serviceUrl: string; hosts: openArray[string]): bool =
  ## Exact hosts: Traffic Manager names are open to anyone, so a suffix
  ## would admit a host somebody else registered.
  let host = serviceHostOf(serviceUrl)
  host.len > 0 and host in hosts

func activitiesUrl*(serviceUrl, conversationId, activityId: string): string =
  ## POST address: a reply in the thread when there is a message to reply
  ## to, otherwise a new message in the conversation.
  let base = if serviceUrl.endsWith("/"): serviceUrl else: serviceUrl & "/"
  result = base & "v3/conversations/" & encodeUrl(conversationId, usePlus = false) &
           "/activities"
  if activityId.len > 0:
    result.add "/" & encodeUrl(activityId, usePlus = false)

proc messageBody*(text, replyToId: string): JsonNode =
  result = %* {"type": "message", "textFormat": "markdown", "text": text}
  if replyToId.len > 0:
    result["replyToId"] = %replyToId

func splitForTeams*(text: string): seq[string] =
  splitChunks(text, TeamsChunkChars)

# ── App token ─────────────────────────────────────────────────────────────────

func tokenUrl*(tenantId: string): string =
  ## Single-tenant bots ask their own tenant; an empty tenant is the old
  ## multi-tenant endpoint.
  let tenant = if tenantId.strip.len > 0: tenantId.strip else: "botframework.com"
  "https://login.microsoftonline.com/" & tenant & "/oauth2/v2.0/token"

func tokenForm*(appId, appPassword: string): string =
  "grant_type=client_credentials" &
    "&client_id=" & encodeUrl(appId, usePlus = true) &
    "&client_secret=" & encodeUrl(appPassword, usePlus = true) &
    "&scope=" & encodeUrl(BotFrameworkScope, usePlus = true)

proc parseTokenResponse*(body: string; nowMs: int64): Result[AppToken, string] =
  let j =
    try: parseJson(body)
    except CatchableError: return err("token response is not JSON")
  let token = j{"access_token"}.getStr
  if token.len == 0:
    return err("no access_token: " & j{"error"}.getStr("unknown error"))
  let expiresIn = max(j{"expires_in"}.getInt(3600) - TokenRenewMarginSec, 60)
  ok(AppToken(token: token, renewAtMs: nowMs + int64(expiresIn) * 1000))

# ── Redelivery ────────────────────────────────────────────────────────────────

const TeamsSeenCapacity* = 512
  ## The connector retries a delivery it saw fail; ids older than this many
  ## activities are not expected again.

type TeamsSeen* = object
  ids*: seq[string]   ## oldest first

func markSeen*(seen: var TeamsSeen; id: string): bool =
  ## True the first time an activity id comes; false for a redelivery.
  if id.len == 0:
    return true
  if id in seen.ids:
    return false
  seen.ids.add id
  if seen.ids.len > TeamsSeenCapacity:
    seen.ids.delete(0)
  true
