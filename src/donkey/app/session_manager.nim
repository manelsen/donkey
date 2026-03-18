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

type
  SessionEntry* = object
    inbox*:    AsyncQueue[AgentMessage]
    ## outbox removed: orchestrators write replies to the global outbox directly.
    channels*: seq[(ChannelKind, string)]  ## (channel, raw_channel_user_id)

  SessionManager* = object
    entries*: Table[string, SessionEntry]  ## string(UserId) → entry

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
    sm.entries[uid] = SessionEntry(
      inbox:    newAsyncQueue[AgentMessage](),
      channels: @[],
    )
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
