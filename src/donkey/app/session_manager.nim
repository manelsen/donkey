## SessionManager — per-user OrchestratorAgent lifecycle + multi-channel tracking.
##
## A session belongs to a UserId (internal UUID), not to a channel.
## The same session is reused when the user messages from any linked channel.
## `channels` tracks which (ChannelKind, raw_id) pairs are associated with
## this session — used for `ctl session list`.

import std/tables
import chronos
import chronos/asyncsync
import ../domain/agent_message
import ../domain/message
import ../core/session_ingress

type
  SessionEntry* = object
    inbox*:                AsyncQueue[AgentMessage]
    askInbox*:             AsyncQueue[string]
    awaitingAsk*:          bool
    ## outbox removed: orchestrators write replies to the global outbox directly.
    channels*:             seq[(ChannelKind, string)]  ## (channel, raw_channel_user_id)
    toolCatalogSignature*: string

  SessionLease* = object
    entry*:    ptr SessionEntry
    oldInbox*: AsyncQueue[AgentMessage]
    oldAskInbox*: AsyncQueue[string]
    isNew*:    bool
    rebuilt*:  bool

  SessionManager* = object
    entries*: Table[string, SessionEntry]  ## string(UserId) → entry

proc newSessionEntry(toolCatalogSignature: SessionRuntimeSignature): SessionEntry =
  SessionEntry(
    inbox: newAsyncQueue[AgentMessage](),
    askInbox: newAsyncQueue[string](),
    awaitingAsk: false,
    channels: @[],
    toolCatalogSignature: $toolCatalogSignature,
  )

proc init*(sm: var SessionManager) =
  sm.entries = initTable[string, SessionEntry]()

func hasSession*(sm: SessionManager; userId: UserId): bool =
  $userId in sm.entries

proc getOrCreate*(sm: var SessionManager; userId: UserId): ptr SessionEntry =
  ## Returns a pointer to the session entry, creating it if absent.
  ## The caller is responsible for spawning the orchestrator on first creation
  ## (check hasSession before calling getOrCreate to detect new sessions).
  let uid = $userId
  if uid notin sm.entries:
    sm.entries[uid] = newSessionEntry(SessionRuntimeSignature(""))
  addr sm.entries[uid]

proc get*(sm: var SessionManager; userId: UserId): ptr SessionEntry =
  addr sm.entries[$userId]

proc recordChannel*(sm: var SessionManager;
                    userId: UserId;
                    kind:   ChannelKind;
                    rawId:  string) =
  ## Records that userId has used (kind, rawId). Idempotent.
  let uid = $userId
  if uid notin sm.entries: return
  let pair = (kind, rawId)
  if pair notin sm.entries[uid].channels:
    sm.entries[uid].channels.add(pair)

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
    currentSignature: SessionRuntimeSignature(entry.toolCatalogSignature),
  )

proc applyIngressDecision*(sm: var SessionManager;
                           userId: UserId;
                           decision: SessionIngressDecision;
                           toolCatalogSignature: SessionRuntimeSignature): SessionLease =
  let uid = $userId
  case decision.actionKind
  of siaStartNewSession:
    sm.entries[uid] = newSessionEntry(toolCatalogSignature)
    result = SessionLease(
      entry: addr sm.entries[uid],
      oldInbox: nil,
      oldAskInbox: nil,
      isNew: true,
      rebuilt: false,
    )
  of siaReuseSessionRuntime:
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
    result.isNew = false
    result.rebuilt = true

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
