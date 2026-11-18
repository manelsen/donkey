## LINE inbound runtime — US-006.
##
## Contract under test:
##   - `line_policy` decides standby/non-text/source/group/user before any
##     identity, session or pairing work;
##   - the replay cache deduplicates `webhookEventId` (one turn per event);
##   - the identity is the speaker but the reply target is the conversation;
##   - only `/continue` is handled locally; everything else is the session
##     fallback.

import std/[json, options, os, strutils, tables, times, unittest]
import donkey/adapters/channel/common_runtime
import donkey/adapters/channel/line
import donkey/adapters/channel/line_runtime
import donkey/app/session_manager
import donkey/core/identity/link_codes
import donkey/core/log
import donkey/core/pipeops
import donkey/domain/channels/line_policy
import donkey/domain/channels/line_pure
import donkey/domain/message
import donkey/ports/http

const
  Fixtures   = "tests/fixtures/line"
  LineTmp    = "/tmp/donkey_line_runtime_tests"
  GroupChat  = "C1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6"
  DmUser     = "U4af4980629a1c5f5b1a1f0e7b7a1e111"

let rtLog = newLogger("test.line_runtime", lvlError)

type
  FakeHttp = ref object
    calls: seq[string]   ## request bodies

proc handle(f: FakeHttp; url, body: string;
            headers: seq[HttpHeader]): Result[HttpResponse, string] {.gcsafe.} =
  {.cast(gcsafe).}:
    f.calls.add body
  ok(HttpResponse(status: 200, body: "{}"))

proc fake(f: FakeHttp): HttpRuntimePort =
  HttpRuntimePort(
    post: proc(url, body: string; headers: seq[HttpHeader] = @[]):
               Result[HttpResponse, string] {.gcsafe.} =
      handle(f, url, body, headers))

var idsSeq = 0

proc newAdapter(f: FakeHttp = nil): LineAdapter =
  inc idsSeq
  createDir(LineTmp)
  let path = LineTmp / ("ids_" & $idsSeq & ".tsv")
  removeFile(path)
  let http =
    if f != nil: fake(f)
    else: HttpRuntimePort()
  newLineAdapter("test-channel-access-token", path,
                 apiBase = "https://line.test", http = http)

proc drainQueue(a: var LineAdapter) =
  while a.tryRecvEvent()[0]:
    discard

type
  ReplySink = ref object
    items: seq[OutboundMessage]

proc sinkFor(sink: ReplySink): proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
  ## Captures what the drain hands to the outbox; it never posts.
  result = proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
    {.cast(gcsafe).}:
      sink.items.add msg
    ok()

proc groupPayload(eventId: string; senderId: string; groupId: string;
                  text = "Group hello"): JsonNode =
  %* {
    "destination": "U9c2f8a1b7d6e5f4a3b2c1d0e9f8a7b6c",
    "events": [{
      "type": "message",
      "mode": "active",
      "webhookEventId": eventId,
      "deliveryContext": {"isRedelivery": false},
      "replyToken": "token-" & eventId,
      "source": {"type": "group", "groupId": groupId, "userId": senderId},
      "message": {"id": "msg-" & eventId, "type": "text", "text": text},
    }],
  }

proc dmPayload(eventId, text: string): JsonNode =
  %* {
    "destination": "U9c2f8a1b7d6e5f4a3b2c1d0e9f8a7b6c",
    "events": [{
      "type": "message",
      "mode": "active",
      "webhookEventId": eventId,
      "deliveryContext": {"isRedelivery": false},
      "replyToken": "token-" & eventId,
      "source": {"type": "user", "userId": DmUser},
      "message": {"id": "msg-" & eventId, "type": "text", "text": text},
    }],
  }

proc policy(groups: seq[string] = @[]; users: seq[string] = @[]): LinePolicy =
  LinePolicy(allowedGroups: groups, allowedUsers: users)

# The daemon opens the queue once at startup, before the route accepts payloads.
openQueue()

suite "LINE runtime — replay cache":

  setup:
    var a = newAdapter()
    drainQueue(a)

  test "the same event id delivered twice produces one turn":
    var ln = newAdapter()
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)

    let payload = dmPayload("evt-dupe", "hello")
    pushEvent(payload)
    pushEvent(payload)  ## redelivery with the same webhookEventId

    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback, nil, rtLog)

    check inbound.len == 1
    check inbound[0].text == "hello"
    check replayCacheLen(replay) == 1

  test "a standby event is consumed and never answered":
    var ln = newAdapter()
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)

    pushEvent(parseFile(Fixtures / "webhook_standby.json"))
    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback, nil, rtLog)

    check inbound.len == 0
    check not ln.tryRecvEvent()[0]  ## the denied event was consumed

suite "LINE runtime — group policy":

  setup:
    var a = newAdapter()
    drainQueue(a)

  test "an empty allowlist denies every group":
    var ln = newAdapter()
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)

    pushEvent(parseFile(Fixtures / "webhook_group_text.json"))
    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback, nil, rtLog)

    check inbound.len == 0
    check not ln.tryRecvEvent()[0]

  test "an allowed group reaches the fallback with the group as chatId":
    var ln = newAdapter()
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)

    pushEvent(parseFile(Fixtures / "webhook_group_text.json"))
    discard drainLineEvents(ln, sm, replay, policy(groups = @[GroupChat]),
                            1_000'i64, fallback, nil, rtLog)

    check inbound.len == 1
    check inbound[0].chatId == GroupChat
    check inbound[0].channelId == GroupChat
    check inbound[0].rawChannelId == DmUser
    check inbound[0].isGroup

  test "matching is exact: C1x is not C1":
    var ln = newAdapter()
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)

    pushEvent(groupPayload("evt-c1x", DmUser, "C1x"))
    discard drainLineEvents(ln, sm, replay, policy(groups = @["C1"]),
                            1_000'i64, fallback, nil, rtLog)

    check inbound.len == 0

  test "two speakers in one group keep distinct identities and reply to the group":
    var ln = newAdapter()
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)

    pushEvent(groupPayload("evt-speaker-1", "Uaaa", GroupChat))
    pushEvent(groupPayload("evt-speaker-2", "Ubbb", GroupChat))
    discard drainLineEvents(ln, sm, replay, policy(groups = @[GroupChat]),
                            1_000'i64, fallback, nil, rtLog)

    check inbound.len == 2
    check inbound[0].userId != inbound[1].userId
    check inbound[0].chatId == GroupChat
    check inbound[1].chatId == GroupChat

suite "LINE runtime — routing agreement and local commands":

  setup:
    var a = newAdapter()
    drainQueue(a)

  test "lineRouting and toInbound agree for DM and group":
    let dm = parseWebhook(parseFile(Fixtures / "webhook_text.json"))[0]
    let dmUid = UserId("user-dm")
    check lineRouting(dm).identityId == toInbound(dm, dmUid).rawChannelId
    check lineRouting(dm).replyTarget == toInbound(dm, dmUid).chatId
    check lineRouting(dm).replyTarget == dm.senderId

    let group = parseWebhook(parseFile(Fixtures / "webhook_group_text.json"))[0]
    let groupUid = UserId("user-group")
    check lineRouting(group).identityId == toInbound(group, groupUid).rawChannelId
    check lineRouting(group).replyTarget == toInbound(group, groupUid).chatId
    check lineRouting(group).replyTarget == group.chatId
    check lineRouting(group).identityId != lineRouting(group).replyTarget

  test "/continue is local and never reaches the session fallback":
    let f = FakeHttp()
    var ln = newAdapter(f)
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)
    let sink = ReplySink()
    let enqueue = sinkFor(sink)

    pushEvent(dmPayload("evt-continue", "/continue ABCD1234"))
    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback,
                            enqueue, rtLog)

    check inbound.len == 0
    check sink.items.len == 1
    check sink.items[0].text == buildContinueResultText(false)
    check f.calls.len == 0

  test "/help falls through to the session fallback":
    var ln = newAdapter()
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)

    pushEvent(dmPayload("evt-help", "/help"))
    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback, nil, rtLog)

    check inbound.len == 1
    check inbound[0].text == "/help"

suite "LINE runtime — shared link codes":

  setup:
    var stale = newAdapter()
    drainQueue(stale)

  test "a code minted by the Telegram resolver links a LINE identity":
    ## F1: `/mycode` on Telegram and `/continue` on LINE use different
    ## resolvers built from the same identity file. Sharing the path must share
    ## the pending-code table, so a code minted on one channel is redeemable on
    ## the other in the same process.
    let path = LineTmp / "shared_codes_telegram_line.tsv"
    removeFile(path)
    let tg = newIdentityResolver(path)
    let target = tg.resolve(ckTelegram, "460001")
    let code = tg.generateLinkCode(target)

    let f = FakeHttp()
    var ln = newLineAdapter("test-channel-access-token", path,
                            apiBase = "https://line.test", http = fake(f))
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)

    let sink = ReplySink()
    let enqueue = sinkFor(sink)

    pushEvent(dmPayload("evt-shared-link", "/continue " & code))
    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback,
                            enqueue, rtLog)

    check inbound.len == 0
    check sink.items.len == 1
    check sink.items[0].text == buildContinueResultText(true)
    check f.calls.len == 0
    check ln.resolver.lookup(ckLine, DmUser) == some(target)

  test "a shared link code is single-use":
    let path = LineTmp / "shared_codes_single_use.tsv"
    removeFile(path)
    let tg = newIdentityResolver(path)
    let target = tg.resolve(ckTelegram, "460002")
    let code = tg.generateLinkCode(target)

    let f = FakeHttp()
    var ln = newLineAdapter("test-channel-access-token", path,
                            apiBase = "https://line.test", http = fake(f))
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    let fallback = proc(msg: InboundMessage) {.gcsafe.} = discard
    let sink = ReplySink()
    let enqueue = sinkFor(sink)

    pushEvent(dmPayload("evt-shared-first", "/continue " & code))
    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback,
                            enqueue, rtLog)
    check sink.items.len == 1
    check sink.items[0].text == buildContinueResultText(true)
    check ln.resolver.lookup(ckLine, DmUser) == some(target)

    pushEvent(dmPayload("evt-shared-second", "/continue " & code))
    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback,
                            enqueue, rtLog)
    check sink.items.len == 2
    check sink.items[1].text == buildContinueResultText(false)
    check f.calls.len == 0
    check not ln.resolver.consumeLinkCode(code, ckLine, "Usecond-redemption")

  test "an expired shared link code is rejected":
    let path = LineTmp / "shared_codes_expired.tsv"
    removeFile(path)
    let target = UserId("expired-link-target")
    let code = sharedLinkCodeService(path).mint(
      target,
      now = getTime() - initDuration(seconds = LinkCodeTtlSec + 1))

    let f = FakeHttp()
    var ln = newLineAdapter("test-channel-access-token", path,
                            apiBase = "https://line.test", http = fake(f))
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    let fallback = proc(msg: InboundMessage) {.gcsafe.} = discard
    let sink = ReplySink()
    let enqueue = sinkFor(sink)

    pushEvent(dmPayload("evt-shared-expired", "/continue " & code))
    discard drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback,
                            enqueue, rtLog)

    check sink.items.len == 1
    check sink.items[0].text == buildContinueResultText(false)
    check f.calls.len == 0
    check ln.resolver.lookup(ckLine, DmUser) != some(target)

suite "LINE runtime — /continue reply is enqueued, never posted inline":
  ## F2: the drain runs on the daemon thread; a synchronous LINE POST would
  ## freeze every other channel for up to the 30 s transport timeout. The
  ## confirmation is handed to the outbox instead.

  setup:
    var stale = newAdapter()
    drainQueue(stale)

  test "a valid code enqueues one reply and makes no HTTP call":
    let path = LineTmp / "enqueue_valid_codes.tsv"
    removeFile(path)
    let target = UserId("enqueue-target")
    let code = sharedLinkCodeService(path).mint(target)

    let f = FakeHttp()
    var ln = newLineAdapter("test-channel-access-token", path,
                            apiBase = "https://line.test", http = fake(f))
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)
    let sink = ReplySink()
    let enqueue = sinkFor(sink)
    ## The speaker identity the drain authorizes; redeeming the code re-points
    ## the LINE mapping to the code's target, so capture it before the drain.
    let lineUser = ln.resolver.resolve(ckLine, DmUser)

    pushEvent(dmPayload("evt-enqueue-continue", "/continue " & code))
    let turns = drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback,
                                enqueue, rtLog)

    check turns == 1
    check inbound.len == 0
    check sink.items.len == 1
    check sink.items[0].text == buildContinueResultText(true)
    check sink.items[0].channel == ckLine
    check sink.items[0].replyTo == DmUser
    check sink.items[0].userId == lineUser
    check f.calls.len == 0

  test "a nil enqueueReply logs and drops without crashing":
    let f = FakeHttp()
    var ln = newAdapter(f)
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    let fallback = proc(msg: InboundMessage) {.gcsafe.} = discard
    var logs: seq[string] = @[]
    let capture = newLogger("test.line_runtime.capture", lvlError,
      proc(entry: LogEntry) {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          logs.add entry.message)

    pushEvent(dmPayload("evt-nil-enqueue", "/continue ABCD1234"))
    let turns = drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback,
                                nil, capture)

    check turns == 1
    check f.calls.len == 0
    check logs.len == 1
    check logs[0].contains("no outbox")
    check not ln.tryRecvEvent()[0]

  test "a failed enqueue is logged and the rest of the batch still runs":
    let f = FakeHttp()
    var ln = newAdapter(f)
    var sm: SessionManager
    sm.init()
    var replay = LineReplayCache()
    var inbound: seq[InboundMessage] = @[]
    let fallback = proc(msg: InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        inbound.add(msg)
    let failing = proc(msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
      discard msg
      err("outbox full")
    var logs: seq[string] = @[]
    let capture = newLogger("test.line_runtime.capture", lvlError,
      proc(entry: LogEntry) {.closure, gcsafe.} =
        {.cast(gcsafe).}:
          logs.add entry.message)

    pushEvent(dmPayload("evt-enqueue-fails", "/continue ABCD1234"))
    pushEvent(dmPayload("evt-after-enqueue-fails", "still here"))
    let turns = drainLineEvents(ln, sm, replay, policy(), 1_000'i64, fallback,
                                failing, capture)

    check turns == 2
    check inbound.len == 1
    check inbound[0].text == "still here"
    check f.calls.len == 0
    check logs.len == 1
    check logs[0].contains("outbox full")
    check not ln.tryRecvEvent()[0]  ## the whole batch was consumed
