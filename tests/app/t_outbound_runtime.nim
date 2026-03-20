import std/[tables, unittest]
import donkey/app/outbound_runtime
import donkey/domain/message

suite "outbound_runtime":

  test "classifyOutbound returns immediate without stream id":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "hi")
    check classifyOutbound(msg, initTable[string, string]()) == okImmediate

  test "classifyOutbound returns stream create when stream id is new":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "hi", streamId: "s1")
    check classifyOutbound(msg, initTable[string, string]()) == okStreamCreate

  test "classifyOutbound returns stream update when stream id exists":
    var streamIds = initTable[string, string]()
    streamIds["s1"] = "m42"
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "hi", streamId: "s1")
    check classifyOutbound(msg, streamIds) == okStreamUpdate

  test "decideStreamAction includes existing message id":
    var streamIds = initTable[string, string]()
    streamIds["s1"] = "m42"
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckDiscord, text: "hi", streamId: "s1")
    let action = decideStreamAction(msg, streamIds)
    check action.kind == okStreamUpdate
    check action.existingMsgId == "m42"

  test "isImplementedOutboundChannel matches supported channels":
    check isImplementedOutboundChannel(ckTelegram)
    check isImplementedOutboundChannel(ckDiscord)
    check isImplementedOutboundChannel(ckWeCom)
    check isImplementedOutboundChannel(ckWeChat)
    check isImplementedOutboundChannel(ckQQ)
    check isImplementedOutboundChannel(ckFeishu)

  test "shouldClearStream only on final streamed message":
    let partial = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "hi",
                                  streamId: "s1", isPartial: true)
    let final = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "done",
                                streamId: "s1", isPartial: false)
    let immediate = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "done")
    check not shouldClearStream(partial)
    check shouldClearStream(final)
    check not shouldClearStream(immediate)

  test "applyStreamCleanup removes final stream id":
    var streamIds = initTable[string, string]()
    streamIds["s1"] = "m42"
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "done",
                              streamId: "s1", isPartial: false)
    applyStreamCleanup(msg, streamIds)
    check "s1" notin streamIds
