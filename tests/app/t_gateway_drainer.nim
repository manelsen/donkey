## Unit tests for gateway_drainer.nim
## Tests:
##   - Event queue draining (polled & batch)
##   - Channel dispatch & fallback handling
##   - Empty event queues handling
##   - Channel configuration gates
##   - GatewayDrainer multi-channel sequencing

import std/unittest
import std/strutils
import donkey/core/types
import donkey/domain/message
import donkey/app/gateway_drainer

suite "gateway drainer — polled & batch queues":

  test "drainPolledGateway with empty queue does not trigger fallback":
    var fallbackCalls: seq[InboundMessage] = @[]
    let pollEmpty = proc(): (bool, InboundMessage) {.gcsafe.} =
      (false, InboundMessage())

    let count = drainPolledGateway(
      ckDingTalk,
      pollEmpty,
      proc(msg: InboundMessage) {.gcsafe.} =
        {.cast(gcsafe).}:
          fallbackCalls.add(msg)
    )
    check count == 0
    check fallbackCalls.len == 0

  test "drainPolledGateway dispatches queued messages in order":
    var queue: seq[InboundMessage] = @[
      InboundMessage(userId: UserId("u1"), channel: ckDingTalk, text: "msg1"),
      InboundMessage(userId: UserId("u2"), channel: ckDingTalk, text: "msg2"),
      InboundMessage(userId: UserId("u3"), channel: ckDingTalk, text: "msg3"),
    ]
    var dispatched: seq[InboundMessage] = @[]

    let pollQueue = proc(): (bool, InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        if queue.len > 0:
          let m = queue[0]
          queue.delete(0)
          (true, m)
        else:
          (false, InboundMessage())

    let count = drainPolledGateway(
      ckDingTalk,
      pollQueue,
      proc(msg: InboundMessage) {.gcsafe.} =
        {.cast(gcsafe).}:
          dispatched.add(msg)
    )
    check count == 3
    check dispatched.len == 3
    check dispatched[0].text == "msg1"
    check dispatched[1].text == "msg2"
    check dispatched[2].text == "msg3"
    check queue.len == 0

  test "drainPolledGateway skips empty or whitespace-only messages without media":
    var queue: seq[InboundMessage] = @[
      InboundMessage(userId: UserId("u1"), channel: ckMatrix, text: "   "),
      InboundMessage(userId: UserId("u2"), channel: ckMatrix, text: "", mediaUrl: "http://example.com/audio.ogg"),
      InboundMessage(userId: UserId("u3"), channel: ckMatrix, text: "valid text"),
    ]
    var dispatched: seq[InboundMessage] = @[]

    let pollQueue = proc(): (bool, InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        if queue.len > 0:
          let m = queue[0]
          queue.delete(0)
          (true, m)
        else:
          (false, InboundMessage())

    let count = drainPolledGateway(
      ckMatrix,
      pollQueue,
      proc(msg: InboundMessage) {.gcsafe.} =
        {.cast(gcsafe).}:
          dispatched.add(msg)
    )
    check count == 2
    check dispatched.len == 2
    check dispatched[0].mediaUrl == "http://example.com/audio.ogg"
    check dispatched[1].text == "valid text"

  test "drainBatchGateway with empty batch returns 0":
    var fallbackCalls: seq[InboundMessage] = @[]
    let pollEmptyBatch = proc(): seq[InboundMessage] {.gcsafe.} =
      @[]

    let count = drainBatchGateway(
      ckTelegram,
      pollEmptyBatch,
      dispatchHandler = proc(msg: InboundMessage): bool {.gcsafe.} = true,
      fallbackHandler = proc(msg: InboundMessage) {.gcsafe.} =
        {.cast(gcsafe).}:
          fallbackCalls.add(msg)
    )
    check count == 0
    check fallbackCalls.len == 0

  test "drainBatchGateway routes between dispatch and fallback":
    let batch: seq[InboundMessage] = @[
      InboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "/start"),
      InboundMessage(userId: UserId("u2"), channel: ckTelegram, text: "regular prompt"),
    ]
    var handledByPrimary: seq[string] = @[]
    var handledByFallback: seq[string] = @[]

    let count = drainBatchGateway(
      ckTelegram,
      proc(): seq[InboundMessage] {.gcsafe.} =
        {.cast(gcsafe).}: batch,
      dispatchHandler = proc(msg: InboundMessage): bool {.gcsafe.} =
        if msg.text.startsWith("/"):
          {.cast(gcsafe).}:
            handledByPrimary.add(msg.text)
          true
        else:
          false,
      fallbackHandler = proc(msg: InboundMessage) {.gcsafe.} =
        {.cast(gcsafe).}:
          handledByFallback.add(msg.text)
    )
    check count == 2
    check handledByPrimary == @["/start"]
    check handledByFallback == @["regular prompt"]

suite "gateway drainer — channel configuration gates":

  test "drainDingTalkGateway respects configured flag":
    var pollInvoked = false
    let dummyPoll = proc(): (bool, InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        pollInvoked = true
      (false, InboundMessage())

    let unconfCount = drainDingTalkGateway(
      configured = false,
      pollEvent = dummyPoll,
      fallbackHandler = nil
    )
    check unconfCount == 0
    check not pollInvoked

    let confCount = drainDingTalkGateway(
      configured = true,
      pollEvent = dummyPoll,
      fallbackHandler = nil
    )
    check confCount == 0
    check pollInvoked

  test "drainMatrixGateway respects configured flag":
    var pollInvoked = false
    let dummyPoll = proc(): (bool, InboundMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        pollInvoked = true
      (false, InboundMessage())

    let unconfCount = drainMatrixGateway(
      configured = false,
      pollEvent = dummyPoll,
      fallbackHandler = nil
    )
    check unconfCount == 0
    check not pollInvoked

    let confCount = drainMatrixGateway(
      configured = true,
      pollEvent = dummyPoll,
      fallbackHandler = nil
    )
    check confCount == 0
    check pollInvoked

  test "drainTelegramGateway respects configured flag":
    var pollInvoked = false
    let dummyPoll = proc(): seq[InboundMessage] {.gcsafe.} =
      {.cast(gcsafe).}:
        pollInvoked = true
      @[]

    let unconfCount = drainTelegramGateway(
      configured = false,
      pollBatch = dummyPoll,
      dispatchHandler = nil,
      fallbackHandler = nil
    )
    check unconfCount == 0
    check not pollInvoked

    let confCount = drainTelegramGateway(
      configured = true,
      pollBatch = dummyPoll,
      dispatchHandler = nil,
      fallbackHandler = nil
    )
    check confCount == 0
    check pollInvoked

  test "drainDiscordGateway and simple gateways respect configured flag":
    var executed = false
    let dummyDrain = proc(): bool {.gcsafe.} =
      {.cast(gcsafe).}:
        executed = true
      true

    check not drainDiscordGateway(configured = false, drainFn = dummyDrain)
    check not executed

    check drainDiscordGateway(configured = true, drainFn = dummyDrain)
    check executed

suite "gateway drainer — GatewayDrainer sequencing":

  test "drainGatewayEvents iterates across channels in order":
    var channelLog: seq[string] = @[]

    let drainer = initGatewayDrainer(
      drainDiscord   = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("dc")
        true,
      drainWeCom     = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("wc")
        true,
      drainWeChat    = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("wch")
        true,
      drainFeishu    = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("fs")
        true,
      drainQQ        = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("qq")
        true,
      drainDingTalk  = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("dt")
        true,
      drainMatrix    = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("mx")
        true,
      drainTelegram  = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("tg")
        true,
      drainWhatsApp  = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("wa")
        true,
    )

    let total = drainGatewayEvents(drainer)
    check total == 9
    check channelLog == @["dc", "wc", "wch", "fs", "qq", "dt", "mx", "tg", "wa"]

  test "drainGatewayEvents skips unconfigured (nil) channels safely":
    var channelLog: seq[string] = @[]

    let drainer = initGatewayDrainer(
      drainDiscord  = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("dc")
        true,
      drainTelegram = proc(): bool {.gcsafe.} =
        {.cast(gcsafe).}: channelLog.add("tg")
        true,
    )

    let total = drainGatewayEvents(drainer)
    check total == 2
    check channelLog == @["dc", "tg"]

  test "empty GatewayDrainer safely returns 0 without crashing":
    let drainer = initGatewayDrainer()
    let total = drainGatewayEvents(drainer)
    check total == 0
