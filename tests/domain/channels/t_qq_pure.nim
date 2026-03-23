## Tests for domain/channels/qq_pure.nim — pure QQ official bot event parser.
## No I/O or HTTP; all input is constructed directly as JsonNode.

import std/[json, unittest]
import donkey/core/pipeops
import donkey/domain/channels/qq_pure
import donkey/core/types

# ── Fixtures ──────────────────────────────────────────────────────────────────

func makeC2cPayload(userId, msgId, content: string): JsonNode =
  %* {
    "op": 0,
    "t": "C2C_MESSAGE_CREATE",
    "s": 1,
    "d": {
      "author": {"user_openid": userId},
      "id": msgId,
      "content": content
    }
  }

func makeGroupPayload(groupId, memberId, msgId, content: string): JsonNode =
  %* {
    "op": 0,
    "t": "GROUP_AT_MESSAGE_CREATE",
    "s": 2,
    "d": {
      "group_openid": groupId,
      "author": {"member_openid": memberId},
      "id": msgId,
      "content": content
    }
  }

func makeGroupMsgReceivePayload(groupId, memberId, msgId, content: string): JsonNode =
  %* {
    "op": 0,
    "t": "GROUP_MSG_RECEIVE",
    "s": 3,
    "d": {
      "group_openid": groupId,
      "author": {"member_openid": memberId},
      "id": msgId,
      "content": content
    }
  }

func makePrivateInteractionPayload(userId, eventId, buttonData: string): JsonNode =
  %* {
    "op": 0,
    "t": "INTERACTION_CREATE",
    "s": 4,
    "d": {
      "id": eventId,
      "scene": "c2c",
      "user_openid": userId,
      "data": {
        "resolved": {"button_data": buttonData}
      }
    }
  }

func makeGroupInteractionPayload(groupId, memberId, eventId, buttonData: string): JsonNode =
  %* {
    "op": 0,
    "t": "INTERACTION_CREATE",
    "s": 5,
    "d": {
      "id": eventId,
      "scene": "group",
      "group_openid": groupId,
      "group_member_openid": memberId,
      "data": {
        "resolved": {"button_data": buttonData}
      }
    }
  }

func makeFlatC2cPayload(userId, msgId, content: string): JsonNode =
  %* {
    "author": {"user_openid": userId},
    "id": msgId,
    "content": content
  }

func makeFlatGroupPayload(groupId, memberId, msgId, content: string): JsonNode =
  %* {
    "group_openid": groupId,
    "author": {"member_openid": memberId},
    "id": msgId,
    "content": content
  }

# ── parseEvent: C2C_MESSAGE_CREATE ────────────────────────────────────────────

suite "qq_pure: C2C private message":
  test "kind is qqkPrivate":
    let r = makeC2cPayload("user_abc", "msg001", "hello") |> parseEvent
    check r.kind == qqkPrivate

  test "rawId is user_openid":
    let r = makeC2cPayload("user_abc", "msg001", "hello") |> parseEvent
    check r.rawId == "user_abc"

  test "messageId prefixed with msg:":
    let r = makeC2cPayload("user_abc", "msg001", "hello") |> parseEvent
    check r.messageId == "msg:msg001"

  test "text is content":
    let r = makeC2cPayload("user_abc", "msg001", "hello world") |> parseEvent
    check r.text == "hello world"

  test "groupId is empty for private":
    let r = makeC2cPayload("user_abc", "msg001", "hello") |> parseEvent
    check r.groupId == ""

# ── parseEvent: GROUP_AT_MESSAGE_CREATE ───────────────────────────────────────

suite "qq_pure: GROUP_AT_MESSAGE_CREATE":
  test "kind is qqkGroup":
    let r = makeGroupPayload("grp_abc", "mem_xyz", "msg002", "at-msg") |> parseEvent
    check r.kind == qqkGroup

  test "rawId is member_openid":
    let r = makeGroupPayload("grp_abc", "mem_xyz", "msg002", "at-msg") |> parseEvent
    check r.rawId == "mem_xyz"

  test "groupId is group_openid":
    let r = makeGroupPayload("grp_abc", "mem_xyz", "msg002", "at-msg") |> parseEvent
    check r.groupId == "grp_abc"

  test "messageId prefixed with msg:":
    let r = makeGroupPayload("grp_abc", "mem_xyz", "msg002", "at-msg") |> parseEvent
    check r.messageId == "msg:msg002"

  test "text is content":
    let r = makeGroupPayload("grp_abc", "mem_xyz", "msg002", "group hello") |> parseEvent
    check r.text == "group hello"

# ── parseEvent: GROUP_MSG_RECEIVE ─────────────────────────────────────────────

suite "qq_pure: GROUP_MSG_RECEIVE":
  test "kind is qqkGroup":
    let r = makeGroupMsgReceivePayload("grp_def", "mem_001", "msg003", "sub") |> parseEvent
    check r.kind == qqkGroup

  test "rawId and groupId extracted":
    let r = makeGroupMsgReceivePayload("grp_def", "mem_001", "msg003", "sub") |> parseEvent
    check r.rawId == "mem_001"
    check r.groupId == "grp_def"

# ── parseEvent: INTERACTION_CREATE (private) ──────────────────────────────────

suite "qq_pure: INTERACTION_CREATE private":
  test "kind is qqkInteraction":
    let r = makePrivateInteractionPayload("user_p", "evt001", "cmd:start") |> parseEvent
    check r.kind == qqkInteraction

  test "rawId is user_openid":
    let r = makePrivateInteractionPayload("user_p", "evt001", "cmd:start") |> parseEvent
    check r.rawId == "user_p"

  test "messageId prefixed with event:":
    let r = makePrivateInteractionPayload("user_p", "evt001", "cmd:start") |> parseEvent
    check r.messageId == "event:evt001"

  test "text is /callback <data>":
    let r = makePrivateInteractionPayload("user_p", "evt001", "cmd:start") |> parseEvent
    check r.text == "/callback cmd:start"

  test "groupId empty for private interaction":
    let r = makePrivateInteractionPayload("user_p", "evt001", "cmd:start") |> parseEvent
    check r.groupId == ""

# ── parseEvent: INTERACTION_CREATE (group) ────────────────────────────────────

suite "qq_pure: INTERACTION_CREATE group":
  test "kind is qqkInteraction":
    let r = makeGroupInteractionPayload("grp_g", "mem_g", "evt002", "sel:1") |> parseEvent
    check r.kind == qqkInteraction

  test "rawId is group_member_openid":
    let r = makeGroupInteractionPayload("grp_g", "mem_g", "evt002", "sel:1") |> parseEvent
    check r.rawId == "mem_g"

  test "groupId is group_openid":
    let r = makeGroupInteractionPayload("grp_g", "mem_g", "evt002", "sel:1") |> parseEvent
    check r.groupId == "grp_g"

  test "text is /callback <data>":
    let r = makeGroupInteractionPayload("grp_g", "mem_g", "evt002", "sel:1") |> parseEvent
    check r.text == "/callback sel:1"

# ── parseEvent: flat webhook format ───────────────────────────────────────────

suite "qq_pure: flat webhook format":
  test "flat C2C detected as qqkPrivate":
    let r = makeFlatC2cPayload("user_flat", "msg_flat", "flat msg") |> parseEvent
    check r.kind == qqkPrivate

  test "flat C2C rawId correct":
    let r = makeFlatC2cPayload("user_flat", "msg_flat", "flat msg") |> parseEvent
    check r.rawId == "user_flat"

  test "flat group detected as qqkGroup":
    let r = makeFlatGroupPayload("grp_flat", "mem_flat", "msg_flat2", "flat group") |> parseEvent
    check r.kind == qqkGroup

  test "flat group rawId and groupId correct":
    let r = makeFlatGroupPayload("grp_flat", "mem_flat", "msg_flat2", "flat group") |> parseEvent
    check r.rawId == "mem_flat"
    check r.groupId == "grp_flat"

# ── parseEvent: error / unknown ───────────────────────────────────────────────

suite "qq_pure: unknown / invalid events":
  test "nil payload returns qqkUnknown":
    let r = parseEvent(nil)
    check r.kind == qqkUnknown

  test "empty object returns qqkUnknown":
    let r = parseEvent(%* {})
    check r.kind == qqkUnknown

  test "unknown event type returns qqkUnknown":
    let payload = %* {"op": 0, "t": "GUILD_MEMBER_ADD", "d": {}}
    let r = payload |> parseEvent
    check r.kind == qqkUnknown

  test "C2C missing userId returns qqkUnknown":
    let payload = %* {"op": 0, "t": "C2C_MESSAGE_CREATE", "d": {"id": "msg1", "content": "hi"}}
    let r = payload |> parseEvent
    check r.kind == qqkUnknown

  test "C2C missing messageId returns qqkUnknown":
    let payload = %* {"op": 0, "t": "C2C_MESSAGE_CREATE", "d": {"author": {"user_openid": "u1"}, "content": "hi"}}
    let r = payload |> parseEvent
    check r.kind == qqkUnknown

  test "GROUP missing groupId returns qqkUnknown":
    let payload = %* {"op": 0, "t": "GROUP_AT_MESSAGE_CREATE", "d": {"author": {"member_openid": "m1"}, "id": "msg1"}}
    let r = payload |> parseEvent
    check r.kind == qqkUnknown

  test "INTERACTION missing buttonData returns qqkUnknown":
    let payload = %* {
      "op": 0, "t": "INTERACTION_CREATE",
      "d": {"id": "evt1", "scene": "c2c", "user_openid": "u1", "data": {"resolved": {}}}
    }
    let r = payload |> parseEvent
    check r.kind == qqkUnknown

# ── parseDispatch ─────────────────────────────────────────────────────────────

suite "qq_pure: parseDispatch":
  test "dispatches C2C correctly":
    let d = %* {"author": {"user_openid": "u1"}, "id": "m1", "content": "hi"}
    let r = parseDispatch("C2C_MESSAGE_CREATE", d)
    check r.kind == qqkPrivate

  test "dispatches GROUP correctly":
    let d = %* {"group_openid": "g1", "author": {"member_openid": "m1"}, "id": "msg1", "content": "hey"}
    let r = parseDispatch("GROUP_AT_MESSAGE_CREATE", d)
    check r.kind == qqkGroup

  test "unknown type returns qqkUnknown":
    let r = parseDispatch("READY", %* {})
    check r.kind == qqkUnknown

# ── predicates ────────────────────────────────────────────────────────────────

suite "qq_pure: predicates":
  test "isInteraction true for qqkInteraction":
    let r = makePrivateInteractionPayload("u", "e", "d") |> parseEvent
    check isInteraction(r)

  test "isInteraction false for private message":
    let r = makeC2cPayload("u", "m", "hi") |> parseEvent
    check not isInteraction(r)

  test "isInteraction false for group message":
    let r = makeGroupPayload("g", "m", "msg", "hi") |> parseEvent
    check not isInteraction(r)

  test "hasMedia always false":
    let r = makeC2cPayload("u", "m", "hi") |> parseEvent
    check not hasMedia(r)

  test "hasMedia false for qqkGroup":
    let r = makeGroupPayload("g", "m", "msg", "hi") |> parseEvent
    check not hasMedia(r)

# ── qqRawIdentity ─────────────────────────────────────────────────────────────

suite "qq_pure: qqRawIdentity":
  test "private message uses rawId directly":
    let r = makeC2cPayload("user_p", "m", "hi") |> parseEvent
    check qqRawIdentity(r) == "user_p"

  test "group message uses group: prefix":
    let r = makeGroupPayload("grp_abc", "mem_xyz", "m", "hi") |> parseEvent
    check qqRawIdentity(r) == "group:grp_abc"

  test "group interaction uses group: prefix":
    let r = makeGroupInteractionPayload("grp_g", "mem_g", "e", "d") |> parseEvent
    check qqRawIdentity(r) == "group:grp_g"

  test "private interaction uses rawId directly":
    let r = makePrivateInteractionPayload("user_i", "e", "d") |> parseEvent
    check qqRawIdentity(r) == "user_i"

# ── toInbound ─────────────────────────────────────────────────────────────────

suite "qq_pure: toInbound":
  test "userId set correctly":
    let r = makeC2cPayload("u1", "msg1", "hello") |> parseEvent
    let msg = toInbound(r, UserId("user-uuid"))
    check $msg.userId == "user-uuid"

  test "channel is ckQQ":
    let r = makeC2cPayload("u1", "msg1", "hello") |> parseEvent
    let msg = toInbound(r, UserId("uuid"))
    check msg.channel == ckQQ

  test "channelId is messageId":
    let r = makeC2cPayload("u1", "msg1", "hello") |> parseEvent
    let msg = toInbound(r, UserId("uuid"))
    check msg.channelId == "msg:msg1"

  test "text preserved":
    let r = makeC2cPayload("u1", "msg1", "hello QQ") |> parseEvent
    let msg = toInbound(r, UserId("uuid"))
    check msg.text == "hello QQ"

  test "mediaUrl empty (no media support)":
    let r = makeC2cPayload("u1", "msg1", "hello") |> parseEvent
    let msg = toInbound(r, UserId("uuid"))
    check msg.mediaUrl == ""
