## webhook_receiver tests — challenge/verification and payload dispatch.
##
## No sockets are opened: the pure request→response handler is exercised
## directly, and dispatched payloads are observed through each adapter queue.

import std/[base64, json, net, os, strutils, tables, times, unittest, uri]
import nimcrypto/[bcmode, rijndael, sha2]
import donkey/core/log
import donkey/core/pipeops
import donkey/adapters/channel/slack
import donkey/adapters/channel/feishu
import donkey/adapters/channel/dingtalk
import donkey/adapters/channel/matrix
import donkey/adapters/channel/whatsapp
import donkey/adapters/webhook/webhook_receiver

const HookTmp = "/tmp/donkey_webhook_tests"
let hookLog = newLogger("test.webhook", lvlError)

proc mkReq(httpMethod, path: string;
           body = "";
           headers: openArray[(string, string)] = [];
           query: openArray[(string, string)] = []): WebhookRequest =
  var h = initTable[string, string]()
  for (k, v) in headers:
    h[k.toLowerAscii()] = v
  var q = initTable[string, string]()
  for (k, v) in query:
    q[k] = v
  WebhookRequest(httpMethod: httpMethod, path: path, query: q, headers: h, body: body)

func slackSig(secret, timestamp, body: string): string =
  "v0=" & hmacSha256Hex(secret, "v0:" & timestamp & ":" & body)

proc feishuEncrypt(encryptKey, plaintext: string): string =
  ## Test-side implementation of Feishu's Encrypt Key envelope:
  ## base64(iv[16] || AES-256-CBC(PKCS7(plaintext))), key = SHA256(encryptKey).
  var sha: sha256
  sha.init()
  sha.update(encryptKey)
  let digest = sha.finish()
  var key: array[32, byte]
  for i in 0 ..< key.len:
    key[i] = digest.data[i]

  var data = plaintext
  let pad = 16 - (data.len mod 16)
  for _ in 0 ..< pad:
    data.add(char(pad))

  var iv: array[16, byte]
  var ivStr = ""
  for i in 0 ..< iv.len:
    iv[i] = byte(i + 1)
    ivStr.add(char(iv[i]))

  var ctx: CBC[aes256]
  ctx.init(key, iv)
  var cipher = newString(data.len)
  ctx.encrypt(data, cipher)
  ctx.clear()
  base64.encode(ivStr & cipher)

proc clearQueues() =
  ## Drains module-level queues so tests are independent.
  var sl = newSlackAdapter("tok", HookTmp / "slack.tsv")
  while sl.tryRecvEvent()[0]: discard
  var fs = newFeishuAdapter("app", "secret", HookTmp / "feishu.tsv")
  while fs.tryRecvEvent()[0]: discard
  var dt = newDingTalkAdapter("key", "secret", "robot", HookTmp / "dt.tsv")
  while dt.tryRecvEvent()[0]: discard
  var mx = newMatrixAdapter("https://mx", "@bot:mx", "tok", HookTmp / "mx.tsv")
  while mx.tryRecvEvent()[0]: discard
  var wa = newWhatsAppAdapter("tok", "PN1", HookTmp / "wa.tsv")
  while wa.tryRecvEvent()[0]: discard

suite "webhook receiver — crypto helpers":

  test "hmacSha256Hex matches the RFC 4231 test vector":
    check hmacSha256Hex("key", "The quick brown fox jumps over the lazy dog") ==
      "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"

suite "webhook receiver — Slack":

  test "url_verification challenge is echoed when the signature is valid":
    let secret = "slack-signing"
    let body = """{"type":"url_verification","challenge":"ch-1"}"""
    let ts = $epochTime().int64
    let cfg = WebhookConfig(slackSigningSecret: secret)

    let resp = handleWebhookRequest(cfg, mkReq("POST", SlackPath, body,
      headers = [("X-Slack-Request-Timestamp", ts),
                 ("X-Slack-Signature", slackSig(secret, ts, body))]))

    check resp.status == 200
    check resp.body == "ch-1"

  test "invalid signature is rejected":
    let cfg = WebhookConfig(slackSigningSecret: "slack-signing")
    let ts = $epochTime().int64
    let resp = handleWebhookRequest(cfg, mkReq("POST", SlackPath,
      """{"type":"url_verification","challenge":"ch-1"}""",
      headers = [("X-Slack-Request-Timestamp", ts),
                 ("X-Slack-Signature", "v0=deadbeef")]))
    check resp.status == 403

  test "stale timestamp is rejected (replay window)":
    let secret = "slack-signing"
    let body = """{"type":"url_verification","challenge":"ch-1"}"""
    let ts = $(epochTime().int64 - 3600)
    let cfg = WebhookConfig(slackSigningSecret: secret)
    let resp = handleWebhookRequest(cfg, mkReq("POST", SlackPath, body,
      headers = [("X-Slack-Request-Timestamp", ts),
                 ("X-Slack-Signature", slackSig(secret, ts, body))]))
    check resp.status == 403

  test "extreme negative timestamp is rejected without overflowing":
    let secret = "slack-signing"
    let body = """{"type":"url_verification","challenge":"ch-1"}"""
    let ts = "-9223372036854775000"
    let cfg = WebhookConfig(slackSigningSecret: secret)
    let resp = handleWebhookRequest(cfg, mkReq("POST", SlackPath, body,
      headers = [("X-Slack-Request-Timestamp", ts),
                 ("X-Slack-Signature", slackSig(secret, ts, body))]))
    check resp.status == 403

  test "extreme positive timestamp is rejected":
    let secret = "slack-signing"
    let body = """{"type":"url_verification","challenge":"ch-1"}"""
    let ts = "9223372036854775807"
    let cfg = WebhookConfig(slackSigningSecret: secret)
    let resp = handleWebhookRequest(cfg, mkReq("POST", SlackPath, body,
      headers = [("X-Slack-Request-Timestamp", ts),
                 ("X-Slack-Signature", slackSig(secret, ts, body))]))
    check resp.status == 403

  test "message payload is dispatched to the Slack queue":
    clearQueues()
    var sl = newSlackAdapter("tok", HookTmp / "slack.tsv")
    sl.openQueue()
    let secret = "slack-signing"
    let body = """{"type":"event_callback","team_id":"T1",
      "event":{"type":"message","user":"U1","text":"hi there",
               "channel":"C1","ts":"1.1"}}"""
    let ts = $epochTime().int64
    let cfg = WebhookConfig(slackSigningSecret: secret)

    let resp = handleWebhookRequest(cfg, mkReq("POST", SlackPath, body,
      headers = [("X-Slack-Request-Timestamp", ts),
                 ("X-Slack-Signature", slackSig(secret, ts, body))]))

    check resp.status == 200
    let (hasEvent, event) = sl.tryRecvEvent()
    check hasEvent
    check event.slackUserId == "U1"
    check event.text == "hi there"

  test "form-encoded slash command is normalized and dispatched":
    clearQueues()
    var sl = newSlackAdapter("tok", HookTmp / "slack.tsv")
    sl.openQueue()
    let secret = "slack-signing"
    let body = "user_id=U9&command=%2Fhelp&text=now&channel_id=C9" &
               "&team_id=T9&trigger_id=tr9"
    let ts = $epochTime().int64
    let cfg = WebhookConfig(slackSigningSecret: secret)

    let resp = handleWebhookRequest(cfg, mkReq("POST", SlackPath, body,
      headers = [("X-Slack-Request-Timestamp", ts),
                 ("X-Slack-Signature", slackSig(secret, ts, body)),
                 ("Content-Type", "application/x-www-form-urlencoded")]))

    check resp.status == 200
    let (hasEvent, event) = sl.tryRecvEvent()
    check hasEvent
    check event.kind == srSlashCommand
    check event.slackUserId == "U9"
    check event.text == "/help now"

  test "form-encoded block action payload is decoded and dispatched":
    clearQueues()
    var sl = newSlackAdapter("tok", HookTmp / "slack.tsv")
    sl.openQueue()
    let secret = "slack-signing"
    let interactive = %* {
      "type": "block_actions",
      "user": {"id": "U7"},
      "actions": [{"action_id": "models", "value": "models"}],
      "channel": {"id": "C7"},
      "team_id": "T7",
      "trigger_id": "tr7",
    }
    let body = "payload=" & encodeUrl($interactive, usePlus = false)
    let ts = $epochTime().int64
    let cfg = WebhookConfig(slackSigningSecret: secret)

    let resp = handleWebhookRequest(cfg, mkReq("POST", SlackPath, body,
      headers = [("X-Slack-Request-Timestamp", ts),
                 ("X-Slack-Signature", slackSig(secret, ts, body)),
                 ("Content-Type", "application/x-www-form-urlencoded")]))

    check resp.status == 200
    let (hasEvent, event) = sl.tryRecvEvent()
    check hasEvent
    check event.kind == srBlockAction
    check event.slackUserId == "U7"
    check event.text == "models"
    check event.triggerId == "tr7"

suite "webhook receiver — Feishu":

  test "url_verification is echoed as JSON with a matching token":
    let cfg = WebhookConfig(feishuVerificationToken: "fs-token")
    let body = """{"type":"url_verification","challenge":"fs-ch","token":"fs-token"}"""
    let resp = handleWebhookRequest(cfg, mkReq("POST", FeishuPath, body))
    check resp.status == 200
    check parseJson(resp.body)["challenge"].getStr() == "fs-ch"

  test "wrong verification token is rejected":
    let cfg = WebhookConfig(feishuVerificationToken: "fs-token")
    let body = """{"type":"url_verification","challenge":"fs-ch","token":"nope"}"""
    check handleWebhookRequest(cfg, mkReq("POST", FeishuPath, body)).status == 403

  test "encrypted payload is decrypted and the challenge is echoed":
    let cfg = WebhookConfig(feishuVerificationToken: "fs-token",
                            feishuEncryptKey: "enc-key")
    let inner = %* {
      "type": "url_verification",
      "challenge": "enc-ch",
      "token": "fs-token",
    }
    let body = $(%* {"encrypt": feishuEncrypt("enc-key", $inner)})
    let resp = handleWebhookRequest(cfg, mkReq("POST", FeishuPath, body))
    check resp.status == 200
    check parseJson(resp.body)["challenge"].getStr() == "enc-ch"

  test "encrypted payload with the wrong key is rejected":
    let cfg = WebhookConfig(feishuVerificationToken: "fs-token",
                            feishuEncryptKey: "other-key")
    let inner = %* {
      "type": "url_verification",
      "challenge": "enc-ch",
      "token": "fs-token",
    }
    let body = $(%* {"encrypt": feishuEncrypt("enc-key", $inner)})
    check handleWebhookRequest(cfg, mkReq("POST", FeishuPath, body)).status == 400

  test "plaintext is rejected when an encrypt key is configured":
    let cfg = WebhookConfig(feishuVerificationToken: "fs-token",
                            feishuEncryptKey: "enc-key")
    let body = """{"type":"url_verification","challenge":"fs-ch","token":"fs-token"}"""
    check handleWebhookRequest(cfg, mkReq("POST", FeishuPath, body)).status == 400

  test "encrypt key alone configures the Feishu route":
    let cfg = WebhookConfig(feishuEncryptKey: "enc-key")
    check anyRouteConfigured(cfg)
    let inner = %* {"type": "url_verification", "challenge": "enc-only"}
    let body = $(%* {"encrypt": feishuEncrypt("enc-key", $inner)})
    let resp = handleWebhookRequest(cfg, mkReq("POST", FeishuPath, body))
    check resp.status == 200
    check parseJson(resp.body)["challenge"].getStr() == "enc-only"

  test "message payload is dispatched to the Feishu queue":
    clearQueues()
    var fs = newFeishuAdapter("cli", "secret", HookTmp / "feishu.tsv")
    fs.openQueue()
    let cfg = WebhookConfig(feishuVerificationToken: "fs-token")
    let body = """{"schema":"2.0",
      "header":{"event_type":"im.message.receive_v1","token":"fs-token"},
      "event":{"message":{"message_type":"text","message_id":"om_1",
                          "chat_id":"oc_1","chat_type":"p2p",
                          "content":"{\"text\":\"oi\"}"},
               "sender":{"sender_id":{"open_id":"ou_1"}}}}"""

    let resp = handleWebhookRequest(cfg, mkReq("POST", FeishuPath, body))
    check resp.status == 200
    let (hasEvent, event) = fs.tryRecvEvent()
    check hasEvent
    check event.openId == "ou_1"
    check event.content == "oi"

suite "webhook receiver — DingTalk":

  test "valid signature dispatches the payload":
    clearQueues()
    var dt = newDingTalkAdapter("key", "dt-secret", "robot", HookTmp / "dt.tsv")
    dt.openQueue()
    let cfg = WebhookConfig(dingtalkAppSecret: "dt-secret")
    let ts = $((epochTime() * 1000).int64)
    let body = """{"msgtype":"text","senderId":"u1","msgId":"m1",
                   "text":{"content":"hi dt"}}"""
    let sign = hmacSha256Base64("dt-secret", ts & "\n" & "dt-secret")

    let resp = handleWebhookRequest(cfg, mkReq("POST", DingTalkPath, body,
      headers = [("timestamp", ts), ("sign", sign)]))

    check resp.status == 200
    let (hasEvent, event) = dt.tryRecvEvent()
    check hasEvent
    check event.rawId == "u1"
    check event.content == "hi dt"

  test "invalid signature is rejected and not dispatched":
    clearQueues()
    let cfg = WebhookConfig(dingtalkAppSecret: "dt-secret")
    let body = """{"msgtype":"text","senderId":"u1","msgId":"m1",
                   "text":{"content":"nope"}}"""
    let ts = $((epochTime() * 1000).int64)
    let resp = handleWebhookRequest(cfg, mkReq("POST", DingTalkPath, body,
      headers = [("timestamp", ts), ("sign", "bogus")]))
    check resp.status == 403

    var dt = newDingTalkAdapter("key", "dt-secret", "robot", HookTmp / "dt.tsv")
    check not dt.tryRecvEvent()[0]

  test "expired timestamp is rejected (replay window)":
    clearQueues()
    let cfg = WebhookConfig(dingtalkAppSecret: "dt-secret")
    let body = """{"msgtype":"text","senderId":"u1","msgId":"m1",
                   "text":{"content":"old"}}"""
    let ts = $((epochTime().int64 - 7200) * 1000)
    let sign = hmacSha256Base64("dt-secret", ts & "\n" & "dt-secret")

    let resp = handleWebhookRequest(cfg, mkReq("POST", DingTalkPath, body,
      headers = [("timestamp", ts), ("sign", sign)]))

    check resp.status == 403
    var dt = newDingTalkAdapter("key", "dt-secret", "robot", HookTmp / "dt.tsv")
    check not dt.tryRecvEvent()[0]

  test "future timestamp is rejected (replay window)":
    clearQueues()
    let cfg = WebhookConfig(dingtalkAppSecret: "dt-secret")
    let body = """{"msgtype":"text","senderId":"u1","msgId":"m1",
                   "text":{"content":"future"}}"""
    let ts = $((epochTime().int64 + 7200) * 1000)
    let sign = hmacSha256Base64("dt-secret", ts & "\n" & "dt-secret")

    let resp = handleWebhookRequest(cfg, mkReq("POST", DingTalkPath, body,
      headers = [("timestamp", ts), ("sign", sign)]))

    check resp.status == 403

  test "non-numeric and extreme timestamps are rejected without overflowing":
    let cfg = WebhookConfig(dingtalkAppSecret: "dt-secret")
    let body = """{"msgtype":"text","senderId":"u1","msgId":"m1",
                   "text":{"content":"x"}}"""

    for ts in ["not-a-number", "-9223372036854775000"]:
      let sign = hmacSha256Base64("dt-secret", ts & "\n" & "dt-secret")
      let resp = handleWebhookRequest(cfg, mkReq("POST", DingTalkPath, body,
        headers = [("timestamp", ts), ("sign", sign)]))
      check resp.status == 403

suite "webhook receiver — Matrix":

  test "bearer token dispatches the payload":
    clearQueues()
    var mx = newMatrixAdapter("https://mx", "@bot:mx", "tok", HookTmp / "mx.tsv")
    mx.openQueue()
    let cfg = WebhookConfig(matrixToken: "mx-token")
    let body = """{"type":"m.room.message","room_id":"!r:mx","event_id":"$e:mx",
                   "sender":"@u:mx","content":{"msgtype":"m.text","body":"hi mx"}}"""

    let resp = handleWebhookRequest(cfg, mkReq("POST", MatrixPath, body,
      headers = [("Authorization", "Bearer mx-token")]))
    check resp.status == 200
    let (hasEvent, event) = mx.tryRecvEvent()
    check hasEvent
    check event.roomId == "!r:mx"
    check event.content == "hi mx"

  test "query access_token is accepted and a bad token is rejected":
    let cfg = WebhookConfig(matrixToken: "mx-token")
    let body = """{"type":"m.room.message","room_id":"!r:mx","event_id":"$e2:mx",
                   "sender":"@u:mx","content":{"msgtype":"m.text","body":"x"}}"""
    check handleWebhookRequest(cfg, mkReq("POST", MatrixPath, body,
      query = [("access_token", "mx-token")])).status == 200
    check handleWebhookRequest(cfg, mkReq("POST", MatrixPath, body,
      headers = [("Authorization", "Bearer wrong")])).status == 403

suite "webhook receiver — WhatsApp":

  test "GET verification echoes the challenge on a matching token":
    let cfg = WebhookConfig(whatsappVerifyToken: "wa-verify")
    let resp = handleWebhookRequest(cfg, mkReq("GET", WhatsAppPath,
      query = [("hub.mode", "subscribe"),
               ("hub.challenge", "wa-ch"),
               ("hub.verify_token", "wa-verify")]))
    check resp.status == 200
    check resp.body == "wa-ch"

  test "GET verification rejects a wrong token":
    let cfg = WebhookConfig(whatsappVerifyToken: "wa-verify")
    let resp = handleWebhookRequest(cfg, mkReq("GET", WhatsAppPath,
      query = [("hub.mode", "subscribe"),
               ("hub.challenge", "wa-ch"),
               ("hub.verify_token", "nope")]))
    check resp.status == 403

  test "signed POST dispatches the payload":
    clearQueues()
    var wa = newWhatsAppAdapter("tok", "PN1", HookTmp / "wa.tsv")
    wa.openQueue()
    let cfg = WebhookConfig(whatsappVerifyToken: "wa-verify",
                            whatsappAppSecret: "wa-secret")
    let body = """{"entry":[{"changes":[{"value":{
      "metadata":{"phone_number_id":"PN1"},
      "messages":[{"from":"5511999","id":"wamid.1","type":"text",
                   "text":{"body":"hi wa"}}]}}]}]}"""
    let sig = "sha256=" & hmacSha256Hex("wa-secret", body)

    let resp = handleWebhookRequest(cfg, mkReq("POST", WhatsAppPath, body,
      headers = [("X-Hub-Signature-256", sig)]))
    check resp.status == 200
    let (hasEvent, event) = wa.tryRecvEvent()
    check hasEvent
    check event.waUserId == "5511999"
    check event.text == "hi wa"

  test "unsigned POST is rejected when no app secret is configured":
    let cfg = WebhookConfig(whatsappVerifyToken: "wa-verify")
    check handleWebhookRequest(cfg, mkReq("POST", WhatsAppPath, "{}")).status == 403

suite "webhook receiver — exposure guard":

  test "unknown path is not found":
    let cfg = WebhookConfig(slackSigningSecret: "x")
    check handleWebhookRequest(cfg, mkReq("POST", "/webhook/nope", "{}")).status == 404

  test "unconfigured channel route is not found":
    let cfg = WebhookConfig(slackSigningSecret: "x")
    check handleWebhookRequest(cfg, mkReq("POST", FeishuPath, "{}")).status == 404

  test "starting a receiver without any secret is refused":
    let r = startWebhookReceiver(WebhookConfig(), 9099, "127.0.0.1", hookLog)
    check r.isErr
    check "no webhook channel" in r.error

  test "invalid port is refused":
    let cfg = WebhookConfig(slackSigningSecret: "x")
    for port in [0, -1, 70000]:
      let r = startWebhookReceiver(cfg, port, "127.0.0.1", hookLog)
      check r.isErr
      check "invalid webhook port" in r.error

  test "bind failure is reported and does not mark the receiver started":
    var blocker = newSocket()
    blocker.setSockOpt(OptReuseAddr, true)
    blocker.bindAddr(Port(0), "127.0.0.1")
    blocker.listen()
    let (_, busyPort) = blocker.getLocalAddr()

    let cfg = WebhookConfig(slackSigningSecret: "x")
    let first = startWebhookReceiver(cfg, int(busyPort), "127.0.0.1", hookLog)
    check first.isErr
    check "cannot bind" in first.error

    ## A second attempt must reach the bind again instead of short-circuiting on
    ## `gWebhookStarted`, proving the failed start did not set the flag.
    let second = startWebhookReceiver(cfg, int(busyPort), "127.0.0.1", hookLog)
    check second.isErr
    check "cannot bind" in second.error
    check not second.error.contains("already started")

    blocker.close()

  test "receiver starts, stops and restarts cleanly":
    var probe = newSocket()
    probe.setSockOpt(OptReuseAddr, true)
    probe.bindAddr(Port(0), "127.0.0.1")
    let (_, port) = probe.getLocalAddr()
    probe.close()

    let cfg = WebhookConfig(feishuVerificationToken: "tok")
    let first = startWebhookReceiver(cfg, int(port), "127.0.0.1", hookLog)
    check first.isOk
    stopWebhookReceiver()

    let second = startWebhookReceiver(cfg, int(port), "127.0.0.1", hookLog)
    check second.isOk
    stopWebhookReceiver()
