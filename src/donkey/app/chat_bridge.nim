## ChatBridge — thread-safe correlation between an API turn and outbox replies.
##
## The HTTP worker registers one pending turn keyed by `$userId`; the session
## actor delivers outbox messages from another thread; the worker polls for
## events until a final answer, a turn error, the deadline or an abandon.
##
## Waiting is injected (`now`/`nap`) so tests never sleep and the production
## adapter can use the real clock without leaking it into domain code.

import std/[locks, tables]
import results
import ../core/types
import ../domain/message

const
  MaxTurnBufferBytes* = 256 * 1024  ## per-turn cap for non-terminal content
  PollStepMs* = 10                  ## nap granularity while a turn is open
  MaxOrphanTtlMs* = 600_000'i64    ## matches the 600 s max agent timeout

type
  NowFn* = proc(): int64 {.gcsafe, raises: [].}
  NapFn* = proc(ms: int) {.gcsafe, raises: [].}

  ChatBridgeErrorKind* = enum
    cbeBusy
    cbeMissing
    cbeAbandoned

  ChatBridgeError* = object
    kind*:    ChatBridgeErrorKind
    message*: string

  ChatBridgeEvent* = object
    ## One outbox message, flattened for the API surface.
    kind*:         ReplyKind
    text*:         string
    toolCall*:     ToolCallNotice
    isPartial*:    bool
    inputTokens*:  int
    outputTokens*: int

  ChatBridgePollStatus* = enum
    cbpEvents    ## drained events; the turn is still open (or non-blocking)
    cbpDone      ## a final answer/turn error closed the turn; entry removed
    cbpDeadline  ## the deadline expired; entry removed
    cbpMissing   ## no pending entry for this user

  ChatBridgeBatch* = object
    status*:    ChatBridgePollStatus
    events*:    seq[ChatBridgeEvent]
    truncated*: bool

  PendingTurn = object
    events:        seq[ChatBridgeEvent]
    bufferedBytes: int
    truncated:     bool
    finished:      bool
    orphaned:     bool   ## the client left; keep the key for the orphan turn
    deadlineMs:    int64  ## absolute clock value; 0 = no deadline (or the TTL)

  ChatBridge* = ref object
    lock:    Lock
    pending: Table[string, PendingTurn]
    nowFn:   NowFn
    napFn:   NapFn

const ChatBridgeBusy* = cbeBusy
  ## The `register` refusal for a user that already has a pending turn.

func isBusy*(error: ChatBridgeError): bool =
  error.kind == ChatBridgeBusy

# ── construction ──────────────────────────────────────────────────────────────

proc newChatBridge*(now: NowFn; nap: NapFn): ChatBridge =
  ## Both the clock and the sleeping primitive are injected: this module never
  ## calls `sleep` itself, so tests drive deadlines deterministically.
  new(result)
  initLock(result.lock)
  result.pending = initTable[string, PendingTurn]()
  result.nowFn = now
  result.napFn = nap

# ── buffer helpers ────────────────────────────────────────────────────────────

func clipToBytes(text: string; limit: int): string =
  if limit <= 0:
    return ""
  if text.len <= limit:
    return text
  var endIdx = limit
  while endIdx > 0 and (ord(text[endIdx]) and 0xC0) == 0x80:
    dec endIdx
  text[0 ..< endIdx]

func eventBytes(event: ChatBridgeEvent): int =
  event.text.len + event.toolCall.name.len + event.toolCall.id.len

func isTerminal(event: ChatBridgeEvent): bool =
  ## A partial `rkFinalAnswer` is still a stream delta; only the closing one
  ## (isPartial == false) ends the turn.
  event.kind in {rkFinalAnswer, rkTurnError} and not event.isPartial

proc appendEvent(turn: var PendingTurn; event: ChatBridgeEvent) =
  if isTerminal(event):
    if turn.bufferedBytes + event.text.len > MaxTurnBufferBytes:
      # The final answer supersedes accumulated partial content.
      turn.events = @[]
      turn.bufferedBytes = 0
      turn.truncated = true
    var terminal = event
    terminal.text = clipToBytes(event.text, MaxTurnBufferBytes)
    turn.events.add(terminal)
    turn.bufferedBytes = terminal.text.len
    turn.finished = true
    return

  let remaining = MaxTurnBufferBytes - turn.bufferedBytes
  if eventBytes(event) > remaining:
    turn.truncated = true
    if remaining <= 0:
      return
    var clipped = event
    clipped.text = clipToBytes(event.text, remaining)
    turn.events.add(clipped)
    turn.bufferedBytes += min(eventBytes(clipped), remaining)
  else:
    turn.events.add(event)
    turn.bufferedBytes += eventBytes(event)

func orphanExpired(turn: PendingTurn; now: int64): bool =
  turn.orphaned and turn.deadlineMs > 0 and now >= turn.deadlineMs

proc markOrphaned(bridge: ChatBridge; key: string) =
  ## Under the lock: drop buffered events but keep the key reserved. The
  ## orphan turn is not cancelled; its terminal answer is discarded when it
  ## arrives, and a new turn cannot mistake it for its own content.
  bridge.pending[key].orphaned = true
  bridge.pending[key].events = @[]
  bridge.pending[key].bufferedBytes = 0
  bridge.pending[key].deadlineMs = bridge.nowFn() + MaxOrphanTtlMs

# ── lifecycle ─────────────────────────────────────────────────────────────────

proc register*(bridge: ChatBridge; userId: UserId;
               timeoutMs: int64 = 0): Result[void, ChatBridgeError] =
  ## Starts a turn for `userId`. A second turn while one is pending is refused
  ## with `cbeBusy` (the caller maps it to 429). `timeoutMs` is 0 for no
  ## deadline; otherwise the deadline is fixed at registration time.
  let key = $userId
  acquire(bridge.lock)
  try:
    if bridge.pending.hasKey(key):
      if orphanExpired(bridge.pending[key], bridge.nowFn()):
        bridge.pending.del(key)
      else:
        # A worker that died after `register` never abandoned and never
        # polled: without this the key would stay busy until a process
        # restart. Reserve it for the orphan TTL instead, so a late terminal
        # is still discarded but the lockout is bounded.
        let entry = bridge.pending[key]
        if not entry.orphaned and entry.deadlineMs > 0 and
            bridge.nowFn() >= entry.deadlineMs:
          bridge.markOrphaned(key)
        return err(ChatBridgeError(
          kind: cbeBusy,
          message: "a turn is already pending for " & key,
        ))
    let deadline =
      if timeoutMs > 0: bridge.nowFn() + timeoutMs
      else: 0'i64
    bridge.pending[key] = PendingTurn(deadlineMs: deadline)
    ok()
  finally:
    release(bridge.lock)

proc deliver*(bridge: ChatBridge; msg: OutboundMessage): bool =
  ## Accepts an outbox message for the pending turn of `msg.userId`.
  ## Returns false when there is no pending turn or the turn already closed
  ## (late delivery is discarded). Debug/channel chatter is accepted and
  ## ignored: it never becomes client content.
  let key = $msg.userId
  acquire(bridge.lock)
  try:
    if not bridge.pending.hasKey(key):
      return false
    let event = ChatBridgeEvent(
      kind:         msg.replyKind,
      text:         msg.text,
      toolCall:     msg.toolCall,
      isPartial:    msg.isPartial,
      inputTokens:  msg.inputTokens,
      outputTokens: msg.outputTokens,
    )
    if bridge.pending[key].orphaned:
      # The orphan may still speak, but never into a new turn. Its terminal
      # (or the TTL) is what releases the key.
      if isTerminal(event) or
          orphanExpired(bridge.pending[key], bridge.nowFn()):
        bridge.pending.del(key)
      return false
    if bridge.pending[key].finished:
      return false
    if msg.replyKind in {rkDebug, rkChannel}:
      return true
    bridge.pending[key].appendEvent(event)
    true
  finally:
    release(bridge.lock)

proc fail*(bridge: ChatBridge; userId: UserId; message: string): bool =
  ## Closes a pending turn with a turn error. No-op when the turn is missing
  ## or already closed.
  let key = $userId
  acquire(bridge.lock)
  try:
    if not bridge.pending.hasKey(key):
      return false
    if bridge.pending[key].orphaned:
      # The orphan failed: the terminal releases the reservation.
      bridge.pending.del(key)
      return false
    if bridge.pending[key].finished:
      return false
    bridge.pending[key].appendEvent(ChatBridgeEvent(
      kind: rkTurnError,
      text: message,
    ))
    true
  finally:
    release(bridge.lock)

proc poll*(bridge: ChatBridge; userId: UserId;
           stepMs: int = PollStepMs): ChatBridgeBatch =
  ## Drains the pending turn. Partial events are returned with `cbpEvents`
  ## while the turn stays registered; a terminal event returns `cbpDone` and
  ## removes the entry. With a deadline the call naps (through the injected
  ## `nap`) until an event arrives or the deadline expires.
  let key = $userId
  while true:
    acquire(bridge.lock)
    try:
      if not bridge.pending.hasKey(key):
        return ChatBridgeBatch(status: cbpMissing)

      if bridge.pending[key].orphaned:
        if orphanExpired(bridge.pending[key], bridge.nowFn()):
          bridge.pending.del(key)
        return ChatBridgeBatch(status: cbpMissing)

      var drained = bridge.pending[key].events
      let truncated = bridge.pending[key].truncated
      let finished = bridge.pending[key].finished
      let deadline = bridge.pending[key].deadlineMs

      if finished:
        bridge.pending.del(key)
        return ChatBridgeBatch(
          status: cbpDone, events: drained, truncated: truncated)

      if drained.len > 0:
        bridge.pending[key].events = @[]
        bridge.pending[key].bufferedBytes = 0
        return ChatBridgeBatch(
          status: cbpEvents, events: drained, truncated: truncated)

      if deadline > 0 and bridge.nowFn() >= deadline:
        # Do not free the key yet: the orphan turn may still emit a terminal
        # answer, which must be discarded rather than handed to the next turn.
        bridge.markOrphaned(key)
        return ChatBridgeBatch(status: cbpDeadline, truncated: truncated)

      if deadline == 0:
        return ChatBridgeBatch(status: cbpEvents, truncated: truncated)
    finally:
      release(bridge.lock)

    if stepMs <= 0:
      return ChatBridgeBatch(status: cbpEvents)
    bridge.napFn(stepMs)

proc abandon*(bridge: ChatBridge; userId: UserId): bool =
  ## The client left: stop waiting without cancelling the agent turn. The key
  ## stays reserved (`cbeBusy`) until the orphan's terminal answer arrives or
  ## the TTL expires, so a late answer can never become the next turn's
  ## content. Returns true only for an active (non-abandoned) turn.
  let key = $userId
  acquire(bridge.lock)
  try:
    if not bridge.pending.hasKey(key):
      return false
    if bridge.pending[key].finished:
      # The terminal answer is already buffered and the client is gone:
      # nothing can consume it, so free the key now instead of holding it for
      # the whole orphan TTL.
      bridge.pending.del(key)
      return false
    if bridge.pending[key].orphaned:
      if orphanExpired(bridge.pending[key], bridge.nowFn()):
        bridge.pending.del(key)
      return false
    bridge.markOrphaned(key)
    true
  finally:
    release(bridge.lock)

proc pendingCount*(bridge: ChatBridge): int =
  acquire(bridge.lock)
  try:
    bridge.pending.len
  finally:
    release(bridge.lock)
