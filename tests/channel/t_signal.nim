## SignalAdapter unit tests.
## IPC calls are not made; tests cover adapter construction, identity
## resolution, and signal_pure parsing integration.

import std/[json, os, unittest]
import donkey/adapters/channel/signal
import donkey/adapters/identity/identity_resolver
import donkey/core/types
import donkey/core/pipeops
import donkey/domain/channels/signal_pure

# ── IdentityResolver (Signal) ──────────────────────────────────────────────────

suite "IdentityResolver (Signal)":

  test "creates new UUID for unknown signal user":
    let path = getTempDir() / "donkey_test_ids_sig.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckSignal, "+1234567890")
    check ($uid).len == 36

  test "same phone returns same UserId":
    let path = getTempDir() / "donkey_test_ids_sig2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckSignal, "+1111111111")
    let u2 = r.resolve(ckSignal, "+1111111111")
    check u1 == u2

  test "different phones get different UserIds":
    let path = getTempDir() / "donkey_test_ids_sig3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckSignal, "+1111111111")
    let u2 = r.resolve(ckSignal, "+2222222222")
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_ids_sig4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid1 = newIdentityResolver(path).resolve(ckSignal, "+3333333333")
    let uid2 = newIdentityResolver(path).resolve(ckSignal, "+3333333333")
    check uid1 == uid2

  test "generated id looks like a UUID":
    let path = getTempDir() / "donkey_test_ids_sig5.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid = $newIdentityResolver(path).resolve(ckSignal, "+4444444444")
    check uid.len == 36
    check uid[8]  == '-'
    check uid[13] == '-'
    check uid[18] == '-'
    check uid[23] == '-'

  test "reverseChannel returns phone for known user":
    let path = getTempDir() / "donkey_test_ids_sig6.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r     = newIdentityResolver(path)
    let uid   = r.resolve(ckSignal, "+5555555555")
    let phone = r.reverseChannel(uid, ckSignal)
    check phone == "+5555555555"

  test "reverseChannel returns empty for unknown user":
    let path = getTempDir() / "donkey_test_ids_sig7.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let res = r.reverseChannel(UserId("nonexistent-uuid"), ckSignal)
    check res == ""

# ── SignalAdapter construction ─────────────────────────────────────────────────

suite "SignalAdapter construction":

  test "account is stored":
    let a = newSignalAdapter("+1234567890", "/tmp/ids_sig.tsv",
                             sockPath = "/tmp/nonexistent.sock")
    check a.account == "+1234567890"

  test "sockPath override is stored":
    let a = newSignalAdapter("+1234567890", "/tmp/ids_sig2.tsv",
                             sockPath = "/tmp/test.sock")
    check a.sockPath == "/tmp/test.sock"

  test "default sockPath is SignalDefaultSock":
    let a = newSignalAdapter("+1234567890", "/tmp/ids_sig3.tsv")
    check a.sockPath == SignalDefaultSock

  test "SignalDefaultSock constant is set":
    check SignalDefaultSock == "/run/signal-cli/socket"

  test "SignalMaxChars constant is positive":
    check SignalMaxChars > 0

# ── signal_pure.parseEnvelope integration ─────────────────────────────────────

suite "signal_pure routing (used by SignalAdapter.receive)":

  test "text envelope is parsed correctly":
    let item = %* {
      "envelope": {
        "sourceNumber": "+9876543210",
        "timestamp":    2000'i64,
        "dataMessage":  {
          "timestamp":  2000'i64,
          "message":    "hello from signal",
          "attachments": [],
        },
      }
    }
    let r = parseEnvelope(item)
    check r.kind  == smkText
    check r.rawId == "+9876543210"
    check r.text  == "hello from signal"

  test "attachment envelope is parsed correctly":
    let item = %* {
      "envelope": {
        "sourceNumber": "+9876543210",
        "timestamp":    2100'i64,
        "dataMessage":  {
          "timestamp":  2100'i64,
          "message":    "photo",
          "attachments": [{"id": "att-xyz", "contentType": "image/jpeg"}],
        },
      }
    }
    let r = parseEnvelope(item)
    check r.kind         == smkAttachment
    check r.attachmentId == "att-xyz"

  test "receipt envelope is ignored":
    let item = %* {
      "envelope": {
        "sourceNumber":   "+9876543210",
        "timestamp":      2200'i64,
        "receiptMessage": {"when": 2200'i64, "isDelivery": true},
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkUnknown

  test "typing envelope is ignored":
    let item = %* {
      "envelope": {
        "sourceNumber":  "+9876543210",
        "timestamp":     2300'i64,
        "typingMessage": {"action": "STARTED"},
      }
    }
    let r = parseEnvelope(item)
    check r.kind == smkUnknown

  test "parseEnvelopes returns only data messages":
    let items = %* [
      {
        "envelope": {
          "sourceNumber": "+9876543210",
          "timestamp":    2400'i64,
          "dataMessage":  {"timestamp": 2400'i64, "message": "keep", "attachments": []},
        }
      },
      {
        "envelope": {
          "sourceNumber":   "+9876543210",
          "timestamp":      2410'i64,
          "receiptMessage": {"when": 2410'i64},
        }
      },
    ]
    let results = parseEnvelopes(items)
    check results.len      == 1
    check results[0].text  == "keep"

  test "toInbound maps to ckSignal channel":
    let item = %* {
      "envelope": {
        "sourceNumber": "+1234567890",
        "timestamp":    2500'i64,
        "dataMessage":  {"timestamp": 2500'i64, "message": "chan test", "attachments": []},
      }
    }
    let r   = parseEnvelope(item)
    let msg = r.toInbound(UserId("test-uuid-sig-010"))
    check msg.channel == ckSignal

  test "ack is a no-op":
    let a = newSignalAdapter("+1234567890", "/tmp/ids_sig_ack.tsv",
                             sockPath = "/tmp/nonexistent.sock")
    a.ack("any-channel-id")  ## must not raise

  test "editMessage returns ok without socket":
    var a = newSignalAdapter("+1234567890", "/tmp/ids_sig_edit.tsv",
                             sockPath = "/tmp/nonexistent.sock")
    let uid = a.resolver.resolve(ckSignal, "+1234567890")
    let res = a.editMessage(uid, "msg-id", "new text")
    check res.isOk
