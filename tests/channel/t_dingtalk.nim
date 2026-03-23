## DingTalkAdapter unit tests.
## HTTP calls are not made; tests cover adapter construction, identity
## resolution, event queue routing, and pure parser integration.

import std/[json, os, unittest]
import donkey/adapters/channel/dingtalk
import donkey/adapters/identity/identity_resolver
import donkey/core/types
import donkey/domain/channels/dingtalk_pure

# ── IdentityResolver (DingTalk) ───────────────────────────────────────────────

suite "IdentityResolver (DingTalk)":

  test "creates new UUID for unknown senderId":
    let path = getTempDir() / "donkey_test_ids_dt1.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckDingTalk, "staff-abc")
    check ($uid).len == 36

  test "same senderId returns same UserId":
    let path = getTempDir() / "donkey_test_ids_dt2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckDingTalk, "staff-abc")
    let u2 = r.resolve(ckDingTalk, "staff-abc")
    check u1 == u2

  test "different senderIds get different UserIds":
    let path = getTempDir() / "donkey_test_ids_dt3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckDingTalk, "staff-aaa")
    let u2 = r.resolve(ckDingTalk, "staff-bbb")
    check u1 != u2

  test "group routing key creates distinct entry from staff":
    let path = getTempDir() / "donkey_test_ids_dt4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckDingTalk, "conv:conv-123")
    let u2 = r.resolve(ckDingTalk, "staff-abc")
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_ids_dt5.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid1 = newIdentityResolver(path).resolve(ckDingTalk, "staff-ccc")
    let uid2 = newIdentityResolver(path).resolve(ckDingTalk, "staff-ccc")
    check uid1 == uid2

# ── DingTalkAdapter construction ──────────────────────────────────────────────

suite "DingTalkAdapter construction":

  test "appKey is stored":
    let a = newDingTalkAdapter("key-001", "secret", "robot-1",
                               "/tmp/ids_dtc1.tsv",
                               apiBase = "https://mock.local")
    check a.appKey == "key-001"

  test "appSecret is stored":
    let a = newDingTalkAdapter("key-002", "my_secret", "robot-2",
                               "/tmp/ids_dtc2.tsv")
    check a.appSecret == "my_secret"

  test "robotCode is stored":
    let a = newDingTalkAdapter("key-003", "s3", "robot-code-abc",
                               "/tmp/ids_dtc3.tsv")
    check a.robotCode == "robot-code-abc"

  test "apiBase override is stored":
    let a = newDingTalkAdapter("key-004", "s4", "rc4",
                               "/tmp/ids_dtc4.tsv",
                               apiBase = "https://test.dingtalk")
    check a.apiBase == "https://test.dingtalk"

  test "default apiBase is empty string":
    let a = newDingTalkAdapter("key-005", "s5", "rc5", "/tmp/ids_dtc5.tsv")
    check a.apiBase == ""

# ── pushEvent → tryRecvEvent ──────────────────────────────────────────────────

suite "pushEvent and tryRecvEvent":

  test "text p2p event is enqueued":
    let a = newDingTalkAdapter("key-q1", "s", "rc", "/tmp/ids_dtq1.tsv")
    a.openQueue()
    let payload = %* {
      "msgtype":          "text",
      "msgId":            "msg-text-1",
      "senderId":         "staff-001",
      "conversationId":   "conv-001",
      "conversationType": "1",
      "text":             {"content": "hello dingtalk"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType   == "text"
    check ev.rawId     == "staff-001"
    check ev.messageId == "msg-text-1"
    check ev.content   == "hello dingtalk"

  test "text group event uses conv: prefix":
    let a = newDingTalkAdapter("key-q2", "s", "rc", "/tmp/ids_dtq2.tsv")
    let payload = %* {
      "msgtype":          "text",
      "msgId":            "msg-grp-1",
      "senderId":         "staff-002",
      "conversationId":   "conv-grp-1",
      "conversationType": "2",
      "text":             {"content": "group hello"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType   == "text"
    check ev.rawId     == "conv:conv-grp-1"
    check ev.messageId == "msg-grp-1"
    check ev.content   == "group hello"

  test "image event is enqueued with downloadCode":
    let a = newDingTalkAdapter("key-q3", "s", "rc", "/tmp/ids_dtq3.tsv")
    let payload = %* {
      "msgtype":          "picture",
      "msgId":            "msg-img-1",
      "senderId":         "staff-003",
      "conversationId":   "conv-003",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_img_001\"}",
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType      == "image"
    check ev.rawId        == "staff-003"
    check ev.downloadCode == "dc_img_001"
    check ev.content      == ""

  test "audio event is enqueued":
    let a = newDingTalkAdapter("key-q4", "s", "rc", "/tmp/ids_dtq4.tsv")
    let payload = %* {
      "msgtype":          "audio",
      "msgId":            "msg-aud-1",
      "senderId":         "staff-004",
      "conversationId":   "conv-004",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_aud_001\"}",
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType      == "audio"
    check ev.downloadCode == "dc_aud_001"

  test "video event is enqueued":
    let a = newDingTalkAdapter("key-q5", "s", "rc", "/tmp/ids_dtq5.tsv")
    let payload = %* {
      "msgtype":          "video",
      "msgId":            "msg-vid-1",
      "senderId":         "staff-005",
      "conversationId":   "conv-005",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_vid_001\"}",
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType      == "video"
    check ev.downloadCode == "dc_vid_001"

  test "file event is enqueued":
    let a = newDingTalkAdapter("key-q6", "s", "rc", "/tmp/ids_dtq6.tsv")
    let payload = %* {
      "msgtype":          "file",
      "msgId":            "msg-file-1",
      "senderId":         "staff-006",
      "conversationId":   "conv-006",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_file_001\"}",
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType      == "file"
    check ev.downloadCode == "dc_file_001"

  test "unknown payload is not enqueued":
    let a = newDingTalkAdapter("key-q7", "s", "rc", "/tmp/ids_dtq7.tsv")
    pushEvent(%* {"random": "data"})
    let (ok, _) = a.tryRecvEvent()
    check not ok

  test "empty queue returns false":
    let a = newDingTalkAdapter("key-q8", "s", "rc", "/tmp/ids_dtq8.tsv")
    let (ok, _) = a.tryRecvEvent()
    check not ok

# ── dingtalk_pure.parseEvent routing ─────────────────────────────────────────

suite "dingtalk_pure.parseEvent routing":

  test "text msgtype produces dtkText":
    let r = parseEvent(%* {
      "msgtype":          "text",
      "msgId":            "p-text-1",
      "senderId":         "sender-1",
      "conversationId":   "conv-p1",
      "conversationType": "1",
      "text":             {"content": "hello"},
    })
    check r.kind           == dtkText
    check r.rawId          == "sender-1"
    check r.messageId      == "p-text-1"
    check r.text           == "hello"
    check r.conversationId == "conv-p1"
    check not r.isGroup

  test "markdown msgtype produces dtkText":
    let r = parseEvent(%* {
      "msgtype":          "markdown",
      "msgId":            "p-md-1",
      "senderId":         "sender-md",
      "conversationId":   "conv-md",
      "conversationType": "1",
      "text":             {"content": "**bold**"},
    })
    check r.kind == dtkText
    check r.text == "**bold**"

  test "group text event sets isGroup":
    let r = parseEvent(%* {
      "msgtype":          "text",
      "msgId":            "p-grp-1",
      "senderId":         "sender-grp",
      "conversationId":   "conv-grp",
      "conversationType": "2",
      "text":             {"content": "group msg"},
    })
    check r.kind    == dtkText
    check r.isGroup == true

  test "picture msgtype produces dtkImage":
    let r = parseEvent(%* {
      "msgtype":          "picture",
      "msgId":            "p-img-1",
      "senderId":         "sender-img",
      "conversationId":   "conv-img",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_img\"}",
    })
    check r.kind         == dtkImage
    check r.downloadCode == "dc_img"

  test "audio msgtype produces dtkAudio":
    let r = parseEvent(%* {
      "msgtype":          "audio",
      "msgId":            "p-aud-1",
      "senderId":         "sender-aud",
      "conversationId":   "conv-aud",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_aud\"}",
    })
    check r.kind         == dtkAudio
    check r.downloadCode == "dc_aud"

  test "video msgtype produces dtkVideo":
    let r = parseEvent(%* {
      "msgtype":          "video",
      "msgId":            "p-vid-1",
      "senderId":         "sender-vid",
      "conversationId":   "conv-vid",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_vid\"}",
    })
    check r.kind == dtkVideo

  test "file msgtype produces dtkFile":
    let r = parseEvent(%* {
      "msgtype":          "file",
      "msgId":            "p-file-1",
      "senderId":         "sender-file",
      "conversationId":   "conv-file",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_file\"}",
    })
    check r.kind == dtkFile

  test "unknown msgtype produces dtkUnknown":
    let r = parseEvent(%* {
      "msgtype":  "voice_call",
      "msgId":    "p-unk-1",
      "senderId": "sender-unk",
    })
    check r.kind == dtkUnknown

  test "nil payload produces dtkUnknown":
    let r = parseEvent(newJNull())
    check r.kind == dtkUnknown

# ── dingtalk_pure.toInbound ───────────────────────────────────────────────────

suite "dingtalk_pure.toInbound":

  test "converts text result to InboundMessage":
    let r = parseEvent(%* {
      "msgtype":          "text",
      "msgId":            "msg-conv1",
      "senderId":         "staff-conv1",
      "conversationId":   "c-conv1",
      "conversationType": "1",
      "text":             {"content": "hello dingtalk"},
    })
    let uid = UserId("test-uuid-dt-0001")
    let msg = r.toInbound(uid)
    check msg.userId    == uid
    check msg.channel   == ckDingTalk
    check msg.channelId == "msg-conv1"
    check msg.text      == "hello dingtalk"
    check msg.mediaUrl  == ""

  test "image result maps downloadCode to mediaUrl":
    let r = parseEvent(%* {
      "msgtype":          "picture",
      "msgId":            "msg-img2",
      "senderId":         "staff-img2",
      "conversationId":   "c-img2",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_img2\"}",
    })
    let msg = r.toInbound(UserId("uid-img"))
    check msg.mediaUrl == "dc_img2"
    check msg.text     == ""

  test "hasMedia is true for image":
    let r = parseEvent(%* {
      "msgtype":          "picture",
      "msgId":            "msg-hm1",
      "senderId":         "staff-hm1",
      "conversationId":   "c-hm1",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_hm1\"}",
    })
    check r.hasMedia

  test "hasMedia is true for audio":
    let r = parseEvent(%* {
      "msgtype":          "audio",
      "msgId":            "msg-hm2",
      "senderId":         "staff-hm2",
      "conversationId":   "c-hm2",
      "conversationType": "1",
      "content":          "{\"downloadCode\":\"dc_hm2\"}",
    })
    check r.hasMedia

  test "hasMedia is false for text":
    let r = parseEvent(%* {
      "msgtype":          "text",
      "msgId":            "msg-hm3",
      "senderId":         "staff-hm3",
      "conversationId":   "c-hm3",
      "conversationType": "1",
      "text":             {"content": "hi"},
    })
    check not r.hasMedia
