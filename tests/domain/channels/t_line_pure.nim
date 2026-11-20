## Tests for domain/channels/line_pure.nim — pure LINE Messaging API webhook parser.
##
## No I/O beyond reading static fixtures; no HTTP, no channel account.
## Protocol facts come from the PRD (§1) and from Hermes' read-only
## `plugins/platforms/line/adapter.py` (`_resolve_chat`, `_dispatch_event`):
##   - payload is `{"events":[…]}` (LINE OpenAPI `webhook.yml`);
##   - `mode` is `active` or `standby` (standby = another module answers);
##   - `deliveryContext.isRedelivery` is telemetry only, never a drop reason;
##   - `source{type,userId,groupId,roomId}`; in group/room `userId` is the
##     speaker and `groupId`/`roomId` is the conversation;
##   - `message{type,id,text}`; any lowercase `type` other than "text" is a
##     non-text message (sticker, image, …).

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/line_pure

const FixtureDir = "tests/fixtures/line/"

proc fixture(name: string): string =
  readFile(FixtureDir & name)

# ── Empty / malformed payloads ────────────────────────────────────────────────

proc runTests*() =
  suite "parseLineWebhook empty and malformed payloads":
    test "console Verify payload (empty events) is ok and empty":
      let res = parseLineWebhook(fixture("webhook_empty_events.json"))
      check res.isOk
      check res.get().len == 0

    test "missing events field yields an empty seq":
      let res = parseLineWebhook("""{"destination":"Ubot"}""")
      check res.isOk
      check res.get().len == 0

    test "non-array events yields an empty seq":
      let res = parseLineWebhook("""{"events":{"type":"message"}}""")
      check res.isOk
      check res.get().len == 0

    test "malformed JSON is an err, never an exception":
      let res = parseLineWebhook("""{"events":[""")
      check res.isErr
      check res.error().len > 0

    test "empty body is an err":
      check parseLineWebhook("").isErr

    test "top-level non-object is an err":
      check parseLineWebhook("""[]""").isErr

    test "parseWebhook(JsonNode) never fails: nil payload is @[]":
      check parseWebhook(nil).len == 0
      check parseWebhook(%* {"events": []}).len == 0

    test "non-object entries inside events are skipped":
      let res = parseLineWebhook("""{"events":["junk",42,null]}""")
      check res.isOk
      check res.get().len == 0

  # ── Text event (DM) ───────────────────────────────────────────────────────────

  suite "parseLineWebhook text message":
    test "parses a DM text event":
      let res = parseLineWebhook(fixture("webhook_text.json"))
      check res.isOk
      let events = res.get()
      check events.len == 1
      let e = events[0]
      check e.sourceKind == lskUser
      check e.contentKind == lckText
      check e.mode == lmActive
      check not e.isRedelivery
      check e.senderId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
      check e.chatId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
      check e.text == "Hello from LINE"
      check e.messageId == "468789577898262530"
      check e.eventId == "01H8Y6Q4Z3J9K2M5N7P8R9S0T1"
      check e.replyToken == "b6f0d5c1e2a34f5b8c9d0e1f2a3b4c5d"

    test "rawId and webhookEventId accessors alias senderId and eventId":
      let e = parseLineWebhook(fixture("webhook_text.json")).get()[0]
      check e.rawId == e.senderId
      check e.webhookEventId == e.eventId

    test "isRedelivery is read from deliveryContext for telemetry":
      let res = parseLineWebhook("""{"events":[{
      "type":"message","mode":"active","webhookEventId":"evt-redeliver",
      "deliveryContext":{"isRedelivery":true},
      "source":{"type":"user","userId":"U1"},
      "message":{"id":"m1","type":"text","text":"again"}}]}""")
      check res.isOk
      let e = res.get()[0]
      check e.isRedelivery
      check e.text == "again"   ## redelivery never suppresses the parse

    test "missing mode defaults to active":
      let res = parseLineWebhook("""{"events":[{
      "type":"message","webhookEventId":"evt-nomode",
      "source":{"type":"user","userId":"U1"},
      "message":{"id":"m1","type":"text","text":"hi"}}]}""")
      check res.isOk
      check res.get()[0].mode == lmActive

  # ── Group / room source ───────────────────────────────────────────────────────

  suite "parseLineWebhook group and room sources":
    test "group event keeps speaker and chat separate":
      let res = parseLineWebhook(fixture("webhook_group_text.json"))
      check res.isOk
      let e = res.get()[0]
      check e.sourceKind == lskGroup
      check e.contentKind == lckText
      check e.senderId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
      check e.chatId == "C1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6"
      check e.senderId != e.chatId
      check e.text == "Group hello"
      check e.eventId == "01H8Y6Q4Z3J9K2M5N7P8R9S0T2"
      check e.replyToken == "c7e1d6b2f3a44c6b9d0e1f2a3b4c5d6e"

    test "room event uses roomId as chat and userId as sender":
      let res = parseLineWebhook("""{"events":[{
      "type":"message","mode":"active","webhookEventId":"evt-room",
      "source":{"type":"room","roomId":"R1room","userId":"U2speaker"},
      "message":{"id":"m2","type":"text","text":"room hello"}}]}""")
      check res.isOk
      let e = res.get()[0]
      check e.sourceKind == lskRoom
      check e.senderId == "U2speaker"
      check e.chatId == "R1room"

    test "unknown source type is lskUnknown and does not become a chat":
      let res = parseLineWebhook("""{"events":[{
      "type":"message","mode":"active","webhookEventId":"evt-nosource",
      "source":{"type":"bot"},
      "message":{"id":"m3","type":"text","text":"hi"}}]}""")
      check res.isOk
      check res.get()[0].sourceKind == lskUnknown
      check res.get()[0].chatId == ""

  # ── Non-text content ──────────────────────────────────────────────────────────

  suite "parseLineWebhook non-text content":
    test "group sticker is lskGroup + lckNonText":
      let res = parseLineWebhook(fixture("webhook_group_sticker.json"))
      check res.isOk
      let e = res.get()[0]
      check e.sourceKind == lskGroup
      check e.contentKind == lckNonText
      check e.senderId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
      check e.chatId == "C1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6"
      check e.messageId == "468789577898262541"
      check e.text == ""

  # ── Standby mode ──────────────────────────────────────────────────────────────

  suite "parseLineWebhook standby mode":
    test "standby event is parsed and marked for the runtime to drop":
      let res = parseLineWebhook(fixture("webhook_standby.json"))
      check res.isOk
      let e = res.get()[0]
      check e.mode == lmStandby
      check e.contentKind == lckText
      check e.senderId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
      check e.messageId == "468789577898262550"
      check e.text == "Handled by another module"

  # ── Non-message events ────────────────────────────────────────────────────────

  suite "parseLineWebhook non-message events":
    test "follow, postback and unfollow are all lckUnknown":
      let res = parseLineWebhook(fixture("webhook_non_message.json"))
      check res.isOk
      let events = res.get()
      check events.len == 3

      let follow = events[0]
      check follow.contentKind == lckUnknown
      check follow.sourceKind == lskUser
      check follow.text == ""
      check follow.messageId == ""
      check follow.eventId == "01H8Y6Q4Z3J9K2M5N7P8R9S0T5"
      check follow.replyToken.startsWith("f0b4")

      let postback = events[1]
      check postback.contentKind == lckUnknown
      check postback.text == ""
      check postback.messageId == ""
      check postback.eventId == "01H8Y6Q4Z3J9K2M5N7P8R9S0T6"
      check postback.replyToken == "a1c5b0f6d7e88a0f3b4c5d6e7f809102"

      let unfollow = events[2]
      check unfollow.contentKind == lckUnknown
      check unfollow.eventId == "01H8Y6Q4Z3J9K2M5N7P8R9S0T7"
      check unfollow.replyToken == ""

  # ── No silent mutations ───────────────────────────────────────────────────────

  suite "parseLineWebhook does not silently mutate fields":
    test "non-bool isRedelivery neither crashes nor becomes true":
      for raw in ["\"yes\"", "1", "null", "{}"]:
        let res = parseLineWebhook("""{"events":[{
        "type":"message","mode":"active","webhookEventId":"evt-bool",
        "deliveryContext":{"isRedelivery":""" & raw & """},
        "source":{"type":"user","userId":"U1"},
        "message":{"id":"m1","type":"text","text":"hi"}}]}""")
        check res.isOk
        check res.get()[0].text == "hi"
        check not res.get()[0].isRedelivery

    test "stray text on a non-text message stays empty":
      let res = parseLineWebhook("""{"events":[{
      "type":"message","mode":"active","webhookEventId":"evt-stray",
      "source":{"type":"group","groupId":"C1","userId":"U1"},
      "message":{"id":"m-img","type":"image","text":"must not leak"}}]}""")
      check res.isOk
      let e = res.get()[0]
      check e.contentKind == lckNonText
      check e.text == ""
      check e.messageId == "m-img"

    test "message event without message.type is lckUnknown, not text":
      let res = parseLineWebhook("""{"events":[{
      "type":"message","mode":"active","webhookEventId":"evt-notype",
      "source":{"type":"user","userId":"U1"},
      "message":{"id":"m-notype"}}]}""")
      check res.isOk
      let e = res.get()[0]
      check e.contentKind == lckUnknown
      check e.text == ""
      check e.messageId == ""

  # ── toInbound ─────────────────────────────────────────────────────────────────

  suite "toInbound":
    test "DM maps channel, speaker identity and DM reply target":
      let e = parseLineWebhook(fixture("webhook_text.json")).get()[0]
      let msg = toInbound(e, UserId("user-42"))
      check msg.channel == ckLine
      check msg.userId == UserId("user-42")
      check msg.rawChannelId == e.senderId
      check msg.channelId == e.chatId
      check msg.chatId == e.chatId
      check msg.chatId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
      check msg.messageId == "468789577898262530"
      check msg.text == "Hello from LINE"
      check not msg.isGroup

    test "group keeps speaker as rawChannelId and group as chat target":
      let e = parseLineWebhook(fixture("webhook_group_text.json")).get()[0]
      let msg = toInbound(e, UserId("user-42"))
      check msg.channel == ckLine
      check msg.rawChannelId == "U4af4980629a1c5f5b1a1f0e7b7a1e111"
      check msg.channelId == "C1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6"
      check msg.chatId == "C1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6"
      check msg.chatId != msg.rawChannelId
      check msg.isGroup

    test "room is a group chat whose target is roomId":
      let e = parseLineWebhook("""{"events":[{
      "type":"message","mode":"active","webhookEventId":"evt-room",
      "source":{"type":"room","roomId":"R1room","userId":"U2speaker"},
      "message":{"id":"m2","type":"text","text":"room hello"}}]}""").get()[0]
      let msg = toInbound(e, UserId("user-7"))
      check msg.channel == ckLine
      check msg.rawChannelId == "U2speaker"
      check msg.channelId == "R1room"
      check msg.chatId == "R1room"
      check msg.isGroup

    test "unknown source is still a non-DM chat with no target":
      let e = parseLineWebhook("""{"events":[{
      "type":"message","mode":"active","webhookEventId":"evt-bot",
      "source":{"type":"bot","userId":"Ubot"},
      "message":{"id":"m3","type":"text","text":"hi"}}]}""").get()[0]
      let msg = toInbound(e, UserId("user-9"))
      check msg.channel == ckLine
      check msg.rawChannelId == "Ubot"
      check msg.chatId == ""
      check msg.channelId == ""
      check msg.isGroup

  # ── lineTarget: internal prefixes never leak to the LINE API ──────────────────

  suite "lineTarget":
    test "strips internal group/room/user prefixes":
      check lineTarget("group:C1") == "C1"
      check lineTarget("room:R1") == "R1"
      check lineTarget("user:U1") == "U1"

    test "already-raw LINE ids pass through unchanged":
      check lineTarget("U1") == "U1"
      check lineTarget("C1a2b3") == "C1a2b3"
      check lineTarget("R1a2b3") == "R1a2b3"

    test "empty or prefix-only ids yield empty":
      check lineTarget("") == ""
      check lineTarget("group:") == ""

when isMainModule:
  runTests()
