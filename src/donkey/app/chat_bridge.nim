## ChatBridge — thread-safe correlation between an API turn and outbox replies.
##
## The HTTP worker registers one pending turn keyed by `$userId`; the session
## actor delivers outbox messages from another thread; the worker polls for
## events until a final answer, a turn error, the deadline or an abandon.
##
## Registration returns a generation token. Replies produced by an API turn
## carry it, so a terminal from a turn that already ended (abandoned, expired)
## is discarded instead of closing the turn that took the user's slot after
## the TTL. Callers with no token — channel turns — pass 0 and keep the
## per-user behaviour.
##
## Waiting is injected (`now`/`nap`) so tests never sleep and the production
## adapter can use the real clock without leaking it into domain code.

import std/[locks, strutils, tables]
import ../core/pipeops
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
    keyboard*:     seq[seq[(string, string)]]
      ## An approval request's buttons (E10.4); empty otherwise.
    editorRequest*: string
      ## A request for the editor (E10.5), JSON; empty otherwise.

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
    token:         uint64 ## identity of this registration; 0 = never handed out
    events:        seq[ChatBridgeEvent]
    bufferedBytes: int
    truncated:     bool
    finished:      bool
    orphaned:     bool   ## the client left; keep the key for the orphan turn
    deadlineMs:    int64  ## absolute clock value; 0 = no deadline (or the TTL)

  ChatBridge* = ref object
    lock:     Lock
    pending:  Table[string, PendingTurn]
    tokenSeq: uint64
    nowFn:    NowFn
    napFn:    NapFn

const ChatBridgeBusy* = cbeBusy
  ## The `register` refusal for a user that already has a pending turn.

func asksApproval*(keyboard: seq[seq[(string, string)]]): bool =
  ## Channel text with approval buttons is the one kind of channel message an
  ## API stream carries: its reader may be the only one who can answer.
  for row in keyboard:
    for (_, callback) in row:
      if callback.startsWith("approval:"): return true
  false

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

# ── turn identity ─────────────────────────────────────────────────────────────

func tokenMatches(turn: PendingTurn; token: uint64): bool =
  ## A zero token is the "I have no generation" caller (a channel turn) and is
  ## accepted for whatever entry exists, preserving the pre-token behaviour.
  ## Non-zero tokens are only accepted by their own registration.
  token == 0 or turn.token == token

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
    ## The terminal supersedes accumulated partial content, so whatever was
    ## lost from partials no longer describes the answer: only a terminal that
    ## is itself clipped makes the turn truncated.
    turn.truncated = false
    if event.text.len > MaxTurnBufferBytes:
      # Only the terminal's own size matters: it replaces the partials.
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

proc sweepExpiredOrphans(bridge: ChatBridge; now: int64) =
  ## Under the lock: an orphan whose TTL passed is only reclaimed when someone
  ## touches its key, so a user who never returns would leak the entry for the
  ## process lifetime. One sweep per registration bounds that.
  var expired: seq[string]
  for key, turn in bridge.pending:
    if turn.orphaned and turn.deadlineMs > 0 and now >= turn.deadlineMs:
      expired.add(key)
  for key in expired:
    bridge.pending.del(key)

proc register*(bridge: ChatBridge; userId: UserId;
               timeoutMs: int64 = 0): Result[uint64, ChatBridgeError] =
  ## Starts a turn for `userId` and returns its generation token. A second turn
  ## while one is pending is refused with `cbeBusy` (the caller maps it to 429).
  ## `timeoutMs` is 0 for no deadline; otherwise the deadline is fixed at
  ## registration time.
  ##
  ## The token identifies this registration, not the user: replies that carry
  ## an older token belong to a turn that already ended and must not close the
  ## current one.
  let key = $userId
  acquire(bridge.lock)
  try:
    bridge.sweepExpiredOrphans(bridge.nowFn())
    if bridge.pending.hasKey(key):
      if orphanExpired(bridge.pending[key], bridge.nowFn()):
        bridge.pending.del(key)
      else:
        # A worker that died after `register` never abandoned and never
        # polled: without this the key would stay busy until a process
        # restart. Reserve it for the orphan TTL instead, so a late terminal
        # is still discarded but the lockout is bounded.
        let entry = bridge.pending[key]
        ## Do not orphan a turn whose terminal is already buffered: the
        ## original worker still has to poll it, and marking it orphaned would
        ## clear the answer.
        if not entry.orphaned and not entry.finished and entry.deadlineMs > 0 and
            bridge.nowFn() >= entry.deadlineMs:
          bridge.markOrphaned(key)
        return err(ChatBridgeError(
          kind: cbeBusy,
          message: "a turn is already pending for " & key,
        ))
    let deadline =
      if timeoutMs > 0: bridge.nowFn() + timeoutMs
      else: 0'i64
    inc bridge.tokenSeq
    let token = bridge.tokenSeq
    bridge.pending[key] = PendingTurn(deadlineMs: deadline, token: token)
    ok(token)
  finally:
    release(bridge.lock)

proc deliver*(bridge: ChatBridge; msg: OutboundMessage;
              token: uint64 = 0): bool =
  ## Accepts an outbox message for the pending turn of `msg.userId`.
  ## Returns false when there is no pending turn or the turn already closed
  ## (late delivery is discarded). Debug/channel chatter is accepted and
  ## ignored: it never becomes client content.
  ##
  ## A non-zero token is the generation the message belongs to: it is only
  ## accepted by the pending entry registered with that token, so a terminal
  ## from an abandoned turn cannot close the turn that replaced it after the
  ## TTL. Callers without a token pass 0 (or leave it on the message) and keep
  ## the previous per-user behaviour.
  let key = $msg.userId
  let effectiveToken = if token != 0: token else: msg.bridgeToken
  acquire(bridge.lock)
  try:
    if not bridge.pending.hasKey(key):
      return false
    if not tokenMatches(bridge.pending[key], effectiveToken):
      ## Another generation's message: discard it without touching the live
      ## entry (it may be a partial, a terminal or an error).
      return false
    let event = ChatBridgeEvent(
      kind:         msg.replyKind,
      text:         msg.text,
      toolCall:     msg.toolCall,
      isPartial:    msg.isPartial,
      inputTokens:  msg.inputTokens,
      outputTokens: msg.outputTokens,
      keyboard:     msg.keyboard,
      editorRequest: msg.editorRequest,
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
    if msg.replyKind == rkDebug or
       (msg.replyKind == rkChannel and not asksApproval(msg.keyboard) and
        msg.editorRequest.len == 0):
      return true
    bridge.pending[key].appendEvent(event)
    true
  finally:
    release(bridge.lock)

proc fail*(bridge: ChatBridge; userId: UserId; message: string;
           token: uint64 = 0): bool =
  ## Closes a pending turn with a turn error. No-op when the turn is missing
  ## or already closed. A non-zero `token` closes only the registration that
  ## owns it: the same rule as `deliver`.
  let key = $userId
  acquire(bridge.lock)
  try:
    if not bridge.pending.hasKey(key):
      return false
    if not tokenMatches(bridge.pending[key], token):
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
           stepMs: int = PollStepMs; token: uint64 = 0): ChatBridgeBatch =
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

      ## A caller that knows its generation must never read or remove another
      ## turn's reservation. Channel callers pass 0 and keep the old behaviour.
      if token != 0 and bridge.pending[key].token != token:
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

      if drained.len > 0 and deadline > 0 and bridge.nowFn() >= deadline:
        ## The deadline wins even when there is buffered content: without this
        ## a chatty turn past its deadline kept answering cbpEvents and the
        ## caller never saw the timeout.
        bridge.markOrphaned(key)
        return ChatBridgeBatch(status: cbpDeadline, truncated: truncated)

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

proc abandon*(bridge: ChatBridge; userId: UserId; token: uint64 = 0): bool =
  ## The client left: stop waiting without cancelling the agent turn. The key
  ## stays reserved (`cbeBusy`) until the orphan's terminal answer arrives or
  ## the TTL expires, so a late answer can never become the next turn's
  ## content. Returns true only for an active (non-abandoned) turn.
  let key = $userId
  acquire(bridge.lock)
  try:
    if not bridge.pending.hasKey(key):
      return false
    ## A worker that timed out must not abandon the turn that registered in
    ## the meantime: the generation it owns is gone.
    if token != 0 and bridge.pending[key].token != token:
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
