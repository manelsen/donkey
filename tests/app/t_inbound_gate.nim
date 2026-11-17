## Inbound authorization gate tests: DM policy plus the group allowlist.
##
## TG-016: an unauthorized chat/user is dropped before any session or turn.

import std/[options, unittest]
import donkey/app/inbound_gate
import donkey/app/session_manager
import donkey/core/security/dm_policy
import donkey/core/types
import donkey/domain/message

proc fixedGate(uid: UserId; linkTarget: Option[UserId] = none(UserId)): IdentityGatePort =
  IdentityGatePort(
    lookup: proc(kind: ChannelKind; rawId: string): Option[UserId] {.gcsafe.} =
      some(uid),
    resolve: proc(kind: ChannelKind; rawId: string): UserId {.gcsafe.} = uid,
    peekLinkCode: proc(code: string): Option[UserId] {.gcsafe.} = linkTarget,
  )

proc allowedOnly(target: UserId): proc(userId: UserId): bool {.gcsafe.} =
  result = proc(userId: UserId): bool {.gcsafe.} = userId == target

proc openManager(): SessionManager =
  var sm: SessionManager
  sm.init()
  sm

suite "group allowlist gate":

  test "a group outside the allowlist is denied even under an open DM policy":
    var sm = openManager()
    sm.configureGroupGate(GroupGate(allowedChats: @["-100123"]))
    let uid = UserId("u-1")
    let gate = fixedGate(uid)

    let allowed = authorizeResolvedInbound(
      sm, gate, ckTelegram, uid, "oi", isGroup = true, chatId = "-100123")
    check allowed.allowed
    check allowed.userId == uid

    let denied = authorizeResolvedInbound(
      sm, gate, ckTelegram, uid, "oi", isGroup = true, chatId = "-100999")
    check not denied.allowed

  test "direct messages are not affected by the group allowlist":
    var sm = openManager()
    sm.configureGroupGate(GroupGate(allowedChats: @["-100123"]))
    let uid = UserId("u-1")
    let dm = authorizeResolvedInbound(
      sm, fixedGate(uid), ckTelegram, uid, "oi", isGroup = false, chatId = "")
    check dm.allowed

  test "an empty group allowlist keeps every group allowed":
    var sm = openManager()
    sm.configureGroupGate(GroupGate())
    let uid = UserId("u-1")
    let res = authorizeResolvedInbound(
      sm, fixedGate(uid), ckTelegram, uid, "oi", isGroup = true, chatId = "-42")
    check res.allowed

  test "a link code cannot admit a sender in a disallowed group":
    var sm = openManager()
    sm.dmPolicy = DmPolicyAllowlist
    let sender = UserId("sender")
    let target = UserId("target")
    sm.isDmAllowed = allowedOnly(target)
    sm.configureGroupGate(GroupGate(allowedChats: @["-100123"]))
    let res = authorizeInbound(
      sm, fixedGate(sender, some(target)), ckTelegram, "raw-1", "/continue ABC",
      isGroup = true, chatId = "-100999")
    check not res.allowed

  test "the link code still works inside an allowed group":
    var sm = openManager()
    sm.dmPolicy = DmPolicyAllowlist
    let sender = UserId("sender")
    let target = UserId("target")
    sm.isDmAllowed = allowedOnly(target)
    sm.configureGroupGate(GroupGate(allowedChats: @["-100123"]))
    let res = authorizeInbound(
      sm, fixedGate(sender, some(target)), ckTelegram, "raw-1", "/continue ABC",
      isGroup = true, chatId = "-100123")
    check res.allowed
