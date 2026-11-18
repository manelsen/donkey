## ChatBridge + capacity tests (US-001).
##
## Every wait uses a fake clock: `nap` advances the clock instead of sleeping,
## so a deadline test is deterministic and the suite never blocks.

import std/[strutils, unittest]
import results
import donkey/core/types
import donkey/domain/message
import donkey/domain/gateway/capacity_pure
import donkey/domain/gateway/chat_response
import donkey/app/chat_bridge

# ── fake clock ────────────────────────────────────────────────────────────────

var fakeNow: int64 = 1_000
var napCount = 0

proc fakeNowFn(): int64 {.gcsafe, raises: [].} =
  fakeNow

proc fakeNapFn(ms: int) {.gcsafe, raises: [].} =
  inc napCount
  fakeNow += int64(ms)

proc resetClock(start: int64 = 1_000) =
  fakeNow = start
  napCount = 0

proc newBridge(): ChatBridge =
  resetClock()
  newChatBridge(fakeNowFn, fakeNapFn)

func apiMsg(text: string; kind = rkFinalAnswer; partial = false;
            tool = ToolCallNotice()): OutboundMessage =
  OutboundMessage(
    userId: UserId("api:alice"),
    text: text,
    replyKind: kind,
    isPartial: partial,
    toolCall: tool,
  )

# ── bridge lifecycle ──────────────────────────────────────────────────────────

suite "ChatBridge lifecycle":

  test "register, deliver a final answer and poll it once":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.pendingCount == 1
    check bridge.deliver(apiMsg("olá"))

    let batch = bridge.poll(uid)
    check batch.status == cbpDone
    check batch.events.len == 1
    check batch.events[0].kind == rkFinalAnswer
    check batch.events[0].text == "olá"
    check bridge.pendingCount == 0

    # The slot is free after the terminal poll.
    check bridge.register(uid, timeoutMs = 5000).isOk

  test "a second turn for the same user is refused as busy":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    let second = bridge.register(uid, timeoutMs = 5000)
    check second.isErr
    check second.error.kind == ChatBridgeBusy
    check second.error.isBusy
    check bridge.pendingCount == 1

  test "a different user gets an independent slot":
    let bridge = newBridge()
    check bridge.register(UserId("api:alice"), timeoutMs = 5000).isOk
    check bridge.register(UserId("api:bob"), timeoutMs = 5000).isOk
    check bridge.pendingCount == 2

  test "delivery without a pending entry is discarded":
    let bridge = newBridge()
    check not bridge.deliver(apiMsg("late"))
    check bridge.pendingCount == 0

  test "abandon keeps the key reserved until the orphan terminal":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.deliver(apiMsg("parcial A", rkFinalAnswer, partial = true))
    check bridge.abandon(uid)
    check not bridge.abandon(uid)
    check not bridge.abandon(UserId("api:nobody"))

    # B cannot take the slot while the orphan may still speak.
    let busy = bridge.register(uid, timeoutMs = 5000)
    check busy.isErr
    check busy.error.isBusy
    check bridge.poll(uid).status == cbpMissing

    # Orphan partial chatter is discarded, never buffered for B.
    check not bridge.deliver(apiMsg("ainda A", rkFinalAnswer, partial = true))
    check bridge.poll(uid).status == cbpMissing

    # A's terminal releases the reservation and is not delivered to B.
    check not bridge.deliver(apiMsg("fim do A"))
    check bridge.register(uid).isOk
    let emptyBatch = bridge.poll(uid)
    check emptyBatch.status == cbpEvents
    check emptyBatch.events.len == 0

    check bridge.deliver(apiMsg("fim do B"))
    let done = bridge.poll(uid)
    check done.status == cbpDone
    check done.events.len == 1
    check done.events[0].text == "fim do B"

  test "an orphan reservation expires after the TTL":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.abandon(uid)
    check bridge.register(uid).isErr

    fakeNow += MaxOrphanTtlMs
    check bridge.register(uid, timeoutMs = 5000).isOk

  test "a complete terminal after truncated partials is not truncated":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    # Partials alone overflow the buffer...
    for i in 0 .. 4:
      check bridge.deliver(apiMsg(repeat("x", MaxTurnBufferBytes div 3), partial = true))
    # ...but the terminal supersedes them and is complete.
    check bridge.deliver(apiMsg("curto"))
    let done = bridge.poll(uid)
    check done.status == cbpDone
    check not done.truncated
    check done.events[^1].text == "curto"

  test "the orphan TTL replaces the turn deadline":
    ## Abandoning at t=0 must reserve the key for MaxOrphanTtlMs, not keep the
    ## original 5 s deadline: at t=10 s the key is still busy.
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.abandon(uid)
    fakeNow += 10_000
    check bridge.register(uid).isErr
    fakeNow += MaxOrphanTtlMs
    check bridge.register(uid).isOk

  test "abandon after the terminal frees the key instead of holding it":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.deliver(apiMsg("resposta"))
    # The client left after the answer was already produced: nothing to
    # preserve, and the key must not stay reserved for the whole TTL.
    check not bridge.abandon(uid)
    check bridge.register(uid, timeoutMs = 5000).isOk

  test "a buffered terminal survives another register past the deadline":
    ## A finished the turn but B registered before A polled: B is refused, and
    ## A must still get its answer. Marking A orphaned here would clear it.
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.deliver(apiMsg("resposta de A"))
    fakeNow += 10_000
    check bridge.register(uid).isErr
    let done = bridge.poll(uid)
    check done.status == cbpDone
    check done.events[^1].text == "resposta de A"

  test "an expired turn that was never polled is reclaimed after the TTL":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    fakeNow += 10_000            # past the deadline, no poll, no abandon
    check bridge.register(uid).isErr
    fakeNow += MaxOrphanTtlMs
    check bridge.register(uid).isOk

  test "poll on an unknown user is missing":
    let bridge = newBridge()
    check bridge.poll(UserId("api:nobody")).status == cbpMissing

  test "partial deltas then the final answer preserve order":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.deliver(apiMsg("ol", rkFinalAnswer, partial = true))
    check bridge.deliver(apiMsg("olá", rkFinalAnswer))

    let batch = bridge.poll(uid)
    check batch.status == cbpDone
    check batch.events.len == 2
    check batch.events[0].text == "ol"
    check batch.events[0].isPartial
    check batch.events[1].text == "olá"
    check not batch.events[1].isPartial

  test "the final answer closes the turn: later delivery is discarded":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.deliver(apiMsg("fim"))
    check not bridge.deliver(apiMsg("depois"))
    let batch = bridge.poll(uid)
    check batch.status == cbpDone
    check batch.events.len == 1
    check batch.events[0].text == "fim"

  test "fail records a turn error and closes the turn":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.fail(uid, "provider down")
    check not bridge.fail(uid, "again")
    let batch = bridge.poll(uid)
    check batch.status == cbpDone
    check batch.events.len == 1
    check batch.events[0].kind == rkTurnError
    check batch.events[0].text == "provider down"

  test "tool notices and debug lines are carried but never content":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.deliver(apiMsg("🔧 fs_read", rkToolNotice,
      tool = ToolCallNotice(phase: "start", name: "fs_read", id: "c1")))
    check bridge.deliver(apiMsg("debug", rkDebug))
    check bridge.deliver(apiMsg("canal", rkChannel))
    check bridge.deliver(apiMsg("fim"))

    let batch = bridge.poll(uid)
    check batch.status == cbpDone
    var content = 0
    var notices = 0
    for event in batch.events:
      if deltaText(event.text, event.kind).len > 0:
        inc content
      if event.kind == rkToolNotice:
        inc notices
        check event.toolCall.phase == "start"
    check content == 1
    check notices == 1

    # Debug/channel chatter must not even reach the pending queue.
    check batch.events.len == 2

# ── limits ────────────────────────────────────────────────────────────────────

suite "ChatBridge buffer and deadline":

  test "the turn buffer is capped and marked truncated":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 5000).isOk
    check bridge.deliver(apiMsg(repeat("x", MaxTurnBufferBytes + 4096),
                                rkFinalAnswer, partial = true))
    check bridge.deliver(apiMsg("tail", rkFinalAnswer, partial = true))

    ## The partial stream is capped and flagged while the turn is open...
    let partials = bridge.poll(uid)
    check partials.status == cbpEvents
    check partials.truncated
    var contentBytes = 0
    for event in partials.events:
      contentBytes += event.text.len
    check contentBytes <= MaxTurnBufferBytes

    ## ...but a complete terminal supersedes them and is not "truncated":
    ## reporting `length` for a short, complete answer was the bug.
    check bridge.deliver(apiMsg("fim"))
    let batch = bridge.poll(uid)
    check batch.status == cbpDone
    check not batch.truncated
    check batch.events[^1].text == "fim"

  test "a deadline with a fake clock ends the turn without sleeping":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 35).isOk
    let batch = bridge.poll(uid)
    check batch.status == cbpDeadline
    check batch.events.len == 0
    check napCount > 0
    check fakeNow >= 1_035
    check bridge.pendingCount == 1  # the orphan reservation, not a free slot

    # The key stays reserved: the orphan may still emit a terminal answer.
    let busy = bridge.register(uid, timeoutMs = 35)
    check busy.isErr
    check busy.error.isBusy

    check not bridge.deliver(apiMsg("late final"))
    check bridge.register(uid, timeoutMs = 35).isOk

  test "events arriving before the deadline win":
    let bridge = newBridge()
    let uid = UserId("api:alice")
    check bridge.register(uid, timeoutMs = 35).isOk
    check bridge.deliver(apiMsg("fim"))
    let batch = bridge.poll(uid)
    check batch.status == cbpDone
    check napCount == 0

# ── admission budget ──────────────────────────────────────────────────────────

suite "admitLongLived":

  test "declares the 8-worker budget with 2 reserved":
    check MaxPendingTurns == 4
    check MaxConcurrentSseConnections == 4
    check MaxLongLivedWorkers == 6
    check GatewayWorkerCount == 8
    check ReservedWorkers == 2
    check GatewayWorkerCount - MaxLongLivedWorkers == ReservedWorkers

  test "admits below every limit":
    check admitted(admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 3, longLivedWorkers: 5)))
    check admitted(admitLongLived(llSseConnection,
      LongLivedSnapshot(sseConnections: 3, longLivedWorkers: 5)))

  test "refuses the 5th pending turn":
    check not admitted(admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 4, longLivedWorkers: 0)))
    check admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 4, longLivedWorkers: 0)) ==
      cvTooManyPendingTurns

  test "refuses the 5th sse connection":
    check not admitted(admitLongLived(llSseConnection,
      LongLivedSnapshot(sseConnections: 4, longLivedWorkers: 0)))
    check admitLongLived(llSseConnection,
      LongLivedSnapshot(sseConnections: 4, longLivedWorkers: 0)) ==
      cvTooManySseConnections

  test "refuses when all long-lived workers are taken":
    check not admitted(admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 0, longLivedWorkers: 6)))
    check not admitted(admitLongLived(llSseConnection,
      LongLivedSnapshot(sseConnections: 0, longLivedWorkers: 6)))

  test "the combined pending + SSE count cannot exceed the worker ceiling":
    check admitted(admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 2, sseConnections: 3,
                        longLivedWorkers: 2)))
    # Occupancy is the count before admitting: 3 + 3 already fills the
    # ceiling, so one more would be the seventh worker.
    check not admitted(admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 3, sseConnections: 3,
                        longLivedWorkers: 3)))
    check not admitted(admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 4, sseConnections: 3,
                        longLivedWorkers: 4)))
    check not admitted(admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 4, sseConnections: 4,
                        longLivedWorkers: 4)))

    # The combined ceiling is independent of the per-class caps.
    let wide = LongLivedLimits(
      maxPendingTurns: 10,
      maxConcurrentSseConnections: 10,
      maxLongLivedWorkers: 6,
    )
    check admitLongLived(llChatTurn,
      LongLivedSnapshot(pendingTurns: 4, sseConnections: 3,
                        longLivedWorkers: 4), wide) == cvNoWorker
    check admitLongLived(llSseConnection,
      LongLivedSnapshot(pendingTurns: 3, sseConnections: 3,
                        longLivedWorkers: 3), wide) == cvNoWorker
