## WhatsAppAdapter unit tests.
## HTTP calls are not made; tests cover adapter construction, identity
## resolution, webhook verification, and event queue routing via whatsapp_pure.

import std/[json, os, unittest]
import donkey/adapters/channel/whatsapp
import donkey/adapters/identity/identity_resolver
import donkey/core/types
import donkey/domain/channels/whatsapp_pure

# ── IdentityResolver (WhatsApp) ────────────────────────────────────────────────

suite "IdentityResolver (WhatsApp)":

  test "creates new UUID for unknown whatsapp user":
    let path = getTempDir() / "donkey_test_ids_wa.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckWhatsApp, "5511999990001")
    check ($uid).len == 36

  test "same phone returns same UserId":
    let path = getTempDir() / "donkey_test_ids_wa2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckWhatsApp, "5511999990002")
    let u2 = r.resolve(ckWhatsApp, "5511999990002")
    check u1 == u2

  test "different phones get different UserIds":
    let path = getTempDir() / "donkey_test_ids_wa3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckWhatsApp, "5511999990003")
    let u2 = r.resolve(ckWhatsApp, "5511999990004")
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_ids_wa4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid1 = newIdentityResolver(path).resolve(ckWhatsApp, "5511999990005")
    let uid2 = newIdentityResolver(path).resolve(ckWhatsApp, "5511999990005")
    check uid1 == uid2

  test "generated id looks like a UUID":
    let path = getTempDir() / "donkey_test_ids_wa5.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid = $newIdentityResolver(path).resolve(ckWhatsApp, "5511999990006")
    check uid.len == 36
    check uid[8]  == '-'
    check uid[13] == '-'
    check uid[18] == '-'
    check uid[23] == '-'

# ── WhatsAppAdapter construction ───────────────────────────────────────────────

suite "WhatsAppAdapter construction":

  test "accessToken is stored":
    let a = newWhatsAppAdapter("EAA-TOKEN", "12345", "/tmp/ids_wa.tsv",
                               apiBase = "https://mock.local")
    check a.accessToken == "EAA-TOKEN"

  test "phoneNumberId is stored":
    let a = newWhatsAppAdapter("EAA-TOKEN", "67890", "/tmp/ids_wa2.tsv",
                               apiBase = "https://mock.local")
    check a.phoneNumberId == "67890"

  test "apiBase override is stored":
    let a = newWhatsAppAdapter("EAA-TOK", "12345", "/tmp/ids_wa3.tsv",
                               apiBase = "https://test.api")
    check a.apiBase == "https://test.api"

  test "default apiBase is empty string":
    let a = newWhatsAppAdapter("EAA-TOK2", "12345", "/tmp/ids_wa4.tsv")
    check a.apiBase == ""

# ── verifyChallenge ────────────────────────────────────────────────────────────

suite "verifyChallenge":

  test "subscribe with matching token returns challenge":
    check verifyChallenge("subscribe", "abc123", "my-secret", "my-secret") == "abc123"

  test "subscribe with wrong token returns empty string":
    check verifyChallenge("subscribe", "abc123", "wrong", "my-secret") == ""

  test "non-subscribe mode returns empty string":
    check verifyChallenge("unsubscribe", "abc123", "my-secret", "my-secret") == ""

  test "empty mode returns empty string":
    check verifyChallenge("", "abc123", "my-secret", "my-secret") == ""

  test "challenge value is preserved verbatim":
    check verifyChallenge("subscribe", "xyz-9876", "tok", "tok") == "xyz-9876"

# ── pushEvent and whatsapp_pure routing ───────────────────────────────────────

suite "whatsapp_pure.parseWebhook routing (used by pushEvent)":

  test "text message produces wmkText result":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata":  {"phone_number_id": "PN1"},
            "messages":  [{
              "from": "5511999990010",
              "id":   "wamid.001",
              "type": "text",
              "text": {"body": "hello world"},
            }],
          }
        }]
      }]
    }
    let msgs = parseWebhook(payload)
    check msgs.len        == 1
    check msgs[0].kind    == wmkText
    check msgs[0].rawId   == "5511999990010"
    check msgs[0].text    == "hello world"
    check msgs[0].messageId     == "wamid.001"
    check msgs[0].phoneNumberId == "PN1"

  test "button_reply interactive produces wmkInteractive":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata":  {"phone_number_id": "PN2"},
            "messages":  [{
              "from": "5511999990011",
              "id":   "wamid.002",
              "type": "interactive",
              "interactive": {
                "type":         "button_reply",
                "button_reply": {"id": "btn_yes", "title": "Yes"},
              },
            }],
          }
        }]
      }]
    }
    let msgs = parseWebhook(payload)
    check msgs.len      == 1
    check msgs[0].kind  == wmkInteractive
    check msgs[0].text  == "btn_yes"
    check msgs[0].rawId == "5511999990011"

  test "image message produces wmkMedia":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata":  {"phone_number_id": "PN3"},
            "messages":  [{
              "from":  "5511999990012",
              "id":    "wamid.003",
              "type":  "image",
              "image": {"id": "media-abc", "mime_type": "image/jpeg"},
            }],
          }
        }]
      }]
    }
    let msgs = parseWebhook(payload)
    check msgs.len        == 1
    check msgs[0].kind    == wmkMedia
    check msgs[0].mediaId == "media-abc"
    check msgs[0].rawId   == "5511999990012"

  test "status-only payload produces no results":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata": {"phone_number_id": "PN4"},
            "statuses": [{"id": "wamid.004", "status": "delivered"}],
          }
        }]
      }]
    }
    let msgs = parseWebhook(payload)
    check msgs.len == 0

  test "empty entry array produces no results":
    let msgs = parseWebhook(%* {"entry": []})
    check msgs.len == 0

  test "nil payload produces no results":
    let msgs = parseWebhook(newJNull())
    check msgs.len == 0

  test "multiple messages in one payload are all returned":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata": {"phone_number_id": "PN5"},
            "messages": [
              {"from": "5511999990013", "id": "wamid.005", "type": "text",
               "text": {"body": "msg1"}},
              {"from": "5511999990014", "id": "wamid.006", "type": "text",
               "text": {"body": "msg2"}},
            ],
          }
        }]
      }]
    }
    let msgs = parseWebhook(payload)
    check msgs.len    == 2
    check msgs[0].text == "msg1"
    check msgs[1].text == "msg2"

# ── toInbound ──────────────────────────────────────────────────────────────────

suite "whatsapp_pure.toInbound":

  test "converts text result to InboundMessage":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata": {"phone_number_id": "PN6"},
            "messages": [{
              "from": "5511999990015",
              "id":   "wamid.007",
              "type": "text",
              "text": {"body": "test text"},
            }],
          }
        }]
      }]
    }
    let msgs   = parseWebhook(payload)
    let userId = UserId("test-uuid-wa-0001")
    let msg    = msgs[0].toInbound(userId)
    check msg.userId    == userId
    check msg.channel   == ckWhatsApp
    check msg.text      == "test text"
    check msg.channelId == "wamid.007"

  test "media result maps mediaId to mediaUrl":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata": {"phone_number_id": "PN7"},
            "messages": [{
              "from":  "5511999990016",
              "id":    "wamid.008",
              "type":  "audio",
              "audio": {"id": "audio-xyz"},
            }],
          }
        }]
      }]
    }
    let msgs = parseWebhook(payload)
    let msg  = msgs[0].toInbound(UserId("test-uuid-wa-0002"))
    check msg.mediaUrl == "audio-xyz"

  test "hasMedia is false for text":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata": {"phone_number_id": "PN8"},
            "messages": [{
              "from": "5511999990017",
              "id":   "wamid.009",
              "type": "text",
              "text": {"body": "hi"},
            }],
          }
        }]
      }]
    }
    let msgs = parseWebhook(payload)
    check not msgs[0].hasMedia

  test "hasMedia is true for image":
    let payload = %* {
      "entry": [{
        "changes": [{
          "value": {
            "metadata": {"phone_number_id": "PN9"},
            "messages": [{
              "from":  "5511999990018",
              "id":    "wamid.010",
              "type":  "image",
              "image": {"id": "img-001"},
            }],
          }
        }]
      }]
    }
    let msgs = parseWebhook(payload)
    check msgs[0].hasMedia
