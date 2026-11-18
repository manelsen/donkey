## LineAdapter — outbound tests (US-004).
##
## Every HTTP call goes through a fake HttpRuntimePort: no network, no LINE
## account and no real credential. The adapter is the only place that knows
## the LINE endpoints; the pure parser/policy live in domain/channels.

import std/[unicode, json, os, strutils, tables, times, unittest]
import donkey/adapters/channel/line
import donkey/core/channels/flood_gate
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/line_pure
import donkey/domain/message
import donkey/ports/channel
import donkey/ports/http

const
  TestToken = "test-channel-access-token-0001"

static:
  ## The adapter must keep the shared port shape even though LINE is
  ## webhook-driven.
  doAssert LineAdapter is ChannelPort

type
  Recorded = object
    url:     string
    body:    string
    headers: seq[HttpHeader]

  FakeLine = ref object
    calls:           seq[Recorded]
    status:          int
    body:            string
    responseHeaders: seq[HttpHeader]
    transportError:  string

proc newFake(): FakeLine =
  FakeLine(status: 200, body: "{}")

proc handle(f: FakeLine; url, body: string;
            headers: seq[HttpHeader]): Result[HttpResponse, string] {.gcsafe.} =
  f.calls.add Recorded(url: url, body: body, headers: headers)
  if f.transportError.len > 0:
    return err(f.transportError)
  ok(HttpResponse(status: f.status, body: f.body, headers: f.responseHeaders))

proc fake(f: FakeLine): HttpRuntimePort =
  HttpRuntimePort(
    post: proc(url, body: string; headers: seq[HttpHeader] = @[]):
               Result[HttpResponse, string] {.gcsafe.} =
      handle(f, url, body, headers)
  )

proc headerValue(headers: seq[HttpHeader]; name: string): string =
  for (key, value) in headers:
    if key.toLowerAscii() == name.toLowerAscii():
      return value
  ""

var idsSeq = 0

proc newTestAdapter(f: FakeLine; token = TestToken): LineAdapter =
  inc idsSeq
  let path = getTempDir() / ("donkey_line_ids_" & $idsSeq & ".tsv")
  removeFile(path)
  newLineAdapter(token, path, apiBase = "https://line.test", http = fake(f))

proc sentJson(f: FakeLine; index = 0): JsonNode =
  parseJson(f.calls[index].body)

# ── 1. push target: replyTo wins, remembered chat is the fallback ─────────────

suite "LineAdapter — push target":

  test "replyTo wins over the remembered chat":
    let f = newFake()
    var a = newTestAdapter(f)
    let uid = a.resolver.resolve(ckLine, "U1")
    a.rememberChat("U1", "C1")
    let res = a.send(OutboundMessage(userId: uid, channel: ckLine,
                                     text: "hi", replyTo: "C2"))
    check res.isOk
    check f.calls.len == 1
    check f.calls[0].url == "https://line.test/v2/bot/message/push"
    check sentJson(f)["to"].getStr == "C2"

  test "the remembered chat is used when replyTo is absent":
    let f = newFake()
    var a = newTestAdapter(f)
    let uid = a.resolver.resolve(ckLine, "U1")
    a.rememberChat("U1", "C1")
    let res = a.send(OutboundMessage(userId: uid, channel: ckLine, text: "hello group"))
    check res.isOk
    check f.calls.len == 1
    check sentJson(f)["to"].getStr == "C1"

  test "a DM without a remembered chat targets the raw sender id":
    let f = newFake()
    var a = newTestAdapter(f)
    let uid = a.resolver.resolve(ckLine, "U2")
    let res = a.send(OutboundMessage(userId: uid, channel: ckLine, text: "hello dm"))
    check res.isOk
    check sentJson(f)["to"].getStr == "U2"

  test "internal prefixes never reach the API":
    let f = newFake()
    let a = newTestAdapter(f)
    for (replyTo, expected) in [("group:C3", "C3"), ("room:R4", "R4"),
                                ("user:U5", "U5"), ("U6", "U6")]:
      let res = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                       text: "x", replyTo: replyTo))
      check res.isOk
      check sentJson(f, f.calls.len - 1)["to"].getStr == expected

  test "the Authorization header carries the bearer token":
    let f = newFake()
    let a = newTestAdapter(f)
    check a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                 text: "x", replyTo: "U9")).isOk
    check headerValue(f.calls[0].headers, "Authorization") == "Bearer " & TestToken
    check headerValue(f.calls[0].headers, "Content-Type").contains("application/json")

  test "the body is one text message with the raw target":
    let f = newFake()
    let a = newTestAdapter(f)
    check a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                 text: "olá LINE", replyTo: "C7")).isOk
    let body = sentJson(f)
    check body["messages"].len == 1
    check body["messages"][0]["type"].getStr == "text"
    check body["messages"][0]["text"].getStr == "olá LINE"

# ── 2. reply token path ──────────────────────────────────────────────────────

suite "LineAdapter — reply token":

  test "sendReply uses /message/reply with the token":
    let f = newFake()
    let a = newTestAdapter(f)
    let res = a.sendReply("reply-token-1", "hello")
    check res.isOk
    check f.calls.len == 1
    check f.calls[0].url == "https://line.test/v2/bot/message/reply"
    let body = sentJson(f)
    check body["replyToken"].getStr == "reply-token-1"
    check not body.hasKey("to")
    check body["messages"][0]["text"].getStr == "hello"

  test "a 400 on reply never falls back to push":
    let f = newFake()
    f.status = 400
    f.body = """{"message":"Invalid reply token"}"""
    let a = newTestAdapter(f)
    let res = a.sendReply("expired-token", "hello")
    check res.isErr
    check f.calls.len == 1
    check f.calls[0].url.endsWith("/v2/bot/message/reply")
    check not f.calls[0].url.contains("/push")
    check res.error.contains("400")

  test "an empty reply token is refused without an HTTP call":
    let f = newFake()
    let a = newTestAdapter(f)
    let res = a.sendReply("  ", "hello")
    check res.isErr
    check res.error.contains("reply token")
    check f.calls.len == 0

# ── 3. flood / retry policy ──────────────────────────────────────────────────

suite "LineAdapter — flood and retries":

  test "a 429 records the window and is not retried immediately":
    let f = newFake()
    f.status = 429
    f.body = """{"message":"rate limited","retry_after":30}"""
    let a = newTestAdapter(f)
    let res = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                     text: "x", replyTo: "U1"))
    check res.isErr
    check f.calls.len == 1
    check a.flood.remainingMs(0, epochMs()) > 0

  test "a second send inside the 429 window makes no HTTP call":
    let f = newFake()
    f.status = 429
    f.body = """{"message":"rate limited","retry_after":30}"""
    let a = newTestAdapter(f)
    discard a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                   text: "first", replyTo: "U1"))
    let second = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                        text: "second", replyTo: "U1"))
    check second.isErr
    check f.calls.len == 1

  test "a standard Retry-After header is honored":
    let f = newFake()
    f.status = 429
    f.body = "{}"
    f.responseHeaders = @[("Retry-After", "42")]
    let a = newTestAdapter(f)
    let res = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                     text: "x", replyTo: "U1"))
    check res.isErr
    check a.flood.remainingMs(0, epochMs()) > 30_000

  test "a non-idempotent 500 is reported without a retry":
    let f = newFake()
    f.status = 500
    f.body = """{"message":"internal error"}"""
    let a = newTestAdapter(f)
    let res = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                     text: "x", replyTo: "U1"))
    check res.isErr
    check f.calls.len == 1
    check res.error.contains("500")

# ── 4. errors never leak the token or a URL with query ──────────────────────

suite "LineAdapter — error hygiene":

  test "a transport error does not echo the token or the URL":
    let f = newFake()
    f.transportError =
      "POST https://line.test/v2/bot/message/push?access_token=" & TestToken & " failed"
    let a = newTestAdapter(f)
    let res = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                     text: "x", replyTo: "U1"))
    check res.isErr
    check not res.error.contains(TestToken)
    check not res.error.contains("access_token")
    check not res.error.contains("https://")
    check not res.error.contains("?")

  test "an HTTP error body containing the token is redacted":
    let f = newFake()
    f.status = 401
    f.body = """{"message":"invalid token """ & TestToken & """"}"""
    let a = newTestAdapter(f)
    let res = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                     text: "x", replyTo: "U1"))
    check res.isErr
    check res.error.contains("401")
    check not res.error.contains(TestToken)

  test "a missing token is an error and makes no HTTP call":
    let f = newFake()
    let a = newTestAdapter(f, token = "")
    let res = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                     text: "x", replyTo: "U1"))
    check res.isErr
    check res.error.contains("token")
    check f.calls.len == 0

  test "the token comes from LINE_CHANNEL_ACCESS_TOKEN when not supplied":
    let previous = getEnv("LINE_CHANNEL_ACCESS_TOKEN")
    putEnv("LINE_CHANNEL_ACCESS_TOKEN", "env-token-42")
    defer:
      if previous.len > 0: putEnv("LINE_CHANNEL_ACCESS_TOKEN", previous)
      else: delEnv("LINE_CHANNEL_ACCESS_TOKEN")
    let f = newFake()
    let a = newTestAdapter(f, token = "")
    check a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                 text: "x", replyTo: "U1")).isOk
    check headerValue(f.calls[0].headers, "Authorization") == "Bearer env-token-42"

# ── 5. long text boundary and empty text ────────────────────────────────────

suite "LineAdapter — text length":

  test "4500 characters fit in one bubble and 4501 need two":
    check buildPushBody("U1", repeat('a', LineChunkChars))["messages"].len == 1
    check buildPushBody("U1", repeat('a', LineChunkChars + 1))["messages"].len == 2

  test "12k characters become three bubbles":
    let body = buildPushBody("U1", repeat('a', 12_000))
    check body["messages"].len == 3
    for msg in body["messages"]:
      check msg["text"].getStr.len <= LineMaxChars

  test "more than five bubbles are ellipsised on the last one":
    let exact = buildPushBody("U1", repeat('a', LineChunkChars * LineMaxBubbles))
    check exact["messages"].len == LineMaxBubbles
    check not exact["messages"][^1]["text"].getStr.endsWith("…")

    let overflow = buildPushBody("U1", repeat('a', LineChunkChars * LineMaxBubbles + 1))
    check overflow["messages"].len == LineMaxBubbles
    let last = overflow["messages"][^1]["text"].getStr
    check last.endsWith("…")
    check last.len <= LineMaxChars

  test "send carries all chunks in one push call":
    let f = newFake()
    let a = newTestAdapter(f)
    check a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                 text: repeat('b', 12_000), replyTo: "U1")).isOk
    check f.calls.len == 1
    let body = parseJson(f.calls[0].body)
    check body["messages"].len == 3
    for msg in body["messages"]:
      check msg["text"].getStr.len <= LineChunkChars

  test "empty or whitespace-only text makes no HTTP call":
    let f = newFake()
    let a = newTestAdapter(f)
    check a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                 text: "", replyTo: "U1")).isOk
    check a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                 text: "   \n\t", replyTo: "U1")).isOk
    check f.calls.len == 0

# ── 6. media is refused explicitly ──────────────────────────────────────────

suite "LineAdapter — media contract":

  test "mediaUrl is refused, not silently dropped":
    let f = newFake()
    let a = newTestAdapter(f)
    let res = a.send(OutboundMessage(userId: UserId("u"), channel: ckLine,
                                     text: "caption", replyTo: "U1",
                                     mediaUrl: "https://example.test/a.png"))
    check res.isErr
    check res.error.toLowerAscii().contains("media")
    check f.calls.len == 0

  test "downloadFile reports media unsupported":
    let a = newTestAdapter(newFake())
    let res = a.downloadFile("468789577898262530")
    check res.isErr
    check res.error.toLowerAscii().contains("media")

# ── 7. queue: pushEvent → tryRecvEvent remembers the chat ───────────────────

suite "LineAdapter — webhook queue":

  test "the text fixture is dequeued and remembers the DM chat":
    let f = newFake()
    var a = newTestAdapter(f)
    a.openQueue()
    pushEvent(parseFile("tests/fixtures/line/webhook_text.json"))
    let (has, ev) = a.tryRecvEvent()
    check has
    check ev.text == "Hello from LINE"
    check ev.senderId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
    check ev.chatId == ev.senderId
    ## Dequeuing no longer remembers the chat: the runtime records it after the
    ## policy accepts the event (a denied group must not become the target).
    check a.chatIds.getOrDefault(ev.senderId, "") == ""
    a.rememberChat(ev.senderId, ev.chatId)
    check a.chatIds.getOrDefault(ev.senderId, "") == ev.chatId

  test "a group event remembers the group, not the speaker":
    let f = newFake()
    var a = newTestAdapter(f)
    a.openQueue()
    # Drain anything a previous test queued before opening this adapter.
    while a.tryRecvEvent()[0]: discard
    pushEvent(parseFile("tests/fixtures/line/webhook_group_text.json"))
    let (has, ev) = a.tryRecvEvent()
    check has
    check ev.senderId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
    check ev.chatId == "C1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6"
    check a.chatIds.getOrDefault(ev.senderId, "") == ""
    a.rememberChat(ev.senderId, ev.chatId)
    check a.chatIds.getOrDefault(ev.senderId, "") == ev.chatId

    let uid = a.resolver.resolve(ckLine, ev.senderId)
    check a.send(OutboundMessage(userId: uid, channel: ckLine,
                                 text: "answer")).isOk
    check sentJson(f)["to"].getStr == ev.chatId

  test "an empty events payload enqueues nothing":
    var a = newTestAdapter(newFake())
    a.openQueue()
    while a.tryRecvEvent()[0]: discard
    pushEvent(parseFile("tests/fixtures/line/webhook_empty_events.json"))
    let (has, _) = a.tryRecvEvent()
    check not has

suite "splitForLine — UTF-16 units":

  test "an emoji counts as two units":
    ## LINE's 4,500 limit is in UTF-16 code units; 3,000 emoji are 6,000 units
    ## and must not fit in one bubble.
    let emoji = "😀"
    let text = emoji.repeat(3000)
    let parts = splitForLine(text)
    check parts.len >= 2
    for part in parts:
      var units = 0
      for r in part.runes:
        units += (if int(r) > 0xFFFF: 2 else: 1)
      check units <= 4500

suite "LineAdapter — invalid configuration fails closed":

  test "an invalid base does not raise; sends return an error":
    ## No injected transport: an injected fake is the documented way to use a
    ## plain-http loopback in tests, and validation is skipped for it.
    let adapter = newLineAdapter("tok", "/tmp/line-invalid.tsv",
                                 apiBase = "http://api.line.me")
    check adapter.configError.len > 0
    let res = adapter.send(OutboundMessage(userId: UserId("U1"),
                                           channel: ckLine, text: "oi",
                                           replyTo: "U1"))
    check res.isErr
    check res.error.contains("apiBase")
