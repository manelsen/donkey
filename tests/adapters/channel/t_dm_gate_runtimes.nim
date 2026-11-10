## DM authorization gate on the non-Telegram/Discord inbound runtimes.
##
## Contract under test:
##   - an unauthorized sender never reaches the LLM provider (complete fn) nor
##     the application session fallback;
##   - the denied event is still consumed from the adapter queue, so the drain
##     loop cannot spin forever;
##   - authorized senders keep flowing through unchanged.

import std/[json, options, os, unittest]
import donkey/core/log
import donkey/core/pipeops
import donkey/core/outbound/outbound
import donkey/core/security/dm_policy
import donkey/domain/message
import donkey/ports/provider
import donkey/adapters/memory/md_file
import donkey/adapters/channel/common_runtime
import donkey/adapters/channel/telegram
import donkey/adapters/channel/telegram_runtime
import donkey/adapters/channel/wecom
import donkey/adapters/channel/wecom_runtime
import donkey/adapters/channel/wechat
import donkey/adapters/channel/wechat_runtime
import donkey/adapters/channel/qq_channel
import donkey/adapters/channel/qq_runtime
import donkey/adapters/channel/feishu
import donkey/adapters/channel/feishu_runtime
import donkey/adapters/channel/whatsapp
import donkey/adapters/channel/whatsapp_runtime
import donkey/app/gateway_drainer
import donkey/app/session_manager

const GateTmp = "/tmp/donkey_dm_gate_tests"

proc gateLoader(): ModelCatalogLoader =
  proc(providerName: string): Result[ModelCatalogResult, string] {.gcsafe.} =
    ok(emptyCatalogResult())

let gateLog = newLogger("test.dm_gate", lvlError)

suite "channel DM gate — runtime drains":

  test "telegram denies unauthorized text before provider and session creation":
    removeDir(GateTmp / "telegram")
    var sm: SessionManager
    sm.init()
    sm.dmPolicy = DmPolicyAllowlist
    sm.isDmAllowed = proc(u: UserId): bool {.gcsafe.} = false
    var tg = TelegramAdapter(
      resolver: newIdentityResolver(GateTmp / "telegram" / "ids.tsv"))
    var presentationState = initPresentationState()
    let memory = MdFileAdapter(paddocksDir: GateTmp / "telegram" / "paddocks")

    var providerCalls = 0
    let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        inc providerCalls
        ok(CompletionResponse(text: "unexpected provider call"))
    var msgSeq = 0

    let msg = InboundMessage(
      userId: UserId("tg-intruder"),
      channel: ckTelegram,
      channelId: "42",
      text: "hello")

    let handled = handleTelegramMessage(
      msg, sm, tg, presentationState, memory, completeBuilder, gateLoader(),
      0, 0, msgSeq, 0, gateLog)

    check handled  ## denied message is consumed, no fallback dispatch
    check providerCalls == 0
    check sm.sessionCount() == 0

  test "parsePreferenceString reads a cursor key from a preferences document":
    let prefs = "discord_last_msg_id = \"123456789012345678\"\n" &
                "provider = \"gemini\"\n"
    check parsePreferenceString(prefs, "discord_last_msg_id") == "123456789012345678"
    check parsePreferenceString(prefs, "provider") == "gemini"
    check parsePreferenceString(prefs, "missing").len == 0

  test "wecom drops unauthorized text but keeps draining authorized traffic":
    removeDir(GateTmp / "wecom")
    var sm: SessionManager
    sm.init()
    sm.dmPolicy = DmPolicyAllowlist
    var wc = newWeComAdapter("corp", "secret", "tok", 42, GateTmp / "wecom" / "ids.tsv")
    let allowed = wc.resolver.resolve(ckWeCom, "allowed-user")
    sm.isDmAllowed = proc(u: UserId): bool {.gcsafe.} =
      {.cast(gcsafe).}:
        u == allowed
    let memory = MdFileAdapter(paddocksDir: GateTmp / "wecom" / "paddocks")

    var providerCalls = 0
    var fallbackMsgs: seq[InboundMessage] = @[]
    let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        inc providerCalls
        ok(CompletionResponse(text: "unexpected provider call"))
    var msgSeq = 0

    gWeComEvents.open()
    gWeComEvents.send(WeComEvent(
      msgType: "text", fromUser: "intruder", msgId: "m1", content: "/status"))
    gWeComEvents.send(WeComEvent(
      msgType: "text", fromUser: "allowed-user", msgId: "m2", content: "hello"))

    let onFallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        fallbackMsgs.add(msg)

    drainWeComEvents(wc, "corp", sm, memory, completeBuilder, gateLoader(),
                     0, 0, 0, msgSeq, gateLog, onFallback)

    check providerCalls == 0
    check fallbackMsgs.len == 1
    check fallbackMsgs[0].text == "hello"
    check sm.sessionCount() == 0
    check not wc.tryRecvEvent()[0]  ## denied event was consumed
    check wc.resolver.lookup(ckWeCom, "intruder").isNone  ## denied sender not minted
    check wc.resolver.lookup(ckWeCom, "allowed-user").isSome

  test "wechat drops unauthorized messages before command dispatch":
    removeDir(GateTmp / "wechat")
    var sm: SessionManager
    sm.init()
    sm.dmPolicy = DmPolicyAllowlist
    sm.isDmAllowed = proc(u: UserId): bool {.gcsafe.} = false
    var wch = newWeChatAdapter("app", "secret", "tok", "", GateTmp / "wechat" / "ids.tsv")
    let memory = MdFileAdapter(paddocksDir: GateTmp / "wechat" / "paddocks")

    var providerCalls = 0
    var fallbackCalls = 0
    let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        inc providerCalls
        ok(CompletionResponse(text: "unexpected provider call"))
    var msgSeq = 0

    let xml = "<xml><FromUserName>intruder</FromUserName>" &
              "<MsgType>text</MsgType><MsgId>w1</MsgId>" &
              "<Content>/mycode</Content></xml>"
    check wch.enqueueWebhookXml(xml).isOk

    let onFallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inc fallbackCalls

    drainWeChatEvents(wch, "app", sm, memory, completeBuilder, gateLoader(),
                      0, 0, 0, msgSeq, onFallback, gateLog)

    check providerCalls == 0
    check fallbackCalls == 0
    check sm.sessionCount() == 0
    check not wch.tryRecvEvent()[0]
    check wch.resolver.lookup(ckWeChat, "intruder").isNone  ## denied sender not minted

  test "qq drops unauthorized messages and consumes the event":
    removeDir(GateTmp / "qq")
    var sm: SessionManager
    sm.init()
    sm.dmPolicy = DmPolicyAllowlist
    sm.isDmAllowed = proc(u: UserId): bool {.gcsafe.} = false
    var qq = newQQOneBotChannelAdapter("http://127.0.0.1:1", "",
                                       GateTmp / "qq" / "ids.tsv")
    let memory = MdFileAdapter(paddocksDir: GateTmp / "qq" / "paddocks")

    var providerCalls = 0
    var fallbackCalls = 0
    let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        inc providerCalls
        ok(CompletionResponse(text: "unexpected provider call"))
    var msgSeq = 0

    check qq.enqueueEventJson("""{"post_type":"message","message_type":"private",
      "user_id":4242,"message_id":7,"raw_message":"/status"}""").isOk

    let onFallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inc fallbackCalls

    drainQQEvents(qq, sm, memory, completeBuilder, gateLoader(),
                  0, 0, 0, msgSeq, onFallback, gateLog)

    check providerCalls == 0
    check fallbackCalls == 0
    check sm.sessionCount() == 0
    check not qq.tryRecvEvent()[0]
    check qq.resolver.lookup(ckQQ, "4242").isNone  ## denied sender not minted

  test "feishu drops unauthorized messages and consumes the event":
    removeDir(GateTmp / "feishu")
    var sm: SessionManager
    sm.init()
    sm.dmPolicy = DmPolicyAllowlist
    sm.isDmAllowed = proc(u: UserId): bool {.gcsafe.} = false
    var fs = newFeishuAdapter("cli_app", "secret", GateTmp / "feishu" / "ids.tsv")
    fs.openQueue()
    let memory = MdFileAdapter(paddocksDir: GateTmp / "feishu" / "paddocks")

    var providerCalls = 0
    var fallbackCalls = 0
    let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        inc providerCalls
        ok(CompletionResponse(text: "unexpected provider call"))
    var msgSeq = 0

    feishu.pushEvent(%* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "text",
          "message_id":   "om_gate1",
          "chat_id":      "oc_gate1",
          "chat_type":    "p2p",
          "content":      "{\"text\":\"/status\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_intruder"}},
      },
    })

    let onFallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inc fallbackCalls

    drainFeishuEvents(fs, "cli_app", sm, memory, completeBuilder, gateLoader(),
                      0, 0, 0, msgSeq, onFallback, gateLog)

    check providerCalls == 0
    check fallbackCalls == 0
    check sm.sessionCount() == 0
    check not fs.tryRecvEvent()[0]
    check fs.resolver.lookup(ckFeishu, "ou_intruder").isNone  ## denied sender not minted

  test "whatsapp drops unauthorized messages before ack and provider dispatch":
    removeDir(GateTmp / "whatsapp")
    var sm: SessionManager
    sm.init()
    sm.dmPolicy = DmPolicyAllowlist
    sm.isDmAllowed = proc(u: UserId): bool {.gcsafe.} = false
    var wa = newWhatsAppAdapter("token", "PN1", GateTmp / "whatsapp" / "ids.tsv",
                                "http://127.0.0.1:1")
    wa.openQueue()
    let memory = MdFileAdapter(paddocksDir: GateTmp / "whatsapp" / "paddocks")

    var providerCalls = 0
    var fallbackCalls = 0
    let completeBuilder = proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        inc providerCalls
        ok(CompletionResponse(text: "unexpected provider call"))
    var msgSeq = 0

    whatsapp.pushEvent(%* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata": {"phone_number_id": "PN1"},
            "messages": [{
              "from": "5511999990010",
              "id":   "wamid.gate1",
              "type": "text",
              "text": {"body": "/status"},
            }],
          }
        }]
      }]
    })

    let onFallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inc fallbackCalls

    drainWhatsAppEvents(wa, "PN1", sm, memory, completeBuilder, gateLoader(),
                        0, 0, 0, msgSeq, onFallback, gateLog)

    check providerCalls == 0
    check fallbackCalls == 0
    check sm.sessionCount() == 0
    check not wa.tryRecvEvent()[0]
    check wa.resolver.lookup(ckWhatsApp, "5511999990010").isNone  ## denied sender not minted

  test "dingtalk gateway drainer denies unauthorized and advances the queue":
    var queue: seq[InboundMessage] = @[
      InboundMessage(userId: UserId("dt-intruder"), channel: ckDingTalk, text: "/status"),
      InboundMessage(userId: UserId("dt-owner"), channel: ckDingTalk, text: "hello"),
    ]
    var dispatched: seq[string] = @[]

    let poll = proc(): (bool, InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        if queue.len == 0:
          return (false, InboundMessage())
        result = (true, queue[0])
        queue.delete(0)

    let count = drainDingTalkGateway(
      true,
      poll,
      proc(msg: InboundMessage) {.gcsafe.} =
        {.cast(gcsafe).}:
          dispatched.add(msg.text),
      gateLog,
      proc(userId: UserId): bool {.gcsafe.} = userId == UserId("dt-owner"))

    check count == 1
    check dispatched == @["hello"]
    check queue.len == 0

  test "matrix gateway drainer denies unauthorized and advances the queue":
    var queue: seq[InboundMessage] = @[
      InboundMessage(userId: UserId("mx-intruder"), channel: ckMatrix, text: "/status"),
      InboundMessage(userId: UserId("mx-owner"), channel: ckMatrix, text: "hi"),
    ]
    var dispatched: seq[string] = @[]

    let poll = proc(): (bool, InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        if queue.len == 0:
          return (false, InboundMessage())
        result = (true, queue[0])
        queue.delete(0)

    let count = drainMatrixGateway(
      true,
      poll,
      proc(msg: InboundMessage) {.gcsafe.} =
        {.cast(gcsafe).}:
          dispatched.add(msg.text),
      gateLog,
      proc(userId: UserId): bool {.gcsafe.} = userId == UserId("mx-owner"))

    check count == 1
    check dispatched == @["hi"]
    check queue.len == 0
