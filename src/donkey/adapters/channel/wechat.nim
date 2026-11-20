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
import ../../core/media_download
import ../../domain/message
import ../../ports/channel
import ../http/std_http
import ../identity/identity_resolver
import ../webhook/http_request_reader
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
    mediaId*:  string

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
    mediaId:  extractXmlTag(xml, "MediaId").strip(),
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

proc respond(s: Socket; status, body: string) =
  let resp = "HTTP/1.1 " & status & "\r\nContent-Length: " &
             $body.len & "\r\nConnection: close\r\n\r\n" & body
  try: s.send(resp) except CatchableError: discard

proc handleWeChatConn*(client: Socket; token: string; logger: Logger;
                       timeoutSec = WebhookClientTimeoutSec) =
  ## Serves one WeChat Official Account webhook request and closes the socket.
  ## GET  /?signature=…&timestamp=…&nonce=…&echostr=…  → echo echostr if valid
  ## POST /?signature=…&timestamp=…&nonce=…            → parse XML, enqueue event
  ## Reading goes through http_request_reader (bounded, timed out).
  defer: closeWebhookClient(client)
  discard applyWebhookClientTimeouts(client, timeoutSec)
  let req = readWebhookRequest(client).valueOr:
    logger.warn("wechat webhook: rejected request: " & error)
    recordWebhookFailure("wechat", error)
    client.respond(statusLine(readErrorStatus(error)), "")
    return
  let signature = req.query.getOrDefault("signature")
  let timestamp = req.query.getOrDefault("timestamp")
  let nonce     = req.query.getOrDefault("nonce")

  if not verifyWebhookSignature(token, timestamp, nonce, signature):
    client.respond("403 Forbidden", "forbidden")
  elif req.httpMethod == "GET":
    client.respond("200 OK", req.query.getOrDefault("echostr"))
  elif req.httpMethod == "POST":
    let evRes = parseWebhookXml(req.body)
    if evRes.isOk and gWeChatEventsOpen:
      gWeChatEvents.send(evRes.value)
    client.respond("200 OK", "success")
  else:
    client.respond("405 Method Not Allowed", "")

proc wechatWebhookThread(args: WeChatWebhookArgs) {.thread.} =
  ## Minimal HTTP/1.1 server for WeChat Official Account webhook.
  var server = newSocket(buffered = false)  ## see http_request_reader
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
      handleWeChatConn(client, args.token, args.logger)
    except CatchableError:
      let errMsg = getCurrentExceptionMsg()
      args.logger.warn("wechat webhook: connection handler error: " & errMsg)
      recordWebhookFailure("wechat", errMsg)

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

proc downloadFile*(a: var WeChatAdapter; mediaId: string): Result[FileDownload, string] =
  ## Downloads a WeChat media file by its media_id.
  ## Requires access_token which is fetched via WeChat OA API.
  if mediaId.len == 0:
    return err("WeChat downloadFile: empty mediaId")
  
  try:
    # Fetch access_token
    let tokenUrl = "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=" & a.appId & "&secret=" & a.appSecret
    let headers: seq[(string, string)] = @[]
    let tokenResp = ? a.http.get(tokenUrl, headers)
    let tokenJson = parseJson(tokenResp.body)
    let accessToken = tokenJson.getOrDefault("access_token").getStr("")
    if accessToken.len == 0:
      return err("WeChat downloadFile: no access_token in response")
    
    # Download media
    let mediaUrl = "https://api.weixin.qq.com/cgi-bin/media/get?access_token=" & accessToken & "&media_id=" & mediaId
    let mediaResp = ? a.http.get(mediaUrl, headers)
    
    var data = newSeq[byte](mediaResp.body.len)
    for i in 0 ..< mediaResp.body.len:
      data[i] = cast[byte](mediaResp.body[i])
    
    ok(FileDownload(
      fileName: "wechat_" & mediaId,
      fileSize: data.len.int64,
      mimeType: "application/octet-stream",
      localPath: "",
      data: data,
    ))
  except CatchableError as e:
    err("WeChat downloadFile: " & e.msg)

proc send*(a: var WeChatAdapter; msg: OutboundMessage): Result[void, string] =
  let rawId = a.resolver.reverseChannel(msg.userId, ckWeChat)
  if rawId.len == 0:
    return err("WeChatAdapter.send: no WeChat openid for user " & $msg.userId)
  a.sendCustomText(rawId, msg.text)
