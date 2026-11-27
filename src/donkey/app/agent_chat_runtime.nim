## agent_chat_runtime.nim — the agent turn behind `/v1/chat/completions`.
##
## The request runs the same turn as a channel (dispatch → ingress → actor →
## memory/tools → outbox). `runAgentChat` answers with the terminal event only;
## `runAgentStream` turns the same bridge events into OpenAI SSE chunks and
## closes with exactly one `[DONE]` (or an error event after the first byte).
##
## Both run on the Chronos event loop: every wait is an injected async `nap`
## (`sleepAsync` in production) and every write an async `send`, so a turn
## never blocks the loop that also serves the other connections and drains
## the outbox that answers it. Tests inject a fake clock and nap, so a
## deadline test never sleeps for real.

import std/[monotimes, strutils]
import chronos
import ../core/pipeops
import ../core/types
import ../domain/message
import ../domain/gateway/chat_request
import ../domain/gateway/chat_response
import ../domain/gateway/identity_pure
import ./chat_bridge

const
  MaxApiRequestBytes* = 1024 * 1024
    ## Single name for the endpoint's body cap (the gateway header check and
    ## this runtime must reject at the same size).
  DefaultAgentTurnTimeoutMs* = 120_000
    ## `DONKEY_HTTP_AGENT_TIMEOUT_SEC` default; the gateway may override.
  MaxSseChunksPerTurn* = 4096
    ## Hard ceiling on data chunks; exceeding it closes with `length`.
  SseKeepaliveIntervalMs* = 15_000
    ## `: ping` cadence while the agent turn is still working.

type
  AgentDispatchFn* = proc(msg: InboundMessage) {.gcsafe, raises: [CatchableError].}
    ## Starts one turn through the session ingress (same path as `/api/chat`).

  AgentNowFn* = proc(): int64 {.gcsafe, raises: [].}
    ## Unix seconds, injected so `created` is deterministic in tests.

  AgentChatReply* = object
    status*: int    ## HTTP status code
    body*:   string ## serialised JSON body

  AgentStreamOpenFn* = proc(): Future[bool] {.gcsafe, raises: [].}
    ## Sends the SSE response headers; false means the client already left.

  AgentStreamSendFn* = proc(chunk: string): Future[bool] {.gcsafe, raises: [].}
    ## Writes one already-framed SSE chunk; false means the client left.

  AgentSlotAcquireFn* = proc(): bool {.gcsafe, raises: [].}
    ## Reserves one SSE slot through `CapacityPolicy`; false maps to 429.

  AgentSlotReleaseFn* = proc() {.gcsafe, raises: [].}

  AgentStreamClockFn* = proc(): int64 {.gcsafe, raises: [].}
  AgentNapFn* = proc(ms: int): Future[void] {.gcsafe, raises: [].}
    ## Waits without blocking the event loop; `sleepAsync` in production.

  AgentStreamOutcome* = enum
    asPreflightError  ## nothing was written; send `reply` as JSON
    asCompleted       ## final chunk and `[DONE]` sent
    asErrored         ## an error event was sent and the stream closed
    asClientGone      ## a write failed; the turn was abandoned

  AgentStreamResult* = object
    outcome*: AgentStreamOutcome
    reply*:   AgentChatReply
    ## Only set for `asPreflightError`.

func errorReply(status: int; message: string; errorType = "server_error";
                code = ""): AgentChatReply =
  AgentChatReply(
    status: status,
    body:   buildAgentError(message, errorType, code),
  )

func isTerminalEvent(event: ChatBridgeEvent): bool =
  event.kind in {rkFinalAnswer, rkTurnError} and not event.isPartial

proc agentChatStreamRequested*(body: string): bool =
  ## Cheap routing check for the gateway: only a well-formed request that asks
  ## for `stream: true` takes the SSE path. Parse errors stay on the JSON path
  ## so they can be answered with a 4xx before any byte is streamed.
  let parsed = parseAgentChatRequest(body)
  parsed.isOk and parsed.get().stream

type PreparedTurn = object
  request:   AgentChatRequest
  timeoutMs: int64

proc prepareTurn(body: string;
                 bridge: ChatBridge;
                 dispatch: AgentDispatchFn;
                 authorize: AuthorizeFn;
                 tokenConfigured: bool;
                 timeoutMs: int;
                 asUser = UserId("")): Result[PreparedTurn, AgentChatReply] =
  ## Shared preflight for both wire shapes: token, body cap, parser,
  ## availability, authorization and the effective deadline. It never writes
  ## anything, so a failure can still become a plain JSON 4xx/5xx.
  if not tokenConfigured:
    return err(errorReply(503, "agent endpoint requires DONKEY_HTTP_TOKEN"))
  if body.len > MaxApiRequestBytes:
    return err(errorReply(
      413, "request body exceeds " & $MaxApiRequestBytes & " bytes",
      "invalid_request_error", "payload_too_large"))

  let parsed = parseAgentChatRequest(body)
  if parsed.isErr:
    return err(AgentChatReply(status: parsed.error.status,
                              body: parsed.error.body))
  var request = parsed.get()
  if ($asUser).len > 0:
    ## An editor's turn (E10.2): the person its credential was paired with,
    ## whatever the body's `user` says.
    request.userId = asUser

  ## Authorization runs before dispatch: an ingress refusal must never be
  ## reached, and no refusal text may become assistant content.
  if bridge == nil or dispatch == nil or authorize == nil:
    return err(errorReply(503, "agent runtime is not available"))
  case authorize(request.userId)
  of avRevoked, avNotAllowed:
    return err(errorReply(403, "permission_error", "permission_error"))
  of avAllowed:
    discard

  let effectiveTimeout =
    if timeoutMs > 0: timeoutMs else: DefaultAgentTurnTimeoutMs
  ok(PreparedTurn(request: request, timeoutMs: effectiveTimeout.int64))

proc defaultNap(ms: int): Future[void] {.gcsafe, raises: [].} =
  sleepAsync(chronos.milliseconds(max(ms, 0)))

proc runAgentChat*(body: string;
                   bridge: ChatBridge;
                   dispatch: AgentDispatchFn;
                   authorize: AuthorizeFn;
                   tokenConfigured: bool;
                   now: AgentNowFn;
                   timeoutMs = DefaultAgentTurnTimeoutMs;
                   model = "";
                   nap: AgentNapFn = nil;
                   asUser = UserId("")): Future[AgentChatReply] {.async.} =
  ## `asUser`: the person a paired client (an A2A agent, E13.4) acts as.
  ## Maps the endpoint contract to a status/body pair:
  ## 503 without a token, 400 parser errors, 403 before dispatch, 413 for an
  ## oversized body, 429 when the user already has a turn in flight, 504 on the
  ## deadline, 502 for a terminal turn error and 200 with usage otherwise.
  ## Only the terminal event is content; partials and tool notices are ignored.
  let prepared = prepareTurn(body, bridge, dispatch, authorize,
                             tokenConfigured, timeoutMs, asUser = asUser)
  if prepared.isErr:
    return prepared.error
  let request = prepared.get().request
  let effectiveTimeout = prepared.get().timeoutMs

  let registered = bridge.register(
    request.userId, timeoutMs = effectiveTimeout)
  if registered.isErr:
    if registered.error.kind == ChatBridgeBusy:
      return errorReply(429, "a turn is already pending for this user",
                        "rate_limit_error", "chat_bridge_busy")
    return errorReply(503, "agent turn could not be registered")
  let turnToken = registered.get()

  ## The generation travels with the turn: every reply the actor emits carries
  ## it back, so a late terminal cannot close another turn.
  try:
    dispatch(InboundMessage(
      userId:    request.userId,
      channel:   ckCli,
      channelId: (if ($asUser).len > 0: "a2a" else: $request.userId),
      text:      request.text,
      bridgeToken: turnToken,
    ))
  except CatchableError as exc:
    ## No turn is running, so close the reservation instead of abandoning it.
    discard bridge.fail(request.userId, exc.msg, token = turnToken)
    discard bridge.poll(request.userId, stepMs = 0, token = turnToken)
    return errorReply(502, exc.msg, "server_error", "dispatch_failed")

  let wait = if nap != nil: nap else: defaultNap
  var terminal: ChatBridgeEvent
  var haveTerminal = false
  var truncated = false
  while true:
    let batch = bridge.poll(request.userId, stepMs = 0, token = turnToken)
    case batch.status
    of cbpEvents:
      ## Partials (including streamed deltas) are never concatenated; keep
      ## waiting for the one event that closes the turn.
      await wait(PollStepMs)
    of cbpDone:
      truncated = batch.truncated
      for event in batch.events:
        if event.isTerminalEvent:
          terminal = event
          haveTerminal = true
      break
    of cbpDeadline, cbpMissing:
      return errorReply(504, "agent turn timed out", "timeout_error",
                        "turn_timeout")

  if not haveTerminal:
    return errorReply(504, "agent turn timed out", "timeout_error",
                      "turn_timeout")
  if terminal.kind == rkTurnError:
    return errorReply(502, terminal.text, "provider_error", "turn_error")

  let created = now()
  let chosenModel =
    if model.len > 0: model
    elif request.model.len > 0: request.model
    else: "donkey/default"
  AgentChatReply(
    status: 200,
    body: buildAgentChatResponse(
      text         = terminal.text,
      model        = chosenModel,
      id           = "chatcmpl-" & $created,
      created      = created,
      inputTokens  = terminal.inputTokens,
      outputTokens = terminal.outputTokens,
      # A terminal over the bridge buffer cap is clipped; presenting it as
      # `stop` would claim the answer is complete.
      finishReason = if truncated: "length" else: "stop",
    ),
  )

proc defaultStreamNowMs(): int64 {.gcsafe, raises: [].} =
  getMonoTime().ticks div 1_000_000

type StreamState = object
  ## What the stream has sent and decided so far. `react` turns one bridge
  ## event into the chunks to write next; the caller does the writing, so
  ## the decisions stay free of I/O.
  chunkId:        string
  model:          string
  created:        int64
  planned:        int     ## chunks written plus chunks about to be written
  sentContent:    string
  finished:       bool
  errored:        bool
  finishReason:   string
  inputTokens:    int
  outputTokens:   int
  gaveUpForChunks: bool
    ## The chunk budget forced us to close the stream before the terminal:
    ## the late answer has no reader, so the reservation must be released.

proc plan(state: var StreamState; output: var seq[string]; payload: string) =
  output.add sseData(payload)
  inc state.planned

proc react(state: var StreamState; event: ChatBridgeEvent): seq[string] =
  case event.kind
  of rkFinalAnswer:
    if event.isPartial:
      let incoming = deltaText(event.text, event.kind)
      if incoming.len > 0:
        ## Producers differ: the tool loop flushes cumulative snapshots
        ## (`"Olá, mundo"` after `"Olá, "`), while a channel-style producer
        ## sends true deltas. Normalise both to a delta so an SSE client that
        ## concatenates chunks never sees the same text twice.
        ## A clipped cumulative snapshot can be shorter than what was
        ## already sent; treating it as a delta duplicated text. Only a
        ## snapshot that extends the sent text contributes its suffix; an
        ## older prefix inside it contributes nothing; anything else is a
        ## genuine delta.
        let text =
          if incoming.len <= state.sentContent.len and
             state.sentContent.contains(incoming):
            ""
          elif incoming.startsWith(state.sentContent):
            incoming[state.sentContent.len .. ^1]
          else:
            incoming
        if text.len > 0:
          if state.planned >= MaxSseChunksPerTurn:
            state.finishReason = "length"
            state.finished = true
            state.gaveUpForChunks = true
            return
          state.plan(result, buildAgentChunk(
            state.chunkId, state.model, state.created, content = text))
          state.sentContent.add(text)
    else:
      var text = event.text
      if state.sentContent.len > 0:
        if text.startsWith(state.sentContent):
          # The terminal answer is the full text; only its unseen suffix is
          # still a delta (an identical answer adds nothing).
          text = text[state.sentContent.len .. ^1]
        else:
          # A stream is append-only: never append a second answer that
          # would contradict what the client already received.
          text = ""
      if text.len > 0:
        if state.planned >= MaxSseChunksPerTurn:
          state.finishReason = "length"
          state.finished = true
          state.gaveUpForChunks = true
          return
        state.plan(result, buildAgentChunk(
          state.chunkId, state.model, state.created, content = text))
        state.sentContent.add(text)
      state.inputTokens = event.inputTokens
      state.outputTokens = event.outputTokens
      state.finished = true
  of rkTurnError:
    ## Diagnostics, not assistant content: redacted error event.
    state.plan(result, buildAgentError(event.text, "provider_error", "turn_error"))
    state.errored = true
  of rkToolNotice:
    if event.toolCall.name.len > 0 or event.toolCall.id.len > 0:
      if state.planned >= MaxSseChunksPerTurn:
        state.finishReason = "length"
        state.finished = true
        state.gaveUpForChunks = true
        return
      state.plan(result, buildAgentChunk(
        state.chunkId, state.model, state.created, toolCall = event.toolCall))
  of rkChannel:
    if event.editorRequest.len > 0:
      if state.planned >= MaxSseChunksPerTurn:
        state.finishReason = "length"
        state.finished = true
        state.gaveUpForChunks = true
        return
      state.plan(result, buildEditorRequestChunk(
        state.chunkId, state.model, state.created, event.editorRequest))
    elif event.keyboard.len > 0:
      if state.planned >= MaxSseChunksPerTurn:
        state.finishReason = "length"
        state.finished = true
        state.gaveUpForChunks = true
        return
      state.plan(result, buildApprovalChunk(
        state.chunkId, state.model, state.created, event.text, event.keyboard))
  of rkDebug:
    discard

proc runAgentStream*(body: string;
                     bridge: ChatBridge;
                     dispatch: AgentDispatchFn;
                     authorize: AuthorizeFn;
                     tokenConfigured: bool;
                     now: AgentNowFn;
                     openStream: AgentStreamOpenFn;
                     send: AgentStreamSendFn;
                     acquireSlot: AgentSlotAcquireFn = nil;
                     releaseSlot: AgentSlotReleaseFn = nil;
                     streamNow: AgentStreamClockFn = nil;
                     streamNap: AgentNapFn = nil;
                     timeoutMs = DefaultAgentTurnTimeoutMs;
                     model = "";
                     asUser = UserId("")): Future[AgentStreamResult] {.async.} =
  ## Runs the same turn behind `stream: true` and emits OpenAI
  ## `chat.completion.chunk` events: role, content deltas (one per partial),
  ## tool-call deltas, then a single finish chunk with usage and `[DONE]`.
  ##
  ## Validation and reservation happen before `openStream`, so a 4xx/429/503
  ## is still a plain JSON response. After the first byte every failure is an
  ## SSE error event with no `[DONE]`. The slot is released on every exit,
  ## including a client abort and the deadline.
  let prepared = prepareTurn(body, bridge, dispatch, authorize,
                             tokenConfigured, timeoutMs, asUser)
  if prepared.isErr:
    return AgentStreamResult(outcome: asPreflightError, reply: prepared.error)
  let request = prepared.get().request
  let effectiveTimeout = prepared.get().timeoutMs

  if acquireSlot != nil and not acquireSlot():
    return AgentStreamResult(
      outcome: asPreflightError,
      reply: errorReply(429, "too many concurrent streams",
                        "rate_limit_error", "sse_capacity"))
  try:
    let registered = bridge.register(
      request.userId, timeoutMs = effectiveTimeout)
    if registered.isErr:
      if registered.error.kind == ChatBridgeBusy:
        return AgentStreamResult(
          outcome: asPreflightError,
          reply: errorReply(429, "a turn is already pending for this user",
                            "rate_limit_error", "chat_bridge_busy"))
      return AgentStreamResult(
        outcome: asPreflightError,
        reply: errorReply(503, "agent turn could not be registered"))
    let turnToken = registered.get()

    try:
      dispatch(InboundMessage(
        userId:    request.userId,
        channel:   ckCli,
        channelId: (if ($asUser).len > 0: "editor" else: $request.userId),
        text:      request.text,
        bridgeToken: turnToken,
      ))
    except CatchableError as exc:
      ## No turn is running, so close the reservation instead of abandoning it.
      discard bridge.fail(request.userId, exc.msg, token = turnToken)
      discard bridge.poll(request.userId, stepMs = 0, token = turnToken)
      return AgentStreamResult(
        outcome: asPreflightError,
        reply: errorReply(502, exc.msg, "server_error", "dispatch_failed"))

    if not await openStream():
      discard bridge.abandon(request.userId, token = turnToken)
      return AgentStreamResult(outcome: asClientGone)

    let created = now()
    var state = StreamState(
      chunkId: "chatcmpl-" & $created,
      model:
        if model.len > 0: model
        elif request.model.len > 0: request.model
        else: "donkey/default",
      created: created,
      finishReason: "stop")
    let clock = if streamNow != nil: streamNow else: defaultStreamNowMs
    let wait = if streamNap != nil: streamNap else: defaultNap
    var clientGone = false
    var reservationClosed = false
      ## `poll` returning done/missing removes the bridge entry; abandoning
      ## then would hit whatever turn registered next for the same user.

    proc closeAsGone(): AgentStreamResult =
      if not reservationClosed:
        discard bridge.abandon(request.userId, token = turnToken)
      AgentStreamResult(outcome: asClientGone)

    var opening: seq[string]
    state.plan(opening, buildAgentChunk(
      state.chunkId, state.model, state.created, role = "assistant"))
    if not await send(opening[0]):
      return closeAsGone()

    var lastPing = clock()
    while not state.finished and not state.errored and not clientGone:
      let batch = bridge.poll(request.userId, stepMs = 0, token = turnToken)
      var pending: seq[string]
      case batch.status
      of cbpEvents:
        for event in batch.events:
          pending.add state.react(event)
          if state.finished or state.errored: break
      of cbpDone:
        reservationClosed = true
        if batch.truncated:
          state.finishReason = "length"
        for event in batch.events:
          pending.add state.react(event)
          if state.finished or state.errored: break
        if not state.finished and not state.errored:
          state.finished = true
      of cbpDeadline:
        ## The bridge already holds the key as an orphan. It is no longer ours
        ## to abandon: by the time the error is written the orphan may have
        ## been reclaimed and a new turn registered for the same user.
        reservationClosed = true
        state.plan(pending, buildAgentError(
          "agent turn timed out", "timeout_error", "turn_timeout"))
        state.errored = true
      of cbpMissing:
        reservationClosed = true
        state.plan(pending, buildAgentError(
          "agent turn is no longer pending", "server_error", "turn_missing"))
        state.errored = true

      for chunk in pending:
        if not await send(chunk):
          clientGone = true
          break

      if not state.finished and not state.errored and not clientGone:
        let current = clock()
        if current - lastPing >= SseKeepaliveIntervalMs:
          if await send(": ping\n\n"):
            lastPing = current
          else:
            clientGone = true
      if not state.finished and not state.errored and not clientGone:
        await wait(PollStepMs)

    if clientGone:
      return closeAsGone()
    if state.errored:
      return AgentStreamResult(outcome: asErrored)

    if not await send(sseData(buildAgentChunk(
        state.chunkId, state.model, state.created,
        finishReason = state.finishReason,
        inputTokens = state.inputTokens,
        outputTokens = state.outputTokens))):
      return closeAsGone()
    let doneSent = await send(sseDone())
    if state.gaveUpForChunks and not reservationClosed:
      ## We closed the stream without the terminal; release the user's slot
      ## instead of leaving it reserved for a reader that no longer exists. Do
      ## it even when `[DONE]` fails: the client is gone either way.
      discard bridge.abandon(request.userId, token = turnToken)
    if not doneSent:
      return AgentStreamResult(outcome: asClientGone)
    return AgentStreamResult(outcome: asCompleted)
  finally:
    if acquireSlot != nil and releaseSlot != nil:
      releaseSlot()
