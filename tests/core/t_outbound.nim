import std/unittest
import donkey/core/outbound/outbound
import donkey/domain/message

suite "core outbound decisions":

  test "classifyOutbound returns immediate without stream id":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "hi")
    check classifyOutbound(msg, initPresentationState()) == okImmediate

  test "classifyOutbound returns stream create when stream id is new":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "hi", streamId: "s1")
    check classifyOutbound(msg, initPresentationState()) == okStreamCreate

  test "classifyOutbound returns stream update when stream id exists":
    var state = initPresentationState()
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "hi", streamId: "s1")
    state.rememberStream(msg, "m42")
    check classifyOutbound(msg, state) == okStreamUpdate

  test "classifyOutbound suppresses partial stream on non-editable channels":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckWeCom, text: "hi",
                              streamId: "s1", isPartial: true)
    check classifyOutbound(msg, initPresentationState()) == okSuppress

  test "classifyOutbound falls back to immediate final on non-editable channels":
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckWeCom, text: "done",
                              streamId: "s1", isPartial: false)
    check classifyOutbound(msg, initPresentationState()) == okImmediate

  test "decideStreamAction includes existing message id":
    var state = initPresentationState()
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckDiscord, text: "hi", streamId: "s1")
    state.rememberStream(msg, "m42")
    let action = decideStreamAction(msg, state)
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
    let partialDecision = decideOutbound(partial, initPresentationState())
    let finalDecision = decideOutbound(final, initPresentationState())
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

  test "presentation capabilities expose replacement stream and component support declaratively":
    let tgCaps = presentationCapabilities(ckTelegram)
    let qqCaps = presentationCapabilities(ckQQ)
    check tgCaps.editableReplacement
    check tgCaps.editableStreams
    check tgCaps.interactiveComponents
    check not qqCaps.editableReplacement
    check not qqCaps.editableStreams
    check not qqCaps.interactiveComponents
    check replacementSlotFor(ckTelegram, "bootstrap") == "bootstrap"
    check replacementSlotFor(ckQQ, "bootstrap") == ""
    check interactiveSelectionFallbackText() == SharedButtonSelectionFallbackText

  test "isImplementedOutboundChannel matches supported channels":
    check isImplementedOutboundChannel(ckTelegram)
    check isImplementedOutboundChannel(ckDiscord)
    check isImplementedOutboundChannel(ckWeCom)
    check isImplementedOutboundChannel(ckWeChat)
    check isImplementedOutboundChannel(ckQQ)
    check isImplementedOutboundChannel(ckFeishu)

  test "withStreamCleanup removes final stream id":
    var state = initPresentationState()
    let msg = OutboundMessage(userId: UserId("u1"), channel: ckTelegram, text: "done",
                              streamId: "s1", isPartial: false)
    state.rememberStream(msg, "m42")
    state = withStreamCleanup(msg, state)
    check state.lookupStream(msg) == ""

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

  test "presentation state stores stream bindings and cleans them up independently":
    var state = initPresentationState()
    let partial = OutboundMessage(
      userId: UserId("u1"),
      channel: ckTelegram,
      text: "partial",
      streamId: "stream-1",
      isPartial: true,
    )
    let final = OutboundMessage(
      userId: UserId("u1"),
      channel: ckTelegram,
      text: "final",
      streamId: "stream-1",
      isPartial: false,
    )
    state.rememberStream(partial, "m-stream")
    check state.lookupStream(partial) == "m-stream"
    check state.lookupStream(final) == "m-stream"
    state.clearStream(final)
    check state.lookupStream(partial) == ""

  test "presentation state stores status bindings separately from menus":
    var state = initPresentationState()
    let menu = OutboundMessage(
      userId: UserId("u1"),
      channel: ckTelegram,
      text: "Bootstrap",
      replacementSlot: "bootstrap",
    )
    state.rememberReplacement(menu, "m-menu")
    state.rememberStatus(ckTelegram, UserId("u1"), "fallback", "m-status")
    check state.lookupReplacement(menu) == "m-menu"
    check state.lookupStatus(ckTelegram, UserId("u1"), "fallback") == "m-status"
    state.clearStatus(ckTelegram, UserId("u1"), "fallback")
    check state.lookupReplacement(menu) == "m-menu"
    check state.lookupStatus(ckTelegram, UserId("u1"), "fallback") == ""
