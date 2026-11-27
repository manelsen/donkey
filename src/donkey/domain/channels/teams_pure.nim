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

import std/[base64, json, strutils, uri]
import ../../core/pipeops

const
  TeamsChunkChars* = 20_000
  TokenRenewMarginSec* = 300
    ## The app token is renewed five minutes before it expires.
  BotFrameworkScope* = "https://api.botframework.com/.default"

type
  TeamsAttachment* = object
    fileId*:   string   ## `file:<downloadUrl>` or `image:<contentUrl>` (E9.4)
    name*:     string
    mimeType*: string

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
    attachments*:      seq[TeamsAttachment]
    name*:             string   ## an invoke's name (fileConsent/invoke, …)
    value*:            string   ## an invoke's value, as JSON text

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

func mimeOfFileType(t: string): string =
  case t.toLowerAscii
  of "pdf": "application/pdf"
  of "png": "image/png"
  of "jpg", "jpeg": "image/jpeg"
  of "gif": "image/gif"
  of "txt": "text/plain"
  of "csv": "text/csv"
  of "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  of "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  of "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
  else: "application/octet-stream"

proc attachmentsOf(payload: JsonNode): seq[TeamsAttachment] =
  ## A file sent in a personal chat (a pre-authenticated SharePoint URL) or
  ## an inline image (a Bot Framework URL, fetched with the bot's token). The
  ## HTML copy of the message and cards are not attachments to read.
  for a in payload{"attachments"}.getElems:
    let ct = a{"contentType"}.getStr
    if ct == "application/vnd.microsoft.teams.file.download.info":
      let url = a{"content"}{"downloadUrl"}.getStr
      if url.len > 0:
        result.add TeamsAttachment(fileId: "file:" & url, name: a{"name"}.getStr,
                                   mimeType: mimeOfFileType(a{"content"}{"fileType"}.getStr))
    elif ct.startsWith("image/"):
      let url = a{"contentUrl"}.getStr
      if url.len > 0:
        result.add TeamsAttachment(fileId: "image:" & url, name: a{"name"}.getStr, mimeType: ct)

func hostOfUrl*(url: string): string =
  ## The host of an `https://` URL; "" for anything else, never a crash.
  if not url.startsWith("https://"): return ""
  let rest = url["https://".len .. ^1]
  let slash = rest.find('/')
  result = if slash >= 0: rest[0 ..< slash] else: rest
  let colon = result.find(':')
  if colon >= 0: result = result[0 ..< colon]

func underHost(host, base: string): bool =
  host == base or host.endsWith("." & base)

func teamsDownload*(fileId: string; serviceHosts: seq[string]):
                    Result[tuple[url: string, withToken: bool], string] =
  ## Where an attachment is fetched and whether the bot's token goes with it:
  ## a file only from SharePoint (its URL is pre-authenticated: no token), an
  ## inline image only from the Bot Framework service (with the token).
  ## Anything else is refused, so the token never leaves Microsoft's service.
  let colon = fileId.find(':')
  if colon <= 0: return err("Teams: not an attachment id")
  let kind = fileId[0 ..< colon]
  let url = fileId[colon + 1 .. ^1]
  if not url.startsWith("https://"): return err("Teams: attachment URL is not HTTPS")
  let host = hostOfUrl(url).toLowerAscii
  case kind
  of "file":
    if underHost(host, "sharepoint.com"): ok((url: url, withToken: false))
    else: err("Teams: a file is downloaded only from SharePoint")
  of "image":
    for h in serviceHosts:
      if underHost(host, h.toLowerAscii): return ok((url: url, withToken: true))
    err("Teams: an image is downloaded only from the Bot Framework service")
  else: err("Teams: not an attachment id")

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
  a.attachments = attachmentsOf(payload)
  a.name = payload{"name"}.getStr
  let value = payload{"value"}
  if not value.isNil: a.value = $value
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


# ── Files out (Teams complete, parts 1 and 2) ─────────────────────────────────

const
  TeamsInlineImageMaxBytes* = 1024 * 1024
    ## Microsoft's limit for an image sent inline as a data URI (PNG, JPEG,
    ## GIF; up to 1024x1024; larger may be accepted and not render).
  FileConsentType = "application/vnd.microsoft.teams.card.file.consent"
  FileInfoType = "application/vnd.microsoft.teams.card.file.info"

func inlineImageMime*(name: string): string =
  let n = name.toLowerAscii
  if n.endsWith(".png"): "image/png"
  elif n.endsWith(".jpg") or n.endsWith(".jpeg"): "image/jpeg"
  elif n.endsWith(".gif"): "image/gif"
  else: ""

proc imageMessageBody*(text, replyToId, mime, name, data: string): JsonNode =
  ## A message carrying a small image inline (no consent needed).
  result = messageBody(text, replyToId)
  result["attachments"] = %* [{"contentType": mime, "name": name,
                               "contentUrl": "data:" & mime & ";base64," & encode(data)}]

func isPersonalConversation*(conversationId: string): bool =
  ## Group chats and channels have `19:` ids; a bot's file consent card only
  ## works in a personal conversation.
  conversationId.len > 0 and not conversationId.startsWith("19:")

proc fileConsentBody*(name, description: string; size: int64;
                      pending, replyToId: string): JsonNode =
  ## The card asking the person to accept a file; the bytes stay with the
  ## bot, keyed by `pending`.
  result = messageBody("", replyToId)
  result.delete("text")
  result["attachments"] = %* [{"contentType": FileConsentType, "name": name,
    "content": {"description": description, "sizeInBytes": size,
                "acceptContext": {"pending": pending},
                "declineContext": {"pending": pending}}}]

type FileConsent* = object
  accepted*: bool
  pending*: string
  uploadUrl*, contentUrl*, name*, uniqueId*, fileType*: string
  tenantId*: string   ## the tenant to ask the file token of

proc parseFileConsent*(name: string; value: JsonNode): Result[FileConsent, string] =
  if name != "fileConsent/invoke": return err("not a file consent")
  if value.isNil or value.kind != JObject: return err("file consent without a value")
  let info = value{"uploadInfo"}
  result = ok(FileConsent(
    accepted: value{"action"}.getStr == "accept",
    pending: value{"context"}{"pending"}.getStr,
    uploadUrl: info{"uploadUrl"}.getStr, contentUrl: info{"contentUrl"}.getStr,
    name: info{"name"}.getStr, uniqueId: info{"uniqueId"}.getStr,
    fileType: info{"fileType"}.getStr, tenantId: info{"tenantId"}.getStr))

proc parseFileConsent*(activity: JsonNode): Result[FileConsent, string] =
  parseFileConsent(activity{"name"}.getStr, activity{"value"})

func uploadAllowed*(url: string): bool =
  ## The person's OneDrive (a SharePoint host), over HTTPS.
  url.startsWith("https://") and underHost(hostOfUrl(url).toLowerAscii, "sharepoint.com")

func uploadHeaders*(size: int): seq[(string, string)] =
  @[("Content-Type", "application/octet-stream"),
    ("Content-Range", "bytes 0-" & $(size - 1) & "/" & $size)]

proc fileInfoBody*(contentUrl, name, uniqueId, fileType, replyToId: string): JsonNode =
  result = messageBody("", replyToId)
  result.delete("text")
  result["attachments"] = %* [{"contentType": FileInfoType, "contentUrl": contentUrl,
    "name": name, "content": {"uniqueId": uniqueId, "fileType": fileType}}]


# ── The file token (Teams complete, part 3) ───────────────────────────────────
## From 1 March 2027 file URLs need an access token from a certificate, a
## federated credential or a managed identity, not the client secret
## (Microsoft, "Send and receive files using a bot"). Here: a certificate,
## through a client assertion.

func fileScope*(url: string): string =
  "https://" & hostOfUrl(url) & "/.default"

func b64urlText(s: string): string =
  encode(s, safe = true).strip(leading = false, chars = {'='})

proc fileTokenAssertionInput*(appId, tenantId, x5t, jti: string; nowSec: int64): string =
  ## The JWT's signing input (header.claims), to sign with the certificate's
  ## key (RS256).
  let header = %* {"alg": "RS256", "typ": "JWT", "x5t": x5t}
  let claims = %* {"aud": "https://login.microsoftonline.com/" & tenantId & "/oauth2/v2.0/token",
                   "iss": appId, "sub": appId, "jti": jti,
                   "nbf": nowSec, "exp": nowSec + 600}
  b64urlText($header) & "." & b64urlText($claims)

func fileTokenForm*(appId, scope, assertion: string): string =
  "client_id=" & encodeUrl(appId) &
    "&scope=" & encodeUrl(scope) &
    "&grant_type=client_credentials" &
    "&client_assertion_type=" & encodeUrl("urn:ietf:params:oauth:client-assertion-type:jwt-bearer") &
    "&client_assertion=" & encodeUrl(assertion)


# ── Cards with buttons (Teams complete, part 4) ───────────────────────────────
## Buttons (approvals, choices) go as an Adaptive Card with Action.Execute; a
## click comes back as an `invoke` named `adaptiveCard/action` whose
## `value.action.data` carries what the button was for. The HTTP response to
## that invoke must say what Teams shows ("Universal Actions" docs).

const CardActionVerb = "donkey"

proc cardBody*(text: string; keyboard: seq[seq[(string, string)]];
               replyToId: string): JsonNode =
  var actions = newJArray()
  for row in keyboard:
    for (label, callback) in row:
      actions.add(%* {"type": "Action.Execute", "title": label, "verb": CardActionVerb,
                      "data": {"donkey": callback}})
  result = messageBody("", replyToId)
  result.delete("text")
  result["attachments"] = %* [{"contentType": "application/vnd.microsoft.card.adaptive",
    "content": {"type": "AdaptiveCard", "version": "1.4",
                "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                "body": [{"type": "TextBlock", "text": text, "wrap": true}],
                "actions": actions}}]

proc parseCardAction*(name: string; value: JsonNode): Result[string, string] =
  ## The callback a clicked button carried.
  if name != "adaptiveCard/action": return err("not a card action")
  if value.isNil or value.kind != JObject: return err("card action without a value")
  let callback = value{"action"}{"data"}{"donkey"}.getStr
  if callback.len == 0: return err("card action without a callback")
  ok(callback)

proc cardActionResponse*(text: string): string =
  $(%* {"statusCode": 200, "type": "application/vnd.microsoft.activity.message", "value": text})
