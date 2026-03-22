## Actor mailbox unit tests.
## Covers Envelope construction, retry logic, dead-letter routing,
## overflow policy, stats tracking, and expiry — all via pipeops pipeline.

import std/[strutils, unittest]
import donkey/core/actor
import donkey/core/pipeops

# ── helpers ───────────────────────────────────────────────────────────────────

proc env(id: string; attempt: int = 0): Envelope[string] =
  newEnvelope(id, "payload-" & id, 1_000)

proc envAt(id: string; createdAt: int64; attempt: int = 0): Envelope[string] =
  Envelope[string](id: id, msg: "payload-" & id,
                   attempt: attempt, createdAt: createdAt)

# ── newEnvelope ───────────────────────────────────────────────────────────────

suite "actor — Envelope construction":

  test "newEnvelope sets fields correctly":
    let e = newEnvelope("abc", 42, 500)
    check e.id        == "abc"
    check e.msg       == 42
    check e.attempt   == 0
    check e.createdAt == 500

  test "newEnvelope attempt starts at zero":
    let e = env("x")
    check e.attempt == 0

# ── incrementAttempt (|>) ──────────────────────────────────────────────────────

suite "actor — incrementAttempt":

  test "|> increments attempt by one":
    let e = env("r1") |> incrementAttempt
    check e.attempt == 1

  test "chained |> increments twice":
    let e = env("r2") |> incrementAttempt |> incrementAttempt
    check e.attempt == 2

  test "incrementAttempt preserves id and msg":
    let original = env("preserve")
    let bumped   = original |> incrementAttempt
    check bumped.id  == original.id
    check bumped.msg == original.msg

  test "incrementAttempt preserves createdAt":
    let original = envAt("ts", 9_999)
    let bumped   = original |> incrementAttempt
    check bumped.createdAt == 9_999

# ── shouldRetry ───────────────────────────────────────────────────────────────

suite "actor — shouldRetry":

  test "attempt 0 should retry (default cap 3)":
    check shouldRetry(0)

  test "attempt 2 should retry (default cap 3)":
    check shouldRetry(2)

  test "attempt 3 should not retry (default cap 3)":
    check not shouldRetry(3)

  test "attempt 0 should not retry when maxAttempts is 0":
    check not shouldRetry(0, 0)

  test "Envelope overload: fresh envelope should retry":
    check (env("fresh") |> shouldRetry)

  test "Envelope overload: exhausted envelope should not retry":
    let e = envAt("ex", 0, DefaultMaxAttempts)
    check not e.shouldRetry

# ── isExpired ─────────────────────────────────────────────────────────────────

suite "actor — isExpired":

  test "message within TTL is not expired":
    check not isExpired(1_000, 10_000, 30_000)

  test "message exactly at TTL boundary is expired":
    check isExpired(0, 30_000, 30_000)

  test "message past TTL is expired":
    check isExpired(0, 60_000, 30_000)

# ── toDeadLetter (|>->) ───────────────────────────────────────────────────────

suite "actor — toDeadLetter":

  test "|>-> wraps envelope in dead-letter with reason":
    let dl = env("dl1") |>-> toDeadLetter("no handler")
    check dl.reason          == "no handler"
    check dl.envelope.id     == "dl1"
    check dl.envelope.attempt == 0

  test "|>-> preserves bumped attempt count":
    let dl = (env("dl2") |> incrementAttempt) |>-> toDeadLetter("exhausted")
    check dl.envelope.attempt == 1
    check dl.reason           == "exhausted"

# ── MailboxStats (|> chain) ───────────────────────────────────────────────────

suite "actor — MailboxStats":

  test "fresh stats are all zero":
    let s = MailboxStats()
    check s.sent == 0 and s.received == 0 and s.dropped == 0 and s.maxDepth == 0

  test "|> trackSent increments sent":
    let s = MailboxStats() |> trackSent
    check s.sent == 1
    check s.received == 0

  test "|> pipeline: sent → received":
    let s = MailboxStats() |> trackSent |> trackReceived
    check s.sent == 1
    check s.received == 1

  test "|> trackDropped increments dropped":
    let s = MailboxStats() |> trackDropped
    check s.dropped == 1

  test "|>-> updateMaxDepth raises high-water mark":
    let s = MailboxStats() |>-> updateMaxDepth(7)
    check s.maxDepth == 7

  test "|>-> updateMaxDepth does not lower existing high-water mark":
    let s = (MailboxStats() |>-> updateMaxDepth(10)) |>-> updateMaxDepth(3)
    check s.maxDepth == 10

  test "chained sent + maxDepth":
    let s = MailboxStats() |> trackSent |>-> updateMaxDepth(5)
    check s.sent     == 1
    check s.maxDepth == 5

# ── applyPolicy (>>= chain) ───────────────────────────────────────────────────

suite "actor — applyPolicy":

  test "not full: all policies return Ok":
    for p in [mpDrop, mpBlock, mpReplace]:
      let r = applyPolicy(p, false, env("ok"))
      check r.isOk

  test "full + mpDrop: returns Err":
    let r = applyPolicy(mpDrop, true, env("drop"))
    check r.isErr
    check "dropped" in r.error

  test "full + mpBlock: returns Ok (transport must await)":
    let r = applyPolicy(mpBlock, true, env("block"))
    check r.isOk

  test "full + mpReplace: returns Ok (transport evicts oldest)":
    let r = applyPolicy(mpReplace, true, env("replace"))
    check r.isOk

  test ">>= chaining: Ok envelope passes through identity step":
    func identity(e: Envelope[string]): Result[Envelope[string], string] = ok(e)
    let r = applyPolicy(mpBlock, false, env("chain")) >>= identity
    check r.isOk
    check r.get().id == "chain"

  test ">>= chaining: Err short-circuits — error message preserved":
    func alsoFail(e: Envelope[string]): Result[Envelope[string], string] =
      ok(e)
    let r = applyPolicy(mpDrop, true, env("skip")) >>= alsoFail
    check r.isErr
    check "skip" in r.error
