## Tests for domain/channels/whatsapp_pure.nim — pure WhatsApp Cloud API parser.
## No I/O or HTTP; all input is constructed directly as JsonNode.

import std/[json, unittest]
import donkey/domain/channels/whatsapp_pure
import donkey/core/types

# ── Fixtures ──────────────────────────────────────────────────────────────────

func makeWebhook(messages: seq[JsonNode]; phoneNumberId = "PN-1"): JsonNode =
  let msgsNode = newJArray()
  for m in messages: msgsNode.add(m)
  %* {
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "WABA-1",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "+1234",
            "phone_number_id": phoneNumberId,
          },
          "contacts": [{"profile": {"name": "Alice"}, "wa_id": "5511999999999"}],
          "messages": msgsNode,
        },
        "field": "messages",
      }],
    }],
  }

func makeTextMsg(fromId, wamid, body: string): JsonNode =
  %* {
    "from":      fromId,
    "id":        wamid,
    "timestamp": "1700000000",
    "type":      "text",
    "text":      {"body": body},
  }

func makeInteractiveButtonMsg(fromId, wamid, btnId: string): JsonNode =
  %* {
    "from":        fromId,
    "id":          wamid,
    "timestamp":   "1700000001",
    "type":        "interactive",
    "interactive": {
      "type":         "button_reply",
      "button_reply": {"id": btnId, "title": "Yes"},
    },
  }

func makeInteractiveListMsg(fromId, wamid, itemId: string): JsonNode =
  %* {
    "from":        fromId,
    "id":          wamid,
    "timestamp":   "1700000002",
    "type":        "interactive",
    "interactive": {
      "type":       "list_reply",
      "list_reply": {"id": itemId, "title": "Option A"},
    },
  }

func makeMediaMsg(fromId, wamid, mediaType, mediaId: string): JsonNode =
  result = %* {
    "from":      fromId,
    "id":        wamid,
    "timestamp": "1700000003",
    "type":      mediaType,
  }
  result[mediaType] = %* {"id": mediaId, "mime_type": "image/jpeg"}

func makeStatusWebhook(): JsonNode =
  ## Webhook carrying only a status update (no messages array).
  %* {
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "WABA-1",
      "changes": [{
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {"phone_number_id": "PN-1"},
          "statuses": [{"id": "wamid.xxx", "status": "delivered"}],
        },
        "field": "messages",
      }],
    }],
  }

# ── parseWebhook — text messages ──────────────────────────────────────────────

suite "whatsapp_pure.parseWebhook — text messages":

  test "returns one result for a text message":
    let payload = makeWebhook(@[makeTextMsg("5511", "wamid.1", "hello")])
    check parseWebhook(payload).len == 1

  test "kind is wmkText":
    let payload = makeWebhook(@[makeTextMsg("5511", "wamid.1", "hello")])
    check parseWebhook(payload)[0].kind == wmkText

  test "rawId is the from field":
    let payload = makeWebhook(@[makeTextMsg("5511999", "wamid.1", "hi")])
    check parseWebhook(payload)[0].rawId == "5511999"

  test "text is the body":
    let payload = makeWebhook(@[makeTextMsg("5511", "wamid.1", "test content")])
    check parseWebhook(payload)[0].text == "test content"

  test "messageId is the wamid":
    let payload = makeWebhook(@[makeTextMsg("5511", "wamid.abc123", "hi")])
    check parseWebhook(payload)[0].messageId == "wamid.abc123"

  test "phoneNumberId is captured from metadata":
    let payload = makeWebhook(@[makeTextMsg("5511", "wamid.1", "hi")], phoneNumberId = "PN-42")
    check parseWebhook(payload)[0].phoneNumberId == "PN-42"

  test "empty text body returns no results":
    let payload = makeWebhook(@[makeTextMsg("5511", "wamid.1", "")])
    check parseWebhook(payload).len == 0

  test "multiple messages returns multiple results":
    let msgs = @[
      makeTextMsg("5511", "wamid.1", "first"),
      makeTextMsg("5512", "wamid.2", "second"),
    ]
    check parseWebhook(makeWebhook(msgs)).len == 2

# ── parseWebhook — interactive messages ──────────────────────────────────────

suite "whatsapp_pure.parseWebhook — interactive messages":

  test "button_reply returns wmkInteractive":
    let payload = makeWebhook(@[makeInteractiveButtonMsg("5511", "wamid.2", "btn-yes")])
    check parseWebhook(payload)[0].kind == wmkInteractive

  test "button_reply text is the button id":
    let payload = makeWebhook(@[makeInteractiveButtonMsg("5511", "wamid.2", "confirm-delete")])
    check parseWebhook(payload)[0].text == "confirm-delete"

  test "list_reply returns wmkInteractive":
    let payload = makeWebhook(@[makeInteractiveListMsg("5511", "wamid.3", "item-42")])
    check parseWebhook(payload)[0].kind == wmkInteractive

  test "list_reply text is the item id":
    let payload = makeWebhook(@[makeInteractiveListMsg("5511", "wamid.3", "option-B")])
    check parseWebhook(payload)[0].text == "option-B"

  test "rawId captured for interactive":
    let payload = makeWebhook(@[makeInteractiveButtonMsg("5511777", "wamid.2", "b1")])
    check parseWebhook(payload)[0].rawId == "5511777"

  test "messageId captured for interactive":
    let payload = makeWebhook(@[makeInteractiveButtonMsg("5511", "wamid.interact-1", "b1")])
    check parseWebhook(payload)[0].messageId == "wamid.interact-1"

  test "interactive with unknown sub-type returns no results":
    let msg = %* {
      "from": "5511", "id": "wamid.x", "timestamp": "1700000001",
      "type": "interactive",
      "interactive": {"type": "unknown_type"},
    }
    check parseWebhook(makeWebhook(@[msg])).len == 0

  test "interactive with missing reply id returns no results":
    let msg = %* {
      "from": "5511", "id": "wamid.x", "timestamp": "1700000001",
      "type": "interactive",
      "interactive": {"type": "button_reply", "button_reply": {"title": "Yes"}},
    }
    check parseWebhook(makeWebhook(@[msg])).len == 0

# ── parseWebhook — media messages ─────────────────────────────────────────────

suite "whatsapp_pure.parseWebhook — media messages":

  test "image returns wmkMedia":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.4", "image", "media-img-1")])
    check parseWebhook(payload)[0].kind == wmkMedia

  test "audio returns wmkMedia":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.5", "audio", "media-aud-1")])
    check parseWebhook(payload)[0].kind == wmkMedia

  test "video returns wmkMedia":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.6", "video", "media-vid-1")])
    check parseWebhook(payload)[0].kind == wmkMedia

  test "document returns wmkMedia":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.7", "document", "media-doc-1")])
    check parseWebhook(payload)[0].kind == wmkMedia

  test "sticker returns wmkMedia":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.8", "sticker", "media-stk-1")])
    check parseWebhook(payload)[0].kind == wmkMedia

  test "mediaId is captured":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.4", "image", "MEDIA-ID-XYZ")])
    check parseWebhook(payload)[0].mediaId == "MEDIA-ID-XYZ"

  test "hasMedia returns true for media":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.4", "image", "media-1")])
    check parseWebhook(payload)[0].hasMedia

  test "text is empty for media":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.4", "image", "media-1")])
    check parseWebhook(payload)[0].text == ""

  test "rawId captured for media":
    let payload = makeWebhook(@[makeMediaMsg("5511888", "wamid.4", "image", "m1")])
    check parseWebhook(payload)[0].rawId == "5511888"

  test "messageId captured for media":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.media-99", "image", "m1")])
    check parseWebhook(payload)[0].messageId == "wamid.media-99"

# ── parseWebhook — unknown / filtered payloads ────────────────────────────────

suite "whatsapp_pure.parseWebhook — unknown payloads":

  test "nil payload returns empty":
    check parseWebhook(nil).len == 0

  test "empty object returns empty":
    check parseWebhook(%* {}).len == 0

  test "status-only webhook returns empty":
    check parseWebhook(makeStatusWebhook()).len == 0

  test "unknown message type returns no results":
    let msg = %* {
      "from": "5511", "id": "wamid.x", "timestamp": "1700000001",
      "type": "reaction",
    }
    check parseWebhook(makeWebhook(@[msg])).len == 0

  test "missing entry array returns empty":
    check parseWebhook(%* {"object": "whatsapp_business_account"}).len == 0

  test "entry with no changes returns empty":
    let payload = %* {"object": "whatsapp_business_account", "entry": [{"id": "X"}]}
    check parseWebhook(payload).len == 0

  test "mixed valid and unknown messages returns only valid":
    let msgs = @[
      makeTextMsg("5511", "wamid.1", "hello"),
      %* {"from": "5512", "id": "wamid.2", "type": "reaction"},
      makeTextMsg("5513", "wamid.3", "world"),
    ]
    check parseWebhook(makeWebhook(msgs)).len == 2

# ── hasMedia ──────────────────────────────────────────────────────────────────

suite "whatsapp_pure.hasMedia":

  test "false for text":
    let payload = makeWebhook(@[makeTextMsg("5511", "wamid.1", "hi")])
    check not parseWebhook(payload)[0].hasMedia

  test "false for interactive":
    let payload = makeWebhook(@[makeInteractiveButtonMsg("5511", "wamid.2", "b1")])
    check not parseWebhook(payload)[0].hasMedia

  test "true for image":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.4", "image", "m1")])
    check parseWebhook(payload)[0].hasMedia

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "whatsapp_pure.toInbound":

  test "converts text WaParseResult to InboundMessage":
    let payload = makeWebhook(@[makeTextMsg("5511", "wamid.t1", "hello world")])
    let r       = parseWebhook(payload)[0]
    let uid     = UserId("uuid-wa-1")
    let msg     = r.toInbound(uid)
    check msg.userId    == uid
    check msg.channel   == ckWhatsApp
    check msg.channelId == "wamid.t1"
    check msg.text      == "hello world"
    check msg.mediaUrl  == ""

  test "converts interactive WaParseResult to InboundMessage":
    let payload = makeWebhook(@[makeInteractiveButtonMsg("5511", "wamid.i1", "btn-42")])
    let r       = parseWebhook(payload)[0]
    let uid     = UserId("uuid-wa-2")
    let msg     = r.toInbound(uid)
    check msg.channel   == ckWhatsApp
    check msg.text      == "btn-42"
    check msg.channelId == "wamid.i1"

  test "converts media WaParseResult — mediaId goes to mediaUrl":
    let payload = makeWebhook(@[makeMediaMsg("5511", "wamid.m1", "image", "MEDIA-ABC")])
    let r       = parseWebhook(payload)[0]
    let msg     = r.toInbound(UserId("uuid-wa-3"))
    check msg.channel   == ckWhatsApp
    check msg.channelId == "wamid.m1"
    check msg.mediaUrl  == "MEDIA-ABC"
    check msg.text      == ""
