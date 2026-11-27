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

import std/[base64, json, locks, os, strutils, sysrand, tables]
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/teams_pure
import ../../infra/event_queue
import ../../infra/fixed
import ../../ports/channel
import ../../ports/http
import ../../ports/link_codes
import ../crypto/rs256
import ../filesystem/confined_read
import ../filesystem/paths
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
      elif nowMs - gKeysFetchedMs > KeysMaxAgeMs:
        sinceAttempt >= MissingKeysRetryMs   ## stale: spaced too, or a failing fetch runs on every request
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

  PendingFile = object
    ## A file offered with a consent card: the path, never the bytes, until
    ## the person answers (Microsoft: keep the bytes out of the card).
    path, mediaRoot, name: string
    serviceUrl, conversationId: string
    createdMs: int64

  TeamsState = ref object
    token:         AppToken
    conversations: Table[string, string]   ## sender key → reply target
    pending:       Table[string, PendingFile]   ## pending id → the file offered
    fileTokens:    Table[string, AppToken]      ## scope → the file token (part 3)

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
    certPem:           string   ## MICROSOFT_APP_CERT: certificate and key (part 3)
    certX5t:           string
    certError:         string
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

const
  TeamsMaxFileBytes* = 100 * 1024 * 1024
  FileUnavailableNote = "(o arquivo não pôde ser enviado)"
  FileNotHereNote = "(o Teams só aceita arquivos do bot em conversa pessoal; " &
                    "o arquivo está guardado no seu espaço)"

proc postActivity(a: TeamsAdapter; serviceUrl, conversationId, activityId: string;
                  body: JsonNode): Result[void, string] =
  if not serviceHostAllowed(serviceUrl, a.serviceHosts):
    return err("Teams: service host not allowed: " & serviceHostOf(serviceUrl))
  let token = ? a.appToken()
  let resp = ? a.http.post(activitiesUrl(serviceUrl, conversationId, activityId), $body,
    @[("Content-Type", "application/json"), ("Authorization", "Bearer " & token)])
  if resp.status notin 200 .. 299:
    return err("Teams: send status " & $resp.status)
  ok()

proc fileToken(a: TeamsAdapter; url, tenant: string): Result[string, string] =
  ## The token for a file URL (part 3): from the certificate, through a
  ## client assertion; "" without a certificate (until 1 March 2027 the URLs
  ## carry `tempauth`). Kept per scope until it is due.
  if a.certError.len > 0:
    return err("Teams: MICROSOFT_APP_CERT: " & a.certError)
  if a.certPem.len == 0:
    return ok("")
  let scope = fileScope(url)
  let now = a.clock()
  let cached = a.state.fileTokens.getOrDefault(scope)
  if cached.token.len > 0 and now < cached.renewAtMs:
    return ok(cached.token)
  var raw: array[16, byte]
  if not urandom(raw): return err("Teams: no randomness for a token id")
  var jti = ""
  for b in raw: jti.add b.toHex(2).toLowerAscii
  let tenantId = if tenant.len > 0: tenant else: a.tenantId
  if tenantId.len == 0:
    ## A client assertion is issued to one tenant's token endpoint; a
    ## multi-tenant app without one has nowhere to ask.
    return err("Teams: the file token needs MICROSOFT_APP_TENANT_ID (or the upload's tenant)")
  let input = fileTokenAssertionInput(a.appId, tenantId, a.certX5t, jti, now div 1000)
  let signature = ? rs256Sign(a.certPem, input)
  let assertion = input & "." & encode(signature, safe = true).strip(leading = false, chars = {'='})
  let resp = ? a.http.post(tokenUrl(tenantId), fileTokenForm(a.appId, scope, assertion),
    @[("Content-Type", "application/x-www-form-urlencoded")])
  if resp.status != 200:
    return err("Teams: file token request status " & $resp.status)
  let token = ? parseTokenResponse(resp.body, now)
  a.state.fileTokens[scope] = token
  ok(token.token)

proc readPaddockFile(path, mediaRoot: string; limit: int): Result[(string, string), string] =
  ## The file's name and bytes, read only inside the paddock (confined_read).
  let safePath = ? resolveConfinedMediaPath(mediaRoot, path)
  var opened = ? openPathComponent(mediaRoot, safePath)
  let data = opened.readPathComponent(limit)
  opened.closeComponent()
  ok((opened.name, ? data))

const
  MaxPendingFiles* = 256
  PendingTtlMs = 86_400_000'i64   ## an offer nobody answered in a day is dropped

func pendingExpired*(createdMs, nowMs: int64): bool =
  nowMs - createdMs > PendingTtlMs

proc prunePending(a: TeamsAdapter) =
  ## Expired offers go; past the cap, the oldest go first.
  let now = a.clock()
  var keys: seq[string]
  for k, p in a.state.pending:
    if pendingExpired(p.createdMs, now): keys.add k
  for k in keys: a.state.pending.del k
  while a.state.pending.len >= MaxPendingFiles:
    var oldest = ""
    var at = high(int64)
    for k, p in a.state.pending:
      if p.createdMs < at:
        at = p.createdMs
        oldest = k
    a.state.pending.del oldest

proc newPendingId(): string =
  var raw: array[12, byte]
  if not urandom(raw): return ""
  for b in raw: result.add b.toHex(2).toLowerAscii

proc sendText(a: TeamsAdapter; target: ReplyTarget; text: string): Result[void, string] =
  for piece in splitForTeams(text):
    ? a.postActivity(target.serviceUrl, target.conversationId, target.activityId,
                     messageBody(piece, target.activityId))
  ok()

proc send*(a: TeamsAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text, as Markdown, in the thread it answers. A file (Teams complete):
  ## a small PNG/JPEG/GIF inline; another file, in a personal chat, offered
  ## with a consent card and uploaded once the person accepts
  ## (handleFileConsent); in a group or channel, a note. Keyboards are not
  ## offered for Teams.
  if a.configError.len > 0:
    return err("Teams: " & a.configError)
  let target = ? a.targetFor(msg)
  var msg = msg
  if msg.keyboard.len > 0:
    ## Buttons (approvals): an Adaptive Card (Teams complete, part 4). A file
    ## that came with them follows on its own.
    ? a.postActivity(target.serviceUrl, target.conversationId, target.activityId,
                     cardBody(msg.text, msg.keyboard, target.activityId))
    if msg.mediaUrl.len == 0: return ok()
    msg.text = ""
  if msg.mediaUrl.len == 0:
    if msg.text.strip.len == 0: return ok()
    return a.sendText(target, msg.text)
  let file = readPaddockFile(msg.mediaUrl, msg.mediaRoot, TeamsMaxFileBytes)
  if file.isErr:
    return a.sendText(target, (if msg.text.strip.len > 0: msg.text & "\n\n" else: "") &
                              FileUnavailableNote)
  let (name, data) = file.get
  let mime = inlineImageMime(name)
  if mime.len > 0 and data.len <= TeamsInlineImageMaxBytes:
    return a.postActivity(target.serviceUrl, target.conversationId, target.activityId,
                          imageMessageBody(msg.text, target.activityId, mime, name, data))
  if not isPersonalConversation(target.conversationId):
    return a.sendText(target, (if msg.text.strip.len > 0: msg.text & "\n\n" else: "") &
                              FileNotHereNote)
  let pending = newPendingId()
  if pending.len == 0:
    return err("Teams: no randomness for a pending file id")
  a.prunePending()
  a.state.pending[pending] = PendingFile(path: msg.mediaUrl, mediaRoot: msg.mediaRoot,
    name: name, serviceUrl: target.serviceUrl, conversationId: target.conversationId,
    createdMs: a.clock())
  a.postActivity(target.serviceUrl, target.conversationId, target.activityId,
    fileConsentBody(name, (if msg.text.strip.len > 0: msg.text else: "Arquivo do Donkey"),
                    data.len.int64, pending, target.activityId))

proc handleFileConsent*(a: TeamsAdapter; act: TeamsActivity): Result[void, string] =
  ## The person's answer to a consent card. Accepted: the file is read again
  ## (inside the paddock), uploaded in one PUT to the person's OneDrive, and a
  ## file card shown; declined: they are told. An unknown or answered offer
  ## is ignored.
  let value = try: parseJson(act.value) except CatchableError: return err("Teams: consent value unreadable")
  let consent = ? parseFileConsent(act.name, value)
  if consent.pending notin a.state.pending:
    return ok()
  let offered = a.state.pending[consent.pending]
  ## Only the conversation the file was offered in may answer: a personal
  ## conversation is the person's own, so a leaked id answered elsewhere
  ## does nothing.
  if act.conversationId != offered.conversationId:
    return ok()
  a.state.pending.del consent.pending
  if not consent.accepted:
    return a.postActivity(offered.serviceUrl, offered.conversationId, "",
      messageBody("Tudo bem, não enviei " & offered.name & ".", ""))
  proc failed(why: string): Result[void, string] =
    ## The person accepted: tell them it did not go, so they can ask again.
    discard a.postActivity(offered.serviceUrl, offered.conversationId, "",
      messageBody("Não consegui enviar " & offered.name & ". Peça de novo, por favor.", ""))
    err(why)
  if not uploadAllowed(consent.uploadUrl):
    return failed("Teams: upload URL outside SharePoint")
  let file = readPaddockFile(offered.path, offered.mediaRoot, TeamsMaxFileBytes)
  if file.isErr:
    return failed("Teams: " & file.error)
  let data = file.get[1]
  var headers = uploadHeaders(data.len)
  let token = a.fileToken(consent.uploadUrl, consent.tenantId)
  if token.isErr:
    return failed(token.error)
  if token.get.len > 0: headers.add ("Authorization", "Bearer " & token.get)
  let sent = a.http.put(consent.uploadUrl, data, headers)
  if sent.isErr:
    return failed("Teams: upload: " & sent.error)
  if sent.get.status notin [200, 201]:
    return failed("Teams: upload status " & $sent.get.status)
  a.postActivity(offered.serviceUrl, offered.conversationId, "",
    fileInfoBody(consent.contentUrl, (if consent.name.len > 0: consent.name else: offered.name),
                 consent.uniqueId, consent.fileType, ""))

const TeamsMaxDownloadBytes* = 25 * 1024 * 1024

proc downloadFile*(a: TeamsAdapter; fileId: string): Result[FileDownload, string] =
  ## An attachment (E9.4): a SharePoint file by its pre-authenticated URL, no
  ## token; an inline image from the Bot Framework service with the bot's
  ## token. Anything else is refused before a request (teamsDownload).
  if a.configError.len > 0:
    return err("Teams: " & a.configError)
  let where = ? teamsDownload(fileId, a.serviceHosts)
  var headers: seq[HttpHeader]
  if where.withToken:
    headers.add ("Authorization", "Bearer " & (? a.appToken()))
  else:
    let token = ? a.fileToken(where.url, "")
    if token.len > 0: headers.add ("Authorization", "Bearer " & token)
  let resp = ? a.http.get(where.url, headers)
  if resp.status != 200:
    return err("Teams: download status " & $resp.status)
  if resp.body.len > TeamsMaxDownloadBytes:
    return err("Teams: attachment larger than " & $(TeamsMaxDownloadBytes div (1024 * 1024)) & " MB")
  var data = newSeq[byte](resp.body.len)
  for i in 0 ..< resp.body.len: data[i] = byte(resp.body[i])
  ok(FileDownload(fileName: "attachment", fileSize: data.len.int64, data: data))

proc newTeamsAdapter*(appId, appPassword, tenantId, identityPath,
                      conversationsPath: string;
                      http: HttpRuntimePort = HttpRuntimePort();
                      clock: Clock = nil;
                      serviceHosts: seq[string] = DefaultServiceHosts;
                      certPath = ""): TeamsAdapter =
  ## `MICROSOFT_APP_ID`, `MICROSOFT_APP_PASSWORD` and `MICROSOFT_APP_TENANT_ID`
  ## from the environment snapshot. Missing credentials do not stop the
  ## daemon: the adapter records why and every send fails with it.
  ## `certPath` (`MICROSOFT_APP_CERT`): a PEM with the app's certificate and
  ## key, for the token file downloads and uploads need from 1 March 2027.
  var transport = http
  if transport.post.isNil:
    transport = newStdHttpAdapter(timeout = TeamsTimeoutSec,
      allowlist = @["login.microsoftonline.com", "sharepoint.com"] & serviceHosts,
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
  if certPath.strip.len > 0:
    try:
      result.certPem = readFile(certPath.strip)
      let x5t = certThumbprint(result.certPem)
      if x5t.isErr: result.certError = x5t.error
      else: result.certX5t = x5t.get
    except CatchableError as e:
      result.certError = "cannot read " & certPath.strip & ": " & e.msg
