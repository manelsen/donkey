import std/[tables, unittest]
import donkey/core/outbound/outbound
import donkey/domain/message

suite "core outbound decisions":

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
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckWeCom, text: "hi",
                              streamId: "s1", isPartial: true)
    check classifyOutbound(msg, initTable[string, string]()) == okSuppress

  test "classifyOutbound falls back to immediate final on non-editable channels":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckWeCom, text: "done",
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
    let partial = OutboundMessage(userId: UserId("u1"), channel: ckQQ, text: "hi",
                                  streamId: "s1", isPartial: true)
    let final = OutboundMessage(userId: UserId("u1"), channel: ckQQ, text: "done",
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

  test "withStreamCleanup removes final stream id":
    var streamIds = initTable[string, string]()
    streamIds["s1"] = "m42"
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "done",
                              streamId: "s1", isPartial: false)
    streamIds = withStreamCleanup(msg, streamIds)
    check "s1" notin streamIds

  test "buildReplacementSurface models reusable outbound UI without channel specifics":
    let surface = buildReplacementSurface(
      slot = "bootstrap",
      text = "Como quer definir minha personalidade?",
      keyboard = @[@[("Calmo", "tone:calm")]],
    )
    check surface.kind == pskReplaceable
    check surface.slot == "bootstrap"
    check surface.fallbackText == "Como quer definir minha personalidade?"
    check surface.msg.text == "Como quer definir minha personalidade?"
    check surface.msg.keyboard.len == 1
    check surface.msg.replacementSlot == "bootstrap"

  test "buildStreamingSurface distinguishes append-only from replaceable status":
    let partial = buildStreamingSurface(
      slot = "status",
      streamId = "s-1",
      text = "Processando",
      isPartial = true,
    )
    let final = buildStreamingSurface(
      slot = "status",
      streamId = "s-1",
      text = "Concluído",
      isPartial = false,
    )
    check partial.kind == pskStreaming
    check partial.slot == "status"
    check partial.fallbackText == "Processando"
    check partial.msg.streamId == "s-1"
    check partial.msg.isPartial
    check final.kind == pskStreaming
    check final.msg.streamId == "s-1"
    check not final.msg.isPartial

  test "toOutboundMessage projects a presentation surface onto a channel message":
    let surface = buildReplacementSurface(
      slot = "help",
      text = "Ajuda",
      keyboard = @[@[("Voltar", "help:page:0")]],
    )
    let base = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, replyTo: "42")
    let projected = toOutboundMessage(surface, base)
    check projected.userId == UserId("u1")
    check projected.channel == ckTelegram
    check projected.replyTo == "42"
    check projected.text == "Ajuda"
    check projected.replacementSlot == "help"
    check projected.keyboard.len == 1

  test "presentation state stores replacement bindings by channel user and slot":
    var state = initPresentationState()
    let msg = OutboundMessage(
      userId: UserId("u1"),
      channel: ckTelegram,
      text: "Bootstrap",
      replacementSlot: "bootstrap",
    )
    check state.lookupReplacement(msg) == ""
    state.rememberReplacement(msg, "m-42")
    check state.lookupReplacement(msg) == "m-42"

  test "presentation state keeps bindings isolated per surface":
    var state = initPresentationState()
    let bootstrap = OutboundMessage(
      userId: UserId("u1"),
      channel: ckTelegram,
      text: "Bootstrap",
      replacementSlot: "bootstrap",
    )
    let help = OutboundMessage(
      userId: UserId("u1"),
      channel: ckTelegram,
      text: "Ajuda",
      replacementSlot: "help",
    )
    state.rememberReplacement(bootstrap, "m-bootstrap")
    state.rememberReplacement(help, "m-help")
    check state.lookupReplacement(bootstrap) == "m-bootstrap"
    check state.lookupReplacement(help) == "m-help"
