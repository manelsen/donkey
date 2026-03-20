## WeChatAdapter — Official Account style channel adapter.
##
## Receiving:
##   Webhook delivery is expected to be terminated elsewhere and forwarded here
##   via enqueueWebhookXml(). The adapter validates/parses the XML payload and
##   exposes tryRecvEvent() for the daemon loop.
##
## Sending:
##   Uses WeChat Official Account APIs for customer-service text messages and
##   template messages.

import std/[algorithm, json, nativesockets, strutils, uri]
import std/sha1
import ../../core/pipeops
import ../../domain/message
import ../http/std_http
import ../identity/identity_resolver

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
    events:         seq[WeChatEvent]

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

proc startWebhook*(a: var WeChatAdapter; port: Port) =
  discard

proc tryRecvEvent*(a: var WeChatAdapter): (bool, WeChatEvent) =
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
