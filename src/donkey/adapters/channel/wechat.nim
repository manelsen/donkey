## WeChatAdapter — Official Account style channel adapter.
##
## Receiving:
##   startWebhook(port) launches an embedded HTTP server on a dedicated OS
##   thread. It handles WeChat's GET verification challenge and POST message
##   delivery, validates the SHA1 signature, and pushes parsed events into a
##   thread-safe Channel drained by tryRecvEvent().
##
##   For testing or external forwarding, enqueueWebhookXml() accepts raw XML
##   directly without going through the HTTP path.
##
## Sending:
##   Uses WeChat Official Account APIs for customer-service text messages and
##   template messages.

import std/[algorithm, json, nativesockets, net, strutils, tables, uri]
import checksums/sha1
import ../../core/log
import ../../core/pipeops
import ../../domain/message
import ../http/std_http
import ../identity/identity_resolver
import ../../app/metrics

const
  WeChatApiBase* = "https://api.weixin.qq.com"

type
  WeChatScope* = enum
    wsnsapiBase = "snsapi_base"
    wsnsapiUserInfo = "snsapi_userinfo"

  WeChatEvent* = object
    msgType*:  string
    fromUser*: string
    msgId*:    string
    content*:  string

  WeChatProfile* = object
    openId*:    string
    unionId*:   string
    nickname*:  string
    avatarUrl*: string

  WeChatAdapter* = object
    appId*:         string
    appSecret*:     string
    callbackToken*: string
    templateId*:    string
    apiBase*:       string
    resolver*:      IdentityResolver
    http*:          StdHttpAdapter
    events:         seq[WeChatEvent]   ## direct-injection queue (tests / external)

  WeChatWebhookArgs = object
    port:   int
    token:  string
    logger: Logger

var gWeChatEvents: Channel[WeChatEvent]
var gWeChatEventsOpen  = false
var gWeChatWebhookStarted = false
var gWeChatWebhookThread: Thread[WeChatWebhookArgs]

func base(a: WeChatAdapter): string =
  if a.apiBase.len > 0: a.apiBase else: WeChatApiBase

proc newWeChatAdapter*(appId, appSecret, callbackToken, templateId: string;
                       identityPath: string;
                       apiBase = ""): WeChatAdapter =
  WeChatAdapter(
    appId:         appId,
    appSecret:     appSecret,
    callbackToken: callbackToken,
    templateId:    templateId,
    apiBase:       apiBase,
    resolver:      newIdentityResolver(identityPath),
    http:          newStdHttpAdapter(),
    events:        @[],
  )

func parseQueryString*(query: string): Table[string, string] =
  ## Splits a URL query string into a key→value table.
  ## Values are NOT percent-decoded (WeChat params are plain ASCII).
  for pair in query.split('&'):
    if pair.len == 0:
      continue
    let kv = pair.split('=', 1)
    if kv.len == 2:
      result[kv[0]] = kv[1]
    elif kv.len == 1 and kv[0].len > 0:
      result[kv[0]] = ""

proc extractXmlTag*(xml, tag: string): string =
  let openTag = "<" & tag & ">"
  let cdataOpen = openTag & "<![CDATA["
  let cdataClose = "]]></" & tag & ">"
  if cdataOpen in xml and cdataClose in xml:
    let start = xml.find(cdataOpen) + cdataOpen.len
    let stop = xml.find(cdataClose, start)
    if stop >= start:
      return xml[start ..< stop]

  let closeTag = "</" & tag & ">"
  if openTag in xml and closeTag in xml:
    let start = xml.find(openTag) + openTag.len
    let stop = xml.find(closeTag, start)
    if stop >= start:
      return xml[start ..< stop]
  ""

proc parseWebhookXml*(xml: string): Result[WeChatEvent, string] =
  let fromUser = extractXmlTag(xml, "FromUserName").strip()
  if fromUser.len == 0:
    return err("missing FromUserName")
  let msgType = extractXmlTag(xml, "MsgType").strip()
  if msgType.len == 0:
    return err("missing MsgType")
  ok(WeChatEvent(
    msgType:  msgType,
    fromUser: fromUser,
    msgId:    extractXmlTag(xml, "MsgId").strip(),
    content:  extractXmlTag(xml, "Content").strip(),
  ))

proc verifyWebhookSignature*(token, timestamp, nonce, signature: string): bool =
  var parts = @[token, timestamp, nonce]
  parts.sort()
  secureHash(parts.join("")) == parseSecureHash(signature)

proc enqueueWebhookXml*(a: var WeChatAdapter; xml: string): Result[void, string] =
  let event = ? parseWebhookXml(xml)
  if gWeChatEventsOpen:
    gWeChatEvents.send(event)
  else:
    a.events.add(event)
  ok()

proc buildOAuthUrl*(a: WeChatAdapter;
                    redirectUri, state: string;
                    scope = wsnsapiUserInfo): string =
  "https://open.weixin.qq.com/connect/oauth2/authorize?appid=" & a.appId &
  "&redirect_uri=" & encodeUrl(redirectUri) &
  "&response_type=code&scope=" & $scope &
  "&state=" & encodeUrl(state) & "#wechat_redirect"

proc fetchAccessToken*(a: WeChatAdapter): Result[string, string] =
  let url = a.base() & "/cgi-bin/token?grant_type=client_credential" &
            "&appid=" & encodeUrl(a.appId) &
            "&secret=" & encodeUrl(a.appSecret)
  let resp = ? a.http.get(url)
  if resp.status < 200 or resp.status >= 300:
    return err("wechat token error " & $resp.status & ": " & resp.body)
  try:
    let parsed = parseJson(resp.body)
    let token = parsed.getOrDefault("access_token").getStr("")
    if token.len == 0:
      return err("wechat token missing access_token")
    ok(token)
  except CatchableError as e:
    err(e.msg)

proc fetchOAuthOpenId*(a: WeChatAdapter; code: string): Result[string, string] =
  let url = "https://api.weixin.qq.com/sns/oauth2/access_token?appid=" &
            encodeUrl(a.appId) &
            "&secret=" & encodeUrl(a.appSecret) &
            "&code=" & encodeUrl(code) &
            "&grant_type=authorization_code"
  let resp = ? a.http.get(url)
  if resp.status < 200 or resp.status >= 300:
    return err("wechat oauth error " & $resp.status & ": " & resp.body)
  try:
    let parsed = parseJson(resp.body)
    let openId = parsed.getOrDefault("openid").getStr("")
    if openId.len == 0:
      return err("wechat oauth missing openid")
    ok(openId)
  except CatchableError as e:
    err(e.msg)

proc fetchProfile*(a: WeChatAdapter; code: string): Result[WeChatProfile, string] =
  let url = "https://api.weixin.qq.com/sns/oauth2/access_token?appid=" &
            encodeUrl(a.appId) &
            "&secret=" & encodeUrl(a.appSecret) &
            "&code=" & encodeUrl(code) &
            "&grant_type=authorization_code"
  let tokenResp = ? a.http.get(url)
  if tokenResp.status < 200 or tokenResp.status >= 300:
    return err("wechat oauth error " & $tokenResp.status & ": " & tokenResp.body)
  try:
    let tokenJson = parseJson(tokenResp.body)
    let oauthToken = tokenJson.getOrDefault("access_token").getStr("")
    let openId = tokenJson.getOrDefault("openid").getStr("")
    if oauthToken.len == 0 or openId.len == 0:
      return err("wechat oauth missing access_token/openid")
    let profileUrl = "https://api.weixin.qq.com/sns/userinfo?access_token=" &
                     encodeUrl(oauthToken) &
                     "&openid=" & encodeUrl(openId) &
                     "&lang=zh_CN"
    let profileResp = ? a.http.get(profileUrl)
    if profileResp.status < 200 or profileResp.status >= 300:
      return err("wechat userinfo error " & $profileResp.status & ": " & profileResp.body)
    let profileJson = parseJson(profileResp.body)
    ok(WeChatProfile(
      openId:    profileJson.getOrDefault("openid").getStr(""),
      unionId:   profileJson.getOrDefault("unionid").getStr(""),
      nickname:  profileJson.getOrDefault("nickname").getStr(""),
      avatarUrl: profileJson.getOrDefault("headimgurl").getStr(""),
    ))
  except CatchableError as e:
    err(e.msg)

proc sendCustomText*(a: WeChatAdapter; openId, text: string): Result[void, string] =
  let accessToken = ? a.fetchAccessToken()
  let url = a.base() & "/cgi-bin/message/custom/send?access_token=" & accessToken
  let body = %* {
    "touser": openId,
    "msgtype": "text",
    "text": {"content": text},
  }
  let resp = ? a.http.post(url, $body, @[("Content-Type", "application/json")])
  if resp.status < 200 or resp.status >= 300:
    return err("wechat custom send error " & $resp.status & ": " & resp.body)
  ok()

proc sendTemplate*(a: WeChatAdapter;
                   openId, title, bodyText: string;
                   url: string = ""): Result[void, string] =
  if a.templateId.len == 0:
    return err("wechat template id not configured")
  let accessToken = ? a.fetchAccessToken()
  let endpoint = a.base() & "/cgi-bin/message/template/send?access_token=" & accessToken
  var payload = %* {
    "touser": openId,
    "template_id": a.templateId,
    "data": {
      "first": {"value": title},
      "remark": {"value": bodyText},
    },
  }
  if url.len > 0:
    payload["url"] = %url
  let resp = ? a.http.post(endpoint, $payload, @[("Content-Type", "application/json")])
  if resp.status < 200 or resp.status >= 300:
    return err("wechat template send error " & $resp.status & ": " & resp.body)
  ok()

proc wechatWebhookThread(args: WeChatWebhookArgs) {.thread.} =
  ## Minimal HTTP/1.1 server for WeChat Official Account webhook.
  ## GET  /?signature=…&timestamp=…&nonce=…&echostr=…  → echo echostr if valid
  ## POST /?signature=…&timestamp=…&nonce=…            → parse XML, enqueue event

  proc readLine(s: Socket): string =
    var buf = ""
    var c: char
    while true:
      if s.recv(c.addr, 1) != 1:
        return buf
      if c == '\r':
        discard s.recv(c.addr, 1)
        break
      buf.add(c)
    buf

  proc respond(s: Socket; status, body: string) =
    let resp = "HTTP/1.1 " & status & "\r\nContent-Length: " &
               $body.len & "\r\nConnection: close\r\n\r\n" & body
    try: s.send(resp) except CatchableError: discard

  var server = newSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(args.port))
  server.listen()

  while true:
    var client: Socket
    try:
      server.accept(client)
    except CatchableError:
      continue
    try:
      let requestLine = client.readLine()
      let parts = requestLine.split(' ')
      let meth  = if parts.len >= 1: parts[0] else: ""
      let url   = if parts.len >= 2: parts[1] else: "/"
      let qpos  = url.find('?')
      let query = if qpos >= 0: url[qpos + 1 .. ^1] else: ""
      # Read headers
      var contentLength = 0
      while true:
        let h = client.readLine()
        if h.len == 0:
          break
        let lower = h.toLowerAscii()
        if lower.startsWith("content-length:"):
          try: contentLength = parseInt(h[15 .. ^1].strip())
          except ValueError: discard
      # Read body
      var body = ""
      if contentLength > 0:
        body = newString(contentLength)
        var received = 0
        while received < contentLength:
          let n = client.recv(body[received].addr, contentLength - received)
          if n <= 0: break
          received += n

      let params    = parseQueryString(query)
      let signature = params.getOrDefault("signature")
      let timestamp = params.getOrDefault("timestamp")
      let nonce     = params.getOrDefault("nonce")

      if not verifyWebhookSignature(args.token, timestamp, nonce, signature):
        client.respond("403 Forbidden", "forbidden")
      elif meth == "GET":
        client.respond("200 OK", params.getOrDefault("echostr"))
      elif meth == "POST":
        let evRes = parseWebhookXml(body)
        if evRes.isOk:
          gWeChatEvents.send(evRes.value)
        client.respond("200 OK", "success")
      else:
        client.respond("405 Method Not Allowed", "")
    except CatchableError:
      let errMsg = getCurrentExceptionMsg()
      args.logger.warn("wechat webhook: connection handler error: " & errMsg)
      recordWebhookFailure("wechat", errMsg)
    try: client.close() except CatchableError: discard

proc startWebhook*(a: WeChatAdapter; port: Port; logger: Logger) {.gcsafe.} =
  ## Starts the embedded WeChat webhook HTTP server on the given port.
  ## Safe to call multiple times — only the first call has effect.
  {.cast(gcsafe).}:
    if gWeChatWebhookStarted:
      return
    gWeChatEvents.open()
    gWeChatEventsOpen    = true
    gWeChatWebhookStarted = true
    createThread(gWeChatWebhookThread, wechatWebhookThread,
                 WeChatWebhookArgs(port: port.int, token: a.callbackToken, logger: logger))

proc tryRecvEvent*(a: var WeChatAdapter): (bool, WeChatEvent) =
  if gWeChatEventsOpen:
    let (ok, ev) = gWeChatEvents.tryRecv()
    if ok:
      return (true, ev)
  if a.events.len == 0:
    return (false, WeChatEvent())
  let event = a.events[0]
  a.events.delete(0)
  (true, event)

proc send*(a: var WeChatAdapter; msg: OutboundMessage): Result[void, string] =
  let rawId = a.resolver.reverseChannel(msg.userId, ckWeChat)
  if rawId.len == 0:
    return err("WeChatAdapter.send: no WeChat openid for user " & $msg.userId)
  a.sendCustomText(rawId, msg.text)
