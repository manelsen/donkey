## line_policy.nim — pure LINE inbound policy: replay cache and chat/speaker
## gates. Signature/MAC verification lives exclusively in
## `core/security/webhook_auth` and is consumed by the webhook ingress; this
## module defines no MAC and imports no crypto or encoding module.
##
## All functions are pure (no clock, no I/O, no exceptions). The caller passes
## `nowSec`; the HTTP layer owns the raw body and the `X-Line-Signature` header.
##
## Protocol facts (PRD §1, §9; Hermes is read-only at
## `/home/micelio/git/hermes-agent`, `plugins/platforms/line/adapter.py`):
##   - `X-Line-Signature` carries the request MAC; its name is exported here
##     for the ingress, but no verification lives here.
##   - There is no signed timestamp. Replay defence is dedupe by
##     `webhookEventId`: 1000 entries kept for 24 h (conservative margin over
##     LINE redelivery; `adapter.py:420-421,524-527`).
##   - Groups/rooms are default-deny through `LINE_ALLOWED_GROUPS`: an empty
##     list denies every group, unlike the generic `GroupGate`
##     (`core/security/dm_policy.groupChatAllowed`, empty = allow).
##   - Identity is the speaker (`source.userId`); the outbound destination is
##     the conversation (`chatId`). `line_pure.toInbound` puts `senderId` in
##     `rawChannelId` and `chatId` in `channelId`/`chatId`, so a group reply
##     never goes to the speaker's DM.
##
## Contract:
##   replayDecision(cache, eventId, nowSec)          → bool (true = accept)
##   recordEvent(cache, eventId, nowSec)             → mutates the cache
##   decideLineEvent(policy, event)                  → LineEventDecision

import ./line_pure

const
  LineSignatureHeader* = "X-Line-Signature"

  LineReplayTtlSec*    = 86_400  ## 24 h: conservative redelivery margin.
  LineReplayMaxEvents* = 1_000   ## Same bound as Hermes' dedupe cache.

type
  LineReplayEntry = object
    eventId:       string
    recordedAtSec: int64

  LineReplayCache* = object
    ## Oldest-first insertion order. Fields stay private so mutating the cache
    ## always goes through `recordEvent` (explicit mutation).
    entries: seq[LineReplayEntry]

  LinePolicy* = object
    allowedGroups*: seq[string]
      ## Empty = deny every group/room (LINE default-deny).
    allowedUsers*: seq[string]
      ## Empty = allow every speaker (the user gate is opt-in).

  LineEventDecision* = enum
    ledAccept
    ledDropStandby          ## `mode == "standby"`: another module answers
    ledDropNonText          ## sticker/image/…: no text to answer
    ledDropUnknownContent   ## follow/postback/…: not a message
    ledDropUnknownSource    ## no usable source/speaker
    ledDropGroupNotAllowed  ## group/room outside LINE_ALLOWED_GROUPS
    ledDropUserNotAllowed   ## speaker outside the user allowlist

# ── Replay cache ──────────────────────────────────────────────────────────────

func isFresh(entry: LineReplayEntry; nowSec: int64): bool =
  ## A timestampless protocol has no signed time to validate; a recorded time
  ## in the future (clock skew) is kept rather than dropped.
  if nowSec <= entry.recordedAtSec:
    return true
  nowSec - entry.recordedAtSec < LineReplayTtlSec

func replayDecision*(cache: LineReplayCache; eventId: string; nowSec: int64): bool =
  ## Pure decision: `true` means "accept this event". An empty id is never a
  ## duplicate (there is nothing to key on). An entry older than the TTL is
  ## considered absent, so a late redelivery is accepted rather than lost.
  if eventId.len == 0:
    return true
  for entry in cache.entries:
    if entry.eventId == eventId:
      return not isFresh(entry, nowSec)
  true

proc recordEvent*(cache: var LineReplayCache; eventId: string; nowSec: int64) =
  ## Records a first-seen event. Expired entries are pruned, a duplicate keeps
  ## its original timestamp (re-recording never extends the TTL) and an empty
  ## id is ignored. At the bound, the oldest insertion is evicted.
  if eventId.len == 0:
    return

  var kept: seq[LineReplayEntry]
  for entry in cache.entries:
    if isFresh(entry, nowSec):
      kept.add(entry)

  for entry in kept:
    if entry.eventId == eventId:
      cache.entries = kept
      return

  while kept.len >= LineReplayMaxEvents:
    kept.delete(0)
  kept.add LineReplayEntry(eventId: eventId, recordedAtSec: nowSec)
  cache.entries = kept

func replayCacheLen*(cache: LineReplayCache): int =
  ## Number of retained events (telemetry and tests); the bound is
  ## `LineReplayMaxEvents`.
  cache.entries.len

# ── Chat and speaker gates ────────────────────────────────────────────────────

func lineGroupAllowed*(allowedGroups: openArray[string];
                       sourceKind: LineSourceKind; chatId: string): bool =
  ## Group/room gate for LINE. Default-deny: an empty list denies every
  ## group/room. DMs are not gated here. Matching is exact and an empty id is
  ## never a match. Rooms use `roomId`, so they are gated the same way.
  case sourceKind
  of lskUser:
    true
  of lskGroup, lskRoom:
    allowedGroups.len > 0 and chatId.len > 0 and allowedGroups.contains(chatId)
  of lskUnknown:
    false

func lineUserAllowed*(allowedUsers: openArray[string]; senderId: string): bool =
  ## Speaker gate. Empty means the operator did not restrict users (same
  ## opt-in semantics as the DM allowlist). A non-empty list requires an exact
  ## `source.userId`, in DMs and groups alike.
  if allowedUsers.len == 0:
    return true
  senderId.len > 0 and allowedUsers.contains(senderId)

func decideLineEvent*(policy: LinePolicy; event: LineParseResult): LineEventDecision =
  ## Single pure decision for the runtime. Precedence matters: standby wins
  ## over content because another module owns the answer, and discard reasons
  ## are checked before any gate so a dropped event never reaches session,
  ## identity or pairing code.
  if event.mode == lmStandby:
    return ledDropStandby
  case event.contentKind
  of lckUnknown:
    return ledDropUnknownContent
  of lckNonText:
    return ledDropNonText
  of lckText:
    discard
  if event.sourceKind == lskUnknown or event.senderId.len == 0:
    return ledDropUnknownSource
  if not lineGroupAllowed(policy.allowedGroups, event.sourceKind, event.chatId):
    return ledDropGroupNotAllowed
  if not lineUserAllowed(policy.allowedUsers, event.senderId):
    return ledDropUserNotAllowed
  ledAccept

# ── Identity / destination mapping ────────────────────────────────────────────

type
  LineRouting* = object
    ## The two LINE ids the runtime must never swap: identity comes from the
    ## speaker, the outbound destination from the conversation.
    identityId*:  string  ## `source.userId` — identity/pairing key
    replyTarget*: string  ## `groupId`/`roomId` in groups, `userId` in DMs

func lineRouting*(event: LineParseResult): LineRouting =
  ## Pure mirror of `line_pure.toInbound`: in a group the speaker is identified
  ## by `senderId` while the reply goes to `chatId`, so answering a group never
  ## DMs the speaker (`adapter.py:247-248,548-551`).
  LineRouting(identityId: event.senderId, replyTarget: event.chatId)
