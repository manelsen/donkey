## Tests for the pure turn-journal state machine (US-001).
##
## The journal has independent delivery, memory and transcript branches; the
## resume decision is total over every combination of their states. TurnEvent
## is a closed variant set: each event carries only the payload of its branch.

import std/[hashes, options, unittest]
import donkey/domain/session/turn_journal_pure

proc mkEntry(phase = tpsAccepted; delivery = rdsNone; source = rsBuffered;
           memory = mwsNone; transcript = twsNone; modelReplays = 0;
           notices = 0; attempts = 0; replyText = "resposta final"):
    TurnEntry =
  TurnEntry(
    turnId: "turn-1",
    userId: "user-1",
    channel: "telegram",
    chatId: "chat-1",
    channelMessageId: "msg-1",
    taskKind: "user_msg",
    inboundText: "oi",
    mediaUrls: @["https://example.test/a.png"],
    replyText: replyText,
    replyHash: "reply-hash",
    memoryHash: "memory-hash",
    deliveryId: "turn-1-reply",
    ownerEpochMs: 1_700_000_000_000,
    modelReplays: modelReplays,
    notices: notices,
    attempts: attempts,
    createdAtMs: 1_700_000_000_001,
    phase: phase,
    replyDelivery: delivery,
    replySource: source,
    memoryWrite: memory,
    transcriptWrite: transcript,
  )

proc acceptedEntry(): TurnEntry =
  TurnEntry(
    turnId: "turn-1",
    userId: "user-1",
    channel: "telegram",
    chatId: "chat-1",
    channelMessageId: "msg-1",
    taskKind: "user_msg",
    inboundText: "oi",
    mediaUrls: @["https://example.test/a.png"],
    createdAtMs: 1_700_000_000_001,
    phase: tpsAccepted,
    replyDelivery: rdsNone,
    replySource: rsBuffered,
    memoryWrite: mwsNone,
    transcriptWrite: twsNone,
    attempts: 0,
  )

proc inboundEvent(): TurnEvent =
  TurnEvent(
    kind: tevInboundAccepted,
    turnId: "turn-1",
    userId: "user-1",
    channel: "telegram",
    chatId: "chat-1",
    channelMessageId: "msg-1",
    taskKind: "user_msg",
    inboundText: "oi",
    mediaUrls: @["https://example.test/a.png"],
    createdAtMs: 10,
  )

proc replyReadyEvent(source = rsBuffered; text = "resposta final"): TurnEvent =
  TurnEvent(
    kind: tevReplyReady,
    replyText: text,
    replyHash: "reply-hash",
    memoryHash: "memory-hash",
    deliveryId: "turn-1-reply",
    replySource: source,
  )

proc attemptedEvent(ownerEpochMs = 7'i64): TurnEvent =
  TurnEvent(
    kind: tevDeliveryAttempted,
    ownerEpochMs: ownerEpochMs,
    deliveryId: "turn-1-reply",
  )

proc simpleEvent(kind: TurnEventKind): TurnEvent =
  TurnEvent(kind: kind)

proc withEvent(e: TurnEntry; event: TurnEvent): TurnEntry =
  let next = applyTurnEvent(some(e), event)
  check next.isSome
  next.get

suite "turn_journal_pure":

  test "TurnEvent is a closed variant set":
    check compiles(TurnEvent(kind: tevDelivered))
    check not compiles(TurnEvent(kind: tevDelivered, replyText: "x"))
    check compiles(TurnEvent(kind: tevInboundAccepted, inboundText: "x"))
    check not compiles(TurnEvent(kind: tevInboundAccepted, ownerEpochMs: 1))
    check not compiles(TurnEvent(kind: tevReplyReady, inboundText: "x"))
    # PRD closed-set spelling.
    check compiles(TurnEvent(kind: tevRecoveryPass))

  test "turnId uses the channel message id":
    check turnIdFor("user-1", "telegram", "msg-1", "chat-1", "oi") == "msg-1"
    check turnIdFor("user-1", "telegram", "msg-1", "chat-1", "outro") ==
          "msg-1"

  test "turnId falls back to chat, channel and text hash":
    let fallback = turnIdFor("user-1", "telegram", "", "chat-1", "oi")
    check fallback == "chat-1:telegram:" & $hash("oi")
    check fallback != turnIdFor("user-1", "telegram", "", "chat-1", "outro")
    check fallback != turnIdFor("user-1", "telegram", "", "chat-2", "oi")

  test "only committed and abandoned turns are duplicate inbound":
    # A redelivery of a committed turn would answer again. An abandoned turn
    # can no longer record a new answer, so re-answering it would create a
    # visible reply that the journal does not know about.
    check not isDuplicateInbound(some(acceptedEntry()))
    check not isDuplicateInbound(some(mkEntry(phase = tpsReplyReady)))
    check isDuplicateInbound(some(mkEntry(phase = tpsAbandoned)))
    check isDuplicateInbound(some(mkEntry(phase = tpsCommitted)))
    check not isDuplicateInbound(none(TurnEntry))

  test "applyTurnEvent builds the entry from the inbound event":
    let e = applyTurnEvent(none(TurnEntry), inboundEvent())
    check e.isSome
    check e.get.turnId == "turn-1"
    check e.get.inboundText == "oi"
    check e.get.mediaUrls == @["https://example.test/a.png"]
    check e.get.phase == tpsAccepted
    check e.get.replyDelivery == rdsNone
    check e.get.memoryWrite == mwsNone
    check e.get.transcriptWrite == twsNone
    check e.get.attempts == 0  # ingress is not a recovery pass

  test "applyTurnEvent without inbound cannot invent an entry":
    check applyTurnEvent(none(TurnEntry),
                         simpleEvent(tevReplyReady)).isNone
    check applyTurnEvent(none(TurnEntry),
                         simpleEvent(tevCommitted)).isNone

  test "buffered happy path advances each branch monotonically":
    var e = acceptedEntry()
    e = withEvent(e, replyReadyEvent())
    check e.phase == tpsReplyReady
    check e.replyText == "resposta final"
    check e.replySource == rsBuffered
    check e.replyDelivery == rdsNone

    e = withEvent(e, simpleEvent(tevReplyQueued))
    check e.replyDelivery == rdsQueued

    e = withEvent(e, attemptedEvent())
    check e.replyDelivery == rdsAttempted
    check e.ownerEpochMs == 7

    e = withEvent(e, simpleEvent(tevDelivered))
    check e.replyDelivery == rdsSent

    e = withEvent(e, simpleEvent(tevMemoryPending))
    check e.memoryWrite == mwsPending

    e = withEvent(e, simpleEvent(tevMemoryWritten))
    check e.memoryWrite == mwsWritten

    e = withEvent(e, simpleEvent(tevTranscriptPending))
    check e.transcriptWrite == twsPending

    e = withEvent(e, simpleEvent(tevTranscriptSaved))
    check e.transcriptWrite == twsSaved

    e = withEvent(e, simpleEvent(tevCommitted))
    check e.phase == tpsCommitted
    check isDuplicateInbound(e)

  test "streamed path records the source and accepts the queued final":
    var e = acceptedEntry()
    e = withEvent(e, simpleEvent(tevStreamStarted))
    check e.replySource == rsStreamed
    check e.phase == tpsAccepted

    e = withEvent(e, replyReadyEvent(rsStreamed))
    check e.phase == tpsReplyReady
    check e.replySource == rsStreamed
    check e.replyDelivery == rdsNone

    # The final streamed reply is queued like the buffered one: crash before
    # the drainer must be recoverable by resending it as a simple message.
    e = withEvent(e, simpleEvent(tevReplyQueued))
    check e.replyDelivery == rdsQueued

  test "M1: delivery events are phase-gated":
    # Before `tpsReplyReady` there is no final reply to attempt or confirm.
    var accepted = acceptedEntry()
    accepted = withEvent(accepted, attemptedEvent())
    check accepted.replyDelivery == rdsNone
    check accepted.ownerEpochMs == 0
    accepted = withEvent(accepted, simpleEvent(tevDelivered))
    check accepted.replyDelivery == rdsNone
    accepted = withEvent(accepted, simpleEvent(tevDeliveryFailed))
    check accepted.replyDelivery == rdsNone

    # `delivered`/`failed` require `attempted`: queued alone is not enough.
    var ready = mkEntry(phase = tpsReplyReady, delivery = rdsNone)
    ready = withEvent(ready, simpleEvent(tevDelivered))
    check ready.replyDelivery == rdsNone
    ready = withEvent(ready, simpleEvent(tevDeliveryFailed))
    check ready.replyDelivery == rdsNone
    ready = withEvent(ready, simpleEvent(tevReplyQueued))
    ready = withEvent(ready, simpleEvent(tevDelivered))
    check ready.replyDelivery == rdsQueued

    # A queued event can never downgrade an attempted/delivered reply.
    var attempted = mkEntry(phase = tpsReplyReady, delivery = rdsAttempted)
    attempted = withEvent(attempted, simpleEvent(tevReplyQueued))
    check attempted.replyDelivery == rdsAttempted

  test "M1: no replay plan when the reply may already have gone out":
    for delivery in [rdsQueued, rdsAttempted, rdsSent, rdsFailed]:
      let plan = resumeDecision(mkEntry(phase = tpsAccepted,
                                      delivery = delivery))
      check not plan.replayModel
    # Only the untouched delivery branch is eligible for a model replay.
    check resumeDecision(mkEntry(phase = tpsAccepted,
                                 delivery = rdsNone)).replayModel

  test "illegal transitions never erase or regress the entry":
    var e = acceptedEntry()
    let earlyDelivery = withEvent(e, simpleEvent(tevDelivered))
    check earlyDelivery.replyDelivery == rdsNone

    let earlyMemory = withEvent(e, simpleEvent(tevMemoryWritten))
    check earlyMemory.memoryWrite == mwsNone

    let earlyTranscript = withEvent(e, simpleEvent(tevTranscriptSaved))
    check earlyTranscript.transcriptWrite == twsNone

    e = withEvent(e, simpleEvent(tevAbandoned))
    check e.phase == tpsAbandoned
    let afterAbandon = withEvent(e, replyReadyEvent())
    check afterAbandon.phase == tpsAbandoned
    check afterAbandon.replyText.len == 0

    var committed = mkEntry(phase = tpsCommitted)
    committed = withEvent(committed, simpleEvent(tevStreamStarted))
    check committed.phase == tpsCommitted

  test "B2: a premature commit is ignored and later events still work":
    # `tpsAccepted` is not terminal: the actor may still run.
    var accepted = acceptedEntry()
    accepted = withEvent(accepted, simpleEvent(tevCommitted))
    check accepted.phase == tpsAccepted
    accepted = withEvent(accepted, replyReadyEvent())
    check accepted.phase == tpsReplyReady

    # replyReady without a terminal delivery is not committable.
    var noDelivery = mkEntry(phase = tpsReplyReady, delivery = rdsNone,
                            memory = mwsWritten, transcript = twsSaved)
    noDelivery = withEvent(noDelivery, simpleEvent(tevCommitted))
    check noDelivery.phase == tpsReplyReady
    noDelivery = withEvent(noDelivery, simpleEvent(tevReplyQueued))
    check noDelivery.replyDelivery == rdsQueued

    # replyReady with a pending transcript is not committable.
    var pendingTranscript = mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                                   memory = mwsWritten,
                                   transcript = twsPending)
    pendingTranscript = withEvent(pendingTranscript,
                                  simpleEvent(tevCommitted))
    check pendingTranscript.phase == tpsReplyReady
    pendingTranscript = withEvent(pendingTranscript,
                                  simpleEvent(tevTranscriptSaved))
    check pendingTranscript.transcriptWrite == twsSaved

  test "B2: commit after every branch is terminal":
    var e = mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                    memory = mwsWritten, transcript = twsSaved)
    e = withEvent(e, simpleEvent(tevCommitted))
    check e.phase == tpsCommitted

  test "B2: isTurnTerminal requires replyReady and three terminal branches":
    check isTurnTerminal(mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                                 memory = mwsWritten, transcript = twsSaved))
    # Queued means "waiting for the drainer": still resumable, not terminal.
    check not isTurnTerminal(mkEntry(phase = tpsReplyReady,
                                     delivery = rdsQueued,
                                     memory = mwsSkipped,
                                     transcript = twsLost))
    check isTurnTerminal(mkEntry(phase = tpsReplyReady, delivery = rdsFailed,
                                 memory = mwsLost, transcript = twsSaved))

    # The delivery branch: none and attempted (uncertain) are not terminal.
    check not isTurnTerminal(mkEntry(phase = tpsReplyReady, delivery = rdsNone,
                                     memory = mwsWritten,
                                     transcript = twsSaved))
    check not isTurnTerminal(mkEntry(phase = tpsReplyReady,
                                     delivery = rdsAttempted,
                                     memory = mwsWritten,
                                     transcript = twsSaved))
    # The memory branch: none and pending are not terminal.
    check not isTurnTerminal(mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                                     memory = mwsNone, transcript = twsSaved))
    check not isTurnTerminal(mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                                     memory = mwsPending,
                                     transcript = twsSaved))
    # The transcript branch: none and pending are not terminal.
    check not isTurnTerminal(mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                                     memory = mwsWritten, transcript = twsNone))
    check not isTurnTerminal(mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                                     memory = mwsWritten,
                                     transcript = twsPending))
    # Every other phase is not terminal-and-committable, even with all three
    # branches terminal (a phase is a different notion from branch progress).
    for phase in [tpsAccepted, tpsCommitted, tpsAbandoned]:
      check not isTurnTerminal(mkEntry(phase = phase, delivery = rdsSent,
                                       memory = mwsWritten,
                                       transcript = twsSaved))


    var e = acceptedEntry()
    let again = applyTurnEvent(some(e), TurnEvent(
      kind: tevInboundAccepted,
      inboundText: "reentrega",
      mediaUrls: @["https://example.test/b.png"],
      createdAtMs: 99,
    ))
    check again.isSome
    check again.get.inboundText == "oi"
    check again.get.mediaUrls == @["https://example.test/a.png"]
    check again.get.attempts == 0

  test "notices are capped at one":
    var e = mkEntry(phase = tpsAbandoned)
    e = withEvent(e, simpleEvent(tevRecoveryNotified))
    check e.notices == 1
    e = withEvent(e, simpleEvent(tevRecoveryNotified))
    check e.notices == MaxNotices
    check e.notices == 1

  test "recovery bounds and constants":
    check MaxModelReplays == 1
    check MaxNotices == 1
    check MaxRecoveryPasses == 2

  test "CP-1/CP-2: accepted turn replays the model once":
    let decision = resumeDecision(mkEntry(phase = tpsAccepted))
    check decision.replayModel
    check not decision.enqueueReply
    check not decision.sendQueuedReply
    check not decision.reconcileDelivery
    check not decision.abandon
    check not decision.emitNotice

  test "CP-3 and CP-4-streamed are distinguishable":
    # CP-3: partials were emitted before any final reply; replay is forbidden.
    let cp3 = mkEntry(phase = tpsAccepted, source = rsStreamed)
    check not resumeDecision(cp3).replayModel
    check resumeDecision(cp3).abandon
    check resumeDecision(cp3).emitNotice

    # CP-4 streamed: replyReady is a different phase, nothing to enqueue and
    # nothing was queued for the drainer.
    let cp4 = mkEntry(phase = tpsReplyReady, source = rsStreamed)
    check not resumeDecision(cp4).replayModel
    check not resumeDecision(cp4).enqueueReply
    check not resumeDecision(cp4).sendQueuedReply
    check not resumeDecision(cp4).abandon

    # Same phase and delivery as CP-3, but buffered: replay is allowed.
    let cp1 = mkEntry(phase = tpsAccepted, source = rsBuffered)
    check resumeDecision(cp1).replayModel
    check not resumeDecision(cp1).abandon

  test "CP-4: buffered reply ready enqueues once, streamed does not":
    let buffered = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        source = rsBuffered))
    check buffered.enqueueReply
    check not buffered.sendQueuedReply
    check buffered.markLost  # the actor will not run again
    check not buffered.abandon
    check not buffered.emitNotice

    let streamed = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        source = rsStreamed))
    check not streamed.enqueueReply
    check not streamed.sendQueuedReply
    check not streamed.abandon
    check streamed.markLost
    check not streamed.emitNotice

  test "CP-5: a queued reply is resent once for both sources":
    let buffered = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        delivery = rdsQueued))
    check buffered.sendQueuedReply
    check not buffered.enqueueReply
    check not buffered.reconcileDelivery
    check not buffered.abandon

    # A streamed final was queued by `streamToOutbox`; if the crash happened
    # before the drainer, resending it as a simple message is the only copy.
    let streamed = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        delivery = rdsQueued,
                                        source = rsStreamed))
    check streamed.sendQueuedReply
    check not streamed.enqueueReply
    check not streamed.reconcileDelivery
    check not streamed.abandon

  test "CP-6/CP-7: an attempted delivery is failed, never resent":
    for delivery in [rdsAttempted, rdsFailed]:
      let decision = resumeDecision(mkEntry(phase = tpsReplyReady,
                                          delivery = delivery))
      check not decision.enqueueReply
      check not decision.abandon
      check decision.emitNotice
      if delivery == rdsAttempted:
        check decision.reconcileDelivery
      else:
        check not decision.reconcileDelivery

  test "CP-8: a sent reply has no delivery action":
    let decision = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        delivery = rdsSent,
                                        memory = mwsWritten,
                                        transcript = twsSaved))
    check not decision.enqueueReply
    check not decision.reconcileDelivery
    check not decision.markLost
    check not decision.emitNotice
    check not decision.abandon

  test "CP-9: pending memory is marked lost, never rewritten":
    let decision = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        delivery = rdsSent,
                                        memory = mwsPending))
    check decision.markLost
    check not decision.enqueueReply
    check not decision.abandon
    check not decision.emitNotice

  test "CP-10: written memory needs nothing":
    let decision = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        delivery = rdsSent,
                                        memory = mwsWritten,
                                        transcript = twsSaved))
    check not decision.markLost
    check not decision.enqueueReply

  test "CP-11: pending transcript is lost, never rewritten":
    let decision = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        delivery = rdsSent,
                                        memory = mwsWritten,
                                        transcript = twsPending))
    check decision.markLost
    check not decision.enqueueReply
    check not decision.abandon

  test "CP-12: committed turn is a no-op duplicate":
    let decision = resumeDecision(mkEntry(phase = tpsCommitted,
                                        delivery = rdsSent,
                                        memory = mwsWritten,
                                        transcript = twsSaved))
    check not decision.replayModel
    check not decision.enqueueReply
    check not decision.reconcileDelivery
    check not decision.markLost
    check not decision.emitNotice
    check not decision.abandon
    check isDuplicateInbound(mkEntry(phase = tpsCommitted))

  test "CP-13: a second restart with the replay spent abandons":
    let decision = resumeDecision(mkEntry(phase = tpsAccepted,
                                        modelReplays = MaxModelReplays,
                                        attempts = 2))
    check not decision.replayModel
    check decision.abandon
    check decision.emitNotice

  test "one restart is healthy: reply ready after replay still enqueues":
    var e = mkEntry(phase = tpsAccepted)

    let first = resumeDecision(e)
    check first.replayModel
    check not first.abandon

    e = withEvent(e, simpleEvent(tevRecoveryPass))
    check e.modelReplays == 1
    check e.attempts == 1  # the first recovery pass

    # The same recovery pass produced the reply; finishing it is not a new
    # pass, so the healthy turn continues.
    e = withEvent(e, replyReadyEvent())
    check e.phase == tpsReplyReady

    let second = resumeDecision(e)
    check second.enqueueReply
    check not second.abandon
    check not second.replayModel

    e = withEvent(e, simpleEvent(tevReplyQueued))
    e = withEvent(e, attemptedEvent())
    e = withEvent(e, simpleEvent(tevDelivered))
    e = withEvent(e, simpleEvent(tevMemoryWritten))
    # tevMemoryWritten alone is not enough: pending must precede it.
    check e.memoryWrite == mwsNone

    e = withEvent(e, simpleEvent(tevMemoryPending))
    e = withEvent(e, simpleEvent(tevMemoryWritten))
    e = withEvent(e, simpleEvent(tevTranscriptPending))
    e = withEvent(e, simpleEvent(tevTranscriptSaved))
    e = withEvent(e, simpleEvent(tevCommitted))

    let third = resumeDecision(e)
    check not third.replayModel
    check not third.enqueueReply
    check not third.abandon
    check isDuplicateInbound(e)

  test "two restarts spend at most one replay and one notice":
    var e = mkEntry(phase = tpsAccepted)

    let first = resumeDecision(e)
    check first.replayModel
    check not first.abandon

    e = withEvent(e, simpleEvent(tevRecoveryPass))
    check e.modelReplays == 1
    check e.attempts == 1

    let second = resumeDecision(e)
    check not second.replayModel
    check second.abandon
    check second.emitNotice

    e = withEvent(e, simpleEvent(tevAbandoned))
    e = withEvent(e, simpleEvent(tevRecoveryNotified))
    check e.phase == tpsAbandoned
    check e.notices == 1

    let third = resumeDecision(e)
    check not third.replayModel
    check not third.enqueueReply
    check not third.emitNotice
    check not third.abandon

    e = withEvent(e, simpleEvent(tevRecoveryNotified))
    check e.notices == 1

  test "M2: attempts and modelReplays are independent guards":
    # Ingress journals 0. The first recovery pass sets 1; the second sets 2
    # and is the last allowed; a third event is ignored.
    var e = mkEntry(phase = tpsAccepted)
    e = withEvent(e, simpleEvent(tevRecoveryPass))
    check e.attempts == 1
    check e.modelReplays == 1
    e = withEvent(e, simpleEvent(tevRecoveryPass))
    check e.attempts == 2
    check e.modelReplays == 1  # the replay cap is independent of the pass cap
    e = withEvent(e, simpleEvent(tevRecoveryPass))
    check e.attempts == 2
    check e.modelReplays == 1

    # The replay budget alone stops another model replay.
    let replaySpent = resumeDecision(mkEntry(phase = tpsAccepted,
                                            attempts = 1,
                                            modelReplays = MaxModelReplays))
    check not replaySpent.replayModel
    check replaySpent.abandon

    # The pass budget alone stops a replay even with the replay budget intact.
    let passesSpent = resumeDecision(mkEntry(phase = tpsAccepted,
                                            attempts = MaxRecoveryPasses,
                                            modelReplays = 0))
    check not passesSpent.replayModel
    check passesSpent.abandon

  test "M3: a streamed turn cannot downgrade to buffered":
    var e = acceptedEntry()
    e = withEvent(e, simpleEvent(tevStreamStarted))
    e = withEvent(e, replyReadyEvent(rsBuffered))
    check e.replySource == rsStreamed
    check e.phase == tpsReplyReady

  test "M4: a second tevReplyReady never overwrites the first":
    var e = acceptedEntry()
    e = withEvent(e, replyReadyEvent(text = "primeira"))
    check e.replyText == "primeira"
    let second = TurnEvent(
      kind: tevReplyReady, replyText: "segunda", replyHash: "outro-hash",
      memoryHash: "outra-memoria", deliveryId: "outro-id",
      replySource: rsStreamed)
    e = withEvent(e, second)
    check e.replyText == "primeira"
    check e.replyHash == "reply-hash"
    check e.memoryHash == "memory-hash"
    check e.deliveryId == "turn-1-reply"
    check e.replySource == rsBuffered
    check e.phase == tpsReplyReady

    # The same guard when the delivery branch is no longer untouched.
    var odd = mkEntry(phase = tpsAccepted, delivery = rdsQueued, replyText = "")
    odd = withEvent(odd, replyReadyEvent(text = "tardia"))
    check odd.phase == tpsAccepted
    check odd.replyText.len == 0

  test "B3: the plan commits exactly a terminal turn":
    let terminal = mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                           memory = mwsWritten, transcript = twsSaved)
    check resumePlan(terminal).commit
    check not resumePlan(mkEntry(phase = tpsReplyReady, delivery = rdsNone,
                                 memory = mwsWritten,
                                 transcript = twsSaved)).commit
    check not resumePlan(mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                                 memory = mwsPending,
                                 transcript = twsSaved)).commit
    check not resumePlan(mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                                 memory = mwsWritten,
                                 transcript = twsPending)).commit
    check not resumePlan(mkEntry(phase = tpsAccepted)).commit
    check not resumePlan(mkEntry(phase = tpsCommitted, delivery = rdsSent,
                                 memory = mwsWritten,
                                 transcript = twsSaved)).commit
    check not resumePlan(mkEntry(phase = tpsAbandoned)).commit
    # A queued delivery is resumable but must not close the turn.
    let queued = resumePlan(mkEntry(phase = tpsReplyReady, delivery = rdsQueued,
                                    memory = mwsSkipped, transcript = twsLost))
    check not queued.commit
    check queued.sendQueuedReply

  test "pin: a queued reply never triggers a delivery notice":
    for source in ReplySource:
      let plan = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        delivery = rdsQueued,
                                        source = source))
      check plan.sendQueuedReply
      check not plan.emitNotice

  test "pin: the notice cap also applies before abandonment":
    var e = mkEntry(phase = tpsReplyReady, delivery = rdsSent,
                    memory = mwsWritten, transcript = twsSaved)
    e = withEvent(e, simpleEvent(tevRecoveryNotified))
    check e.notices == 1
    e = withEvent(e, simpleEvent(tevRecoveryNotified))
    check e.notices == MaxNotices

  test "pin: an unknown owner epoch does not erase the stored one":
    var e = mkEntry(phase = tpsReplyReady, delivery = rdsNone)
    check e.ownerEpochMs == 1_700_000_000_000
    e = withEvent(e, attemptedEvent(ownerEpochMs = 0))
    check e.replyDelivery == rdsAttempted
    check e.ownerEpochMs == 1_700_000_000_000

    # A known epoch still fills an entry that never had an owner.
    var fresh = mkEntry(phase = tpsReplyReady, delivery = rdsNone)
    fresh.ownerEpochMs = 0
    fresh = withEvent(fresh, attemptedEvent(ownerEpochMs = 7))
    check fresh.ownerEpochMs == 7

  test "pin: a duplicate queued event does not double-count":
    var e = mkEntry(phase = tpsReplyReady)
    e = withEvent(e, simpleEvent(tevReplyQueued))
    let queuedId = e.deliveryId
    e = withEvent(e, simpleEvent(tevReplyQueued))
    check e.replyDelivery == rdsQueued
    check e.deliveryId == queuedId
    let plan = resumeDecision(e)
    check plan.sendQueuedReply
    check not plan.enqueueReply

  test "fail-closed: a ready reply without text abandons instead of sending":
    let decision = resumeDecision(mkEntry(phase = tpsReplyReady,
                                        delivery = rdsQueued,
                                        replyText = ""))
    check not decision.enqueueReply
    check decision.abandon
    check decision.emitNotice

  test "resumeDecision is total and deterministic over every state product":
    for phase in TurnPhase:
      for delivery in ReplyDelivery:
        for memory in MemoryWrite:
          for transcript in TranscriptWrite:
            for source in ReplySource:
              let e = mkEntry(phase = phase, delivery = delivery, memory = memory,
                            transcript = transcript, source = source)
              let first = resumeDecision(e)
              let second = resumeDecision(e)
              check first == second
              check first.turnId == e.turnId

              if phase == tpsCommitted:
                check not first.replayModel
                check not first.enqueueReply
                check not first.sendQueuedReply
                check not first.reconcileDelivery
                check not first.markLost
                check not first.emitNotice
                check not first.abandon
                check not first.commit

              if first.replayModel:
                check phase == tpsAccepted
                check e.replySource == rsBuffered
                check delivery == rdsNone
                check e.modelReplays < MaxModelReplays
                check e.attempts < MaxRecoveryPasses

              if first.enqueueReply:
                check phase == tpsReplyReady
                check delivery == rdsNone
                check e.replySource == rsBuffered
                check e.replyText.len > 0
                check not first.sendQueuedReply
                check not first.abandon

              if first.sendQueuedReply:
                check phase == tpsReplyReady
                check delivery == rdsQueued
                check e.replyText.len > 0
                check not first.enqueueReply
                check not first.abandon

              check first.commit == (isTurnTerminal(e) and
                                    phase != tpsCommitted)

              if phase == tpsReplyReady and delivery == rdsQueued:
                check not first.emitNotice
                check not first.reconcileDelivery

              if first.emitNotice:
                check e.replyDelivery in {rdsAttempted, rdsFailed} or
                      first.abandon or e.phase == tpsAbandoned

              if phase == tpsAbandoned and e.notices >= MaxNotices:
                check not first.emitNotice
                check not first.replayModel
                check not first.enqueueReply
                check not first.sendQueuedReply
                check not first.reconcileDelivery
                check not first.abandon
                check not first.commit

  test "recovery notice only exists for attempted or abandoned delivery":
    check recoveryNoticeText(mkEntry(phase = tpsReplyReady,
                                   delivery = rdsNone), "telegram").len == 0
    check recoveryNoticeText(mkEntry(phase = tpsReplyReady,
                                   delivery = rdsQueued), "telegram").len == 0
    check recoveryNoticeText(mkEntry(phase = tpsReplyReady,
                                   delivery = rdsSent), "telegram").len == 0
    check recoveryNoticeText(mkEntry(phase = tpsReplyReady,
                                   delivery = rdsAttempted),
                             "telegram").len > 0
    check recoveryNoticeText(mkEntry(phase = tpsReplyReady,
                                   delivery = rdsFailed), "telegram").len > 0
    check recoveryNoticeText(mkEntry(phase = tpsAbandoned,
                                   delivery = rdsNone), "telegram").len > 0

  test "resumePlan alias matches the decision":
    let e = mkEntry(phase = tpsReplyReady, delivery = rdsAttempted)
    check resumePlan(e) == resumeDecision(e)
