## turn_journal_pure — pure state machine for the turn journal (US-001).
##
## A turn is not a single line of progress: delivery, memory and transcript are
## independent branches. This module is the total, deterministic reducer and
## the resume policy for those branches. It performs no I/O and raises nothing;
## the adapter (US-002) owns files and the callers own the effects.
##
## Journal rule: the entry is written before the effect and only the caller of
## `port.send` records `delivered`/`failed`. Recovery never repeats an effect
## that may already have happened: an `attempted` delivery is reconciled as a
## failure, a pending memory is lost rather than rewritten, and a pending
## transcript is lost because it is derived from memory.
##
## There is deliberately no linear `Delivered` phase: `tpsCommitted` means the
## turn is closed, while the delivery outcome lives in `ReplyDelivery`.

import std/[hashes, options]

const
  MaxModelReplays* = 1
    ## A stored turn may replay the model at most once.
  MaxNotices* = 1
    ## At most one recovery notice per turn.
  MaxRecoveryPasses* = 2
    ## Initial pass plus one recovery pass; a further restart abandons.

type
  TurnPhase* = enum
    tpsAccepted        ## inbound journaled; the actor may still run
    tpsReplyReady      ## the final reply exists, delivery still pending
    tpsCommitted       ## terminal: turn closed, redelivery is a duplicate
    tpsAbandoned       ## terminal: recovery gave up, never replay again

  ReplyDelivery* = enum
    rdsNone
    rdsQueued
    rdsAttempted       ## `port.send` may have happened; never resend
    rdsSent
    rdsFailed

  ReplySource* = enum
    ## Schema substitute for the PRD's `streamStarted` bool: `rsStreamed` means
    ## `tevStreamStarted` was journaled before the first partial. The enum is
    ## kept because it is stronger than a bool (the default branch is explicit)
    ## and US-002 decodes `reply_source`/`rsBuffered|rsStreamed`, not
    ## `stream_started`, so its decoder must not look for the old bool.
    rsBuffered         ## one final reply, enqueued for the drainer
    rsStreamed         ## partials were already published to the channel

  MemoryWrite* = enum
    mwsNone
    mwsPending         ## before `safeAppendMemory`; on resume it is lost
    mwsWritten
    mwsSkipped
    mwsLost

  TranscriptWrite* = enum
    twsNone
    twsPending         ## before the save; on resume it is lost, never retried
    twsSaved
    twsLost

  TurnEventKind* = enum
    tevInboundAccepted
    tevStreamStarted
    tevReplyReady
    tevReplyQueued
    tevDeliveryAttempted
    tevDelivered
    tevDeliveryFailed
    tevMemoryPending
    tevMemoryWritten
    tevMemorySkipped
    tevMemoryLost
    tevTranscriptPending
    tevTranscriptSaved
    tevTranscriptLost
    tevCommitted
    tevAbandoned
    tevRecoveryPass
    tevRecoveryNotified

  TurnEvent* = object
    ## Closed variant set: the discriminant is the only event identity and
    ## each variant carries just its own payload. There is no free-form event
    ## name and no field that belongs to another variant.
    deliveryId*: string  # shared by reply-ready and delivery-attempted; Nim
                         # rejects the same field name in two case branches, so
                         # per-variant construction cannot be enforced without
                         # breaking the adapter's shared `event.deliveryId` read
    case kind*: TurnEventKind
    of tevInboundAccepted:
      turnId*: string
      userId*: string
      channel*: string
      chatId*: string
      channelMessageId*: string
      taskKind*: string
      inboundText*: string
      mediaUrls*: seq[string]
      createdAtMs*: int64
    of tevReplyReady:
      replyText*: string
      replyHash*: string
      memoryHash*: string
      replySource*: ReplySource
    of tevDeliveryAttempted:
      ownerEpochMs*: int64
    of tevStreamStarted, tevReplyQueued, tevDelivered, tevDeliveryFailed,
       tevMemoryPending, tevMemoryWritten, tevMemorySkipped, tevMemoryLost,
       tevTranscriptPending, tevTranscriptSaved, tevTranscriptLost,
       tevCommitted, tevAbandoned, tevRecoveryPass, tevRecoveryNotified:
      discard

  TurnEntry* = object
    turnId*: string
    userId*: string
    channel*: string
    chatId*: string
    channelMessageId*: string
    taskKind*: string
    inboundText*: string
    mediaUrls*: seq[string]
    replyText*: string
    replyHash*: string
    memoryHash*: string
    deliveryId*: string
    ownerEpochMs*: int64
    modelReplays*: int
    notices*: int
    attempts*: int           ## recovery passes; 0 at ingress, capped below
    createdAtMs*: int64
    phase*: TurnPhase
    replyDelivery*: ReplyDelivery
    replySource*: ReplySource
    memoryWrite*: MemoryWrite
    transcriptWrite*: TranscriptWrite

  TurnResumePlan* = object
    turnId*: string
    replayModel*: bool
    enqueueReply*: bool
    sendQueuedReply*: bool
    reconcileDelivery*: bool
    markLost*: bool
    emitNotice*: bool
    abandon*: bool
    commit*: bool      ## journal `tevCommitted` after any pending reply
                       ## action in this plan (never before `sendQueuedReply`)

func turnIdFor*(userId, channel, channelMessageId, chatId,
                text: string): string =
  ## Stable identity of the inbound turn. The channel message id is used when
  ## the channel provides one; only an empty id falls back to
  ## `chatId:channelId:hash(text)`. `userId` is part of the signature because
  ## the ingress already has it, but the identity comes from the channel.
  if channelMessageId.len > 0:
    channelMessageId
  else:
    chatId & ":" & channel & ":" & $hash(text)

func isTurnTerminal*(entry: TurnEntry): bool =
  ## Terminal-and-committable: `tevCommitted` closes a turn only when the final
  ## reply exists (`tpsReplyReady`), the delivery branch reached a **final**
  ## outcome (`rdsSent` or `rdsFailed`), memory is terminal (`mwsWritten`,
  ## `mwsSkipped` or `mwsLost`) and the transcript is terminal (`twsSaved` or
  ## `twsLost`; it is derived and never rewritten).
  ##
  ## `rdsQueued` is deliberately NOT terminal: the reply is still waiting for
  ## the drainer, and committing it would hide the turn from `loadActive`, so a
  ## crash in that window would lose the answer. It stays resumable through
  ## `sendQueuedReply`, and only `tevDelivered`/`tevDeliveryFailed` may close
  ## the turn.
  ##
  ## `tpsAccepted`, `tpsCommitted` and `tpsAbandoned` are deliberately NOT
  ## terminal-and-committable: accepted still has work to do, and the two
  ## terminal phases are already closed. This predicate answers "may the
  ## caller journal `tevCommitted` now?", not "is the turn over?".
  entry.phase == tpsReplyReady and
    entry.replyDelivery in {rdsSent, rdsFailed} and
    entry.memoryWrite in {mwsWritten, mwsSkipped, mwsLost} and
    entry.transcriptWrite in {twsSaved, twsLost}

func isDuplicateInbound*(entry: TurnEntry): bool =
  ## Both terminal phases are duplicates for ingress: a committed turn was
  ## already answered, and an abandoned turn can no longer record a new answer,
  ## so re-answering it would publish a reply the journal does not know about.
  entry.phase in {tpsCommitted, tpsAbandoned}

func isDuplicateInbound*(entry: Option[TurnEntry]): bool =
  entry.isSome and entry.get.isDuplicateInbound()

func applyTurnEvent*(previous: Option[TurnEntry],
                    event: TurnEvent): Option[TurnEntry] =
  ## Reducer over the append-only journal. It only advances each branch; an
  ## event that cannot move the entry (a replay of an old event, an illegal
  ## transition, an event after a terminal phase) leaves the entry untouched
  ## instead of erasing journal state. `none` means no entry was ever created.
  if previous.isNone:
    case event.kind
    of tevInboundAccepted:
      let created = TurnEntry(
        turnId: (if event.turnId.len > 0: event.turnId
                 else: turnIdFor(event.userId, event.channel,
                                 event.channelMessageId, event.chatId,
                                 event.inboundText)),
        userId: event.userId,
        channel: event.channel,
        chatId: event.chatId,
        channelMessageId: event.channelMessageId,
        taskKind: event.taskKind,
        inboundText: event.inboundText,
        mediaUrls: event.mediaUrls,
        createdAtMs: event.createdAtMs,
        phase: tpsAccepted,
        replyDelivery: rdsNone,
        replySource: rsBuffered,
        memoryWrite: mwsNone,
        transcriptWrite: twsNone,
        attempts: 0,
      )
      return some(created)
    else:
      return none(TurnEntry)

  result = previous
  var entry = previous.get
  if entry.phase in {tpsCommitted, tpsAbandoned}:
    # Only the recovery notice may still be journaled for an abandoned turn;
    # a committed turn is closed for every event.
    if entry.phase == tpsAbandoned and event.kind == tevRecoveryNotified and
       entry.notices < MaxNotices:
      inc entry.notices
    result = some(entry)
    return result

  case event.kind
  of tevInboundAccepted:
    discard  # Idempotent: a redelivery never resets the stored turn.
  of tevStreamStarted:
    if entry.phase == tpsAccepted:
      entry.replySource = rsStreamed
  of tevReplyReady:
    # Exactly one final reply per turn: after the phase moved (or if a
    # delivery outcome somehow exists) a second event must not rewrite the
    # text, hashes or delivery id.
    if entry.phase == tpsAccepted and entry.replyDelivery == rdsNone:
      entry.phase = tpsReplyReady
      # `rsStreamed` is sticky: once `tevStreamStarted` was journaled, a
      # buffered event cannot downgrade the source.
      if event.replySource == rsStreamed:
        entry.replySource = rsStreamed
      if event.replyText.len > 0:
        entry.replyText = event.replyText
      if event.replyHash.len > 0:
        entry.replyHash = event.replyHash
      if event.memoryHash.len > 0:
        entry.memoryHash = event.memoryHash
      entry.deliveryId =
        (if event.deliveryId.len > 0: event.deliveryId
         else: entry.turnId & "-reply")
  of tevReplyQueued:
    # The final reply is queued by whoever put it in the outbox, buffered or
    # streamed: a crash before the drainer must be resendable (PRD CP-5).
    if entry.phase == tpsReplyReady and entry.replyDelivery == rdsNone:
      entry.replyDelivery = rdsQueued
  of tevDeliveryAttempted:
    # Only a ready reply can be attempted; an accepted turn has not produced
    # its final answer yet, and an uncertain/delivered reply never re-attempts.
    if entry.phase == tpsReplyReady and
       entry.replyDelivery in {rdsNone, rdsQueued}:
      entry.replyDelivery = rdsAttempted
      if event.ownerEpochMs != 0:
        entry.ownerEpochMs = event.ownerEpochMs
      if event.deliveryId.len > 0:
        entry.deliveryId = event.deliveryId
      elif entry.deliveryId.len == 0:
        entry.deliveryId = entry.turnId & "-reply"
  of tevDelivered:
    # `delivered`/`failed` are acknowledgements of an attempt, never of a bare
    # queued reply, and never before the reply exists.
    if entry.phase == tpsReplyReady and entry.replyDelivery == rdsAttempted:
      entry.replyDelivery = rdsSent
  of tevDeliveryFailed:
    if entry.phase == tpsReplyReady and entry.replyDelivery == rdsAttempted:
      entry.replyDelivery = rdsFailed
  of tevMemoryPending:
    if entry.memoryWrite == mwsNone:
      entry.memoryWrite = mwsPending
  of tevMemoryWritten:
    if entry.memoryWrite == mwsPending:
      entry.memoryWrite = mwsWritten
  of tevMemorySkipped:
    if entry.memoryWrite in {mwsNone, mwsPending}:
      entry.memoryWrite = mwsSkipped
  of tevMemoryLost:
    if entry.memoryWrite in {mwsNone, mwsPending}:
      entry.memoryWrite = mwsLost
  of tevTranscriptPending:
    if entry.transcriptWrite == twsNone:
      entry.transcriptWrite = twsPending
  of tevTranscriptSaved:
    if entry.transcriptWrite == twsPending:
      entry.transcriptWrite = twsSaved
  of tevTranscriptLost:
    if entry.transcriptWrite in {twsNone, twsPending}:
      entry.transcriptWrite = twsLost
  of tevCommitted:
    # Close only a turn whose three branches are terminal; a premature commit
    # is an illegal transition and is ignored, never raised.
    if isTurnTerminal(entry):
      entry.phase = tpsCommitted
  of tevAbandoned:
    entry.phase = tpsAbandoned
  of tevRecoveryPass:
    # A pass is only meaningful before the reply exists. `attempts` counts
    # recovery passes (0 at ingress, 1 then 2, the last allowed) while
    # `modelReplays` caps the model specifically; the two limits are checked
    # independently so an exhausted pass budget refuses a replay even when the
    # replay budget is untouched.
    if entry.phase == tpsAccepted and entry.replySource == rsBuffered and
       entry.attempts < MaxRecoveryPasses:
      inc entry.attempts
      if entry.modelReplays < MaxModelReplays:
        inc entry.modelReplays
  of tevRecoveryNotified:
    if entry.notices < MaxNotices:
      inc entry.notices

  result = some(entry)

func hasLostBranch(entry: TurnEntry): bool =
  entry.memoryWrite in {mwsNone, mwsPending} or
    entry.transcriptWrite in {twsNone, twsPending}

func resumeDecision*(entry: TurnEntry): TurnResumePlan =
  ## Total decision over the product of `TurnPhase`, `ReplyDelivery`,
  ## `MemoryWrite`, `TranscriptWrite` and `ReplySource`: every combination
  ## yields a plan, never an exception. It says what recovery may still do; it
  ## never performs the action. Duplicating an effect is worse than losing it:
  ## uncertain delivery is reconciled, pending memory/transcript are lost.
  ## `sendQueuedReply` resends a final that was already handed to the outbox
  ## (buffered or streamed), and `commit` is set only for a terminal-and-
  ## committable turn so the caller can journal `tevCommitted`.
  result.turnId = entry.turnId
  if entry.phase == tpsCommitted:
    return

  let mayNotice = entry.notices < MaxNotices

  if entry.phase == tpsAbandoned:
    # Terminal: at most the one notice that may have been cut short.
    result.emitNotice = mayNotice
    return

  # Delivery is independent from the phase and from model replay.
  if entry.replyDelivery == rdsAttempted:
    result.reconcileDelivery = true
  if entry.replyDelivery in {rdsAttempted, rdsFailed} and mayNotice:
    result.emitNotice = true

  # `attempts` counts recovery passes: ingress journals 0, the first pass sets
  # 1 and the second sets 2, the last allowed. `modelReplays` is a separate
  # budget for the model. Both gates are checked so an exhausted pass budget
  # refuses a replay even when no model replay happened yet, and a spent replay
  # budget refuses one even with passes left. The budget must not abandon a turn
  # whose reply is already ready or whose delivery still needs reconciling,
  # because finishing the current pass is healthy.
  case entry.phase
  of tpsAccepted:
    if entry.replySource == rsStreamed:
      # CP-3: partials already reached the channel; replaying could duplicate
      # text and the final reply cannot be reconstructed.
      result.abandon = true
      if mayNotice:
        result.emitNotice = true
    elif entry.replyDelivery != rdsNone:
      # Unreachable through the reducer (delivery events require
      # `tpsReplyReady`), but the plan must stay total: a reply that may
      # already have gone out is never replayed, so give up instead.
      result.abandon = true
      if mayNotice:
        result.emitNotice = true
    elif entry.modelReplays < MaxModelReplays and
         entry.attempts < MaxRecoveryPasses:
      result.replayModel = true
    else:
      # CP-13: the single recovery pass was already spent.
      result.abandon = true
      if mayNotice:
        result.emitNotice = true
  of tpsReplyReady:
    # The actor will not run again, so a branch that never reached a terminal
    # state is lost. Recovery never writes memory or transcript.
    result.markLost = hasLostBranch(entry)
    if entry.replyDelivery == rdsQueued:
      # CP-5: the final exists and was handed to the outbox but the drainer may
      # not have run. Both buffered and streamed resend it exactly once as a
      # simple message; `enqueueReply` is for the never-queued case only.
      if entry.replyText.len > 0:
        result.sendQueuedReply = true
      else:
        # Fail-closed: without the stored text the queued reply is empty.
        result.abandon = true
        if mayNotice:
          result.emitNotice = true
    elif entry.replyDelivery == rdsNone and entry.replySource == rsBuffered:
      if entry.replyText.len > 0:
        result.enqueueReply = true
      else:
        # Fail-closed: without the stored text the reply cannot be rebuilt.
        result.abandon = true
        if mayNotice:
          result.emitNotice = true
    # Streamed with nothing queued (CP-4-streamed): nothing was shown yet.
  of tpsCommitted, tpsAbandoned:
    discard

  # Close the turn in the same pass that made every branch terminal.
  result.commit = isTurnTerminal(entry) and entry.phase != tpsCommitted

func resumePlan*(entry: TurnEntry): TurnResumePlan =
  ## PRD spelling for `resumeDecision`; kept as an alias so callers of either
  ## name share one implementation.
  resumeDecision(entry)

func recoveryNoticeText*(entry: TurnEntry; channel: string): string =
  ## One user-visible copy per turn, and only for a delivery that may have
  ## happened or for an abandoned turn. Empty means "do not send anything".
  ## `channel` is accepted now so US-007 can vary the copy later without
  ## changing this interface; today the text is the same for every channel.
  if entry.phase != tpsAbandoned and
     entry.replyDelivery notin {rdsAttempted, rdsFailed}:
    return ""
  "Não consegui confirmar a entrega desta resposta. Para evitar uma resposta " &
    "duplicada, não vou reenviá-la automaticamente."
