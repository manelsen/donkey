## What the daemon's endpoints (IPC status, HTTP gateway) answer, apart from
## the wiring: the status snapshot, the access policy and the dashboard's
## session action. No sockets, no daemon.

import std/unittest
import donkey/core/types
import donkey/core/security/dm_policy
import donkey/domain/agent_message
import donkey/domain/gateway/identity_pure
import donkey/domain/message
import donkey/app/http_gateway
import donkey/app/route_health
import donkey/app/session_manager
import donkey/app/daemon_endpoints
import donkey/core/providers/smart_routing

var gEnqueued {.threadvar.}: seq[(InboundMessage, TaskKind, string)]

proc enqueueProbe(msg: InboundMessage; kind: TaskKind; payload: string)
                 {.gcsafe, raises: [CatchableError].} =
  gEnqueued.add((msg, kind, payload))

proc allowAll(userId: UserId): AuthVerdict {.gcsafe, raises: [].} = avAllowed
proc revokeAll(userId: UserId): AuthVerdict {.gcsafe, raises: [].} = avRevoked

proc runTests*() =
  suite "daemon status":
    test "active channels are named in a fixed order":
      check activeChannelNames(ActiveChannels(qq: true, telegram: true, slack: true)) ==
        @["telegram", "slack", "qq"]
      check activeChannelNames(ActiveChannels()).len == 0

    test "the snapshot carries sessions, channels, tools and route health":
      var sm: SessionManager
      sm.init()
      discard sm.getOrCreate(UserId("u1"))
      sm.recordChannel(UserId("u1"), ckTelegram, "tg-1", persist = false)
      let health = newRouteHealth("")
      health.recordChoice(ProviderSelection(providerName: "openrouter", modelName: "a"))
      let st = daemonStatus(sm, DaemonStatusInputs(
        channels: ActiveChannels(telegram: true), health: health,
        toolsCount: 7, uptimeSec: 42, providers: @["openrouter"],
        memoryBackend: "md"))
      check st.sessionCount == 1
      check st.sessions[0].userId == "u1"
      check st.sessions[0].channels == @["telegram"]
      check st.channels == @["telegram"]
      check st.toolsCount == 7
      check st.uptimeSec == 42
      check st.routeCounts[0].route == "openrouter/a"
      check st.memoryBackend == "md"

  suite "access policy":
    proc notRevoked(u: UserId): bool {.gcsafe, raises: [CatchableError].} = false
    proc revoked(u: UserId): bool {.gcsafe, raises: [CatchableError].} = true
    proc unreadable(u: UserId): bool {.gcsafe, raises: [CatchableError].} =
      raise newException(IOError, "profile unreadable")
    proc allowed(u: UserId): bool {.gcsafe, raises: [CatchableError].} = true
    proc notAllowed(u: UserId): bool {.gcsafe, raises: [CatchableError].} = false

    test "revocation wins over the DM policy":
      check authorizeUser(UserId("u"), revoked, allowed, DmPolicyOpen) == avRevoked

    test "outside an open policy the DM allowlist decides":
      check authorizeUser(UserId("u"), notRevoked, notAllowed, DmPolicyAllowlist) == avNotAllowed
      check authorizeUser(UserId("u"), notRevoked, allowed, DmPolicyAllowlist) == avAllowed
      check authorizeUser(UserId("u"), notRevoked, notAllowed, DmPolicyOpen) == avAllowed

    test "a profile that cannot be read fails closed":
      check authorizeUser(UserId("u"), unreadable, allowed, DmPolicyOpen) == avRevoked

  suite "dashboard session action":
    setup:
      gEnqueued = @[]
      var sm: SessionManager
      sm.init()
      discard sm.getOrCreate(UserId("u1"))
      sm.recordChannel(UserId("u1"), ckDiscord, "dc-9", persist = false)

    test "an unknown session key is not found and nothing is enqueued":
      check runSessionAction(sm, "nope", tkCompact, "", allowAll, enqueueProbe) == gsaoNotFound
      check gEnqueued.len == 0

    test "a revoked user is refused and nothing is enqueued":
      check runSessionAction(sm, "u1", tkCompact, "", revokeAll, enqueueProbe) == gsaoRevoked
      check gEnqueued.len == 0

    test "an allowed action is enqueued on the user's latest channel":
      check runSessionAction(sm, "u1", tkCompact, "x", allowAll, enqueueProbe) == gsaoAccepted
      check gEnqueued.len == 1
      let (msg, kind, payload) = gEnqueued[0]
      check msg.userId == UserId("u1")
      check (msg.channel, msg.channelId, msg.rawChannelId) == (ckDiscord, "dc-9", "dc-9")
      check (kind, payload) == (tkCompact, "x")

when isMainModule:
  runTests()
