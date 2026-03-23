## MatrixAdapter unit tests.
## HTTP calls are not made; tests cover adapter construction, identity
## resolution, event queue routing, and pure parser integration.

import std/[json, os, unittest]
import donkey/adapters/channel/matrix
import donkey/adapters/identity/identity_resolver
import donkey/core/types
import donkey/domain/channels/matrix_pure

# ── IdentityResolver (Matrix) ─────────────────────────────────────────────────

suite "IdentityResolver (Matrix)":

  test "creates new UUID for unknown room_id":
    let path = getTempDir() / "donkey_test_ids_mx1.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckMatrix, "!room-abc:matrix.org")
    check ($uid).len == 36

  test "same room_id returns same UserId":
    let path = getTempDir() / "donkey_test_ids_mx2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckMatrix, "!room-abc:matrix.org")
    let u2 = r.resolve(ckMatrix, "!room-abc:matrix.org")
    check u1 == u2

  test "different room_ids get different UserIds":
    let path = getTempDir() / "donkey_test_ids_mx3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckMatrix, "!room-aaa:matrix.org")
    let u2 = r.resolve(ckMatrix, "!room-bbb:matrix.org")
    check u1 != u2

  test "identity persists across resolver instances":
    let path = getTempDir() / "donkey_test_ids_mx4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let uid1 = newIdentityResolver(path).resolve(ckMatrix, "!room-ccc:matrix.org")
    let uid2 = newIdentityResolver(path).resolve(ckMatrix, "!room-ccc:matrix.org")
    check uid1 == uid2

# ── MatrixAdapter construction ────────────────────────────────────────────────

suite "MatrixAdapter construction":

  test "homeserver is stored":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-001", "/tmp/ids_mxc1.tsv")
    check a.homeserver == "https://matrix.example.com"

  test "botUserId is stored":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-002", "/tmp/ids_mxc2.tsv")
    check a.botUserId == "@bot:example.com"

  test "accessToken is stored":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "syt_token_abc", "/tmp/ids_mxc3.tsv")
    check a.accessToken == "syt_token_abc"

  test "apiBase override is stored":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-004", "/tmp/ids_mxc4.tsv",
                             apiBase = "https://mock.local")
    check a.apiBase == "https://mock.local"

  test "default apiBase is empty string":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-005", "/tmp/ids_mxc5.tsv")
    check a.apiBase == ""

# ── pushEvent → tryRecvEvent ──────────────────────────────────────────────────

suite "pushEvent and tryRecvEvent":

  test "text event is enqueued":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q1", "/tmp/ids_mxq1.tsv")
    a.openQueue()
    let payload = %* {
      "type":     "m.room.message",
      "room_id":  "!room-q1:matrix.org",
      "event_id": "$evt-q1:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.text", "body": "hello matrix"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType  == "text"
    check ev.roomId   == "!room-q1:matrix.org"
    check ev.senderId == "@alice:matrix.org"
    check ev.eventId  == "$evt-q1:matrix.org"
    check ev.content  == "hello matrix"

  test "m.notice event is enqueued as text":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q2", "/tmp/ids_mxq2.tsv")
    let payload = %* {
      "type":     "m.room.message",
      "room_id":  "!room-q2:matrix.org",
      "event_id": "$evt-q2:matrix.org",
      "sender":   "@bob:matrix.org",
      "content":  {"msgtype": "m.notice", "body": "notice text"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType == "text"
    check ev.content == "notice text"

  test "image event is enqueued with mediaUrl":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q3", "/tmp/ids_mxq3.tsv")
    let payload = %* {
      "type":     "m.room.message",
      "room_id":  "!room-q3:matrix.org",
      "event_id": "$evt-q3:matrix.org",
      "sender":   "@carol:matrix.org",
      "content":  {"msgtype": "m.image", "body": "image.png",
                   "url": "mxc://matrix.org/abc123"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType  == "image"
    check ev.mediaUrl == "mxc://matrix.org/abc123"
    check ev.content  == ""

  test "audio event is enqueued":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q4", "/tmp/ids_mxq4.tsv")
    let payload = %* {
      "type":     "m.room.message",
      "room_id":  "!room-q4:matrix.org",
      "event_id": "$evt-q4:matrix.org",
      "sender":   "@dave:matrix.org",
      "content":  {"msgtype": "m.audio", "body": "audio.ogg",
                   "url": "mxc://matrix.org/audio1"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType  == "audio"
    check ev.mediaUrl == "mxc://matrix.org/audio1"

  test "video event is enqueued":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q5", "/tmp/ids_mxq5.tsv")
    let payload = %* {
      "type":     "m.room.message",
      "room_id":  "!room-q5:matrix.org",
      "event_id": "$evt-q5:matrix.org",
      "sender":   "@eve:matrix.org",
      "content":  {"msgtype": "m.video", "body": "video.mp4",
                   "url": "mxc://matrix.org/video1"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType  == "video"
    check ev.mediaUrl == "mxc://matrix.org/video1"

  test "file event is enqueued":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q6", "/tmp/ids_mxq6.tsv")
    let payload = %* {
      "type":     "m.room.message",
      "room_id":  "!room-q6:matrix.org",
      "event_id": "$evt-q6:matrix.org",
      "sender":   "@frank:matrix.org",
      "content":  {"msgtype": "m.file", "body": "doc.pdf",
                   "url": "mxc://matrix.org/file1"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.msgType  == "file"
    check ev.mediaUrl == "mxc://matrix.org/file1"

  test "non-message event type is not enqueued":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q7", "/tmp/ids_mxq7.tsv")
    pushEvent(%* {"type": "m.room.member", "room_id": "!r:s",
                  "event_id": "$e:s", "sender": "@u:s",
                  "content": {"membership": "join"}})
    let (ok, _) = a.tryRecvEvent()
    check not ok

  test "unknown msgtype is not enqueued":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q8", "/tmp/ids_mxq8.tsv")
    pushEvent(%* {"type": "m.room.message", "room_id": "!r:s",
                  "event_id": "$e:s", "sender": "@u:s",
                  "content": {"msgtype": "m.location", "body": "loc"}})
    let (ok, _) = a.tryRecvEvent()
    check not ok

  test "empty queue returns false":
    let a = newMatrixAdapter("https://matrix.example.com", "@bot:example.com",
                             "tok-q9", "/tmp/ids_mxq9.tsv")
    let (ok, _) = a.tryRecvEvent()
    check not ok

# ── matrix_pure.parseEvent routing ───────────────────────────────────────────

suite "matrix_pure.parseEvent routing":

  test "m.text produces mxkText":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-p1:matrix.org",
      "event_id": "$evt-p1:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.text", "body": "hello"},
    })
    check r.kind     == mxkText
    check r.roomId   == "!room-p1:matrix.org"
    check r.senderId == "@alice:matrix.org"
    check r.eventId  == "$evt-p1:matrix.org"
    check r.text     == "hello"

  test "m.notice produces mxkText":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-p2:matrix.org",
      "event_id": "$evt-p2:matrix.org",
      "sender":   "@bot:matrix.org",
      "content":  {"msgtype": "m.notice", "body": "notice body"},
    })
    check r.kind == mxkText
    check r.text == "notice body"

  test "m.emote produces mxkText":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-p3:matrix.org",
      "event_id": "$evt-p3:matrix.org",
      "sender":   "@user:matrix.org",
      "content":  {"msgtype": "m.emote", "body": "waves"},
    })
    check r.kind == mxkText
    check r.text == "waves"

  test "m.image produces mxkImage":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-p4:matrix.org",
      "event_id": "$evt-p4:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.image", "body": "img.png",
                   "url": "mxc://matrix.org/img1"},
    })
    check r.kind     == mxkImage
    check r.mediaUrl == "mxc://matrix.org/img1"
    check r.text     == ""

  test "m.audio produces mxkAudio":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-p5:matrix.org",
      "event_id": "$evt-p5:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.audio", "body": "audio.ogg",
                   "url": "mxc://matrix.org/aud1"},
    })
    check r.kind     == mxkAudio
    check r.mediaUrl == "mxc://matrix.org/aud1"

  test "m.video produces mxkVideo":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-p6:matrix.org",
      "event_id": "$evt-p6:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.video", "body": "video.mp4",
                   "url": "mxc://matrix.org/vid1"},
    })
    check r.kind == mxkVideo

  test "m.file produces mxkFile":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-p7:matrix.org",
      "event_id": "$evt-p7:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.file", "body": "doc.pdf",
                   "url": "mxc://matrix.org/file1"},
    })
    check r.kind == mxkFile

  test "unknown msgtype produces mxkUnknown":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-p8:matrix.org",
      "event_id": "$evt-p8:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.location", "body": "loc"},
    })
    check r.kind == mxkUnknown

  test "non-message event type produces mxkUnknown":
    let r = parseEvent(%* {
      "type":     "m.room.member",
      "room_id":  "!room-p9:matrix.org",
      "event_id": "$evt-p9:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"membership": "join"},
    })
    check r.kind == mxkUnknown

  test "nil payload produces mxkUnknown":
    let r = parseEvent(newJNull())
    check r.kind == mxkUnknown

  test "missing room_id produces mxkUnknown":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "event_id": "$evt-pa:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.text", "body": "hi"},
    })
    check r.kind == mxkUnknown

  test "missing sender produces mxkUnknown":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-pb:matrix.org",
      "event_id": "$evt-pb:matrix.org",
      "content":  {"msgtype": "m.text", "body": "hi"},
    })
    check r.kind == mxkUnknown

# ── matrix_pure.toInbound ─────────────────────────────────────────────────────

suite "matrix_pure.toInbound":

  test "converts text result to InboundMessage":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-ti1:matrix.org",
      "event_id": "$evt-ti1:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.text", "body": "hello matrix"},
    })
    let uid = UserId("test-uuid-mx-0001")
    let msg = r.toInbound(uid)
    check msg.userId    == uid
    check msg.channel   == ckMatrix
    check msg.channelId == "$evt-ti1:matrix.org"
    check msg.text      == "hello matrix"
    check msg.mediaUrl  == ""

  test "image result maps mediaUrl":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-ti2:matrix.org",
      "event_id": "$evt-ti2:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.image", "body": "img.png",
                   "url": "mxc://matrix.org/img2"},
    })
    let msg = r.toInbound(UserId("uid-img"))
    check msg.mediaUrl == "mxc://matrix.org/img2"
    check msg.text     == ""

  test "hasMedia is true for image":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-hm1:matrix.org",
      "event_id": "$evt-hm1:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.image", "body": "img.png",
                   "url": "mxc://matrix.org/img_hm1"},
    })
    check r.hasMedia

  test "hasMedia is true for audio":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-hm2:matrix.org",
      "event_id": "$evt-hm2:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.audio", "body": "audio.ogg",
                   "url": "mxc://matrix.org/aud_hm2"},
    })
    check r.hasMedia

  test "hasMedia is true for video":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-hm3:matrix.org",
      "event_id": "$evt-hm3:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.video", "body": "video.mp4",
                   "url": "mxc://matrix.org/vid_hm3"},
    })
    check r.hasMedia

  test "hasMedia is true for file":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-hm4:matrix.org",
      "event_id": "$evt-hm4:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.file", "body": "doc.pdf",
                   "url": "mxc://matrix.org/file_hm4"},
    })
    check r.hasMedia

  test "hasMedia is false for text":
    let r = parseEvent(%* {
      "type":     "m.room.message",
      "room_id":  "!room-hm5:matrix.org",
      "event_id": "$evt-hm5:matrix.org",
      "sender":   "@alice:matrix.org",
      "content":  {"msgtype": "m.text", "body": "plain text"},
    })
    check not r.hasMedia
