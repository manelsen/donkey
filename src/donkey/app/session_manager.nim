## SessionManager — per-user OrchestratorAgent lifecycle + multi-channel tracking.
##
## A session belongs to a UserId (internal UUID), not to a channel.
## The same session is reused when the user messages from any linked channel.
## `channels` tracks which (ChannelKind, raw_id) pairs are associated with
## this session — used for `ctl session list`.

import std/[options, tables]
import chronos
import chronos/asyncsync
import ../core/pipeops
import ../domain/agent_message
import ../domain/message
import ../core/session/session_ingress
import ../core/security/dm_policy
import ../ports/runtime_state

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
