## SessionManager — per-user OrchestratorAgent lifecycle + multi-channel tracking.
##
## A session belongs to a UserId (internal UUID), not to a channel.
## The same session is reused when the user messages from any linked channel.
## `channels` tracks which (ChannelKind, raw_id) pairs are associated with
## this session — used for `ctl session list`.

import std/[algorithm, options, tables]
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../core/commands/command_routing
import ../domain/agent_message
import ../domain/message
import ../domain/gateway/dashboard_pure
import ../core/session/session_ingress
import ../core/security/dm_policy
import ../ports/runtime_state
import ../infra/queue/nonblocking
import ./approval_runtime

const
  RestoredRuntimeSignature* = "__donkey_restored_runtime__"
    ## Sentinel used after process restart. A restored entry has metadata but no
    ## live orchestrator, so the next inbound message rebuilds the runtime.

var gSessionCounter: uint64 = 0

type
  SessionEntry* = object
    inbox*:                AsyncQueue[AgentMessage]
    askInbox*:             AsyncQueue[string]
    awaitingAsk*:          bool
    lastInboundAtMs*:      int64
    lastInboundEpochMs*:   int64   ## wall-clock timestamp for the registry
    ## outbox removed: orchestrators write replies to the global outbox directly.
    channels*:             seq[(ChannelKind, string)]  ## (channel, raw_channel_user_id)
    toolCatalogSignature*: string
    sessionId*:            string
    restored*:             bool    ## true until a fresh orchestrator is attached

  SessionLease* = object
    entry*:    ptr SessionEntry
    oldInbox*: AsyncQueue[AgentMessage]
    oldAskInbox*: AsyncQueue[string]
    isNew*:    bool
    rebuilt*:  bool

  SessionManager* = object
    entries*: Table[string, SessionEntry]  ## string(UserId) → entry
    dmPolicy*: DmPolicy
    isDmAllowed*: proc(userId: UserId): bool {.gcsafe.}
    groupGate*: GroupGate
    pairingRequest*: proc(kind: ChannelKind; rawId: string): Result[void, string] {.gcsafe.}
      ## Creates a pending pairing request; wired by the composition root.
    registryStore*: SessionRegistryPort
    registryErrorHook*: proc(error: string) {.gcsafe, raises: [].}

proc newSessionId(): string =
  inc gSessionCounter
  $epochMs() & "-" & $gSessionCounter

proc newSessionEntry(toolCatalogSignature: SessionRuntimeSignature): SessionEntry =
  SessionEntry(
    inbox: newAsyncQueue[AgentMessage](),
    askInbox: newAsyncQueue[string](),
    awaitingAsk: false,
    lastInboundAtMs: 0,
    lastInboundEpochMs: 0,
    channels: @[],
    toolCatalogSignature: $toolCatalogSignature,
    sessionId: newSessionId(),
    restored: false,
  )

proc setRegistryStore*(sm: var SessionManager; store: SessionRegistryPort) =
  ## Enables best-effort session metadata persistence.
  sm.registryStore = store

proc setRegistryErrorHook*(sm: var SessionManager;
                           hook: proc(error: string) {.gcsafe, raises: [].}) =
  sm.registryErrorHook = hook

proc reportRegistryError(sm: SessionManager; error: string) =
  if sm.registryErrorHook != nil:
    sm.registryErrorHook(error)

proc persistSession*(sm: var SessionManager; userId: UserId) =
  ## Best-effort upsert of one session's metadata. Store failures are reported
  ## through the registry error hook and never enter the message path.
  if not sm.registryStore.hasSessionRegistry:
    return
  let uid = $userId
  if uid notin sm.entries:
    return
  let entry = sm.entries[uid]
  let record = SessionRegistryRecord(
    userId: uid,
    channels: entry.channels,
    lastInboundAtMs: entry.lastInboundEpochMs,
    sessionId: entry.sessionId,
    runtimeSignature: entry.toolCatalogSignature,
  )
  let saved = sm.registryStore.upsert(record)
  if saved.isErr:
    sm.reportRegistryError(saved.error)

proc restoreSessions*(sm: var SessionManager): Result[int, string] =
  ## Loads persisted session metadata into the in-memory manager. Restored
  ## entries have `restored = true`, so the first inbound message rebuilds the
  ## orchestrator runtime instead of expecting a live actor.
  if not sm.registryStore.hasSessionRegistry:
    return ok(0)
  let loaded = sm.registryStore.loadAll()
  if loaded.isErr:
    return err(loaded.error)
  var count = 0
  for record in loaded.value:
    if record.userId.len == 0:
      continue
    var entry = newSessionEntry(SessionRuntimeSignature(record.runtimeSignature))
    if record.sessionId.len > 0:
      entry.sessionId = record.sessionId
    entry.channels = record.channels
    entry.lastInboundEpochMs = record.lastInboundAtMs
    entry.lastInboundAtMs = 0
    entry.restored = true
    sm.entries[record.userId] = entry
    inc count
  ok(count)

var gSessionStopGeneration: uint64 = 0
var gUserInterrupts: Table[string, uint64]
var gShuttingDown = false
var gLiveActors = 0
var gAllActorsStopped: Future[void]

proc requestSessionStop*() {.gcsafe, raises: [].} =
  ## Process-wide shutdown signal. Actors compare the generation they started
  ## with; a newer generation means "stop". Per-session `/stop` keeps using the
  ## inbox cancel message.
  {.cast(gcsafe).}:
    gShuttingDown = true
    inc gSessionStopGeneration

proc requestUserStop*(userId: string) {.gcsafe, raises: [].} =
  ## Bumps the per-user interrupt counter. Safe to set from a channel handler
  ## while the session actor is busy inside a tool batch or approval wait.
  ## Turns compare the counter they started with, so a turn started after the
  ## interrupt is not stopped by it — no global flag has to be cleared, which
  ## is what let a rebuilt actor un-stop an older in-flight turn.
  if userId.len == 0:
    return
  {.cast(gcsafe).}:
    gUserInterrupts[userId] = gUserInterrupts.getOrDefault(userId) + 1

proc currentUserInterrupt*(userId: string): uint64 {.gcsafe, raises: [].} =
  if userId.len == 0:
    return 0
  {.cast(gcsafe).}:
    gUserInterrupts.getOrDefault(userId)

proc isUserStoppedSince*(userId: string; interrupt: uint64): bool
                        {.gcsafe, raises: [].} =
  ## True when a `/stop` arrived after the turn recorded `interrupt`.
  if userId.len == 0:
    return false
  {.cast(gcsafe).}:
    gUserInterrupts.getOrDefault(userId) != interrupt

func interruptsTurn*(kind: CommandKind): bool =
  ## Cross-channel policy: these commands abort the current turn and deny
  ## pending approvals before their control task is processed.
  kind in {cmdStop, cmdNew, cmdRestart, cmdReset}

proc requestTurnInterrupt*(sm: var SessionManager; userId: UserId)
                          {.gcsafe, raises: [].} =
  requestUserStop($userId)
  cancelPendingApprovals(userId)
  let uid = $userId
  sm.entries.withValue(uid, entry):
    if entry[].awaitingAsk and entry[].askInbox != nil:
      ## A full ask queue already has a pending answer; dropping the cancel
      ## marker is safe and must not abort the interrupt.
      discard tryAddLastNoWait(entry[].askInbox, "__DONKEY_ASK_CANCELLED__")
      entry[].awaitingAsk = false

proc daemonShuttingDown*(): bool {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    gShuttingDown

proc currentSessionStopGeneration*(): uint64 {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    gSessionStopGeneration

proc isSessionStopRequested*(startGeneration: uint64): bool
                                           {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    gSessionStopGeneration != startGeneration

proc registerActor*() {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    if gLiveActors == 0 or gAllActorsStopped.isNil or
       gAllActorsStopped.finished():
      gAllActorsStopped = newFuture[void]("session.allActorsStopped")
    inc gLiveActors

proc unregisterActor*() {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    if gLiveActors > 0:
      dec gLiveActors
    if gLiveActors == 0 and not gAllActorsStopped.isNil and
       not gAllActorsStopped.finished():
      gAllActorsStopped.complete()

proc allActorsStoppedFuture*(): Future[void] {.gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    if gLiveActors == 0:
      let done = newFuture[void]("session.allActorsStopped.done")
      done.complete()
      return done
    if gAllActorsStopped.isNil or gAllActorsStopped.finished():
      gAllActorsStopped = newFuture[void]("session.allActorsStopped")
    gAllActorsStopped

proc cancelAllActors*(sm: var SessionManager): Future[void] =
  ## Signals live orchestrators and returns the shared stop future. The inbox
  ## cancel message stops an idle actor; the generation bump and ask
  ## cancellation wake a turn that is waiting on spawn_subagent or askInbox.
  requestSessionStop()
  for _, entry in sm.entries:
    if entry.restored or entry.inbox == nil:
      continue
    entry.inbox.addLastNoWait(newCancelMsg())
    if entry.askInbox != nil:
      entry.askInbox.addLastNoWait("__DONKEY_ASK_CANCELLED__")
  result = allActorsStoppedFuture()

proc init*(sm: var SessionManager) =
  sm.entries = initTable[string, SessionEntry]()
  sm.dmPolicy = DmPolicyOpen
  sm.isDmAllowed = nil
  sm.pairingRequest = nil

proc configureDmPolicy*(sm: var SessionManager;
                        policy: DmPolicy;
                        isAllowed: proc(userId: UserId): bool {.gcsafe.}) =
  ## Configures DM authorization once at daemon startup. Kept out of pure
  ## `func` builders so service construction has no hidden side effects.
  sm.dmPolicy = policy
  sm.isDmAllowed = isAllowed

proc configureGroupGate*(sm: var SessionManager; gate: GroupGate) =
  ## Configures the group chat allowlist once at daemon startup. It is
  ## independent of the DM policy: an allowed DM user in a disallowed group is
  ## still dropped.
  sm.groupGate = gate

func groupAllows*(sm: SessionManager; chatId: string): bool =
  groupChatAllowed(sm.groupGate, chatId)

proc allows*(sm: SessionManager; userId: UserId): bool =
  ## Channel-level authorization used before command/callback dispatch.
  if sm.dmPolicy == DmPolicyOpen:
    return true
  sm.isDmAllowed != nil and sm.isDmAllowed(userId)

func hasSession*(sm: SessionManager; userId: UserId): bool =
  $userId in sm.entries

func hasLiveSession*(sm: SessionManager; userId: UserId): bool =
  ## A restored entry has metadata but no orchestrator actor yet.
  sm.hasSession(userId) and not sm.entries[$userId].restored

proc getOrCreate*(sm: var SessionManager; userId: UserId): ptr SessionEntry =
  ## Returns a pointer to the session entry, creating it if absent.
  ## The caller is responsible for spawning the orchestrator on first creation
  ## (check hasSession before calling getOrCreate to detect new sessions).
  let uid = $userId
  if uid notin sm.entries:
    sm.entries[uid] = newSessionEntry(SessionRuntimeSignature(""))
    sm.persistSession(userId)
  addr sm.entries[uid]

proc get*(sm: var SessionManager; userId: UserId): ptr SessionEntry =
  addr sm.entries[$userId]

func latestChannelFor*(sm: SessionManager; userId: string):
                       tuple[kind: ChannelKind, rawId: string] =
  ## The channel a background action should answer on: the last one the user
  ## used. Never invents one, so a session with no channel falls back to an
  ## empty CLI target instead of recording a bogus `(ckCli, <session key>)`
  ## entry that would hijack `latestChannel`.
  result = (kind: ckCli, rawId: "")
  if userId notin sm.entries:
    return
  let channels = sm.entries[userId].channels
  if channels.len > 0:
    result = (kind: channels[^1][0], rawId: channels[^1][1])

proc recordChannel*(sm: var SessionManager;
                    userId: UserId;
                    kind:   ChannelKind;
                    rawId:  string;
                    persist: bool = true) =
  ## Records that userId has used (kind, rawId). Idempotent.
  if rawId.len == 0:
    return
  let uid = $userId
  if uid notin sm.entries: return
  let pair = (kind, rawId)
  let existingIdx = sm.entries[uid].channels.find(pair)
  if existingIdx >= 0:
    sm.entries[uid].channels.delete(existingIdx)
  sm.entries[uid].channels.add(pair)
  if persist:
    sm.persistSession(userId)

func latestChannel*(sm: SessionManager; userId: UserId): Option[ChannelKind] =
  let uid = $userId
  if uid notin sm.entries or sm.entries[uid].channels.len == 0:
    return none(ChannelKind)
  some(sm.entries[uid].channels[^1][0])

func listSessions*(sm: SessionManager): seq[(UserId, seq[(ChannelKind, string)])] =
  for uid, entry in sm.entries:
    result.add((UserId(uid), entry.channels))

func listSessionDetails*(sm: SessionManager): seq[SessionDetail] =
  ## Additive dashboard view of the registry. `SessionInfo` (IPC) stays
  ## untouched; this exposes the session id, the wall-clock timestamp and the
  ## restored flag without leaking raw channel ids.
  for uid, entry in sm.entries:
    var channels: seq[string]
    for (kind, _) in entry.channels:
      let name = $kind
      if name notin channels:
        channels.add(name)
    result.add(SessionDetail(
      sessionId: entry.sessionId,
      userId: uid,
      channels: channels,
      lastInboundEpochMs: entry.lastInboundEpochMs,
      restored: entry.restored,
    ))
  result.sort(proc(a, b: SessionDetail): int =
    if a.lastInboundEpochMs != b.lastInboundEpochMs:
      cmp(b.lastInboundEpochMs, a.lastInboundEpochMs)
    else:
      cmp(a.userId, b.userId))

func sessionCount*(sm: SessionManager): int = sm.entries.len

func snapshot*(sm: SessionManager; userId: UserId): SessionIngressState =
  let uid = $userId
  if uid notin sm.entries:
    return SessionIngressState(
      hasSession: false,
      awaitingAsk: false,
      currentSignature: SessionRuntimeSignature(""),
    )
  let entry = sm.entries[uid]
  SessionIngressState(
    hasSession: true,
    awaitingAsk: entry.awaitingAsk,
    lastInboundAtMs: entry.lastInboundAtMs,
    currentSignature:
      if entry.restored:
        SessionRuntimeSignature(RestoredRuntimeSignature)
      else:
        SessionRuntimeSignature(entry.toolCatalogSignature),
  )

proc applyIngressDecision*(sm: var SessionManager;
                           userId: UserId;
                           decision: SessionIngressDecision;
                           toolCatalogSignature: SessionRuntimeSignature): SessionLease =
  let uid = $userId
  case decision.actionKind
  of siaStartNewSession:
    sm.entries[uid] = newSessionEntry(toolCatalogSignature)
    sm.entries[uid].restored = false
    result = SessionLease(
      entry: addr sm.entries[uid],
      oldInbox: nil,
      oldAskInbox: nil,
      isNew: true,
      rebuilt: false,
    )
  of siaReuseSessionRuntime:
    sm.entries[uid].restored = false
    result = SessionLease(
      entry: addr sm.entries[uid],
      oldInbox: nil,
      oldAskInbox: nil,
      isNew: false,
      rebuilt: false,
    )
  of siaRebuildSessionRuntime:
    result.entry = addr sm.entries[uid]
    result.oldInbox = result.entry[].inbox
    result.oldAskInbox = result.entry[].askInbox
    result.entry[].inbox = newAsyncQueue[AgentMessage]()
    result.entry[].askInbox = newAsyncQueue[string]()
    result.entry[].awaitingAsk = false
    result.entry[].toolCatalogSignature = $toolCatalogSignature
    result.entry[].restored = false
    result.isNew = false
    result.rebuilt = true
  ## Persistence is the caller's responsibility: the ingress path batches the
  ## timestamp and channel updates into a single registry write per message.

proc prepareEntry*(sm: var SessionManager;
                   userId: UserId;
                   toolCatalogSignature: string): SessionLease =
  let signature = SessionRuntimeSignature(toolCatalogSignature)
  let decision = decideSessionIngress(SessionIngressRequest(
    userId: userId,
    state: sm.snapshot(userId),
    nextSignature: signature,
  ))
  sm.applyIngressDecision(userId, decision, signature)
