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

  test "classifyOutbound suppresses partial stream on non-editable channels":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckWeChat, text: "hi",
                              streamId: "s1", isPartial: true)
    check classifyOutbound(msg, initTable[string, string]()) == okSuppress

  test "classifyOutbound falls back to immediate final on non-editable channels":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckWeChat, text: "done",
                              streamId: "s1", isPartial: false)
    check classifyOutbound(msg, initTable[string, string]()) == okImmediate

  test "decideStreamAction includes existing message id":
    var streamIds = initTable[string, string]()
    streamIds["s1"] = "m42"
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckDiscord, text: "hi", streamId: "s1")
    let action = decideStreamAction(msg, streamIds)
    check action.kind == okStreamUpdate
    check action.existingMsgId == "m42"

  test "toOutboundIntent maps kinds to intents":
    check toOutboundIntent(okImmediate) == oiSend
    check toOutboundIntent(okStreamCreate) == oiStreamCreate
    check toOutboundIntent(okStreamUpdate) == oiStreamUpdate
    check toOutboundIntent(okSuppress) == oiSuppress

  test "decideOutbound returns suppression and cleanup intent":
    let partial = OutboundMessage(userId: UserId("u1"), channel: ckFeishu, text: "hi",
                                  streamId: "s1", isPartial: true)
    let final = OutboundMessage(userId: UserId("u1"), channel: ckFeishu, text: "done",
                                streamId: "s1", isPartial: false)
    let partialDecision = decideOutbound(partial, initTable[string, string]())
    let finalDecision = decideOutbound(final, initTable[string, string]())
    check partialDecision.intent == oiSuppress
    check not partialDecision.shouldCleanup
    check finalDecision.intent == oiSend
    check finalDecision.shouldCleanup

  test "supportsEditableStreams is only true for editable channels":
    check supportsEditableStreams(ckTelegram)
    check supportsEditableStreams(ckDiscord)
    check not supportsEditableStreams(ckWeCom)
    check not supportsEditableStreams(ckWeChat)
    check not supportsEditableStreams(ckQQ)
    check not supportsEditableStreams(ckFeishu)

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

  test "withStreamCleanup removes final stream id":
    var streamIds = initTable[string, string]()
    streamIds["s1"] = "m42"
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "done",
                              streamId: "s1", isPartial: false)
    streamIds = withStreamCleanup(msg, streamIds)
    check "s1" notin streamIds
