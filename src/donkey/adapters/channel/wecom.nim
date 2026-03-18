## WeComAdapter — ChannelPort for WeCom (企业微信 / WeCom Enterprise).
##
## Receiving: WeCom pushes HTTP POST callbacks to a configurable endpoint.
##   A background OS thread runs a minimal HTTP server on the callback port.
##   The thread pushes WeComRawEvent values to a module-level Channel.
##   The daemon calls tryRecvEvent() (non-blocking) in its main loop.
##
## Sending: REST API — POST /cgi-bin/message/send with an access token.
##   Access tokens expire every 2 hours; getAccessToken() caches and refreshes.
##
## Signature (all callbacks):
##   sort([token, timestamp, nonce]).join("") → SHA-1 hex lowercase
##   WeCom calls this the "message signature" (消息签名).
##
## GET verification: WeCom sends GET with signature + echostr; reply = echostr.
## POST message:     WeCom sends POST with signature + XML body.

import std/[algorithm, json, net, options, strutils, times]
import nimcrypto/sha
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../http/std_http
import ../identity/identity_resolver

const
  WeComApiBase* = "https://qyapi.weixin.qq.com/cgi-bin"
  WeComTokenUrl = WeComApiBase & "/gettoken"

# ── Public event type (thread → main) ─────────────────────────────────────────

type
  WeComRawEvent* = object
    toUser*:   string   ## CorpID (the recipient corp)
    fromUser*: string   ## WeChat OpenID of the sender
    msgType*:  string   ## "text", "event", "image", …
    content*:  string   ## text body (empty for non-text)
    msgId*:    string   ## unique message ID (dedup)

## Module-level channel — opened once, valid for daemon lifetime.
var gWeComEvents* {.global.}: Channel[WeComRawEvent]

# ── Pure functions ─────────────────────────────────────────────────────────────

func wecomSignature*(token, timestamp, nonce: string): string =
  ## Computes the WeCom message signature.
  ## sort([token, timestamp, nonce]).join("") → lowercase SHA-1 hex.
  var parts = @[token, timestamp, nonce]
  parts.sort()
  let plain = parts.join("")
  toLowerAscii($sha1.digest(plain))

func verifyWeComSig*(token, timestamp, nonce, sig: string): bool =
  ## Returns true when sig matches the expected WeCom signature.
  wecomSignature(token, timestamp, nonce) == sig

func extractCdata(xml, tag: string): string =
  ## Extracts the first CDATA value for a given XML tag.
  ## Handles both <tag><![CDATA[value]]></tag> and <tag>value</tag>.
  let open  = "<" & tag & ">"
  let close = "</" & tag & ">"
  let si = xml.find(open)
  if si < 0: return ""
  let contentStart = si + open.len
  let ei = xml.find(close, contentStart)
  if ei < 0: return ""
  var content = xml[contentStart ..< ei].strip()
  if content.startsWith("<![CDATA[") and content.endsWith("]]>"):
    content = content[9 ..< content.len - 3]
  content

func parseWeComMessage*(xml: string): Option[WeComRawEvent] =
  ## Parses a WeCom XML callback body into a WeComRawEvent.
  ## Returns none if the XML is clearly malformed (no ToUserName).
  let toUser = extractCdata(xml, "ToUserName")
  if toUser.len == 0:
    return none(WeComRawEvent)
  some(WeComRawEvent(
    toUser:   toUser,
    fromUser: extractCdata(xml, "FromUserName"),
    msgType:  extractCdata(xml, "MsgType"),
    content:  extractCdata(xml, "Content"),
    msgId:    extractCdata(xml, "MsgId"),
  ))

func buildSendBody*(agentId: int; toUser, text: string): JsonNode =
  ## Constructs the JSON body for POST /cgi-bin/message/send.
  %* {
    "touser":  toUser,
    "msgtype": "text",
    "agentid": agentId,
    "text":    {"content": text},
  }

# ── WeComAdapter ───────────────────────────────────────────────────────────────

type
  WeComAdapter* = object
    corpId*:      string
    corpSecret*:  string
    agentId*:     int
    token*:       string  ## verification token (signature check)
    apiBase*:     string  ## override for testing
    resolver*:    IdentityResolver
    http*:        StdHttpAdapter
    ## Cached access token.
    cachedToken:  string
    tokenExpiry:  int64   ## unix seconds

func base(a: WeComAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: WeComApiBase

# ── Access token ───────────────────────────────────────────────────────────────

proc getAccessToken*(a: var WeComAdapter): Result[string, string] =
  ## Returns a valid access token, refreshing if expired or absent.
  ## Tokens are valid ~7200 s; we refresh 60 s early to avoid races.
  let now = getTime().toUnix()
  if a.cachedToken.len > 0 and now < a.tokenExpiry - 60:
    return ok(a.cachedToken)
  let url = WeComTokenUrl & "?corpid=" & a.corpId & "&corpsecret=" & a.corpSecret
  let resp = ? a.http.get(url, @[])
  if resp.status < 200 or resp.status >= 300:
    return err("WeCom token error " & $resp.status & ": " & resp.body)
  try:
    let j = parseJson(resp.body)
    if j.getOrDefault("errcode").getInt(0) != 0:
      return err("WeCom token API error: " & j.getOrDefault("errmsg").getStr(""))
    a.cachedToken = j["access_token"].getStr()
    a.tokenExpiry  = now + j["expires_in"].getInt(7200)
    ok(a.cachedToken)
  except CatchableError as e:
    err(e.msg)

# ── Sending ────────────────────────────────────────────────────────────────────

proc send*(a: var WeComAdapter; msg: OutboundMessage): Result[void, string] =
  ## Sends a text message to a WeCom user via the Send Message API.
  let wecomId = a.resolver.reverseChannel(msg.userId, ckWeCom)
  if wecomId.len == 0:
    return err("WeComAdapter.send: no WeCom ID for user " & $msg.userId)
  let tok = ? a.getAccessToken()
  let url  = a.base() & "/message/send?access_token=" & tok
  let body = buildSendBody(a.agentId, wecomId, msg.text)
  let resp = ? a.http.post(url, $body, @[("Content-Type", "application/json")])
  if resp.status < 200 or resp.status >= 300:
    return err("WeCom send error " & $resp.status & ": " & resp.body)
  try:
    let j = parseJson(resp.body)
    if j.getOrDefault("errcode").getInt(0) != 0:
      return err("WeCom send API error: " & j.getOrDefault("errmsg").getStr(""))
    ok()
  except CatchableError as e:
    err(e.msg)

# ── Webhook HTTP server (background thread) ────────────────────────────────────
##
## WeCom sends GET for ownership verification and POST for messages.
## Both carry ?msg_signature=&timestamp=&nonce= query params.
## This is a minimal line-by-line HTTP parser — no full HTTP library needed
## because the requests are simple and size-bounded by WeCom's platform.

type WebhookArgs = object
  token:    string
  port:     Port

proc parseQueryParam(query, key: string): string =
  ## Extracts a single value from a URL query string.
  let prefix = key & "="
  let si = query.find(prefix)
  if si < 0: return ""
  let vi = si + prefix.len
  let ei = query.find('&', vi)
  if ei < 0: query[vi .. ^1] else: query[vi ..< ei]

proc recvHttpRequest(client: Socket): tuple[
    meth, path, query, body: string] =
  ## Reads a single HTTP/1.x request from the socket.
  var firstLine = true
  var contentLength = 0
  while true:
    let line = client.recvLine(timeout = 5000)
    if line.len == 0: break
    if firstLine:
      firstLine = false
      let parts = line.split(' ')
      if parts.len >= 2:
        result.meth = parts[0]
        let pathFull = parts[1]
        let qi = pathFull.find('?')
        if qi >= 0:
          result.path  = pathFull[0 ..< qi]
          result.query = pathFull[qi + 1 .. ^1]
        else:
          result.path = pathFull
    else:
      let lup = line.toLowerAscii()
      if lup.startsWith("content-length:"):
        contentLength = parseInt(lup[15..^1].strip())
  if contentLength > 0:
    result.body = client.recv(contentLength, timeout = 5000)

proc wecomWebhookThread(arg: WebhookArgs) {.thread.} =
  ## Minimal HTTP server for WeCom callbacks.
  var server = newSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(arg.port)
  server.listen()
  while true:
    var client: Socket
    try:
      server.accept(client)
      let req = recvHttpRequest(client)
      let sig  = parseQueryParam(req.query, "msg_signature")
      let ts   = parseQueryParam(req.query, "timestamp")
      let nc   = parseQueryParam(req.query, "nonce")
      if not verifyWeComSig(arg.token, ts, nc, sig):
        client.send("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
        client.close()
        continue
      case req.meth
      of "GET":
        ## Ownership verification — echo back echostr.
        let echo = parseQueryParam(req.query, "echostr")
        client.send(
          "HTTP/1.1 200 OK\r\nContent-Length: " & $echo.len &
          "\r\nContent-Type: text/plain\r\n\r\n" & echo)
      of "POST":
        let evtOpt = parseWeComMessage(req.body)
        if evtOpt.isSome:
          gWeComEvents.send(evtOpt.get)
        client.send("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
      else:
        client.send("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n")
      client.close()
    except Exception as e:
      echo "[wecom] webhook error: " & e.msg
      try: client.close() except: discard

var gWebhookThread {.global.}: Thread[WebhookArgs]

# ── Lifecycle ──────────────────────────────────────────────────────────────────

proc startWebhook*(a: WeComAdapter; port: Port) {.gcsafe.} =
  ## Starts the WeCom webhook listener thread. Call once at daemon startup.
  {.cast(gcsafe).}:
    gWeComEvents.open()
    createThread(gWebhookThread, wecomWebhookThread,
                 WebhookArgs(token: a.token, port: port))

proc tryRecvEvent*(a: WeComAdapter): (bool, WeComRawEvent) =
  ## Non-blocking poll for webhook events. Returns (false, default) when empty.
  gWeComEvents.tryRecv()

# ── Constructor ────────────────────────────────────────────────────────────────

proc newWeComAdapter*(corpId, corpSecret, token: string;
                      agentId:      int;
                      identityPath: string;
                      apiBase       = ""): WeComAdapter =
  WeComAdapter(
    corpId:      corpId,
    corpSecret:  corpSecret,
    token:       token,
    agentId:     agentId,
    apiBase:     apiBase,
    resolver:    newIdentityResolver(identityPath),
    http:        newStdHttpAdapter(),
  )
