## google_chat_pure — Google Chat, the pure half (second round, front 1).
##
## Chat posts interaction events to the app's HTTP endpoint with a bearer
## token Google signed (RS256, issuer `chat@system.gserviceaccount.com`,
## audience the Cloud project number). Replies go asynchronously through
## the Chat API as the app's service account: a JWT assertion it signs is
## exchanged for an access token with the `chat.bot` scope. Formats from
## "Receive and respond to interaction events", "Verify requests from Google
## Chat" and "Authenticate as a Chat app" (developers.google.com/workspace/chat).

import std/[base64, json, strutils, uri]
import ../../core/pipeops

const
  ChatIssuer* = "chat@system.gserviceaccount.com"
  ChatKeysUrl* = "https://www.googleapis.com/service_accounts/v1/jwk/chat@system.gserviceaccount.com"
  ChatBotScope* = "https://www.googleapis.com/auth/chat.bot"
  ChatApiBase = "https://chat.googleapis.com/v1/"
  ChatTextChars* = 4_000      ## a message holds 4096
  ClockSkewSec = 300
  AssertionLifetimeSec = 3_600
  TokenRenewMarginSec = 300

type
  ChatAttachment* = object
    resourceName*: string   ## for media.download; empty for a Drive file
    name*, mimeType*: string
    drive*: bool            ## a Drive file: named only (no Drive access)

  ChatEvent* = object
    kind*, id*, sender*, displayName*, senderType*: string
    text*, space*, thread*: string
    isGroup*: bool
    attachments*: seq[ChatAttachment]   ## E9.2

  ServiceAccount* = object
    clientEmail*, privateKey*, tokenUri*: string

  AccessToken* = object
    token*:     string
    renewAtMs*: int64

proc attachmentsOf(msg: JsonNode): seq[ChatAttachment] =
  ## Uploaded files carry the resource name media.download needs; a Drive
  ## file only a Drive reference.
  for a in msg{"attachment"}.getElems:
    let name = a{"contentName"}.getStr
    let mime = a{"contentType"}.getStr
    let resource = a{"attachmentDataRef"}{"resourceName"}.getStr
    if resource.len > 0:
      result.add ChatAttachment(resourceName: resource, name: name, mimeType: mime)
    elif a{"source"}.getStr == "DRIVE_FILE" or a{"driveDataRef"} != nil:
      result.add ChatAttachment(name: name, mimeType: mime, drive: true)

proc parseChatEvent*(body: string): Result[ChatEvent, string] =
  let j =
    try: parseJson(body)
    except CatchableError: return err("not JSON")
  if j.kind != JObject: return err("not an event")
  let msg = j{"message"}
  let space = if msg{"space"} != nil: msg{"space"} else: j{"space"}
  let argument = msg{"argumentText"}.getStr
  let text = if argument.strip.len > 0: argument else: msg{"text"}.getStr
  let spaceType = space{"type"}.getStr & space{"spaceType"}.getStr
  ok(ChatEvent(
    kind: j{"type"}.getStr, id: msg{"name"}.getStr,
    sender: msg{"sender"}{"name"}.getStr,
    displayName: msg{"sender"}{"displayName"}.getStr,
    senderType: msg{"sender"}{"type"}.getStr,
    text: text.strip, space: space{"name"}.getStr,
    thread: msg{"thread"}{"name"}.getStr,
    isGroup: "DM" notin spaceType and "DIRECT_MESSAGE" notin spaceType,
    attachments: attachmentsOf(msg)))

func isTurn*(e: ChatEvent): bool =
  e.kind == "MESSAGE" and e.senderType != "BOT" and e.sender.len > 0 and
    e.space.len > 0 and (e.text.len > 0 or e.attachments.len > 0)

func validResourceName(r: string): bool =
  ## Google's resource name (it may hold slashes); never a `..` segment or
  ## anything outside a safe set, since it goes into the URL path.
  if r.len == 0 or r.len > 1024 or r[0] == '/' or r.endsWith("/"): return false
  for c in r:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '_', '-', '=', '.', '+', '/'}: return false
  for part in r.split('/'):
    if part.len == 0 or part == "." or part == "..": return false
  true

func mediaUrl*(resourceName: string): Result[string, string] =
  if not validResourceName(resourceName):
    return err("Google Chat: not an attachment resource name")
  ok("https://chat.googleapis.com/v1/media/" & resourceName & "?alt=media")

proc checkChatClaims*(claims: JsonNode; projectNumber: string; nowSec: int64): Result[void, string] =
  if projectNumber.len == 0: return err("no project number configured")
  if claims{"iss"}.getStr != ChatIssuer: return err("not issued by Google Chat")
  let aud = claims{"aud"}
  var audOk = aud != nil and aud.kind == JString and aud.getStr == projectNumber
  if aud != nil and aud.kind == JArray:
    for a in aud:
      if a.getStr == projectNumber: audOk = true
  if not audOk: return err("issued for another project")
  if claims{"exp"}.getBiggestInt(0) + ClockSkewSec < nowSec: return err("expired")
  if claims{"iat"}.getBiggestInt(0) - ClockSkewSec > nowSec: return err("issued in the future")
  ok()

proc parseServiceAccount*(text: string): Result[ServiceAccount, string] =
  let j =
    try: parseJson(text)
    except CatchableError: return err("the service account is not JSON")
  let sa = ServiceAccount(clientEmail: j{"client_email"}.getStr,
                          privateKey: j{"private_key"}.getStr,
                          tokenUri: j{"token_uri"}.getStr("https://oauth2.googleapis.com/token"))
  if sa.clientEmail.len == 0 or sa.privateKey.len == 0:
    return err("the service account has no client_email or private_key")
  ok(sa)

func b64url(s: string): string =
  encode(s).replace('+', '-').replace('/', '_').strip(leading = false, chars = {'='})

proc assertionSigningInput*(sa: ServiceAccount; nowSec: int64): string =
  let header = $(%* {"alg": "RS256", "typ": "JWT"})
  let claims = $(%* {"iss": sa.clientEmail, "scope": ChatBotScope, "aud": sa.tokenUri,
                     "iat": nowSec, "exp": nowSec + AssertionLifetimeSec})
  b64url(header) & "." & b64url(claims)

func assertionJwt*(signingInput, signature: string): string =
  signingInput & "." & b64url(signature)

func tokenForm*(assertion: string): string =
  encodeQuery({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
               "assertion": assertion})

proc parseAccessToken*(body: string; nowMs: int64): Result[AccessToken, string] =
  let j =
    try: parseJson(body)
    except CatchableError: return err("token response is not JSON")
  let token = j{"access_token"}.getStr
  if token.len == 0:
    return err("no access_token: " & j{"error"}.getStr("unknown error"))
  let life = max(j{"expires_in"}.getInt(3600) - TokenRenewMarginSec, 60)
  ok(AccessToken(token: token, renewAtMs: nowMs + int64(life) * 1000))

func replyTarget*(e: ChatEvent): string =
  if e.thread.len > 0: e.space & "|" & e.thread else: e.space

func splitTarget(target: string): (string, string) =
  let bar = target.find('|')
  if bar < 0: (target, "") else: (target[0 ..< bar], target[bar + 1 .. ^1])

func validTarget*(target: string): bool =
  ## `spaces/<id>` and, optionally, `|spaces/<id>/threads/<id>`: nothing
  ## else may reach the API URL.
  let (space, thread) = splitTarget(target)
  let parts = space.split('/')
  if parts.len != 2 or parts[0] != "spaces" or parts[1].len == 0: return false
  for c in parts[1]:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '_', '-'}: return false
  if thread.len > 0 and not thread.startsWith(space & "/threads/"): return false
  if ".." in target: return false
  true

func messagesUrl*(target: string): string =
  let (space, thread) = splitTarget(target)
  result = ChatApiBase & space & "/messages"
  if thread.len > 0:
    result.add "?messageReplyOption=REPLY_MESSAGE_FALLBACK_TO_NEW_THREAD"

proc messageBody*(target, text: string): string =
  let (_, thread) = splitTarget(target)
  var body = %* {"text": text}
  if thread.len > 0:
    body["thread"] = %* {"name": thread}
  $body

func splitForChat*(text: string): seq[string] =
  splitChunks(text, ChatTextChars)
