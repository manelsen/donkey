## What the daemon's endpoints answer, apart from their wiring: the status
## snapshot the IPC socket and the HTTP gateway serve, the access policy the
## gateway applies, and the dashboard's session action. The composition root
## only plugs these into the servers.

import ../core/pipeops
import ../core/types
import ../core/security/dm_policy
import ../domain/agent_message
import ../domain/gateway/identity_pure
import ../domain/message
import ../ports/access
export access
import ../ports/ipc
import ./http_gateway
import ./route_health
import ./session_manager

type
  ActiveChannels* = set[ChannelKind]
    ## Which channels this daemon runs, for the status views: any of them,
    ## so a new channel needs no change here.

  DaemonStatusInputs* = object
    channels*:      ActiveChannels
    health*:        RouteHealth
    toolsCount*:    int
    uptimeSec*:     int64
    providers*:     seq[string]
    memoryBackend*: string
    memoryStats*:   MemoryStats

  SessionTaskEnqueue* = proc(msg: InboundMessage; kind: TaskKind; payload: string)
                            {.gcsafe, raises: [CatchableError].}

func activeChannelNames*(channels: ActiveChannels): seq[string] =
  for kind in ChannelKind:
    if kind in channels: result.add $kind

proc daemonStatus*(sm: SessionManager; inputs: DaemonStatusInputs): DaemonStatus =
  var sessions: seq[SessionInfo]
  for (uid, chans) in sm.listSessions():
    var names: seq[string]
    for (kind, _) in chans:
      names.add($kind)
    sessions.add(SessionInfo(userId: $uid, channels: names))
  result = DaemonStatus(
    uptimeSec: inputs.uptimeSec,
    sessionCount: sm.sessionCount(),
    sessions: sessions,
    channels: activeChannelNames(inputs.channels),
    providers: inputs.providers,
    toolsCount: inputs.toolsCount,
    memoryBackend: inputs.memoryBackend,
    memoryStats: inputs.memoryStats,
  )
  if inputs.health != nil:
    result.routeCounts = inputs.health.topRouteCounts()
    result.routeMetrics = inputs.health.topRouteMetrics()
    result.recentRouteMetrics = inputs.health.topRecentRouteMetrics()
    ## Every provider with recent calls: the TUI shows each one's health
    ## (the stats panel keeps to the busiest).
    result.recentProviderMetrics = inputs.health.topRecentProviderMetrics(limit = high(int))
    result.providerCooldowns = inputs.health.activeCooldownLabels()

proc authorizeUser*(userId: UserId; isRevoked, isDmAllowed: ProfileCheck;
                    dmPolicy: DmPolicy): AuthVerdict {.raises: [].} =
  ## The ingress policy, for the gateway: revocation wins, then the DM
  ## allowlist (unless the policy is open). A profile that cannot be read
  ## fails closed, whatever the policy.
  let revoked = isRevoked(userId).valueOr:
    return avRevoked
  if revoked:
    return avRevoked
  if dmPolicy == DmPolicyOpen:
    return avAllowed
  let allowed = isDmAllowed(userId).valueOr:
    return avRevoked
  if allowed: avAllowed else: avNotAllowed

proc noProfileFlag(userId: UserId): Result[bool, string] {.gcsafe, raises: [].} =
  ok(false)

proc authorizeUser*(userId: UserId; access: AccessPort; dmPolicy: DmPolicy):
                   AuthVerdict {.raises: [].} =
  ## A port without a check answers like `revoked` and `dmAllowed` do:
  ## nobody is revoked, nobody is on the allowlist.
  authorizeUser(userId,
                if access.isRevoked != nil: access.isRevoked else: noProfileFlag,
                if access.isDmAllowed != nil: access.isDmAllowed else: noProfileFlag,
                dmPolicy)

proc runSessionAction*(sm: SessionManager; rawUserId: string; kind: TaskKind;
                       payload: string; authorize: AuthorizeFn;
                       enqueue: SessionTaskEnqueue): GatewaySessionActionOutcome
                      {.raises: [CatchableError].} =
  ## The dashboard's management action. It takes the raw session key (the
  ## user key column), never an `api:` identity: accepting a session id too
  ## let a user key equal to another session's id reach the wrong session.
  ## Same policy as the API, so a denied user never gets a 202 for a task the
  ## ingress would drop. The answer goes to the channel the user last used:
  ## inventing a CLI target recorded a fake channel.
  if not sm.hasSession(UserId(rawUserId)):
    return gsaoNotFound
  let uid = UserId(rawUserId)
  case authorize(uid)
  of avAllowed: discard
  of avRevoked, avNotAllowed: return gsaoRevoked
  let target = sm.latestChannelFor(rawUserId)
  enqueue(InboundMessage(userId: uid, channel: target.kind,
                         channelId: target.rawId, rawChannelId: target.rawId),
          kind, payload)
  gsaoAccepted
