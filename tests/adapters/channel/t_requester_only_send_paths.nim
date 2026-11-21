## Requester-only replies through the real channel runtimes and adapters.
##
## Each adapter points at a local HTTP server that records every request. A
## `/mycode` (whose reply is a link code that takes over a session) is sent
## from a group or server channel, and the test asserts where the code went:
## to the requester's private path, or nowhere, but never to the shared space.

import std/[json, locks, nativesockets, net, os, strutils, unittest]
import chronos/asyncsync
import donkey/core/log
import donkey/core/pipeops
import donkey/core/outbound/outbound
import donkey/core/security/dm_policy
import donkey/domain/message
import donkey/ports/provider
import donkey/adapters/memory/md_file
import donkey/adapters/channel/common_runtime
import donkey/adapters/channel/discord
import donkey/adapters/channel/discord_runtime
import donkey/adapters/channel/feishu
import donkey/adapters/channel/feishu_runtime
import donkey/adapters/channel/slack
import donkey/adapters/channel/slack_runtime
import donkey/adapters/channel/whatsapp
import donkey/adapters/channel/whatsapp_runtime
import donkey/adapters/channel/wechat
import donkey/adapters/channel/wechat_runtime
import donkey/adapters/channel/wecom
import donkey/adapters/channel/wecom_runtime
import donkey/adapters/channel/qq_channel
import donkey/adapters/channel/qq_runtime
import donkey/adapters/channel/telegram
import donkey/adapters/channel/telegram_runtime
import donkey/core/commands/command_routing
import donkey/app/command_dispatch
import donkey/app/session_manager

# ── Recording HTTP server ─────────────────────────────────────────────────────

type
  Recorded = object
    target: string  ## "METHOD /path?query"
    body:   string
  ServerArgs = object
    fd: int

var gLock: Lock
var gRequests: seq[Recorded]
var gFailPaths: seq[string]  ## path fragments answered with HTTP 500
var gStop: bool
initLock(gLock)

const CannedBody = """{"ok":true,"code":0,"errcode":0,"retcode":0,"status":"ok",
"tenant_access_token":"t","expire":7200,"access_token":"t","expires_in":7200,
"channel":{"id":"D1"},"id":"D1","messages":[{"id":"wamid.1"}],
"result":{"message_id":1},"data":{"message_id":"om_1"}}"""

proc serve(args: ServerArgs) {.thread.} =
  let server = newSocket(SocketHandle(args.fd), AF_INET, SOCK_STREAM,
                         IPPROTO_TCP, buffered = false)
  while true:
    var client: Socket
    try:
      server.accept(client)
    except CatchableError:
      break
    var stopping = false
    {.cast(gcsafe).}:
      withLock gLock:
        stopping = gStop
    if stopping:
      client.close()
      break
    try:
      let requestLine = client.recvLine(timeout = 5000)
      var contentLength = 0
      while true:
        let line = client.recvLine(timeout = 5000)
        if line.len == 0 or line == "\r\n":
          break
        if line.toLowerAscii.startsWith("content-length:"):
          contentLength = parseInt(line.split(':', 1)[1].strip)
      var body = ""
      if contentLength > 0:
        body = client.recv(contentLength, timeout = 5000)
      let parts = requestLine.split(' ')
      let target = parts[0] & " " & (if parts.len > 1: parts[1] else: "")
      var status = "200 OK"
      {.cast(gcsafe).}:
        withLock gLock:
          gRequests.add(Recorded(target: target, body: body))
          for fragment in gFailPaths:
            if fragment in target:
              status = "500 Internal Server Error"
      client.send("HTTP/1.1 " & status & "\r\nContent-Type: application/json\r\n" &
                  "Content-Length: " & $CannedBody.len & "\r\nConnection: close\r\n\r\n" &
                  CannedBody)
    except CatchableError:
      discard
    client.close()

var gServerThread: Thread[ServerArgs]
var gPort: int

proc startServer() =
  let listener = newSocket(buffered = false)
  listener.setSockOpt(OptReuseAddr, true)
  listener.bindAddr(Port(0), "127.0.0.1")
  listener.listen()
  gPort = int(listener.getLocalAddr()[1])
  createThread(gServerThread, serve, ServerArgs(fd: int(listener.getFd())))

proc stopServer() =
  withLock gLock:
    gStop = true
  try:
    let poke = newSocket()
    poke.connect("127.0.0.1", Port(gPort))
    poke.close()
  except CatchableError:
    discard
  joinThread(gServerThread)

proc base(): string = "http://127.0.0.1:" & $gPort

proc reset(failPaths: seq[string] = @[]) =
  withLock gLock:
    gRequests = @[]
    gFailPaths = failPaths

proc requests(): seq[Recorded] =
  withLock gLock:
    result = gRequests

proc anyRequest(pred: proc(r: Recorded): bool): bool =
  for r in requests():
    if pred(r):
      return true
  false

# ── Shared fixtures ──────────────────────────────────────────────────────────

const Tmp = "/tmp/donkey_requester_only_send_paths"
let logger = newLogger("t.send_paths", lvlError)

proc env(dir: string): ChannelRuntimeEnv =
  newChannelRuntimeEnv(
    MdFileAdapter(paddocksDir: Tmp / dir / "paddocks"),
    proc(preferencesMd: string): CompleteFn {.gcsafe.} =
      proc(req: CompletionRequest): Result[CompletionResponse, string] =
        ok(CompletionResponse(text: "pong")),
    proc(p: string): Result[ModelCatalogResult, string] {.gcsafe.} =
      ok(emptyCatalogResult()))

proc openSessions(): SessionManager =
  result.init()
  result.dmPolicy = DmPolicyOpen

let noop = proc(msg: InboundMessage) {.gcsafe.} = discard

proc carriesLinkCode(r: Recorded): bool = "link code" in r.body

proc runTests*() =
  startServer()
  defer: stopServer()
  removeDir(Tmp)

  suite "requester-only replies on the real send paths":
    test "Discord: a link code asked in a server channel goes to the DM":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc" / "ids.tsv", apiBase = base())
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage, discordUserId: "42",
        content: "/mycode", channelId: "guild-chan", messageId: "m1"),
        dc, state, env("dc"), msgSeq, logger, noop, noop, noop)
      check anyRequest(proc(r: Recorded): bool =
        "/channels/D1/messages" in r.target and r.carriesLinkCode)
      check not anyRequest(proc(r: Recorded): bool = "guild-chan" in r.target)

    test "Discord: a failed DM is not posted in the server channel":
      reset(failPaths = @["/users/@me/channels"])
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc2" / "ids.tsv", apiBase = base())
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage, discordUserId: "43",
        content: "/mycode", channelId: "guild-chan", messageId: "m2"),
        dc, state, env("dc2"), msgSeq, logger, noop, noop, noop)
      check anyRequest(proc(r: Recorded): bool = "/users/@me/channels" in r.target)
      check not anyRequest(proc(r: Recorded): bool = "guild-chan" in r.target)
      check not anyRequest(carriesLinkCode)

    test "Discord: public replies still go to the server channel":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc3" / "ids.tsv", apiBase = base())
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage, discordUserId: "44",
        content: "/start", channelId: "guild-chan", messageId: "m3"),
        dc, state, env("dc3"), msgSeq, logger, noop, noop, noop)
      check anyRequest(proc(r: Recorded): bool =
        "/channels/guild-chan/messages" in r.target)

    test "Discord: a slash command link code is ephemeral":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc4" / "ids.tsv", apiBase = base())
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage, discordUserId: "45",
        content: "/mycode", channelId: "guild-chan", interactionId: "i1",
        interactionToken: "tok"),
        dc, state, env("dc4"), msgSeq, logger, noop, noop, noop)
      var callbacks = 0
      for r in requests():
        if "/interactions/i1/tok/callback" in r.target:
          inc callbacks
          check parseJson(r.body)["data"]["flags"].getInt == DiscordEphemeralFlag
      check callbacks == 1
      check not anyRequest(proc(r: Recorded): bool = "guild-chan" in r.target)

    test "QQ: a group gets the notice, not the link code":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var qq = newQQOneBotChannelAdapter(base(), "", Tmp / "qq" / "ids.tsv")
      check qq.enqueueEventJson("""{"post_type":"message","message_type":"group",
        "group_id":99,"user_id":7,"message_id":8,"raw_message":"/mycode"}""").isOk
      drainQQEvents(qq, sm, env("qq"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        "send_group_msg" in r.target and RequesterOnlyNotice in r.body)
      check not anyRequest(carriesLinkCode)

    test "QQ: a link code asked in a DM goes to that DM, even with a group bound first":
      ## The reply target is where the command came from, not the first QQ
      ## binding of the user: a group bound earlier must not receive the code.
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var qq = newQQOneBotChannelAdapter(base(), "", Tmp / "qq-dm" / "ids.tsv")
      let user = qq.resolver.resolve(ckQQ, "group:99")
      check qq.resolver.consumeLinkCode(qq.resolver.generateLinkCode(user), ckQQ, "7")
      check qq.resolver.reverseChannel(user, ckQQ) == "group:99"
      check qq.enqueueEventJson("""{"post_type":"message","message_type":"private",
        "user_id":7,"message_id":9,"raw_message":"/mycode"}""").isOk
      drainQQEvents(qq, sm, env("qq-dm"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        "send_private_msg" in r.target and "\"user_id\":\"7\"" in r.body and carriesLinkCode(r))
      check not anyRequest(proc(r: Recorded): bool = "send_group_msg" in r.target)

    test "QQ official: every command reply is a passive reply carrying msg_id":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var qq = newQQOfficialChannelAdapter("app", "secret", Tmp / "qqo-help" / "ids.tsv",
                                           apiBase = base(), tokenBase = base())
      check qq.enqueueEventJson($(%* {"op": 0, "t": "GROUP_AT_MESSAGE_CREATE",
        "s": 2, "d": {"group_openid": "G2", "author": {"member_openid": "M2"},
                      "id": "msg-78", "content": "/help"}})).isOk
      drainQQEvents(qq, sm, env("qqo-help"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        "/v2/groups/G2/messages" in r.target and "msg-78" in r.body)

    test "Feishu: a link code asked in a group chat goes to the sender's open_id":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var fs = newFeishuAdapter("cli_app", "secret", Tmp / "fs" / "ids.tsv",
                                apiBase = base())
      fs.openQueue()
      feishu.pushEvent(%* {
        "schema": "2.0",
        "header": {"event_type": "im.message.receive_v1"},
        "event": {
          "message": {"message_type": "text", "message_id": "om_g1",
                      "chat_id": "oc_group", "chat_type": "group",
                      "content": "{\"text\":\"/mycode\"}"},
          "sender": {"sender_id": {"open_id": "ou_requester"}},
        },
      })
      drainFeishuEvents(fs, "cli_app", sm, env("fs"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        "receive_id_type=open_id" in r.target and r.carriesLinkCode and
          "ou_requester" in r.body)
      check not anyRequest(proc(r: Recorded): bool = "oc_group" in r.body)

    test "Slack: a link code asked in a public channel goes to the DM":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var sl = newSlackAdapter("token", Tmp / "sl" / "ids.tsv", apiBase = base())
      sl.openQueue()
      slack.pushEvent(%* {
        "type": "event_callback", "team_id": "T1",
        "event": {"type": "message", "user": "U1", "text": "/mycode",
                  "channel": "C_public", "ts": "1700000000.000002"},
      })
      drainSlackEvents(sl, sm, env("sl"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        "chat.postMessage" in r.target and r.carriesLinkCode and "D1" in r.body)
      check not anyRequest(proc(r: Recorded): bool =
        "chat.postMessage" in r.target and "C_public" in r.body)

    test "WhatsApp: the link code goes to the sender's number":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var wa = newWhatsAppAdapter("token", "PN1", Tmp / "wa" / "ids.tsv", base())
      wa.openQueue()
      whatsapp.pushEvent(%* {"entry": [{"changes": [{"value": {
        "metadata": {"phone_number_id": "PN1"},
        "messages": [{"from": "5511999990001", "id": "wamid.c1", "type": "text",
                      "text": {"body": "/mycode"}}]}}]}]})
      drainWhatsAppEvents(wa, "PN1", sm, env("wa"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        r.carriesLinkCode and "5511999990001" in r.body)

    test "WeChat: the link code goes to the sender's openid":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var wch = newWeChatAdapter("app", "secret", "tok", "", Tmp / "wch" / "ids.tsv",
                                 apiBase = base())
      check wch.enqueueWebhookXml("<xml><FromUserName>openid-1</FromUserName>" &
        "<MsgType>text</MsgType><MsgId>w1</MsgId><Content>/mycode</Content></xml>").isOk
      drainWeChatEvents(wch, "app", sm, env("wch"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        r.carriesLinkCode and "openid-1" in r.body)

    test "WeCom: the link code goes to the sender's user id":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var wc = newWeComAdapter("corp", "secret", "tok", 42, Tmp / "wc" / "ids.tsv",
                               apiBase = base())
      gWeComEvents.open()
      gWeComEvents.send(WeComEvent(msgType: "text", fromUser: "wc-user",
                                   msgId: "c1", content: "/mycode"))
      drainWeComEvents(wc, "corp", sm, env("wc"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        r.carriesLinkCode and "\"touser\":\"wc-user\"" in r.body)

    test "Telegram: a group gets the notice, never the link code or the doctor report":
      for text in ["/mycode", "/doctor", "/memory", "/whoami"]:
        reset()
        var sm = openSessions()
        var msgSeq = 0
        var state = initPresentationState()
        var tg = newTelegramAdapter("TOK", Tmp / "tg" / "ids.tsv", apiBase = base())
        let e = env("tg")
        let msg = InboundMessage(userId: tg.resolver.resolve(ckTelegram, "7"),
                                 channel: ckTelegram,
                                 channelId: "11", chatId: "-100", rawChannelId: "7",
                                 isGroup: true, text: text)
        check handleTelegramMessage(msg, sm, tg, state, e.memory, e.completeBuilder,
                                    e.modelCatalogLoader, 0, 0, msgSeq, 0, logger)
        check anyRequest(proc(r: Recorded): bool =
          "sendMessage" in r.target and RequesterOnlyNotice in r.body)
        check not anyRequest(carriesLinkCode)
        check not anyRequest(proc(r: Recorded): bool = "Doctor" in r.body)

    test "Telegram: a private chat gets the link code":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      var tg = newTelegramAdapter("TOK", Tmp / "tg2" / "ids.tsv", apiBase = base())
      let e = env("tg2")
      let msg = InboundMessage(userId: tg.resolver.resolve(ckTelegram, "8"),
                               channel: ckTelegram,
                               channelId: "12", chatId: "8", rawChannelId: "8",
                               text: "/mycode")
      check handleTelegramMessage(msg, sm, tg, state, e.memory, e.completeBuilder,
                                  e.modelCatalogLoader, 0, 0, msgSeq, 0, logger)
      check anyRequest(proc(r: Recorded): bool =
        "sendMessage" in r.target and r.carriesLinkCode)

    test "Discord: the DM goes to the account that sent the command":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc5" / "ids.tsv", apiBase = base())
      let user = dc.resolver.resolve(ckDiscord, "first-account")
      check dc.resolver.consumeLinkCode(dc.resolver.generateLinkCode(user),
                                        ckDiscord, "second-account")
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage,
        discordUserId: "second-account", content: "/mycode",
        channelId: "guild-chan", messageId: "m5"),
        dc, state, env("dc5"), msgSeq, logger, noop, noop, noop)
      check anyRequest(proc(r: Recorded): bool =
        "/users/@me/channels" in r.target and "second-account" in r.body)
      check not anyRequest(proc(r: Recorded): bool = "first-account" in r.body)

    test "QQ official: the group notice is a passive reply carrying msg_id":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var qq = newQQOfficialChannelAdapter("app", "secret", Tmp / "qqo" / "ids.tsv",
                                           apiBase = base(), tokenBase = base())
      check qq.enqueueEventJson($(%* {"op": 0, "t": "GROUP_AT_MESSAGE_CREATE",
        "s": 2, "d": {"group_openid": "G1", "author": {"member_openid": "M1"},
                      "id": "msg-77", "content": "/mycode"}})).isOk
      drainQQEvents(qq, sm, env("qqo"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        "/v2/groups/G1/messages" in r.target and RequesterOnlyNotice in r.body and
          "msg-77" in r.body)
      check not anyRequest(carriesLinkCode)

    test "Slack: an accepted slash command is acknowledged":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var sl = newSlackAdapter("token", Tmp / "sl2" / "ids.tsv", apiBase = base())
      sl.openQueue()
      discard sm.getOrCreate(sl.resolver.resolve(ckSlack, "U2"))
      slack.pushEvent(%* {"type": "slash_command", "user_id": "U2",
                          "command": "/compact", "channel_id": "C_public",
                          "team_id": "T1", "trigger_id": "tr-1"})
      drainSlackEvents(sl, sm, env("sl2"), msgSeq, noop, logger)
      check msgSeq == 1
      check anyRequest(proc(r: Recorded): bool =
        "chat.postMessage" in r.target and acceptedText(cmdCompact) in r.body)

    test "Slack: a /menu keyboard is not followed by an acknowledgement":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var sl = newSlackAdapter("token", Tmp / "sl3" / "ids.tsv", apiBase = base())
      sl.openQueue()
      slack.pushEvent(%* {"type": "slash_command", "user_id": "U3",
                          "command": "/menu", "channel_id": "C_public",
                          "team_id": "T1", "trigger_id": "tr-2"})
      drainSlackEvents(sl, sm, env("sl3"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool = "chat.postMessage" in r.target)
      check not anyRequest(proc(r: Recorded): bool = "Comando recebido" in r.body)

    test "Telegram: /whoami names the account that sent it":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      var tg = newTelegramAdapter("TOK", Tmp / "tg3" / "ids.tsv", apiBase = base())
      let user = tg.resolver.resolve(ckTelegram, "111")
      check tg.resolver.consumeLinkCode(tg.resolver.generateLinkCode(user),
                                        ckTelegram, "222")
      let e = env("tg3")
      let msg = InboundMessage(userId: user, channel: ckTelegram, channelId: "222",
                               chatId: "222", rawChannelId: "222", text: "/whoami")
      check handleTelegramMessage(msg, sm, tg, state, e.memory, e.completeBuilder,
                                  e.modelCatalogLoader, 0, 0, msgSeq, 0, logger)
      check anyRequest(proc(r: Recorded): bool =
        "sendMessage" in r.target and "222" in r.body and "Identity" in r.body)
      check not anyRequest(proc(r: Recorded): bool = "`111`" in r.body)

    test "Telegram: a failed /reasoning save is reported, not hidden by the keyboard":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      var tg = newTelegramAdapter("TOK", Tmp / "tg4" / "ids.tsv", apiBase = base())
      let user = tg.resolver.resolve(ckTelegram, "333")
      let e = env("tg4")
      check e.memory.savePreferences(user, "reasoning = \"on\"").isOk
      setUiMsgId(state, ckTelegram, user, UiSlotConfig, "55")
      let dir = e.memory.paddockDir(user)
      let prefsFile = e.memory.preferencesMdPath(user)
      setFilePermissions(prefsFile, {fpUserRead})
      setFilePermissions(dir, {fpUserRead, fpUserExec})
      defer:
        setFilePermissions(dir, {fpUserRead, fpUserWrite, fpUserExec})
        setFilePermissions(prefsFile, {fpUserRead, fpUserWrite})
      let writable =
        try:
          let f = open(prefsFile, fmAppend)
          f.close()
          true
        except IOError:
          false
      let msg = InboundMessage(userId: user, channel: ckTelegram, channelId: "333",
                               chatId: "333", rawChannelId: "333", text: "/reasoning")
      check handleTelegramMessage(msg, sm, tg, state, e.memory, e.completeBuilder,
                                  e.modelCatalogLoader, 0, 0, msgSeq, 0, logger)
      if not writable:  ## root writes anywhere
        check anyRequest(proc(r: Recorded): bool =
          "sendMessage" in r.target and "Não foi possível" in r.body)
        check not anyRequest(proc(r: Recorded): bool = "editMessage" in r.target)

    test "Telegram: /reasoning is confirmed when the /config keyboard cannot be edited":
      ## The /config message may be gone while its id is still stored. The
      ## preference is already saved, so the toggle must be confirmed once
      ## (a repeated /reasoning would flip it back) and the stale id dropped.
      reset(failPaths = @["editMessage"])
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      var tg = newTelegramAdapter("TOK", Tmp / "tg5" / "ids.tsv", apiBase = base())
      let user = tg.resolver.resolve(ckTelegram, "444")
      let e = env("tg5")
      check e.memory.savePreferences(user, "reasoning = \"on\"").isOk
      setUiMsgId(state, ckTelegram, user, UiSlotConfig, "56")
      let msg = InboundMessage(userId: user, channel: ckTelegram, channelId: "444",
                               chatId: "444", rawChannelId: "444", text: "/reasoning")
      check handleTelegramMessage(msg, sm, tg, state, e.memory, e.completeBuilder,
                                  e.modelCatalogLoader, 0, 0, msgSeq, 0, logger)
      check anyRequest(proc(r: Recorded): bool = "editMessage" in r.target)
      check anyRequest(proc(r: Recorded): bool =
        "sendMessage" in r.target and "Reasoning desativado." in r.body)
      check getUiMsgId(state, ckTelegram, user, UiSlotConfig) == ""

when isMainModule:
  runTests()
