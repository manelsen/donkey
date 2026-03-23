## signal_pure unit tests.
## Pure parsing functions only — no I/O, no sockets.

import std/[json, unittest]
import donkey/domain/channels/signal_pure
import donkey/core/types
import donkey/core/pipeops

# ── parseEnvelope — text messages ─────────────────────────────────────────────

suite "signal_pure.parseEnvelope — text":

  test "text envelope produces smkText":
    let item = %* {
      "envelope": {
        "source":       "+1234567890",
        "sourceNumber": "+1234567890",
        "timestamp":    1609459200000'i64,
        "dataMessage":  {
          "timestamp":  1609459200000'i64,
          "message":    "Hello Signal",
          "attachments": [],
        },
      }
    }
    let r = parseEnvelope(item)
    check r.kind      == smkText
    check r.rawId     == "+1234567890"
    check r.text      == "Hello Signal"
    check r.timestamp == 1609459200000'i64

  test "prefers sourceNumber over source":
    let item = %* {
      "envelope": {
        "source":       "uuid-form",
        "sourceNumber": "+19991234567",
        "timestamp":    100'i64,
        "dataMessage":  {"timestamp": 100'i64, "message": "hi", "attachments": []},
      }
    }
    let r = parseEnvelope(item)
    check r.rawId == "+19991234567"

  test "falls back to source when sourceNumber absent":
    let item = %* {
      "envelope": {
        "source":    "+15550001111",
        "timestamp": 200'i64,
        "dataMessage": {"timestamp": 200'i64, "message": "fallback", "attachments": []},
      }
    }
    let r = parseEnvelope(item)
    check r.rawId == "+15550001111"
    check r.kind  == smkText

  test "empty dataMessage.message without attachments returns smkUnknown":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1111111111",
        "timestamp":    300'i64,
        "dataMessage":  {"timestamp": 300'i64, "message": "", "attachments": []},
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkUnknown

  test "nil item returns smkUnknown":
    let r = parseEnvelope(newJNull())
    check r.kind == smkUnknown

  test "missing envelope field returns smkUnknown":
    let r = parseEnvelope(%* {"other": "data"})
    check r.kind == smkUnknown

  test "missing sourceNumber and source returns smkUnknown":
    let item = %* {
      "envelope": {
        "timestamp":   400'i64,
        "dataMessage": {"timestamp": 400'i64, "message": "no sender", "attachments": []},
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkUnknown

  test "missing dataMessage returns smkUnknown":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    500'i64,
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkUnknown

# ── parseEnvelope — receipt and typing (non-data) ─────────────────────────────

suite "signal_pure.parseEnvelope — non-data envelopes":

  test "receiptMessage envelope returns smkUnknown":
    let item = %* {
      "envelope": {
        "sourceNumber":   "+1234567890",
        "timestamp":      600'i64,
        "receiptMessage": {"when": 600'i64, "isDelivery": true, "timestamps": [100'i64]},
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkUnknown

  test "typingMessage envelope returns smkUnknown":
    let item = %* {
      "envelope": {
        "sourceNumber":  "+1234567890",
        "timestamp":     700'i64,
        "typingMessage": {"action": "STARTED", "timestamp": 700'i64},
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkUnknown

  test "syncMessage envelope returns smkUnknown":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    800'i64,
        "syncMessage":  {"sentMessage": {"destination": "+9999999999", "message": "synced"}},
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkUnknown

# ── parseEnvelope — attachments ────────────────────────────────────────────────

suite "signal_pure.parseEnvelope — attachments":

  test "dataMessage with attachment produces smkAttachment":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    900'i64,
        "dataMessage":  {
          "timestamp":  900'i64,
          "message":    "",
          "attachments": [{
            "contentType": "image/jpeg",
            "id":          "att-001",
            "filename":    "photo.jpg",
            "size":        12345,
          }],
        },
      }
    }
    let r = parseEnvelope(item)
    check r.kind         == smkAttachment
    check r.attachmentId == "att-001"
    check r.rawId        == "+1234567890"

  test "attachment without id falls back to filename":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    1000'i64,
        "dataMessage":  {
          "timestamp":  1000'i64,
          "message":    "",
          "attachments": [{
            "contentType": "image/png",
            "filename":    "image.png",
            "size":        99,
          }],
        },
      }
    }
    let r = parseEnvelope(item)
    check r.kind         == smkAttachment
    check r.attachmentId == "image.png"

  test "attachment with caption text stores text":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    1100'i64,
        "dataMessage":  {
          "timestamp":  1100'i64,
          "message":    "See attached",
          "attachments": [{"id": "att-002"}],
        },
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkAttachment
    check r.text == "See attached"

  test "hasAttachment is false for text":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    1200'i64,
        "dataMessage":  {"timestamp": 1200'i64, "message": "plain text", "attachments": []},
      }
    }
    let r = parseEnvelope(item)
    check not r.hasAttachment

  test "hasAttachment is true for attachment":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    1300'i64,
        "dataMessage":  {
          "timestamp":  1300'i64,
          "message":    "",
          "attachments": [{"id": "att-003"}],
        },
      }
    }
    let r = parseEnvelope(item)
    check r.hasAttachment

# ── parseEnvelopes ─────────────────────────────────────────────────────────────

suite "signal_pure.parseEnvelopes":

  test "filters out smkUnknown entries":
    let items = %* [
      {
        "envelope": {
          "sourceNumber": "+1111111111",
          "timestamp":    1400'i64,
          "dataMessage":  {"timestamp": 1400'i64, "message": "msg1", "attachments": []},
        }
      },
      {
        "envelope": {
          "sourceNumber": "+1111111111",
          "timestamp":    1410'i64,
          "receiptMessage": {"when": 1410'i64},
        }
      },
      {
        "envelope": {
          "sourceNumber": "+2222222222",
          "timestamp":    1420'i64,
          "dataMessage":  {"timestamp": 1420'i64, "message": "msg2", "attachments": []},
        }
      },
    ]
    let results = parseEnvelopes(items)
    check results.len == 2
    check results[0].text == "msg1"
    check results[1].text == "msg2"

  test "empty array returns empty seq":
    let results = parseEnvelopes(%* [])
    check results.len == 0

  test "nil input returns empty seq":
    let results = parseEnvelopes(newJNull())
    check results.len == 0

  test "all unknown returns empty seq":
    let items = %* [
      {"envelope": {"sourceNumber": "+1234567890", "timestamp": 1500'i64,
                    "receiptMessage": {"when": 1500'i64}}},
    ]
    let results = parseEnvelopes(items)
    check results.len == 0

  test "|> parseEnvelopes pipeline works":
    let items = %* [
      {
        "envelope": {
          "sourceNumber": "+3333333333",
          "timestamp":    1600'i64,
          "dataMessage":  {"timestamp": 1600'i64, "message": "pipe test", "attachments": []},
        }
      }
    ]
    let results = items |> parseEnvelopes
    check results.len     == 1
    check results[0].text == "pipe test"

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "signal_pure.toInbound":

  test "converts text result to InboundMessage":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    1700'i64,
        "dataMessage":  {"timestamp": 1700'i64, "message": "convert me", "attachments": []},
      }
    }
    let r      = parseEnvelope(item)
    let userId = UserId("test-uuid-sig-001")
    let msg    = r.toInbound(userId)
    check msg.userId    == userId
    check msg.channel   == ckSignal
    check msg.text      == "convert me"
    check msg.channelId == "1700"
    check msg.mediaUrl  == ""

  test "attachment result maps attachmentId to mediaUrl":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    1800'i64,
        "dataMessage":  {
          "timestamp":  1800'i64,
          "message":    "",
          "attachments": [{"id": "att-media-001"}],
        },
      }
    }
    let r   = parseEnvelope(item)
    let msg = r.toInbound(UserId("test-uuid-sig-002"))
    check msg.mediaUrl == "att-media-001"

  test "channelId is the timestamp as string":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    9876543210000'i64,
        "dataMessage":  {"timestamp": 9876543210000'i64, "message": "ts test", "attachments": []},
      }
    }
    let r   = parseEnvelope(item)
    let msg = r.toInbound(UserId("test-uuid-sig-003"))
    check msg.channelId == "9876543210000"
