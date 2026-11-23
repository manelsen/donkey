## Requester-only replies through the real channel runtimes and adapters.
##
## Each adapter points at a local HTTP server that records every request. A
## `/mycode` (whose reply is a link code that takes over a session) is sent
## from a group or server channel, and the test asserts where the code went:
## to the requester's private path, or nowhere, but never to the shared space.

import std/[json, locks, nativesockets, net, options, os, strutils, unittest]
import chronos/asyncsync
import donkey/config/environment
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
import donkey/infra/event_queue

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
var gFallbacks {.threadvar.}: seq[InboundMessage]
let captureFallback = proc(msg: InboundMessage) {.gcsafe.} = gFallbacks.add(msg)

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

    test "Discord: no message the bot posts or edits can ping @everyone or a role":
      ## hermes efa6c9f715. The model's text reaches Discord verbatim; without
      ## `allowed_mentions`, an "@everyone" in a reply (or one a prompt
      ## injection planted) pings the whole server.
      reset()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-m" / "ids.tsv", apiBase = base())
      dc.appId[] = "app"
      let uid = dc.resolver.resolve(ckDiscord, "49")
      let ping = "@everyone <@&1> hi"
      let kb = @[@[("ok", "ok")]]
      check dc.send(OutboundMessage(userId: uid, text: ping,
                                    replyTo: "channel:guild-chan")).isOk
      check dc.send(OutboundMessage(userId: uid, text: ping, keyboard: kb)).isOk
      check dc.sendReturnId(OutboundMessage(userId: uid, text: ping)).isOk
      check dc.editMessage(uid, "m1", ping).isOk
      check dc.editKeyboard(uid, "m1", ping, kb).isOk
      check dc.sendInteractionResponse("i1", "t1", ping).isOk
      check dc.sendInteractionKeyboard("i1", "t1", ping, kb).isOk
      check dc.editInteractionKeyboard("t1", ping, kb).isOk
      check dc.sendInteractionEmbedPage("i1", "t1", ping, ping, 0, kb).isOk
      check dc.editInteractionEmbedPage("t1", ping, ping, 0, kb).isOk
      var carriers = 0
      for r in requests():
        if r.body.len == 0 or "@everyone" notin r.body: continue
        inc carriers
        let j = parseJson(r.body)
        let payload = if j.hasKey("data"): j["data"] else: j
        check payload["allowed_mentions"] == %* {"parse": ["users"]}
      check carriers == 10

    test "Discord: a table in a reply or a streamed edit arrives as bullets":
      ## hermes cf7bf5bdc9: Discord shows raw pipes for a GFM table.
      reset()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-t" / "ids.tsv", apiBase = base())
      let uid = dc.resolver.resolve(ckDiscord, "50")
      let table = "| Name | Score |\n|---|---|\n| Alice | 95 |"
      check dc.send(OutboundMessage(userId: uid, text: table,
                                    replyTo: "channel:guild-chan")).isOk
      check dc.sendReturnId(OutboundMessage(userId: uid, text: table)).isOk
      check dc.editMessage(uid, "m1", table).isOk
      var seen = 0
      for r in requests():
        if "Alice" notin r.body: continue
        inc seen
        let content = parseJson(r.body)["content"].getStr
        check content == "**Alice**\n• Score: 95"
      check seen == 3

    test "Discord: with mentions required, an unaddressed server message is ignored":
      ## hermes 608e8a6062. DONKEY_DISCORD_REQUIRE_MENTION: in a server the
      ## bot answers only when mentioned or replied to; DMs are unaffected.
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-rm" / "ids.tsv",
                                 apiBase = base(), requireMention = true)
      dc.appId[] = "BOT"
      proc reply(id, guild, text: string; refAuthor = "") =
        handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage,
          discordUserId: "51", content: text, channelId: "chan-" & id,
          messageId: id, guildId: guild, referencedAuthorId: refAuthor),
          dc, state, env("dc-rm"), msgSeq, logger, noop, noop, noop)
      proc answered(id: string): bool =
        anyRequest(proc(r: Recorded): bool =
          ("/channels/chan-" & id & "/messages") in r.target)
      reply("a", "g1", "/start")
      reply("b", "g1", "<@BOT> /start")
      reply("c", "g1", "<@!BOT> /start")
      reply("d", "g1", "/start", refAuthor = "BOT")
      reply("e", "g1", "<@OTHER> /start")
      check not answered("a")
      check answered("b")
      check answered("c")
      check answered("d")
      check not answered("e")

    test "Discord: a DM is answered without a mention even when mentions are required":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-rm2" / "ids.tsv",
                                 apiBase = base(), requireMention = true)
      dc.appId[] = "BOT"
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage,
        discordUserId: "52", content: "/start", messageId: "dm1"),
        dc, state, env("dc-rm2"), msgSeq, logger, noop, noop, noop)
      check anyRequest(proc(r: Recorded): bool = "/messages" in r.target)

    test "Discord: without the setting, server messages are answered as before":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-rm3" / "ids.tsv", apiBase = base())
      dc.appId[] = "BOT"
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage,
        discordUserId: "53", content: "/start", channelId: "chan-z",
        messageId: "z", guildId: "g1"),
        dc, state, env("dc-rm3"), msgSeq, logger, noop, noop, noop)
      check anyRequest(proc(r: Recorded): bool = "/channels/chan-z/messages" in r.target)

    test "Discord: an attachment reaches the turn for download":
      ## The event carried the attachment URL but the turn was built from the
      ## text alone: a file sent on Discord never reached the agent.
      reset()
      gFallbacks = @[]
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-att" / "ids.tsv", apiBase = base())
      dc.appId[] = "BOT"
      discard sm.getOrCreate(dc.resolver.resolve(ckDiscord, "54"))
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage,
        discordUserId: "54", content: "", channelId: "chan-att",
        messageId: "att1", guildId: "g1",
        attachmentUrl: "https://cdn.discordapp.com/attachments/1/2/a.png",
        attachmentName: "a.png", attachmentMime: "image/png",
        extraAttachments: @["b.pdf"]),
        dc, state, env("dc-att"), msgSeq, logger, noop, noop, captureFallback)
      check gFallbacks.len == 1
      let msg = gFallbacks[0]
      check msg.mediaUrl == "https://cdn.discordapp.com/attachments/1/2/a.png"
      check msg.mediaFileName == "a.png"
      check msg.mediaMimeType == "image/png"
      check "b.pdf" in msg.text

    test "Discord: attachments are only downloaded from Discord's CDN":
      let dc = newDiscordAdapter("TOK", Tmp / "dc-cdn" / "ids.tsv", apiBase = base())
      check dc.downloadFile(base() & "/x.png").isErr
      check dc.downloadFile("http://cdn.discordapp.com/a.png").isErr
      check dc.downloadFile("https://cdn.discordapp.com.evil.test/a.png").isErr

    test "Discord: a retried message create carries the same nonce, so it is not posted twice":
      ## A POST that timed out may already have created the message. With
      ## `nonce` + `enforce_nonce`, Discord answers the retry with the message
      ## it already has instead of creating a second one.
      reset(failPaths = @["/channels/chan-n/messages"])
      let dc = newDiscordAdapter("TOK", Tmp / "dc-n" / "ids.tsv", apiBase = base())
      let uid = dc.resolver.resolve(ckDiscord, "55")
      discard dc.send(OutboundMessage(userId: uid, text: "hello",
                                      replyTo: "channel:chan-n"))
      var nonces: seq[string]
      for r in requests():
        if "/channels/chan-n/messages" notin r.target: continue
        let j = parseJson(r.body)
        check j["enforce_nonce"].getBool
        nonces.add(j["nonce"].getStr)
      check nonces.len >= 2
      for n in nonces:
        check n == nonces[0]
        check n.len in 1 .. 25

    test "Discord: two different messages get different nonces":
      reset()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-n2" / "ids.tsv", apiBase = base())
      let uid = dc.resolver.resolve(ckDiscord, "56")
      check dc.send(OutboundMessage(userId: uid, text: "one",
                                    replyTo: "channel:chan-n2")).isOk
      check dc.send(OutboundMessage(userId: uid, text: "two",
                                    replyTo: "channel:chan-n2")).isOk
      check dc.sendReturnId(OutboundMessage(userId: uid, text: "three",
                                            replyTo: "channel:chan-n2")).isOk
      var nonces: seq[string]
      for r in requests():
        if "/channels/chan-n2/messages" in r.target:
          nonces.add(parseJson(r.body)["nonce"].getStr)
      check nonces.len == 3
      check nonces[0] != nonces[1] and nonces[1] != nonces[2] and nonces[0] != nonces[2]

    test "Discord: a message delivered twice is handled once":
      ## A gateway RESUME replays events, and the startup backfill can overlap
      ## the live stream: the second copy must not answer again.
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc5" / "ids.tsv", apiBase = base())
      for _ in 0 ..< 2:
        handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage, discordUserId: "46",
          content: "/start", channelId: "guild-chan", messageId: "m-dup"),
          dc, state, env("dc5"), msgSeq, logger, noop, noop, noop)
      var replies = 0
      for r in requests():
        if "/channels/guild-chan/messages" in r.target: inc replies
      check replies == 1

    test "Discord: only listed servers are served (DONKEY_DISCORD_ALLOWED_CHANNELS)":
      ## Checked before the identity gate, like TG-016: an unlisted server
      ## gets no turn, no identity and no pairing.
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-ac" / "ids.tsv", apiBase = base(),
                                 allowedChannels = @["g-ok", "chan-listed"])
      dc.appId[] = "BOT"
      for (id, guild, chan) in [("1", "g-ok", "chan-a"), ("2", "g-bad", "chan-b"),
                                ("3", "g-bad", "chan-listed"), ("4", "", "dm-c")]:
        gDiscordEvents.push(DiscordRawEvent(kind: deMessage,
          discordUserId: "6" & id, content: "/start", channelId: chan,
          originChannelId: chan, messageId: "ac" & id, guildId: guild))
      drainDiscordEvents(sm, dc, "TOK", state, env("dc-ac"), msgSeq, logger,
                         noop, noop, noop)
      proc answered(chan: string): bool =
        anyRequest(proc(r: Recorded): bool = ("/channels/" & chan & "/messages") in r.target)
      check answered("chan-a")
      check not answered("chan-b")
      check answered("chan-listed")
      check dc.resolver.lookup(ckDiscord, "62").isNone

    test "Discord: a slash command in a server is not dropped by the mention requirement":
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc-sl" / "ids.tsv", apiBase = base(),
                                 requireMention = true)
      dc.appId[] = "BOT"
      handleDiscordEvent(sm, DiscordRawEvent(kind: deMessage, discordUserId: "57",
        content: "/start", guildId: "g1", originChannelId: "c1",
        interactionId: "i9", interactionToken: "tk9"),
        dc, state, env("dc-sl"), msgSeq, logger, noop, noop, noop)
      check anyRequest(proc(r: Recorded): bool = "/interactions/i9/tk9/callback" in r.target)

    test "Discord: a new gateway session recovers the gap by REST":
      ## A READY after a lost session means the gateway did not replay the
      ## gap; the drain runs the same recovery as the startup.
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      let dc = newDiscordAdapter("TOK", Tmp / "dc6" / "ids.tsv", apiBase = base())
      discard sm.getOrCreate(dc.resolver.resolve(ckDiscord, "48"))
      gDiscordEvents.push(DiscordRawEvent(kind: deResync))
      drainDiscordEvents(sm, dc, "TOK", state, env("dc6"), msgSeq, logger,
                         noop, noop, noop)
      check anyRequest(proc(r: Recorded): bool =
        r.target.startsWith("GET /channels/D1/messages"))

    test "Discord: only a READY after an earlier one asks for recovery":
      check not readyNeedsResync(readyBefore = false)
      check readyNeedsResync(readyBefore = true)

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

    test "QQ: /continue with a valid code in a group is refused before it is used":
      ## The refusal comes before the dispatch: the group gets the notice
      ## and the code is still valid for the DM it was meant for.
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var qq = newQQOneBotChannelAdapter(base(), "", Tmp / "qq-cont" / "ids.tsv")
      let owner = qq.resolver.resolve(ckQQ, "5")
      let code = qq.resolver.generateLinkCode(owner)
      check qq.enqueueEventJson("""{"post_type":"message","message_type":"group",
        "group_id":98,"user_id":6,"message_id":10,"raw_message":"/continue """ &
        code & """"}""").isOk
      drainQQEvents(qq, sm, env("qq-cont"), msgSeq, noop, logger)
      check anyRequest(proc(r: Recorded): bool =
        "send_group_msg" in r.target and RequesterOnlyNotice in r.body)
      check requests().len == 1
      check qq.resolver.consumeLinkCode(code, ckQQ, "6")
      check qq.resolver.resolve(ckQQ, "6") == owner

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

    test "Slack: no reply, edit or keyboard message can ping the whole channel":
      reset()
      var sl = newSlackAdapter("token", Tmp / "sl-b" / "ids.tsv", apiBase = base())
      let uid = sl.resolver.resolve(ckSlack, "U9")
      let ping = "<!channel> heads up"
      check sl.send(OutboundMessage(userId: uid, text: ping)).isOk
      ## The canned reply has no `ts`, so only the request matters here.
      discard sl.sendReturnId(OutboundMessage(userId: uid, text: ping))
      check sl.editMessage(uid, "1.2", ping).isOk
      check sl.sendKeyboard(uid, ping, @[@[("ok", "ok")]]).isOk
      check sl.editKeyboard(uid, "1.2", ping, @[@[("ok", "ok")]]).isOk
      check sl.sendToChannel("C9", ping).isOk
      var carriers = 0
      for r in requests():
        if "heads up" notin r.body: continue
        inc carriers
        check "<!channel>" notin r.body
        check "&lt;!channel>" in r.body
      check carriers >= 6

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
      ## the WeCom queue exists with the module
      gWeComEvents.push(WeComEvent(msgType: "text", fromUser: "wc-user",
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

    test "Telegram: a group message not addressed to the bot is ignored":
      ## Goes through the album-mention gate, which lives on the daemon loop
      ## and is created on first use.
      reset()
      var sm = openSessions()
      var msgSeq = 0
      var state = initPresentationState()
      var tg = newTelegramAdapter("TOK", Tmp / "tg-mention" / "ids.tsv", apiBase = base(),
        settings = telegramSettings(environmentOf({
          "DONKEY_TELEGRAM_BOT_USERNAME": "donkeybot",
          "DONKEY_TELEGRAM_REQUIRE_MENTION": "1"})))
      let e = env("tg-mention")
      let msg = InboundMessage(userId: tg.resolver.resolve(ckTelegram, "9"),
                               channel: ckTelegram,
                               channelId: "13", chatId: "-200", rawChannelId: "9",
                               isGroup: true, text: "just chatting")
      check handleTelegramMessage(msg, sm, tg, state, e.memory, e.completeBuilder,
                                  e.modelCatalogLoader, 0, 0, msgSeq, 0, logger)
      check not anyRequest(proc(r: Recorded): bool = "sendMessage" in r.target)

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
