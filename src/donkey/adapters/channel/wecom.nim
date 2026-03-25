## WeComAdapter — ChannelPort for WeCom (企业微信) Application.
##
## Receiving: HTTP webhook server runs on a dedicated OS thread.
##   WeCom POSTs XML to the configured URL; thread pushes WeComEvents
##   to a module-level Channel.  Main loop calls tryRecvEvent().
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
##   WECOM_CALLBACK_TOKEN, WECOM_WEBHOOK_PORT (default 8081)

import std/[algorithm, json, net, strutils, tables, times]
import checksums/sha1
import ../../core/log
import ../../core/pipeops
import ../../domain/message
import ../../domain/channels/wechat_pure
import ../http/std_http
import ../identity/identity_resolver

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
    resolver*:      IdentityResolver
    http:           StdHttpAdapter
    accessToken:    string
    tokenExpiry:    int64   ## epoch ms; 0 = not yet fetched

## Module-level channel — opened once, valid for daemon lifetime.
var gWeComEvents* {.global.}: Channel[WeComEvent]

# ── Token management ──────────────────────────────────────────────────────────

proc epochMs(): int64 =
  let t = getTime()
  t.toUnix() * 1000 + (t.nanosecond div 1_000_000)

proc refreshToken*(a: var WeComAdapter): Result[void, string] =
  let url = WeComApiBase & "/cgi-bin/gettoken?corpid=" & a.corpId &
            "&corpsecret=" & a.corpSecret
  let resp = ? a.http.get(url)
  var j: JsonNode
  try: j = parseJson(resp.body)
  except: return err("WeCom token: invalid JSON")
  let code = j.getOrDefault("errcode").getInt(0)
  if code != 0:
    return err("WeCom token error " & $code & ": " &
               j.getOrDefault("errmsg").getStr(""))
  a.accessToken = j.getOrDefault("access_token").getStr("")
  let expiresIn = j.getOrDefault("expires_in").getInt(7200)
  a.tokenExpiry = epochMs() + expiresIn.int64 * 1000 - 60_000  # refresh 1 min early
  ok()

proc ensureToken(a: var WeComAdapter): Result[string, string] =
  if a.accessToken.len == 0 or epochMs() >= a.tokenExpiry:
    ? a.refreshToken()
  ok(a.accessToken)

# ── Signature ─────────────────────────────────────────────────────────────────

func wecomSignature*(token, timestamp, nonce: string): string =
  ## SHA1(sort([token, timestamp, nonce]).join("")) — lowercase hex.
  var parts = @[token, timestamp, nonce]
  parts.sort()
  ($secureHash(parts.join(""))).toLowerAscii()

# ── Sending ───────────────────────────────────────────────────────────────────

proc apiPost(a: var WeComAdapter; endpoint: string; body: JsonNode): Result[void, string] =
  let token = ? a.ensureToken()
  let url = WeComApiBase & endpoint & "?access_token=" & token
  let resp = ? a.http.post(url, $body, @[("Content-Type", "application/json")])
  if resp.status < 200 or resp.status >= 300:
    return err("WeCom HTTP " & $resp.status)
  var j: JsonNode
  try: j = parseJson(resp.body)
  except: return err("WeCom: invalid JSON response")
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

# ── Webhook HTTP server ────────────────────────────────────────────────────────

## Simple dedup table: msgId → timestamp.  Prevents processing WeCom retries.
var gWeComSeen   {.global.}: Table[string, int64]
var gWeComSeenTs {.global.}: int64  ## last prune epoch ms

const DedupWindowMs = 5 * 60 * 1000  ## 5 minutes

proc dedupCheck(msgId: string): bool =
  ## Returns true if this msgId was recently seen (duplicate).
  {.cast(gcsafe).}:
    let now = epochMs()
    if now - gWeComSeenTs > DedupWindowMs:
      # Prune stale entries
      var toDelete: seq[string]
      for k, ts in gWeComSeen:
        if now - ts > DedupWindowMs: toDelete.add(k)
      for k in toDelete: gWeComSeen.del(k)
      gWeComSeenTs = now
    if msgId in gWeComSeen: return true
    gWeComSeen[msgId] = now
    false

proc readHttpLine(s: Socket): string =
  var c: char
  while true:
    if s.recv(c.addr, 1) != 1: break
    if c == '\r':
      discard s.recv(c.addr, 1)
      break
    result.add(c)

proc sendHttpReply(s: Socket; status, body: string) =
  let r = "HTTP/1.1 " & status & "\r\n" &
          "Content-Type: text/plain; charset=utf-8\r\n" &
          "Content-Length: " & $body.len & "\r\n" &
          "Connection: close\r\n\r\n" & body
  try: s.send(r) except CatchableError: discard

proc parseQueryParams(requestLine: string): Table[string, string] =
  let q = requestLine.find('?')
  if q < 0: return
  let sp = requestLine.find(' ', q)
  let qs = if sp > q: requestLine[q+1 ..< sp] else: requestLine[q+1 .. ^1]
  for pair in qs.split('&'):
    let kv = pair.split('=', 1)
    if kv.len == 2: result[kv[0]] = kv[1]

proc handleWeComConn(client: Socket; token: string; logger: Logger) =
  defer:
    try: client.close() except CatchableError: discard
  try:
    let requestLine = client.readHttpLine()
    if requestLine.len == 0: return

    ## Read and discard headers; capture Content-Length.
    var contentLen = 0
    while true:
      let line = client.readHttpLine()
      if line.len == 0: break
      if line.toLowerAscii().startsWith("content-length:"):
        try: contentLen = parseInt(line[15 .. ^1].strip())
        except ValueError: discard

    let params  = parseQueryParams(requestLine)
    let sig     = params.getOrDefault("msg_signature")
    let ts      = params.getOrDefault("timestamp")
    let nonce   = params.getOrDefault("nonce")
    let isGet   = requestLine.startsWith("GET ")

    if isGet:
      ## URL verification handshake.
      let echostr  = params.getOrDefault("echostr")
      let expected = wecomSignature(token, ts, nonce)
      if sig.len > 0 and sig != expected:
        logger.warn("wecom: URL verify sig mismatch")
        client.sendHttpReply("403 Forbidden", "invalid signature")
        return
      client.sendHttpReply("200 OK", echostr)
      logger.info("wecom: URL verification OK")
      return

    ## POST — read body, ack immediately.
    var body = ""
    if contentLen > 0:
      body = newString(contentLen)
      discard client.recv(body, contentLen)
    client.sendHttpReply("200 OK", "")  ## respond fast before processing

    if body.len == 0: return

    ## Verify signature on POST (plaintext mode).
    if sig.len > 0:
      let expected = wecomSignature(token, ts, nonce)
      if sig != expected:
        logger.warn("wecom: POST sig mismatch")
        return

    let r = parseXmlMsg(body)
    if r.kind != wckText: return
    let text = r.text.strip()
    if text.len == 0: return
    if r.msgId.len > 0 and dedupCheck(r.msgId):
      logger.debug("wecom: duplicate msgId " & r.msgId & " skipped")
      return

    logger.info("wecom: message from " & r.rawId)
    {.cast(gcsafe).}:
      gWeComEvents.send(WeComEvent(
        msgType:  "text",
        fromUser: r.rawId,
        msgId:    r.msgId,
        content:  text,
      ))
  except CatchableError as e:
    logger.warn("wecom: conn error: " & e.msg)

type WeComWebhookArgs = object
  token:  string
  port:   int
  logger: Logger

proc webhookThread(args: WeComWebhookArgs) {.thread.} =
  {.cast(gcsafe).}:
    var server = newSocket()
    server.setSockOpt(OptReuseAddr, true)
    server.bindAddr(Port(args.port))
    server.listen()
    args.logger.info("wecom: webhook listening on port " & $args.port)
    while true:
      var client: Socket
      try:
        server.accept(client)
        handleWeComConn(client, args.token, args.logger)
      except CatchableError as e:
        args.logger.warn("wecom: accept error: " & e.msg)
        try: client.close() except CatchableError: discard

var gWeComThread: Thread[WeComWebhookArgs]

proc startWebhook*(a: WeComAdapter; port: Port; logger: Logger) =
  ## Starts the webhook listener on a dedicated OS thread.
  gWeComEvents.open()
  {.cast(gcsafe).}:
    let args = WeComWebhookArgs(token: a.callbackToken, port: port.int, logger: logger)
    createThread(gWeComThread, webhookThread, args)

proc tryRecvEvent*(a: var WeComAdapter): (bool, WeComEvent) =
  let (ok, ev) = gWeComEvents.tryRecv()
  (ok, ev)

# ── Constructor ────────────────────────────────────────────────────────────────

proc newWeComAdapter*(corpId, corpSecret, callbackToken: string;
                      agentId: int; identityPath: string): WeComAdapter =
  WeComAdapter(
    corpId:        corpId,
    corpSecret:    corpSecret,
    callbackToken: callbackToken,
    agentId:       agentId,
    resolver:      newIdentityResolver(identityPath),
    http:          newStdHttpAdapter(),
  )
