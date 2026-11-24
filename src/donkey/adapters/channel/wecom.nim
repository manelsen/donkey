## WeComAdapter — ChannelPort for WeCom (企业微信) Application.
##
## Receiving: WeCom POSTs XML to the shared webhook receiver at
##   /webhook/wecom (DONKEY_WEBHOOK_PORT); the receiver checks the signature
##   and calls acceptWeComXml, which queues WeComEvents. The main loop calls
##   tryRecvEvent().
##
## Sending: WeCom REST API (POST /cgi-bin/message/send).
##   access_token is fetched lazily and refreshed ~1 minute before expiry.
##
## Signature: SHA1(sort([callbackToken, timestamp, nonce]).join(""))
##   Used for both URL verification (GET) and message receipt (POST).
##
## Message types sent:
##   text     — plain text reply
##   markdown — structured rich reply (headers, bold, colour tags)
##
## Config env vars:
##   WECOM_CORP_ID, WECOM_CORP_SECRET, WECOM_AGENT_ID,
##   WECOM_CALLBACK_TOKEN (the route is mounted only when it is set)

import std/[algorithm, json, locks, strutils, tables, times]
import checksums/sha1
import ../../core/log
import ../../core/pipeops
import ../../core/security/webhook_auth
import ../../domain/message
import ../../domain/channels/wechat_pure
import ../http/std_http
import ../identity/identity_resolver
import ../../app/metrics
import ../../infra/event_queue
import ../../infra/fixed
import ../../domain/channels/access_token_pure

const WeComApiBase = "https://qyapi.weixin.qq.com"

# ── Public event type (webhook thread → main) ─────────────────────────────────

type
  WeComEvent* = object
    msgType*:  string   ## "text" (only type routed for now)
    fromUser*: string   ## WeCom userid
    msgId*:    string   ## unique message id for dedup
    content*:  string

  WeComAdapter* = object
    corpId*:        string
    corpSecret*:    string
    callbackToken*: string
    agentId*:       int
    apiBase*:       string  ## override for testing
    resolver*:      IdentityResolver
    http:           StdHttpAdapter
    token:          AccessToken

## Module-level queue, valid for the daemon's lifetime. Thread-safe: an
## `EventQueue` (shared memory, events moved, not copied); the receiver's
## workers push, the daemon loop polls.
var gWeComEvents* = initEventQueue[WeComEvent]("wecom")

# ── Token management ──────────────────────────────────────────────────────────


func base(a: WeComAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: WeComApiBase

proc refreshToken*(a: var WeComAdapter): Result[void, string] =
  let url = a.base() & "/cgi-bin/gettoken?corpid=" & a.corpId &
            "&corpsecret=" & a.corpSecret
  let resp = ? a.http.get(url)
  var j: JsonNode
  try: j = parseJson(resp.body)
  except JsonParsingError: return err("WeCom token: invalid JSON")
  let code = j.getOrDefault("errcode").getInt(0)
  if code != 0:
    return err("WeCom token error " & $code & ": " &
               j.getOrDefault("errmsg").getStr(""))
  a.token = issuedToken(j.getOrDefault("access_token").getStr(""),
                        j.getOrDefault("expires_in").getInt(7200).int64,
                        getTime().toUnix())
  ok()

proc ensureToken(a: var WeComAdapter): Result[string, string] =
  if not a.token.isFresh(getTime().toUnix()):
    ? a.refreshToken()
  ok(a.token.value)

# ── Signature ─────────────────────────────────────────────────────────────────

func wecomSignature*(token, timestamp, nonce: string): string =
  ## SHA1(sort([token, timestamp, nonce]).join("")) — lowercase hex.
  var parts = @[token, timestamp, nonce]
  parts.sort()
  ($secureHash(parts.join(""))).toLowerAscii()

# ── Sending ───────────────────────────────────────────────────────────────────

proc apiPost(a: var WeComAdapter; endpoint: string; body: JsonNode): Result[void, string] =
  let token = ? a.ensureToken()
  let url = a.base() & endpoint & "?access_token=" & token
  let resp = ? a.http.post(url, $body, @[("Content-Type", "application/json")])
  if resp.status < 200 or resp.status >= 300:
    return err("WeCom HTTP " & $resp.status)
  var j: JsonNode
  try: j = parseJson(resp.body)
  except JsonParsingError: return err("WeCom: invalid JSON response")
  let code = j.getOrDefault("errcode").getInt(0)
  if code != 0:
    return err("WeCom error " & $code & ": " & j.getOrDefault("errmsg").getStr(""))
  ok()

proc send*(a: var WeComAdapter; msg: OutboundMessage): Result[void, string] =
  let wecomId = a.resolver.reverseChannel(msg.userId, ckWeCom)
  if wecomId.len == 0:
    return err("WeComAdapter.send: no WeCom ID for " & $msg.userId)
  a.apiPost("/cgi-bin/message/send", %* {
    "touser":  wecomId,
    "msgtype": "text",
    "agentid": a.agentId,
    "text":    {"content": msg.text},
  })

proc sendMarkdown*(a: var WeComAdapter; userId: UserId; md: string): Result[void, string] =
  ## Sends a markdown message.  WeCom markdown supports:
  ##   ## heading, **bold**, <font color="info/comment/warning">text</font>,
  ##   [link](url), > quote, - list item.
  let wecomId = a.resolver.reverseChannel(userId, ckWeCom)
  if wecomId.len == 0:
    return err("WeComAdapter.sendMarkdown: no WeCom ID for " & $userId)
  a.apiPost("/cgi-bin/message/send", %* {
    "touser":   wecomId,
    "msgtype":  "markdown",
    "agentid":  a.agentId,
    "markdown": {"content": md},
  })

# ── Webhook callbacks ──────────────────────────────────────────────────────────
## The shared webhook receiver (adapters/webhook/webhook_receiver) serves the
## route and checks msg_signature; it hands the body here.

const
  DedupWindowMs = 5 * 60 * 1000  ## WeCom retries within seconds; 5 min is ample
  DedupSlots    = 1024
    ## Recent message ids remembered (72 KiB). WeCom retries three times about
    ## 5 s apart, so a retry is missed only when more than ~60 other messages
    ## a second arrive in between. The old Table had no bound at all, which
    ## let a flood of distinct ids grow it without limit.
  DedupIdBytes  = 64

type SeenId = object
  id:   FixedText[DedupIdBytes]
  atMs: int64

var
  gWeComSeenLock: Lock
  gWeComSeen: array[DedupSlots, SeenId]
    ## A ring of recent message ids, plain values under a lock: the receiver's
    ## workers handle requests in parallel, so a retry may reach another one.
  gWeComSeenNext = 0

initLock(gWeComSeenLock)

proc seenRecently(msgId: string; nowMs: int64): bool {.gcsafe.} =
  ## True when `msgId` arrived within the window; otherwise remembers it.
  withLock gWeComSeenLock:
    for slot in gWeComSeen:
      if slot.atMs > 0 and nowMs - slot.atMs <= DedupWindowMs and slot.id == msgId:
        return true
    gWeComSeen[gWeComSeenNext] = SeenId(id: toFixed[DedupIdBytes](msgId), atMs: nowMs)
    gWeComSeenNext = (gWeComSeenNext + 1) mod DedupSlots
  false

proc acceptWeComXml*(body: string) {.gcsafe.} =
  ## Queues a signed callback's text message for the daemon loop. Non-text
  ## messages, empty text and WeCom's retries of a message already queued are
  ## dropped.
  if body.len == 0: return
  let r = parseXmlMsg(body)
  if r.kind != wckText: return
  let text = r.text.strip()
  if text.len == 0: return
  if r.msgId.len > 0 and seenRecently(r.msgId, epochMs()):
    return
  gWeComEvents.push(WeComEvent(
    msgType:  "text",
    fromUser: r.rawId,
    msgId:    r.msgId,
    content:  text,
  ))

proc tryRecvEvent*(a: var WeComAdapter): (bool, WeComEvent) =
  let (ok, ev) = gWeComEvents.tryTake()
  (ok, ev)

# ── Constructor ────────────────────────────────────────────────────────────────

proc newWeComAdapter*(corpId, corpSecret, callbackToken: string;
                      agentId: int; identityPath: string;
                      apiBase = ""): WeComAdapter =
  WeComAdapter(
    apiBase:       apiBase,
    corpId:        corpId,
    corpSecret:    corpSecret,
    callbackToken: callbackToken,
    agentId:       agentId,
    resolver:      newIdentityResolver(identityPath),
    http:          newStdHttpAdapter(),
  )
