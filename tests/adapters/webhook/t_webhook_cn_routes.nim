## WeCom, WeChat and QQ OneBot on the shared webhook receiver: the same
## signature rules their private servers enforced, now as routes. No sockets:
## the request→response handler is exercised directly and events are observed
## through each adapter's queue.

import std/[algorithm, os, strutils, tables, unittest]
import checksums/sha1
import donkey/app/metrics
import donkey/core/security/webhook_auth
import donkey/adapters/channel/qq
import donkey/adapters/channel/wechat
import donkey/adapters/channel/wecom
import donkey/adapters/webhook/webhook_receiver

proc mkReq(httpMethod, path: string; body = "";
           headers: openArray[(string, string)] = [];
           query: openArray[(string, string)] = []): WebhookRequest =
  var h = initTable[string, string]()
  for (k, v) in headers:
    h[k.toLowerAscii()] = v
  var q = initTable[string, string]()
  for (k, v) in query:
    q[k] = v
  WebhookRequest(httpMethod: httpMethod, path: path, query: q, headers: h, body: body)

proc wechatSig(token, ts, nonce: string): string =
  var parts = @[token, ts, nonce]
  parts.sort()
  $secureHash(parts.join(""))

func wecomXml(msgId, text: string): string =
  "<xml><ToUserName>corp</ToUserName><FromUserName>zhang</FromUserName>" &
  "<MsgType>text</MsgType><Content>" & text & "</Content><MsgId>" & msgId &
  "</MsgId></xml>"

const wechatXml = "<xml><ToUserName>gh</ToUserName><FromUserName>openid-1</FromUserName>" &
                  "<CreateTime>1</CreateTime><MsgType>text</MsgType>" &
                  "<Content>oi</Content><MsgId>7</MsgId></xml>"

const oneBotEvent = """{"post_type":"message","message_type":"private",""" &
                    """"user_id":42,"message_id":1,"raw_message":"hi"}"""

proc drainWeCom(): seq[WeComEvent] =
  var a = newWeComAdapter("c", "s", "tok", 1, getTempDir() / "donkey_cn_routes_wecom.tsv")
  while true:
    let (ok, ev) = a.tryRecvEvent()
    if not ok: break
    result.add ev

proc drainWeChat(): seq[WeChatEvent] =
  var a = newWeChatAdapter("app", "secret", "tok", "", getTempDir() / "donkey_cn_routes_wechat.tsv")
  while true:
    let (ok, ev) = a.tryRecvEvent()
    if not ok: break
    result.add ev

proc drainQQ(): seq[QQEvent] =
  var a = newQQAdapter("", "", getTempDir() / "donkey_cn_routes_qq.tsv")
  while true:
    let (ok, ev) = a.tryRecvEvent()
    if not ok: break
    result.add ev

proc runTests*() =
  suite "WeCom on the shared receiver":
    let cfg = WebhookConfig(wecomToken: "tok")

    test "the route is mounted only with a callback token":
      check anyRouteConfigured(cfg)
      check handleWebhookRequest(WebhookConfig(), mkReq("GET", WeComPath)).status == 404

    test "a request without msg_signature is refused (no forged messages)":
      discard drainWeCom()
      let r = handleWebhookRequest(cfg, mkReq("POST", WeComPath, wecomXml("1", "hi"),
                                              query = {"timestamp": "1", "nonce": "2"}))
      check r.status == 403
      check drainWeCom().len == 0
      check handleWebhookRequest(cfg, mkReq("GET", WeComPath,
        query = {"timestamp": "1", "nonce": "2", "echostr": "e"})).status == 403

    test "URL verification echoes echostr when signed":
      let r = handleWebhookRequest(cfg, mkReq("GET", WeComPath, query = {
        "msg_signature": wecomSignature("tok", "1", "2"),
        "timestamp": "1", "nonce": "2", "echostr": "hello"}))
      check r.status == 200
      check r.body == "hello"

    test "a signed message is queued once, even when WeCom retries it":
      discard drainWeCom()
      let q = {"msg_signature": wecomSignature("tok", "1", "2"),
               "timestamp": "1", "nonce": "2"}
      for _ in 0 ..< 2:
        check handleWebhookRequest(cfg, mkReq("POST", WeComPath,
          wecomXml("9001", "olá"), query = q)).status == 200
      let events = drainWeCom()
      check events.len == 1
      check events[0].fromUser == "zhang"
      check events[0].content == "olá"

  suite "WeChat on the shared receiver":
    let cfg = WebhookConfig(wechatToken: "tok")
    let signed = {"signature": wechatSig("tok", "1", "2"), "timestamp": "1", "nonce": "2"}

    test "the route is mounted only with a callback token":
      check anyRouteConfigured(cfg)
      check handleWebhookRequest(WebhookConfig(), mkReq("POST", WeChatPath)).status == 404

    test "a bad signature is refused":
      check handleWebhookRequest(cfg, mkReq("POST", WeChatPath, wechatXml, query = {
        "signature": "0".repeat(40), "timestamp": "1", "nonce": "2"})).status == 403

    test "URL verification echoes echostr when signed":
      var q = @signed
      q.add ("echostr", "hello")
      let r = handleWebhookRequest(cfg, mkReq("GET", WeChatPath, query = q))
      check r.status == 200
      check r.body == "hello"

    test "a signed message is queued and answered with success":
      discard drainWeChat()
      let r = handleWebhookRequest(cfg, mkReq("POST", WeChatPath, wechatXml, query = signed))
      check r.status == 200
      check r.body == "success"
      check drainWeChat().len == 1

    test "an unparseable body is still 200 (WeChat retries) but counted":
      initMetrics()
      let before = webhookFailureCount("wechat")
      let r = handleWebhookRequest(cfg, mkReq("POST", WeChatPath, "not xml", query = signed))
      check r.status == 200
      check webhookFailureCount("wechat") == before + 1

  suite "QQ OneBot on the shared receiver":
    let signedCfg = WebhookConfig(qqOneBotEnabled: true, qqOneBotSecret: "onebot-secret")

    test "the route is mounted only when OneBot is enabled":
      check anyRouteConfigured(WebhookConfig(qqOneBotEnabled: true))
      check handleWebhookRequest(WebhookConfig(), mkReq("POST", QQOneBotPath,
                                                        oneBotEvent)).status == 404

    test "with a secret, an unsigned or forged event is refused":
      discard drainQQ()
      check handleWebhookRequest(signedCfg, mkReq("POST", QQOneBotPath,
                                                  oneBotEvent)).status == 403
      check handleWebhookRequest(signedCfg, mkReq("POST", QQOneBotPath, oneBotEvent,
        headers = {"X-Signature": "sha1=" & '0'.repeat(40)})).status == 403
      check drainQQ().len == 0

    test "a correctly signed event is queued":
      discard drainQQ()
      let r = handleWebhookRequest(signedCfg, mkReq("POST", QQOneBotPath, oneBotEvent,
        headers = {"X-Signature": "sha1=" & hmacSha1Hex("onebot-secret", oneBotEvent)}))
      check r.status == 200
      let events = drainQQ()
      check events.len == 1
      check events[0].content == "hi"

    test "only POST is served":
      check handleWebhookRequest(signedCfg, mkReq("GET", QQOneBotPath)).status == 405

when isMainModule:
  runTests()
