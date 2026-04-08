import std/[tables, unittest]
import results
import donkey/app/outbound_runtime
import donkey/core/log
import donkey/domain/message
import donkey/ports/channel

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

  test "routeOutbound edits immediate message when edit target is provided":
    var sentCount = 0
    var editedText = ""
    var editedKeyboardCount = -1
    let ports = OutboundChannelPorts(
      telegram: OutboundChannelPort(
        send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
          {.cast(gcsafe).}: inc sentCount
          ok(),
        sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} = ok("m1"),
        editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
          {.cast(gcsafe).}: editedText = text
          ok(),
        sendKeyboard: proc(userId: UserId; text: string;
                           buttons: seq[seq[(string, string)]];
                           replyTo = ""): Result[void, string] {.gcsafe.} = ok(),
        editKeyboard: proc(userId: UserId; msgId, text: string;
                           buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
          {.cast(gcsafe).}:
            editedText = text
            editedKeyboardCount = buttons.len
          ok(),
        setMessageReaction: proc(userId: UserId; msgId, emoji: string): Result[void, string] {.gcsafe.} = ok(),
      )
    )
    var streamIds = initTable[string, string]()
    var replacementIds = initTable[string, string]()
    routeOutbound(
      OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "edit me", editTargetId: "42"),
      ports,
      newLogger("test.outbound"),
      streamIds,
      replacementIds)
    check sentCount == 0
    check editedText == "edit me"
    check editedKeyboardCount == -1

  test "routeOutbound can replace keyboard while editing immediate message":
    var editedText = ""
    var editedKeyboardCount = -1
    let ports = OutboundChannelPorts(
      telegram: OutboundChannelPort(
        send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} = ok(),
        sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} = ok("m1"),
        editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} = ok(),
        sendKeyboard: proc(userId: UserId; text: string;
                           buttons: seq[seq[(string, string)]];
                           replyTo = ""): Result[void, string] {.gcsafe.} = ok(),
        editKeyboard: proc(userId: UserId; msgId, text: string;
                           buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} =
          {.cast(gcsafe).}:
            editedText = text
            editedKeyboardCount = buttons.len
          ok(),
        setMessageReaction: proc(userId: UserId; msgId, emoji: string): Result[void, string] {.gcsafe.} = ok(),
      )
    )
    var streamIds = initTable[string, string]()
    var replacementIds = initTable[string, string]()
    routeOutbound(
      OutboundMessage(
        userId: UserId("u1"),
        channel: ckTelegram,
        text: "pick one",
        editTargetId: "42",
        replaceKeyboard: true,
        keyboard: @[@[("A", "a")]],
      ),
      ports,
      newLogger("test.outbound"),
      streamIds,
      replacementIds)
    check editedText == "pick one"
    check editedKeyboardCount == 1

  test "routeOutbound reuses replacement slot for editable channels":
    var sentCount = 0
    var editedText = ""
    let ports = OutboundChannelPorts(
      telegram: OutboundChannelPort(
        send: proc(msg: OutboundMessage): Result[void, string] {.gcsafe.} =
          {.cast(gcsafe).}: inc sentCount
          ok(),
        sendReturnId: proc(msg: OutboundMessage): Result[string, string] {.gcsafe.} = ok("m-slot"),
        editMessage: proc(userId: UserId; msgId, text: string): Result[void, string] {.gcsafe.} =
          {.cast(gcsafe).}: editedText = msgId & ":" & text
          ok(),
        sendKeyboard: proc(userId: UserId; text: string;
                           buttons: seq[seq[(string, string)]];
                           replyTo = ""): Result[void, string] {.gcsafe.} = ok(),
        editKeyboard: proc(userId: UserId; msgId, text: string;
                           buttons: seq[seq[(string, string)]]): Result[void, string] {.gcsafe.} = ok(),
        setMessageReaction: proc(userId: UserId; msgId, emoji: string): Result[void, string] {.gcsafe.} = ok(),
      )
    )
    var streamIds = initTable[string, string]()
    var replacementIds = initTable[string, string]()
    routeOutbound(
      OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "first", replacementSlot: "bootstrap"),
      ports,
      newLogger("test.outbound"),
      streamIds,
      replacementIds)
    check replacementIds["telegram|u1|bootstrap"] == "m-slot"
    routeOutbound(
      OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "second", replacementSlot: "bootstrap"),
      ports,
      newLogger("test.outbound"),
      streamIds,
      replacementIds)
    check sentCount == 0
    check editedText == "m-slot:second"
