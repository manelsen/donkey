## DingTalkAdapter — ChannelPort for DingTalk webhook (HTTP callback) mode.
##
## Receiving: DingTalk POSTs events to your callback endpoint.
##   The HTTP layer calls pushEvent() with the parsed JSON payload.
##   The daemon calls tryRecvEvent() (non-blocking) in its main loop.
##
## Sending: DingTalk Open Platform robot API with access token.
##   p2p:   POST /v1.0/robot/oToMessages/batchSend
##   group: POST /v1.0/robot/groupMessages/send
##
## Token: POST /v1.0/oauth2/accessToken
##   Body:    {"appKey":"..","appSecret":".."}
##   Returns: {"accessToken":"..","expireIn":7200}
##   Header:  x-acs-dingtalk-access-token: <token>
##
## Routing convention:
##   p2p events  → rawId = senderId
##   group events → rawId = "conv:" + conversationId
##
## Topology (pipeops):
##   |>    — payload |> parseEvent
##   >>=   — http.post(...) >>= parseDtBody

import std/[json, strutils, times]
import ../../core/types
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/dingtalk_pure
import ../../ports/http
import ../http/std_http
import ../identity/identity_resolver

export identity_resolver

const
  DtDefaultApiBase* = "https://api.dingtalk.com"
  DtTokenSkewSec    = 60'i64

# ── Public event type ─────────────────────────────────────────────────────────

type
  DingTalkEvent* = object
    msgType*:      string  ## "text" | "image" | "audio" | "video" | "file"
    rawId*:        string  ## senderId or "conv:<conversationId>" for group
    messageId*:    string  ## msgId
    content*:      string  ## message text (dtkText only); "" otherwise
    downloadCode*: string  ## downloadCode for media types

# ── Module-level event queue ──────────────────────────────────────────────────

var gDtEvents* {.global.}: Channel[DingTalkEvent]

# ── Inbound helpers (called by HTTP layer) ────────────────────────────────────

proc pushEvent*(payload: JsonNode) =
  ## Parses an incoming DingTalk webhook payload and enqueues actionable events.
  ## Ignores dtkUnknown events.
  let r = payload |> parseEvent
  case r.kind
  of dtkUnknown: discard
  of dtkText:
    let evRawId = if r.isGroup: "conv:" & r.conversationId else: r.rawId
    {.cast(gcsafe).}:
      gDtEvents.send(DingTalkEvent(
        msgType:   "text",
        rawId:     evRawId,
        messageId: r.messageId,
        content:   r.text,
      ))
  of dtkImage:
    let evRawId = if r.isGroup: "conv:" & r.conversationId else: r.rawId
    {.cast(gcsafe).}:
      gDtEvents.send(DingTalkEvent(
        msgType:      "image",
        rawId:        evRawId,
        messageId:    r.messageId,
        downloadCode: r.downloadCode,
      ))
  of dtkAudio:
    let evRawId = if r.isGroup: "conv:" & r.conversationId else: r.rawId
    {.cast(gcsafe).}:
      gDtEvents.send(DingTalkEvent(
        msgType:      "audio",
        rawId:        evRawId,
        messageId:    r.messageId,
        downloadCode: r.downloadCode,
      ))
  of dtkVideo:
    let evRawId = if r.isGroup: "conv:" & r.conversationId else: r.rawId
    {.cast(gcsafe).}:
      gDtEvents.send(DingTalkEvent(
        msgType:      "video",
        rawId:        evRawId,
        messageId:    r.messageId,
        downloadCode: r.downloadCode,
      ))
  of dtkFile:
    let evRawId = if r.isGroup: "conv:" & r.conversationId else: r.rawId
    {.cast(gcsafe).}:
      gDtEvents.send(DingTalkEvent(
        msgType:      "file",
        rawId:        evRawId,
        messageId:    r.messageId,
        downloadCode: r.downloadCode,
      ))

# ── DingTalkAdapter ───────────────────────────────────────────────────────────

type
  DingTalkAdapter* = object
    appKey*:        string
    appSecret*:     string
    robotCode*:     string
    apiBase*:       string   ## override for testing
    resolver*:      IdentityResolver
    http*:          StdHttpAdapter
    accessToken:    string
    tokenExpirySec: int64

func resolvedApiBase(a: DingTalkAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: DtDefaultApiBase

func dtTokenHeader(token: string): (string, string) =
  ("x-acs-dingtalk-access-token", token)

# ── Token management ──────────────────────────────────────────────────────────

proc nowUnixSec(): int64 =
  getTime().toUnix()

proc parseDtBody(resp: HttpResponse): Result[JsonNode, string]
               {.gcsafe, raises: [].} =
  ## Validates HTTP status. Designed for >>= chaining.
  if resp.status < 200 or resp.status >= 300:
    return err("DingTalk HTTP " & $resp.status & ": " & resp.body)
  try:
    ok(parseJson(resp.body))
  except CatchableError as e:
    err(e.msg)

proc ensureAccessToken*(a: var DingTalkAdapter): Result[string, string] =
  ## Returns a valid access token, refreshing if expired.
  if a.accessToken.len > 0 and
     (a.tokenExpirySec - DtTokenSkewSec) > nowUnixSec():
    return ok(a.accessToken)
  let body    = %* {"appKey": a.appKey, "appSecret": a.appSecret}
  let headers = @[("Content-Type", "application/json")]
  let resp    = ? a.http.post(
    a.resolvedApiBase().strip(chars = {'/'}) & "/v1.0/oauth2/accessToken",
    $body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err("DingTalk token error " & $resp.status & ": " & resp.body)
  try:
    let j     = parseJson(resp.body)
    let tok   = j.getOrDefault("accessToken").getStr("")
    let exSec = j.getOrDefault("expireIn").getInt(0)
    if tok.len == 0 or exSec <= 0:
      return err("DingTalk token: missing accessToken/expireIn")
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
    return err("DingTalkAdapter.send: missing target id")
  if rawId.startsWith("conv:"):
    return ok(root & "/v1.0/robot/groupMessages/send")
  ok(root & "/v1.0/robot/oToMessages/batchSend")

func buildSendBody(robotCode, rawId, text: string): Result[JsonNode, string] =
  ## Builds the DingTalk robot message request body.
  if rawId.len == 0:
    return err("DingTalkAdapter.buildSendBody: missing target id")
  let msgParam = "{\"content\":\"" &
    text.replace("\\", "\\\\").replace("\"", "\\\"") & "\"}"
  if rawId.startsWith("conv:"):
    let convId = rawId["conv:".len .. ^1]
    return ok(%* {
      "robotCode":          robotCode,
      "openConversationId": convId,
      "msgKey":             "sampleText",
      "msgParam":           msgParam,
    })
  ok(%* {
    "robotCode": robotCode,
    "userIds":   [rawId],
    "msgKey":    "sampleText",
    "msgParam":  msgParam,
  })

proc sendToRawId*(a: var DingTalkAdapter;
                  rawId: string;
                  msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the given raw identity key (staffId or "conv:<convId>").
  let token = ? a.ensureAccessToken()
  let url   = ? buildSendUrl(a.resolvedApiBase(), rawId)
  let body  = ? buildSendBody(a.robotCode, rawId, msg.text)
  let hdrs  = @[dtTokenHeader(token), ("Content-Type", "application/json")]
  let resp  = ? a.http.post(url, $body, hdrs)
  if resp.status < 200 or resp.status >= 300:
    return err("DingTalk send error " & $resp.status & ": " & resp.body)
  ok()

proc send*(a: var DingTalkAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a message to the user resolved from the identity store.
  let rawId = a.resolver.reverseChannel(msg.userId, ckDingTalk)
  if rawId.len == 0:
    return err("DingTalkAdapter.send: no DingTalk id for user " & $msg.userId)
  a.sendToRawId(rawId, msg)

proc sendReturnId*(a: var DingTalkAdapter;
                   msg: OutboundMessage): Result[string, string] =
  ## Sends a message and returns the processQueryKey from the API response.
  let rawId = a.resolver.reverseChannel(msg.userId, ckDingTalk)
  if rawId.len == 0:
    return err("DingTalkAdapter.sendReturnId: no DingTalk id for user " & $msg.userId)
  let token = ? a.ensureAccessToken()
  let url   = ? buildSendUrl(a.resolvedApiBase(), rawId)
  let body  = ? buildSendBody(a.robotCode, rawId, msg.text)
  let hdrs  = @[dtTokenHeader(token), ("Content-Type", "application/json")]
  let j     = ? (a.http.post(url, $body, hdrs) >>= parseDtBody)
  ok(j.getOrDefault("processQueryKey").getStr(""))

proc editMessage*(a: DingTalkAdapter; userId: UserId;
                  msgId, text: string): Result[void, string] =
  ## No-op — DingTalk robot API does not support message editing.
  discard userId
  discard msgId
  discard text
  ok()

proc ack*(a: DingTalkAdapter; msgId: string) =
  ## No-op — DingTalk webhook does not require explicit ack (HTTP 200 suffices).
  discard

# ── Queue management ──────────────────────────────────────────────────────────

proc openQueue*(a: DingTalkAdapter) =
  ## Opens the module-level event queue. Call once at daemon startup.
  {.cast(gcsafe).}:
    gDtEvents.open()

proc startGateway*(a: var DingTalkAdapter) =
  ## Opens the webhook event queue. Named startGateway to match the ChannelPort
  ## convention used by WebSocket-based adapters.
  a.openQueue()

proc tryRecvEvent*(a: DingTalkAdapter): (bool, DingTalkEvent) =
  ## Non-blocking poll for webhook events. Returns (false, default) when empty.
  {.cast(gcsafe).}:
    gDtEvents.tryRecv()

# ── Constructor ───────────────────────────────────────────────────────────────

proc newDingTalkAdapter*(appKey, appSecret, robotCode: string;
                         identityPath: string;
                         apiBase = ""): DingTalkAdapter =
  DingTalkAdapter(
    appKey:    appKey,
    appSecret: appSecret,
    robotCode: robotCode,
    apiBase:   apiBase,
    resolver:  newIdentityResolver(identityPath),
    http:      newStdHttpAdapter(),
  )
