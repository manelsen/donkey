## QQWebhookAdapter unit tests.
## HTTP calls are not made; tests cover adapter construction, identity
## resolution, event queue routing, and parsing via qq_pure.

import std/[json, os, unittest]
import donkey/adapters/channel/qq_webhook
import donkey/adapters/identity/identity_resolver
import donkey/core/types
import donkey/domain/channels/qq_pure

# ── IdentityResolver (QQ webhook) ─────────────────────────────────────────────

suite "IdentityResolver (QQ webhook)":

  test "creates new UUID for unknown user_openid":
    let path = getTempDir() / "donkey_test_ids_qqwb1.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r   = newIdentityResolver(path)
    let uid = r.resolve(ckQQ, "user-openid-abc")
    check ($uid).len == 36

  test "same user_openid returns same UserId":
    let path = getTempDir() / "donkey_test_ids_qqwb2.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckQQ, "user-abc")
    let u2 = r.resolve(ckQQ, "user-abc")
    check u1 == u2

  test "different openids get different UserIds":
    let path = getTempDir() / "donkey_test_ids_qqwb3.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckQQ, "user-aaa")
    let u2 = r.resolve(ckQQ, "user-bbb")
    check u1 != u2

  test "group routing key creates distinct entry":
    let path = getTempDir() / "donkey_test_ids_qqwb4.tsv"
    removeFile(path)
    defer: removeFile(path)
    let r  = newIdentityResolver(path)
    let u1 = r.resolve(ckQQ, "group:grp-123")
    let u2 = r.resolve(ckQQ, "user-abc")
    check u1 != u2

# ── QQWebhookAdapter construction ─────────────────────────────────────────────

suite "QQWebhookAdapter construction":

  test "appId is stored":
    let a = newQQWebhookAdapter("app-001", "secret", "/tmp/ids_qqwb_c1.tsv",
                                apiBase = "https://mock.local")
    check a.appId == "app-001"

  test "clientSecret is stored":
    let a = newQQWebhookAdapter("app-002", "my_secret", "/tmp/ids_qqwb_c2.tsv")
    check a.clientSecret == "my_secret"

  test "apiBase override is stored":
    let a = newQQWebhookAdapter("app-003", "s3", "/tmp/ids_qqwb_c3.tsv",
                                apiBase = "https://test.api")
    check a.apiBase == "https://test.api"

  test "default apiBase is empty string":
    let a = newQQWebhookAdapter("app-004", "s4", "/tmp/ids_qqwb_c4.tsv")
    check a.apiBase == ""

  test "tokenBase override is stored":
    let a = newQQWebhookAdapter("app-005", "s5", "/tmp/ids_qqwb_c5.tsv",
                                tokenBase = "https://tok.local")
    check a.tokenBase == "https://tok.local"

  test "default tokenBase is empty string":
    let a = newQQWebhookAdapter("app-006", "s6", "/tmp/ids_qqwb_c6.tsv")
    check a.tokenBase == ""

# ── pushEvent → tryRecvEvent ──────────────────────────────────────────────────

suite "pushEvent and tryRecvEvent":

  test "c2c private event is enqueued":
    let a = newQQWebhookAdapter("app-q1", "s", "/tmp/ids_qqwb_q1.tsv")
    a.openQueue()
    let payload = %* {
      "t": "C2C_MESSAGE_CREATE",
      "d": {
        "id":      "msg-priv-1",
        "content": "hello",
        "author":  {"user_openid": "user-open-1"},
      },
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.messageType == "private"
    check ev.userId      == "user-open-1"
    check ev.messageId   == "msg:msg-priv-1"
    check ev.content     == "hello"
    check ev.groupId     == ""

  test "group event is enqueued with groupId":
    let a = newQQWebhookAdapter("app-q2", "s", "/tmp/ids_qqwb_q2.tsv")
    let payload = %* {
      "t": "GROUP_AT_MESSAGE_CREATE",
      "d": {
        "id":           "msg-grp-1",
        "content":      "hi group",
        "group_openid": "grp-open-1",
        "author":       {"member_openid": "member-open-1"},
      },
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.messageType == "group"
    check ev.userId      == "member-open-1"
    check ev.groupId     == "grp-open-1"
    check ev.messageId   == "msg:msg-grp-1"
    check ev.content     == "hi group"

  test "interaction event is enqueued with callback text":
    let a = newQQWebhookAdapter("app-q3", "s", "/tmp/ids_qqwb_q3.tsv")
    let payload = %* {
      "t": "INTERACTION_CREATE",
      "d": {
        "id":                  "evt-click-1",
        "scene":               "group",
        "group_openid":        "grp-open-2",
        "group_member_openid": "member-open-2",
        "data": {
          "resolved": {"button_data": "models:provider:zai"},
        },
      },
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.messageType == "interaction"
    check ev.userId      == "member-open-2"
    check ev.groupId     == "grp-open-2"
    check ev.content     == "/callback models:provider:zai"

  test "flat webhook format (no t field) is parsed":
    let a = newQQWebhookAdapter("app-q4", "s", "/tmp/ids_qqwb_q4.tsv")
    let payload = %* {
      "id":           "msg-flat-1",
      "content":      "flat event",
      "group_openid": "grp-flat",
      "author":       {"member_openid": "member-flat"},
    }
    pushEvent(payload)
    let (ok, ev) = a.tryRecvEvent()
    check ok
    check ev.messageType == "group"
    check ev.groupId     == "grp-flat"

  test "unknown payload is not enqueued":
    let a = newQQWebhookAdapter("app-q5", "s", "/tmp/ids_qqwb_q5.tsv")
    pushEvent(%* {"random": "data"})
    let (ok, _) = a.tryRecvEvent()
    check not ok

  test "empty queue returns false":
    let a = newQQWebhookAdapter("app-q6", "s", "/tmp/ids_qqwb_q6.tsv")
    let (ok, _) = a.tryRecvEvent()
    check not ok

# ── qq_pure.parseEvent routing ────────────────────────────────────────────────

suite "qq_pure.parseEvent routing":

  test "C2C_MESSAGE_CREATE produces qqkPrivate":
    let r = parseEvent(%* {
      "t": "C2C_MESSAGE_CREATE",
      "d": {
        "id":      "msg-1",
        "content": "hello",
        "author":  {"user_openid": "user-1"},
      },
    })
    check r.kind      == qqkPrivate
    check r.rawId     == "user-1"
    check r.text      == "hello"
    check r.messageId == "msg:msg-1"
    check r.groupId   == ""

  test "GROUP_AT_MESSAGE_CREATE produces qqkGroup":
    let r = parseEvent(%* {
      "t": "GROUP_AT_MESSAGE_CREATE",
      "d": {
        "id":           "msg-2",
        "content":      "grp hi",
        "group_openid": "grp-1",
        "author":       {"member_openid": "member-1"},
      },
    })
    check r.kind      == qqkGroup
    check r.rawId     == "member-1"
    check r.groupId   == "grp-1"
    check r.messageId == "msg:msg-2"

  test "INTERACTION_CREATE produces qqkInteraction":
    let r = parseEvent(%* {
      "t": "INTERACTION_CREATE",
      "d": {
        "id":          "evt-1",
        "scene":       "c2c",
        "user_openid": "user-int",
        "data": {
          "resolved": {"button_data": "action:foo"},
        },
      },
    })
    check r.kind == qqkInteraction
    check r.text == "/callback action:foo"

  test "unknown event type produces qqkUnknown":
    let r = parseEvent(%* {"t": "UNSUPPORTED_EVENT", "d": {}})
    check r.kind == qqkUnknown

  test "nil payload produces qqkUnknown":
    let r = parseEvent(newJNull())
    check r.kind == qqkUnknown

# ── qq_pure.toInbound ─────────────────────────────────────────────────────────

suite "qq_pure.toInbound":

  test "converts private result to InboundMessage":
    let r = parseEvent(%* {
      "t": "C2C_MESSAGE_CREATE",
      "d": {
        "id":      "msg-conv1",
        "content": "hello qq",
        "author":  {"user_openid": "user-conv1"},
      },
    })
    let uid = UserId("test-uuid-qqwb-0001")
    let msg = r.toInbound(uid)
    check msg.userId    == uid
    check msg.channel   == ckQQ
    check msg.channelId == "msg:msg-conv1"
    check msg.text      == "hello qq"
    check msg.mediaUrl  == ""

  test "hasMedia is always false for QQ v1":
    let r = parseEvent(%* {
      "t": "C2C_MESSAGE_CREATE",
      "d": {
        "id":      "msg-hm1",
        "content": "any",
        "author":  {"user_openid": "user-hm1"},
      },
    })
    check not r.hasMedia

  test "qqRawIdentity uses group prefix for group events":
    let r = parseEvent(%* {
      "t": "GROUP_AT_MESSAGE_CREATE",
      "d": {
        "id":           "msg-ri1",
        "content":      "hi",
        "group_openid": "grp-ri1",
        "author":       {"member_openid": "member-ri1"},
      },
    })
    check r.qqRawIdentity == "group:grp-ri1"

  test "qqRawIdentity uses rawId for private events":
    let r = parseEvent(%* {
      "t": "C2C_MESSAGE_CREATE",
      "d": {
        "id":      "msg-ri2",
        "content": "hi",
        "author":  {"user_openid": "user-ri2"},
      },
    })
    check r.qqRawIdentity == "user-ri2"

  test "isInteraction is true for INTERACTION_CREATE":
    let r = parseEvent(%* {
      "t": "INTERACTION_CREATE",
      "d": {
        "id":          "evt-is1",
        "scene":       "c2c",
        "user_openid": "user-is1",
        "data": {"resolved": {"button_data": "foo"}},
      },
    })
    check r.isInteraction

  test "isInteraction is false for message events":
    let r = parseEvent(%* {
      "t": "C2C_MESSAGE_CREATE",
      "d": {
        "id":      "msg-is2",
        "content": "hi",
        "author":  {"user_openid": "user-is2"},
      },
    })
    check not r.isInteraction
