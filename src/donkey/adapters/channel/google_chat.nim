## google_chat — Google Chat as a channel (second round, front 1).
##
## `/webhook/google-chat` queues an event only after Google's bearer token
## checks out: RS256 with one of the keys Chat publishes (fetched at first
## use, daily, and when a token names an unknown key, spaced), issuer Chat,
## audience the project number. The daemon loop drains the queue
## (google_chat_runtime). Replies go through the Chat API as the app's
## service account, with an access token it gets by signing an assertion
## (adapters/crypto/rs256), renewed before it expires.

import std/[json, locks, os, strutils, tables]
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/google_chat_pure
import ../../infra/event_queue
import ../../infra/fixed
import ../../ports/http
import ../../ports/link_codes
import ../crypto/rs256
import ../http/std_http
import ../identity/identity_resolver
import ../state/durable_file
import ./teams_auth   ## the JWT and JWKS helpers, and rs256Valid

export google_chat_pure

const
  KeysBytes = 65_536
  KeysMaxAgeMs = 24 * 3_600_000'i64
  UnknownKeyRetryMs = 5 * 60_000'i64
  MissingKeysRetryMs = 30_000'i64
  GoogleChatQueueCapacity* = 256
  GoogleChatTimeoutSec = 30

# ── Google's keys, shared by the webhook threads ──────────────────────────────

type ChatKeyFetch* = proc(): Result[string, string] {.gcsafe.}

var gChatKeysLock: Lock
var gChatKeysJson: FixedText[KeysBytes]
var gChatKeysFetchedMs: int64
var gChatKeysAttemptMs: int64
initLock(gChatKeysLock)

proc resetChatKeys*() =
  withLock gChatKeysLock:
    gChatKeysJson = toFixed[KeysBytes]("")
    gChatKeysFetchedMs = 0
    gChatKeysAttemptMs = 0

proc storeChatKeys(jwks: string; nowMs: int64): Result[void, string] =
  if jwks.len >= KeysBytes:
    return err("Google Chat: keys document too large")
  let keys = ? parseJwks(jwks)
  if keys.len == 0:
    return err("Google Chat: keys document has no RSA key")
  withLock gChatKeysLock:
    gChatKeysJson = toFixed[KeysBytes](jwks)
    gChatKeysFetchedMs = nowMs
  ok()

proc seedChatKeys*(jwks: string; nowMs: int64) =
  ## For tests and a warm start: the keys as if just fetched.
  discard storeChatKeys(jwks, nowMs)

proc currentChatKeys*(): seq[BotJwk] =
  var text: string
  withLock gChatKeysLock:
    text = $gChatKeysJson
  if text.len == 0:
    return @[]
  parseJwks(text).get(@[])

proc refreshChatKeys*(fetch: ChatKeyFetch; nowMs: int64;
                      unknownKey = false): Result[void, string] =
  ## As for Teams: none, older than a day, or a token naming a key not in
  ## hand; each kind of retry spaced, so bad tokens cannot make the daemon
  ## hammer Google.
  var due = false
  withLock gChatKeysLock:
    let empty = gChatKeysJson == ""
    let sinceAttempt = nowMs - gChatKeysAttemptMs
    due =
      if empty: gChatKeysAttemptMs == 0 or sinceAttempt >= MissingKeysRetryMs
      elif nowMs - gChatKeysFetchedMs > KeysMaxAgeMs:
        sinceAttempt >= MissingKeysRetryMs   ## stale: spaced too, or a failing fetch runs on every request
      elif unknownKey: sinceAttempt >= UnknownKeyRetryMs
      else: false
    if due:
      gChatKeysAttemptMs = nowMs
  if not due:
    return ok()
  let jwks = ? fetch()
  storeChatKeys(jwks, nowMs)

proc defaultChatKeyFetch*(): ChatKeyFetch =
  ## For a webhook thread: its own transport, egress only to Google's keys.
  result = proc(): Result[string, string] {.gcsafe.} =
    let http = newStdHttpAdapter(timeout = GoogleChatTimeoutSec,
      allowlist = @["www.googleapis.com"]).toRuntimePort()
    let resp = ? http.get(ChatKeysUrl, @[])
    if resp.status != 200:
      return err("Google Chat: keys document status " & $resp.status)
    ok(resp.body)

proc verifyChatRequest*(authHeader, projectNumber: string; keys: openArray[BotJwk];
                        nowSec: int64): Result[void, AuthFailure] =
  ## 401 when the token is missing, malformed, not RS256, not signed by a
  ## published key, or not Chat's for this project; `unknownKey` tells the
  ## caller to fetch the keys again before giving up.
  template deny(why: string; unknown = false): untyped =
    return err(AuthFailure(status: 401, reason: why, unknownKey: unknown))
  let token = bearerToken(authHeader)
  if token.len == 0: deny("no bearer token")
  let parts = splitJwt(token).valueOr: deny(error)
  if parts.alg != "RS256": deny("algorithm is not RS256")
  var found = -1
  for i, key in keys:
    if key.kid == parts.kid:
      found = i
      break
  if found < 0: deny("signed with an unknown key", unknown = true)
  if not rs256Valid(parts.signingInput, parts.signature, keys[found].n, keys[found].e):
    deny("bad signature")
  checkChatClaims(parts.claims, projectNumber, nowSec).isOkOr:
    deny(error)
  ok()

# ── Verified events, from the webhook threads to the daemon loop ─────────────

var gGoogleChatEvents* = initEventQueue[ChatEvent]("google-chat",
                                                   capacity = GoogleChatQueueCapacity)

proc pushChatEvent*(e: ChatEvent): bool {.discardable.} =
  ## False when the queue is full: the route answers 503 and Chat retries.
  gGoogleChatEvents.push(e)

proc tryRecvChatEvent*(): (bool, ChatEvent) =
  gGoogleChatEvents.tryTake()

# ── Adapter ───────────────────────────────────────────────────────────────────

type
  Clock* = proc(): int64 {.gcsafe.}

  GoogleChatState = ref object
    token:  AccessToken
    spaces: Table[string, string]   ## sender → last direct-message space
    seen:   seq[string]             ## message names, oldest first

  GoogleChatAdapter* = object
    account:      ServiceAccount
    resolver*:    IdentityResolver
    linkCodes*:   LinkCodePort
    http:         HttpRuntimePort
    clock:        Clock
    spacesPath:   string
    state:        GoogleChatState
    configError*: string

proc loadSpaces(path: string): Table[string, string] =
  result = initTable[string, string]()
  if path.len == 0 or not fileExists(path):
    return
  try:
    let j = parseJson(readFile(path))
    if j.kind == JObject:
      for key, value in j.pairs:
        if value.kind == JString:
          result[key] = value.getStr
  except CatchableError:
    discard   ## an unreadable file only costs the sends without a target until the next message

proc rememberSpace*(a: GoogleChatAdapter; sender, space: string): Result[void, string] {.discardable.} =
  if sender.len == 0 or space.len == 0:
    return ok()
  if a.state.spaces.getOrDefault(sender) == space:
    return ok()
  a.state.spaces[sender] = space
  if a.spacesPath.len == 0:
    return ok()
  var j = newJObject()
  for key, value in a.state.spaces:
    j[key] = %value
  atomicWriteText(a.spacesPath, $j, "w")

const ChatSeenCapacity* = 512

proc markSeen*(a: GoogleChatAdapter; id: string): bool =
  ## True the first time a message comes; false when Chat delivers it again.
  if id.len == 0: return true
  if id in a.state.seen: return false
  a.state.seen.add id
  if a.state.seen.len > ChatSeenCapacity:
    a.state.seen.delete(0)
  true

proc accessToken(a: GoogleChatAdapter): Result[string, string] =
  let now = a.clock()
  if a.state.token.token.len > 0 and now < a.state.token.renewAtMs:
    return ok(a.state.token.token)
  let input = assertionSigningInput(a.account, now div 1000)
  let signature = ? rs256Sign(a.account.privateKey, input)
  let resp = ? a.http.post(a.account.tokenUri, tokenForm(assertionJwt(input, signature)),
    @[("Content-Type", "application/x-www-form-urlencoded")])
  if resp.status != 200:
    return err("Google Chat: token request status " & $resp.status)
  a.state.token = ? parseAccessToken(resp.body, now)
  ok(a.state.token.token)

proc send*(a: GoogleChatAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text, in the thread it answers. Media and cards are not offered
  ## (channel_capability), so they are refused, not dropped.
  if a.configError.len > 0:
    return err("Google Chat: " & a.configError)
  if msg.mediaUrl.len > 0 or msg.keyboard.len > 0:
    return err("Google Chat: only text is supported")
  if msg.text.strip.len == 0:
    return ok()
  var target = msg.replyTo.strip
  if target.len == 0:
    let sender = a.resolver.reverseChannel(msg.userId, ckGoogleChat)
    target = if sender.len > 0: a.state.spaces.getOrDefault(sender) else: ""
    if target.len == 0:
      return err("Google Chat: no space known for user " & $msg.userId)
  if not validTarget(target):
    return err("Google Chat: not a space: " & target)
  var token = ? a.accessToken()
  for piece in splitForChat(msg.text):
    var resp = ? a.http.post(messagesUrl(target), messageBody(target, piece),
      @[("Content-Type", "application/json"), ("Authorization", "Bearer " & token)])
    if resp.status == 401:
      ## Revoked or expired early: a new token, once.
      a.state.token = AccessToken()
      token = ? a.accessToken()
      resp = ? a.http.post(messagesUrl(target), messageBody(target, piece),
        @[("Content-Type", "application/json"), ("Authorization", "Bearer " & token)])
    if resp.status notin 200 .. 299:
      return err("Google Chat: send status " & $resp.status)
  ok()

proc newGoogleChatAdapter*(serviceAccountJson, identityPath, spacesPath: string;
                           http: HttpRuntimePort = HttpRuntimePort();
                           clock: Clock = nil): GoogleChatAdapter =
  ## `GOOGLE_CHAT_SERVICE_ACCOUNT` (the key's JSON, kept in the vault) from
  ## the environment snapshot. A missing or unreadable account does not stop
  ## the daemon: the adapter records why and every send fails with it.
  let account = parseServiceAccount(serviceAccountJson)
  var transport = http
  if transport.post.isNil:
    transport = newStdHttpAdapter(timeout = GoogleChatTimeoutSec,
      allowlist = @["oauth2.googleapis.com", "chat.googleapis.com"],
      retryNonIdempotent = false, retryConflict = false).toRuntimePort()
  var now = clock
  if now == nil:
    now = proc(): int64 {.gcsafe.} = epochMs()
  result = GoogleChatAdapter(
    account: account.get(ServiceAccount()), resolver: newIdentityResolver(identityPath),
    http: transport, clock: now, spacesPath: spacesPath,
    state: GoogleChatState(spaces: loadSpaces(spacesPath)),
    configError:
      if serviceAccountJson.strip.len == 0: "GOOGLE_CHAT_SERVICE_ACCOUNT is not set"
      elif account.isErr: account.error
      else: "")
  result.linkCodes = result.resolver.linkCodePort()
