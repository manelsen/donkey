## FeishuAdapter unit tests.
## HTTP calls are not made; tests cover adapter construction, identity
## resolution, event queue routing, and parseChallenge via feishu_pure.

import std/[json, os, unittest]
import donkey/adapters/channel/feishu
import donkey/adapters/identity/identity_resolver
import donkey/core/types
import donkey/domain/channels/feishu_pure

# ── IdentityResolver (Feishu) ─────────────────────────────────────────────────

suite "IdentityResolver (Feishu)":

  test "creates new UUID for unknown open_id":
    let path = getTempDir() / "donkey_test_ids_feishu.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckFeishu, "ou_abc123")
    check ($uid).len == 36

  test "same open_id returns same UserId":
    let path = getTempDir() / "donkey_test_ids_feishu2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckFeishu, "ou_abc")
    let u2 = r.resolve(ckFeishu, "ou_abc")
    check u1 == u2

  test "different open_ids get different UserIds":
    let path = getTempDir() / "donkey_test_ids_feishu3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckFeishu, "ou_aaa")
    let u2 = r.resolve(ckFeishu, "ou_bbb")
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_ids_feishu4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid1 = newIdentityResolver(path).resolve(ckFeishu, "ou_ccc")
    let uid2 = newIdentityResolver(path).resolve(ckFeishu, "ou_ccc")
    check uid1 == uid2

  test "generated id looks like a UUID":
    let path = getTempDir() / "donkey_test_ids_feishu5.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid = $newIdentityResolver(path).resolve(ckFeishu, "ou_777")
    check uid.len == 36
    check uid[8]  == '-'
    check uid[13] == '-'
    check uid[18] == '-'
    check uid[23] == '-'

# ── FeishuAdapter construction ────────────────────────────────────────────────

suite "FeishuAdapter construction":

  test "appId is stored":
    let a = newFeishuAdapter("cli_MYAPP", "secret", "/tmp/ids_fs.tsv",
                             apiBase = "https://mock.local")
    check a.appId == "cli_MYAPP"

  test "appSecret is stored":
    let a = newFeishuAdapter("cli_APP2", "my_secret", "/tmp/ids_fs2.tsv")
    check a.appSecret == "my_secret"

  test "accessToken is stored":
    let a = newFeishuAdapter("cli_A3", "s3", "/tmp/ids_fs3.tsv",
                             accessToken = "tok_abc")
    check a.accessToken == "tok_abc"

  test "apiBase override is stored":
    let a = newFeishuAdapter("cli_A4", "s4", "/tmp/ids_fs4.tsv",
                             apiBase = "https://test.api")
    check a.apiBase == "https://test.api"

  test "default apiBase is empty string":
    let a = newFeishuAdapter("cli_A5", "s5", "/tmp/ids_fs5.tsv")
    check a.apiBase == ""

  test "default accessToken is empty string":
    let a = newFeishuAdapter("cli_A6", "s6", "/tmp/ids_fs6.tsv")
    check a.accessToken == ""

# ── parseChallenge ────────────────────────────────────────────────────────────

suite "parseChallenge":

  test "url_verification returns challenge value":
    let payload = %* {"type": "url_verification", "challenge": "abc123", "token": "tok"}
    check parseChallenge(payload) == "abc123"

  test "schema 2.0 message event returns empty string":
    let payload = %* {
      "schema": "2.0",
      "header": {
        "event_id":   "ev1",
        "event_type": "im.message.receive_v1",
        "token":      "tok",
      },
      "event": {
        "message": {
          "message_type": "text",
          "message_id":   "om_1",
          "chat_id":      "oc_1",
          "chat_type":    "p2p",
          "content":      "{\"text\":\"hello\"}",
        },
        "sender": {
          "sender_id": {"open_id": "ou_1"},
        },
      },
    }
    check parseChallenge(payload) == ""

  test "nil payload returns empty string":
    let payload = newJNull()
    check parseChallenge(payload) == ""

  test "unknown event type returns empty string":
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "contact.user.updated_v3"},
      "event": {},
    }
    check parseChallenge(payload) == ""

# ── feishu_pure.parseEvent routing (used by pushEvent) ───────────────────────

suite "feishu_pure.parseEvent routing":

  test "url_verification produces fmkEvent with challenge":
    let r = parseEvent(%* {"type": "url_verification", "challenge": "ch99", "token": "t"})
    check r.kind      == fmkEvent
    check r.challenge == "ch99"
    check r.isVerification

  test "text message produces fmkText":
    let payload = %* {
      "schema": "2.0",
      "header": {
        "event_id":   "ev1",
        "event_type": "im.message.receive_v1",
      },
      "event": {
        "message": {
          "message_type": "text",
          "message_id":   "om_text1",
          "chat_id":      "oc_1",
          "chat_type":    "p2p",
          "content":      "{\"text\":\"hello world\"}",
        },
        "sender": {
          "sender_id": {"open_id": "ou_sender1"},
        },
      },
    }
    let r = parseEvent(payload)
    check r.kind      == fmkText
    check r.rawId     == "ou_sender1"
    check r.text      == "hello world"
    check r.messageId == "om_text1"
    check r.chatId    == "oc_1"
    check r.chatType  == "p2p"

  test "image message produces fmkImage":
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "image",
          "message_id":   "om_img1",
          "chat_id":      "oc_2",
          "chat_type":    "group",
          "content":      "{\"image_key\":\"img_abc\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_s2"}},
      },
    }
    let r = parseEvent(payload)
    check r.kind    == fmkImage
    check r.fileKey == "img_abc"

  test "audio message produces fmkAudio":
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "audio",
          "message_id":   "om_aud1",
          "chat_id":      "oc_3",
          "chat_type":    "p2p",
          "content":      "{\"file_key\":\"fk_audio\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_s3"}},
      },
    }
    let r = parseEvent(payload)
    check r.kind    == fmkAudio
    check r.fileKey == "fk_audio"

  test "other event type produces fmkEvent (not message)":
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "p2p_chat_create"},
      "event": {},
    }
    let r = parseEvent(payload)
    check r.kind      == fmkEvent
    check r.eventType == "p2p_chat_create"
    check not r.isVerification

  test "nil payload produces fmkUnknown":
    let r = parseEvent(newJNull())
    check r.kind == fmkUnknown

# ── pushEvent → tryRecvEvent ──────────────────────────────────────────────────

suite "pushEvent and tryRecvEvent":

  test "text event is enqueued and dequeued":
    let a = newFeishuAdapter("cli_Q1", "s", "/tmp/ids_fsq1.tsv")
    a.openQueue()
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "text",
          "message_id":   "om_q1",
          "chat_id":      "oc_q1",
          "chat_type":    "p2p",
          "content":      "{\"text\":\"test msg\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_q1"}},
      },
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType  == "text"
    check ev.openId   == "ou_q1"
    check ev.msgId    == "om_q1"
    check ev.chatId   == "oc_q1"
    check ev.chatType == "p2p"
    check ev.content  == "test msg"

  test "image event is enqueued with correct msgType":
    let a = newFeishuAdapter("cli_Q2", "s", "/tmp/ids_fsq2.tsv")
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "image",
          "message_id":   "om_q2",
          "chat_id":      "oc_q2",
          "chat_type":    "group",
          "content":      "{\"image_key\":\"img_q2\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_q2"}},
      },
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType == "image"
    check ev.openId  == "ou_q2"
    check ev.content == ""

  test "url_verification is not enqueued":
    let a = newFeishuAdapter("cli_Q3", "s", "/tmp/ids_fsq3.tsv")
    pushEvent(%* {"type": "url_verification", "challenge": "ch", "token": "t"})
    let (ok, _) = a.tryRecvEvent()
    check not ok

  test "unknown payload is not enqueued":
    let a = newFeishuAdapter("cli_Q4", "s", "/tmp/ids_fsq4.tsv")
    pushEvent(%* {"random": "data"})
    let (ok, _) = a.tryRecvEvent()
    check not ok

  test "non-message event (fmkEvent) is not enqueued":
    let a = newFeishuAdapter("cli_Q5", "s", "/tmp/ids_fsq5.tsv")
    pushEvent(%* {
      "schema": "2.0",
      "header": {"event_type": "p2p_chat_create"},
      "event": {},
    })
    let (ok, _) = a.tryRecvEvent()
    check not ok

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "feishu_pure.toInbound":

  test "converts text result to InboundMessage":
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "text",
          "message_id":   "om_conv1",
          "chat_id":      "oc_conv1",
          "chat_type":    "p2p",
          "content":      "{\"text\":\"hello feishu\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_conv1"}},
      },
    }
    let r      = parseEvent(payload)
    let userId = UserId("test-uuid-feishu-0000")
    let msg    = r.toInbound(userId)
    check msg.userId    == userId
    check msg.channel   == ckFeishu
    check msg.channelId == "om_conv1"
    check msg.text      == "hello feishu"
    check msg.mediaUrl  == ""

  test "image result maps fileKey to mediaUrl":
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "image",
          "message_id":   "om_img2",
          "chat_id":      "oc_img2",
          "chat_type":    "p2p",
          "content":      "{\"image_key\":\"img_tokey\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_img2"}},
      },
    }
    let r   = parseEvent(payload)
    let msg = r.toInbound(UserId("uid-img"))
    check msg.mediaUrl == "img_tokey"
    check msg.text     == ""

  test "hasMedia is true for image":
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "image",
          "message_id":   "om_hm1",
          "chat_id":      "oc_hm1",
          "chat_type":    "p2p",
          "content":      "{\"image_key\":\"k1\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_hm1"}},
      },
    }
    let r = parseEvent(payload)
    check r.hasMedia

  test "hasMedia is false for text":
    let payload = %* {
      "schema": "2.0",
      "header": {"event_type": "im.message.receive_v1"},
      "event": {
        "message": {
          "message_type": "text",
          "message_id":   "om_hm2",
          "chat_id":      "oc_hm2",
          "chat_type":    "p2p",
          "content":      "{\"text\":\"hi\"}",
        },
        "sender": {"sender_id": {"open_id": "ou_hm2"}},
      },
    }
    let r = parseEvent(payload)
    check not r.hasMedia
