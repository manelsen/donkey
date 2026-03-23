## QQWebhookAdapter — QQ official bot HTTP webhook adapter.
##
## Receiving: QQ POSTs events to your webhook endpoint (callback URL).
##   The HTTP layer calls pushEvent() with the parsed JSON payload.
##   The daemon calls tryRecvEvent() (non-blocking) in its main loop.
##
## Event format: QQ delivers gateway dispatch `{"op":0,"t":"TYPE","d":{...}}`
##   or flat webhook `{...fields directly...}`. qq_pure handles both.
##
## Sending: QQ official bot API with bearer token authentication.
##   POST https://api.sgroup.qq.com/v2/users/{openid}/messages
##   POST https://api.sgroup.qq.com/v2/groups/{group_openid}/messages
##
## Topology (pipeops):
##   |>    — payload |> parseEvent
##   >>=   — http.post(...) >>= parseQqBody

import std/[json, strutils, times]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/qq_pure
import ../../ports/http
import ../http/std_http
import ../identity/identity_resolver

export identity_resolver

const
  QQWebhookDefaultApiBase*   = "https://api.sgroup.qq.com"
  QQWebhookDefaultTokenBase* = "https://bots.qq.com"
  QQWebhookTokenSkewSec      = 60'i64

# ── Public event type ─────────────────────────────────────────────────────────

type
  QQWebhookEvent* = object
    messageType*: string  ## "private" | "group" | "interaction"
    userId*:      string  ## member_openid or user_openid
    groupId*:     string  ## group_openid; non-empty for group events
    messageId*:   string  ## "msg:<id>" or "event:<id>"
    content*:     string  ## message text or "/callback <data>"

# ── Module-level event queue ──────────────────────────────────────────────────

var gQQWbEvents* {.global.}: Channel[QQWebhookEvent]

# ── Inbound helpers (called by HTTP layer) ────────────────────────────────────

proc pushEvent*(payload: JsonNode) =
  ## Parses an incoming QQ official bot webhook payload and enqueues it.
  ## Ignores qqkUnknown events.
  let r = payload |> parseEvent
  case r.kind
  of qqkUnknown: discard
  of qqkPrivate:
    gQQWbEvents.send(QQWebhookEvent(
      messageType: "private",
      userId:      r.rawId,
      messageId:   r.messageId,
      content:     r.text,
    ))
  of qqkGroup:
    gQQWbEvents.send(QQWebhookEvent(
      messageType: "group",
      userId:      r.rawId,
      groupId:     r.groupId,
      messageId:   r.messageId,
      content:     r.text,
    ))
  of qqkInteraction:
    gQQWbEvents.send(QQWebhookEvent(
      messageType: "interaction",
      userId:      r.rawId,
      groupId:     r.groupId,
      messageId:   r.messageId,
      content:     r.text,
    ))

# ── QQWebhookAdapter ──────────────────────────────────────────────────────────

type
  QQWebhookAdapter* = object
    appId*:         string
    clientSecret*:  string
    apiBase*:       string   ## override for testing
    tokenBase*:     string   ## override for testing
    resolver*:      IdentityResolver
    http*:          StdHttpAdapter
    accessToken:    string
    tokenExpirySec: int64

func apiBase(a: QQWebhookAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: QQWebhookDefaultApiBase

func tokenBase(a: QQWebhookAdapter): string =
  if a.tokenBase.len > 0: a.tokenBase else: QQWebhookDefaultTokenBase

func qqBotHeader(token: string): (string, string) =
  ("Authorization", "QQBot " & token)

# ── Token management ──────────────────────────────────────────────────────────

proc nowUnixSec(): int64 =
  getTime().toUnix()

proc parseQqBody(resp: HttpResponse): Result[JsonNode, string]
               {.gcsafe, raises: [].} =
  ## Validates HTTP status. Designed for >>= chaining.
  if resp.status < 200 or resp.status >= 300:
    return err("QQ webhook HTTP " & $resp.status & ": " & resp.body)
  try:
    ok(parseJson(resp.body))
  except CatchableError as e:
    err(e.msg)

proc ensureAccessToken*(a: var QQWebhookAdapter): Result[string, string] =
  ## Returns a valid access token, refreshing if expired.
  if a.accessToken.len > 0 and
     (a.tokenExpirySec - QQWebhookTokenSkewSec) > nowUnixSec():
    return ok(a.accessToken)
  let body    = %* {"appId": a.appId, "clientSecret": a.clientSecret}
  let headers = @[("Content-Type", "application/json")]
  let resp    = ? a.http.post(
    a.tokenBase().strip(chars = {'/'}) & "/app/getAppAccessToken",
    $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("QQ webhook token error " & $resp.status & ": " & resp.body)
  try:
    let j     = parseJson(resp.body)
    let tok   = j.getOrDefault("access_token").getStr("")
    let rawEx = j.getOrDefault("expires_in")
    let exSec =
      if rawEx.kind == JString: parseInt(rawEx.getStr("0"))
      else: rawEx.getInt(0)
    if tok.len == 0 or exSec <= 0:
      return err("QQ webhook token: missing access_token/expires_in")
    a.accessToken    = tok
    a.tokenExpirySec = nowUnixSec() + int64(exSec)
    ok(tok)
  except CatchableError as e:
    err(e.msg)

# ── Send helpers ──────────────────────────────────────────────────────────────

func buildSendUrl(apiBase, rawId: string): Result[string, string] =
  ## Builds the send endpoint URL from the raw identity key.
  let root = apiBase.strip(chars = {'/'})
  if rawId.len == 0:
    return err("QQWebhookAdapter.send: missing target id")
  if rawId.startsWith("group:"):
    let gid = rawId["group:".len .. ^1]
    if gid.len == 0:
      return err("QQWebhookAdapter.send: missing group_openid")
    return ok(root & "/v2/groups/" & gid & "/messages")
  ok(root & "/v2/users/" & rawId & "/messages")

func parseReplyToken(replyTo: string): (string, string) =
  ## Splits "event:<id>" or "msg:<id>" into (kind, id).
  if replyTo.startsWith("event:"):
    return ("event", replyTo["event:".len .. ^1])
  if replyTo.startsWith("msg:"):
    return ("msg", replyTo["msg:".len .. ^1])
  ("msg", replyTo)

func buildSendBody(msg: OutboundMessage): Result[JsonNode, string] =
  ## Builds the QQ official bot message request body.
  if msg.mediaUrl.len > 0:
    return err("QQWebhookAdapter: media send not implemented")
  var body = %* {"content": msg.text, "msg_type": 0}
  if msg.replyTo.len > 0:
    let (replyKind, replyId) = parseReplyToken(msg.replyTo)
    if replyKind == "event":
      body["event_id"] = %replyId
    else:
      body["msg_id"] = %replyId
  ok(body)

proc sendToRawId*(a: var QQWebhookAdapter;
                  rawId: string;
                  msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the given raw identity key (user_openid or "group:<gid>").
  let token = ? a.ensureAccessToken()
  let url   = ? buildSendUrl(a.apiBase(), rawId)
  let body  = ? buildSendBody(msg)
  let hdrs  = @[qqBotHeader(token), ("Content-Type", "application/json")]
  let resp  = ? a.http.post(url, $body, hdrs)
  if resp.status < 200 or resp.status >= 300:
    return err("QQ webhook send error " & $resp.status & ": " & resp.body)
  ok()

proc send*(a: var QQWebhookAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the user resolved from the identity store.
  let rawId = a.resolver.reverseChannel(msg.userId, ckQQ)
  if rawId.len == 0:
    return err("QQWebhookAdapter.send: no QQ id for user " & $msg.userId)
  a.sendToRawId(rawId, msg)

proc sendReturnId*(a: var QQWebhookAdapter;
                   msg: OutboundMessage): Result[string, string] =
  ## Sends a message and returns the message id from the API response.
  let rawId = a.resolver.reverseChannel(msg.userId, ckQQ)
  if rawId.len == 0:
    return err("QQWebhookAdapter.sendReturnId: no QQ id for user " & $msg.userId)
  let token = ? a.ensureAccessToken()
  let url   = ? buildSendUrl(a.apiBase(), rawId)
  let body  = ? buildSendBody(msg)
  let hdrs  = @[qqBotHeader(token), ("Content-Type", "application/json")]
  let j     = ? (a.http.post(url, $body, hdrs) >>= parseQqBody)
  let msgId = j.getOrDefault("id").getStr("")
  if msgId.len == 0:
    return err("QQWebhookAdapter.sendReturnId: missing id in response")
  ok(msgId)

proc editMessage*(a: QQWebhookAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## No-op — QQ official bot v1 does not support message editing.
  discard userId
  discard msgId
  discard text
  ok()

proc ack*(a: QQWebhookAdapter; msgId: string) =
  ## No-op — QQ webhook does not require explicit ack (HTTP 200 suffices).
  discard

# ── Queue management ──────────────────────────────────────────────────────────

proc openQueue*(a: QQWebhookAdapter) =
  ## Opens the module-level event queue. Call once at daemon startup.
  {.cast(gcsafe).}:
    gQQWbEvents.open()

proc startGateway*(a: var QQWebhookAdapter) =
  ## Opens the webhook event queue. Named startGateway to match ChannelPort
  ## convention used by WebSocket-based adapters.
  a.openQueue()

proc tryRecvEvent*(a: QQWebhookAdapter): (bool, QQWebhookEvent) =
  ## Non-blocking poll for webhook events. Returns (false, default) when empty.
  gQQWbEvents.tryRecv()

# ── Constructor ───────────────────────────────────────────────────────────────

proc newQQWebhookAdapter*(appId, clientSecret: string;
                          identityPath: string;
                          apiBase   = "";
                          tokenBase = ""): QQWebhookAdapter =
  QQWebhookAdapter(
    appId:        appId,
    clientSecret: clientSecret,
    apiBase:      apiBase,
    tokenBase:    tokenBase,
    resolver:     newIdentityResolver(identityPath),
    http:         newStdHttpAdapter(),
  )
