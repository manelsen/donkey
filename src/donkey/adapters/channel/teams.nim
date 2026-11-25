## teams — Microsoft Teams through the Bot Framework REST API (PRD-roadmap
## E2). The pure rules are in domain/channels/teams_pure and teams_auth_pure.
##
## Three things live here:
##   - the connector's signing keys, shared by the webhook threads: JSON text
##     of fixed capacity under a lock (infra/fixed), fetched when missing,
##     older than a day, or when a token names an unknown key (at most once
##     in five minutes);
##   - the queue the webhook threads push verified activities into, drained
##     by the daemon loop (teams_runtime);
##   - the adapter: the app token (client credentials, renewed before it
##     expires) and sending through the connector. Each person's last
##     conversation is kept on disk, so a reminder reaches them after a
##     restart.

import std/[json, locks, os, strutils, tables]
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/teams_pure
import ../../infra/event_queue
import ../../infra/fixed
import ../../ports/http
import ../../ports/link_codes
import ../http/std_http
import ../identity/identity_resolver
import ../state/durable_file
import ./teams_auth

export teams_pure, teams_auth

const
  KeysBytes = 65_536
    ## The connector's keys document is a few KB; a bigger one is refused.
  KeysMaxAgeMs = 24 * 3_600_000'i64
    ## "refresh their local cache … at least once every 24 hours"
  UnknownKeyRetryMs = 5 * 60_000'i64
  MissingKeysRetryMs = 30_000'i64
  TeamsQueueCapacity* = 256
  DefaultServiceHosts* = @["smba.trafficmanager.net"]
  TeamsTimeoutSec = 30

# ── The connector's keys, shared by the webhook threads ──────────────────────

type KeyFetch* = proc(): Result[string, string] {.gcsafe.}

var gKeysLock: Lock
var gKeysJson: FixedText[KeysBytes]   ## not GC memory: no cast to share it
var gKeysFetchedMs: int64
var gKeysAttemptMs: int64
initLock(gKeysLock)

proc resetBotKeys*() =
  withLock gKeysLock:
    gKeysJson = toFixed[KeysBytes]("")
    gKeysFetchedMs = 0
    gKeysAttemptMs = 0

proc storeKeys(jwks: string; nowMs: int64): Result[void, string] =
  if jwks.len >= KeysBytes:
    return err("Teams: keys document too large")
  let keys = ? parseJwks(jwks)
  if keys.len == 0:
    return err("Teams: keys document has no RSA key")
  withLock gKeysLock:
    gKeysJson = toFixed[KeysBytes](jwks)
    gKeysFetchedMs = nowMs
  ok()

proc seedBotKeys*(jwks: string; nowMs: int64) =
  ## For tests and a warm start: the keys as if just fetched.
  discard storeKeys(jwks, nowMs)

proc currentBotKeys*(): seq[BotJwk] =
  var text: string
  withLock gKeysLock:
    text = $gKeysJson
  if text.len == 0:
    return @[]
  parseJwks(text).get(@[])

proc refreshBotKeys*(fetch: KeyFetch; nowMs: int64;
                     unknownKey = false): Result[void, string] =
  ## Fetches the keys when there are none, they are older than a day, or a
  ## token named a key not in hand; each kind of retry is spaced, so a flood
  ## of bad tokens cannot make the daemon hammer the connector.
  var due = false
  withLock gKeysLock:
    let empty = gKeysJson == ""
    let sinceAttempt = nowMs - gKeysAttemptMs
    due =
      if empty: gKeysAttemptMs == 0 or sinceAttempt >= MissingKeysRetryMs
      elif nowMs - gKeysFetchedMs > KeysMaxAgeMs: true
      elif unknownKey: sinceAttempt >= UnknownKeyRetryMs
      else: false
    if due:
      gKeysAttemptMs = nowMs
  if not due:
    return ok()
  let jwks = ? fetch()
  storeKeys(jwks, nowMs)

proc botKeyFetch*(http: HttpRuntimePort): KeyFetch =
  ## The OpenID document, then the keys at its `jwks_uri`.
  result = proc(): Result[string, string] {.gcsafe.} =
    let doc = ? http.get(BotFrameworkOpenIdUrl, @[])
    if doc.status != 200:
      return err("Teams: OpenID document status " & $doc.status)
    let uri = ? jwksUriOf(doc.body)
    let keys = ? http.get(uri, @[])
    if keys.status != 200:
      return err("Teams: keys document status " & $keys.status)
    ok(keys.body)

proc defaultKeyFetch*(): KeyFetch =
  ## For a webhook thread: its own transport, egress only to the connector,
  ## made only when the keys are actually fetched.
  result = proc(): Result[string, string] {.gcsafe.} =
    botKeyFetch(newStdHttpAdapter(timeout = TeamsTimeoutSec,
      allowlist = @["login.botframework.com"]).toRuntimePort())()

# ── Verified activities, from the webhook threads to the daemon loop ─────────

var gTeamsEvents* = initEventQueue[TeamsActivity]("teams",
                                                  capacity = TeamsQueueCapacity)

proc pushActivity*(a: TeamsActivity): bool {.discardable.} =
  ## False when the queue is full: the route answers 503 and the connector
  ## tries again.
  gTeamsEvents.push(a)

proc tryRecvActivity*(): (bool, TeamsActivity) =
  gTeamsEvents.tryTake()

# ── Adapter ───────────────────────────────────────────────────────────────────

type
  Clock* = proc(): int64 {.gcsafe.}

  TeamsState = ref object
    token:         AppToken
    conversations: Table[string, string]   ## sender key → reply target

  TeamsAdapter* = object
    appId*:            string
    appPassword:       string
    tenantId*:         string
    resolver*:         IdentityResolver
    linkCodes*:        LinkCodePort
    http:              HttpRuntimePort
    clock:             Clock
    serviceHosts*:     seq[string]
    conversationsPath: string
    state:             TeamsState
    configError*:      string

proc loadConversations(path: string): Table[string, string] =
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
    discard   ## an unreadable file only costs the proactive sends until the next message

proc rememberConversation*(a: TeamsAdapter; senderKey, serviceUrl,
                           conversationId: string): Result[void, string] {.discardable.} =
  ## Where a person last wrote from, for sends without a reply target. The
  ## file is written only when that changes; an error is returned for the
  ## caller to log (the mapping still holds in memory).
  if senderKey.len == 0 or conversationId.len == 0:
    return ok()
  let target = replyTarget(serviceUrl, conversationId, "")
  if a.state.conversations.getOrDefault(senderKey) == target:
    return ok()
  a.state.conversations[senderKey] = target
  if a.conversationsPath.len == 0:
    return ok()
  var j = newJObject()
  for key, value in a.state.conversations:
    j[key] = %value
  atomicWriteText(a.conversationsPath, $j, "w")

proc appToken(a: TeamsAdapter): Result[string, string] =
  let now = a.clock()
  if a.state.token.token.len > 0 and now < a.state.token.renewAtMs:
    return ok(a.state.token.token)
  let resp = ? a.http.post(tokenUrl(a.tenantId), tokenForm(a.appId, a.appPassword),
    @[("Content-Type", "application/x-www-form-urlencoded")])
  if resp.status != 200:
    return err("Teams: token request status " & $resp.status)
  a.state.token = ? parseTokenResponse(resp.body, now)
  ok(a.state.token.token)

proc targetFor(a: TeamsAdapter; msg: OutboundMessage): Result[ReplyTarget, string] =
  if msg.replyTo.strip.len > 0:
    return parseReplyTarget(msg.replyTo.strip)
  let key = a.resolver.reverseChannel(msg.userId, ckTeams)
  let remembered = a.state.conversations.getOrDefault(key)
  if key.len == 0 or remembered.len == 0:
    return err("Teams: no conversation known for user " & $msg.userId)
  parseReplyTarget(remembered)

proc send*(a: TeamsAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text, as Markdown, in the thread it answers. Media and keyboards are not
  ## offered for Teams (channel_capability), so they are refused, not dropped.
  if a.configError.len > 0:
    return err("Teams: " & a.configError)
  if msg.mediaUrl.len > 0 or msg.keyboard.len > 0:
    return err("Teams: only text is supported")
  if msg.text.strip.len == 0:
    return ok()
  let target = ? a.targetFor(msg)
  if not serviceHostAllowed(target.serviceUrl, a.serviceHosts):
    return err("Teams: service host not allowed: " & serviceHostOf(target.serviceUrl))
  let token = ? a.appToken()
  let url = activitiesUrl(target.serviceUrl, target.conversationId, target.activityId)
  for piece in splitForTeams(msg.text):
    let resp = ? a.http.post(url, $messageBody(piece, target.activityId),
      @[("Content-Type", "application/json"), ("Authorization", "Bearer " & token)])
    if resp.status notin 200 .. 299:
      return err("Teams: send status " & $resp.status)
  ok()

proc newTeamsAdapter*(appId, appPassword, tenantId, identityPath,
                      conversationsPath: string;
                      http: HttpRuntimePort = HttpRuntimePort();
                      clock: Clock = nil;
                      serviceHosts: seq[string] = DefaultServiceHosts): TeamsAdapter =
  ## `MICROSOFT_APP_ID`, `MICROSOFT_APP_PASSWORD` and `MICROSOFT_APP_TENANT_ID`
  ## from the environment snapshot. Missing credentials do not stop the
  ## daemon: the adapter records why and every send fails with it.
  var transport = http
  if transport.post.isNil:
    transport = newStdHttpAdapter(timeout = TeamsTimeoutSec,
      allowlist = @["login.microsoftonline.com"] & serviceHosts,
      retryNonIdempotent = false, retryConflict = false).toRuntimePort()
  var now = clock
  if now == nil:
    now = proc(): int64 {.gcsafe.} = epochMs()
  result = TeamsAdapter(
    appId: appId.strip, appPassword: appPassword.strip, tenantId: tenantId.strip,
    resolver: newIdentityResolver(identityPath), http: transport, clock: now,
    serviceHosts: serviceHosts, conversationsPath: conversationsPath,
    state: TeamsState(conversations: loadConversations(conversationsPath)),
    configError:
      if appId.strip.len == 0 or appPassword.strip.len == 0:
        "MICROSOFT_APP_ID and MICROSOFT_APP_PASSWORD are not set"
      else: "")
  result.linkCodes = result.resolver.linkCodePort()
