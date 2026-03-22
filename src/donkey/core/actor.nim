## actor.nim — Actor model mailbox types and resilience logic.
##
## Pure domain model for BEAM/Pincer-inspired actor message passing.
## The async transport layer (AsyncQueue) lives in app/; this module
## provides the envelope abstraction, delivery policies, and pipeline-
## friendly pure functions for building resilient mailbox semantics.
##
## Boundary: no Chronos, no I/O — only `func` and `import ./pipeops`.
##
## Pipeline usage:
##   let retried = envelope |> incrementAttempt
##   let dead    = envelope |>-> toDeadLetter("no handler")
##   applyPolicy(mpDrop, isFull, e) >>= record >>= notify

import ./pipeops

const
  DefaultMaxAttempts* = 3
  DefaultTtlMs*       = 30_000

# ── types ─────────────────────────────────────────────────────────────────────

type
  MailboxPolicy* = enum
    ## Overflow policy for a bounded mailbox.
    mpDrop    ## drop the newest message when full — producer never blocks
    mpBlock   ## backpressure: let the transport layer await space
    mpReplace ## ring-buffer style: drop oldest, enqueue newest

  Envelope*[M] = object
    ## Wraps a message with delivery metadata for resilient routing.
    id*:        string   ## correlation / tracing id
    msg*:       M        ## payload
    attempt*:   int      ## 0 = first delivery; incremented on each retry
    createdAt*: int64    ## monotonic ms (from pipeops.nowMs)

  DeadLetter*[M] = object
    ## Record of an undeliverable message and the reason for failure.
    envelope*: Envelope[M]
    reason*:   string

  MailboxStats* = object
    ## Immutable snapshot of mailbox health counters.
    sent*:     int64   ## total messages enqueued
    received*: int64   ## total messages consumed
    dropped*:  int64   ## total messages discarded due to policy / expiry
    maxDepth*: int     ## high-water mark of simultaneous messages in box

# ── construction ──────────────────────────────────────────────────────────────

func newEnvelope*[M](id: string; msg: M; createdAt: int64): Envelope[M] =
  ## Constructs an Envelope with a caller-supplied timestamp.
  ## Prefer this in pure contexts; use nowMs() at the call site.
  Envelope[M](id: id, msg: msg, attempt: 0, createdAt: createdAt)

# ── pure transforms (|> friendly — unary, piped value is first/only arg) ──────

func incrementAttempt*[M](e: Envelope[M]): Envelope[M] =
  ## Returns a copy of the envelope with the delivery counter bumped.
  ##   envelope |> incrementAttempt
  Envelope[M](id: e.id, msg: e.msg,
              attempt: e.attempt + 1, createdAt: e.createdAt)

func trackSent*(s: MailboxStats): MailboxStats =
  ## Returns stats with the sent counter incremented.
  ##   stats |> trackSent
  MailboxStats(sent: s.sent + 1, received: s.received,
               dropped: s.dropped, maxDepth: s.maxDepth)

func trackReceived*(s: MailboxStats): MailboxStats =
  ## Returns stats with the received counter incremented.
  ##   stats |> trackReceived
  MailboxStats(sent: s.sent, received: s.received + 1,
               dropped: s.dropped, maxDepth: s.maxDepth)

func trackDropped*(s: MailboxStats): MailboxStats =
  ## Returns stats with the dropped counter incremented.
  ##   stats |> trackDropped
  MailboxStats(sent: s.sent, received: s.received,
               dropped: s.dropped + 1, maxDepth: s.maxDepth)

# ── last-arg transforms (|>-> friendly — piped value is the last argument) ────

func toDeadLetter*[M](reason: string; e: Envelope[M]): DeadLetter[M] =
  ## Wraps an envelope in a DeadLetter record.
  ##   envelope |>-> toDeadLetter("no handler registered")
  DeadLetter[M](envelope: e, reason: reason)

func updateMaxDepth*(depth: int; s: MailboxStats): MailboxStats =
  ## Returns stats with maxDepth raised to depth if it is a new high-water mark.
  ##   stats |>-> updateMaxDepth(currentQueueLen)
  MailboxStats(sent: s.sent, received: s.received, dropped: s.dropped,
               maxDepth: if depth > s.maxDepth: depth else: s.maxDepth)

# ── predicates ────────────────────────────────────────────────────────────────

func shouldRetry*(attempt: int; maxAttempts = DefaultMaxAttempts): bool =
  ## True when there are delivery attempts remaining.
  attempt < maxAttempts

func shouldRetry*[M](e: Envelope[M]; maxAttempts = DefaultMaxAttempts): bool =
  ## Envelope overload — pipeline-friendly predicate.
  ##   if envelope |> shouldRetry: ...
  e.attempt < maxAttempts

func isExpired*(createdAt: int64; nowMs: int64;
               ttlMs: int64 = DefaultTtlMs): bool =
  ## True when the message has exceeded its time-to-live.
  ##   if isExpired(e.createdAt, nowMs()): ...
  nowMs - createdAt >= ttlMs

# ── overflow decision (Result[T,E], >>= friendly) ─────────────────────────────

func applyPolicy*[M](policy: MailboxPolicy; isFull: bool;
                     e: Envelope[M]): Result[Envelope[M], string] =
  ## Returns Ok(e) when the envelope may be enqueued, Err when discarded.
  ## Allows railway-oriented chaining:
  ##   applyPolicy(mpDrop, isFull, e) >>= enqueue >>= acknowledge
  if not isFull:
    ok(e)
  else:
    case policy
    of mpDrop:
      err("mailbox full: dropped (id=" & e.id & ")")
    of mpBlock:
      ok(e)   ## transport layer must await; policy only signals intent
    of mpReplace:
      ok(e)   ## transport layer evicts oldest; policy only signals intent
