## agent_chat_runtime.nim — the agent turn behind `/v1/chat/completions`.
##
## The request runs the same turn as a channel (dispatch → ingress → actor →
## memory/tools → outbox). `runAgentChat` answers with the terminal event only;
## `runAgentStream` turns the same bridge events into OpenAI SSE chunks and
## closes with exactly one `[DONE]` (or an error event after the first byte).
##
## Every wait goes through the injected `ChatBridge` clock (`now`/`nap`), so a
## deadline test never sleeps for real.

import std/[monotimes, os, strutils]
import results
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
  AgentDispatchFn* = proc(msg: InboundMessage) {.gcsafe.}
    ## Starts one turn through the session ingress (same path as `/api/chat`).

  AgentNowFn* = proc(): int64 {.gcsafe, raises: [].}
    ## Unix seconds, injected so `created` is deterministic in tests.

  AgentChatReply* = object
    status*: int    ## HTTP status code
    body*:   string ## serialised JSON body

  AgentStreamOpenFn* = proc(): bool {.gcsafe.}
    ## Sends the SSE response headers; false means the client already left.

  AgentStreamSendFn* = proc(chunk: string): bool {.gcsafe.}
    ## Writes one already-framed SSE chunk; false means the client left.

  AgentSlotAcquireFn* = proc(): bool {.gcsafe.}
    ## Reserves one SSE slot through `CapacityPolicy`; false maps to 429.

  AgentSlotReleaseFn* = proc() {.gcsafe.}

  AgentStreamClockFn* = proc(): int64 {.gcsafe, raises: [].}
  AgentStreamNapFn* = proc(ms: int) {.gcsafe, raises: [].}

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
                 timeoutMs: int): Result[PreparedTurn, AgentChatReply] =
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
  let request = parsed.get()

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

proc runAgentChat*(body: string;
                   bridge: ChatBridge;
                   dispatch: AgentDispatchFn;
                   authorize: AuthorizeFn;
                   tokenConfigured: bool;
                   now: AgentNowFn;
                   timeoutMs = DefaultAgentTurnTimeoutMs;
                   model = ""): AgentChatReply =
  ## Maps the endpoint contract to a status/body pair:
  ## 503 without a token, 400 parser errors, 403 before dispatch, 413 for an
  ## oversized body, 429 when the user already has a turn in flight, 504 on the
  ## deadline, 502 for a terminal turn error and 200 with usage otherwise.
  ## Only the terminal event is content; partials and tool notices are ignored.
  let prepared = prepareTurn(body, bridge, dispatch, authorize,
                             tokenConfigured, timeoutMs)
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

  try:
    dispatch(InboundMessage(
      userId:    request.userId,
      channel:   ckCli,
      channelId: $request.userId,
      text:      request.text,
    ))
  except CatchableError as exc:
    ## No turn is running, so close the reservation instead of abandoning it.
    discard bridge.fail(request.userId, exc.msg)
    discard bridge.poll(request.userId)
    return errorReply(502, exc.msg, "server_error", "dispatch_failed")

  var terminal: ChatBridgeEvent
  var haveTerminal = false
  var truncated = false
  while true:
    let batch = bridge.poll(request.userId)
    case batch.status
    of cbpEvents:
      ## Partials (including streamed deltas) are never concatenated; keep
      ## waiting for the one event that closes the turn.
      discard
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

proc defaultStreamNap(ms: int) {.gcsafe, raises: [].} =
  if ms > 0:
    os.sleep(ms)

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
                     streamNap: AgentStreamNapFn = nil;
                     timeoutMs = DefaultAgentTurnTimeoutMs;
                     model = ""): AgentStreamResult =
  ## Runs the same turn behind `stream: true` and emits OpenAI
  ## `chat.completion.chunk` events: role, content deltas (one per partial),
  ## tool-call deltas, then a single finish chunk with usage and `[DONE]`.
  ##
  ## Validation and reservation happen before `openStream`, so a 4xx/429/503
  ## is still a plain JSON response. After the first byte every failure is an
  ## SSE error event with no `[DONE]`. The slot is released on every exit,
  ## including a client abort and the deadline.
  let prepared = prepareTurn(body, bridge, dispatch, authorize,
                             tokenConfigured, timeoutMs)
  if prepared.isErr:
    return AgentStreamResult(outcome: asPreflightError, reply: prepared.error)
  let request = prepared.get().request
  let effectiveTimeout = prepared.get().timeoutMs

  var slotHeld = false
  defer:
    if slotHeld:
      slotHeld = false
      if releaseSlot != nil:
        releaseSlot()

  if acquireSlot != nil:
    if not acquireSlot():
      return AgentStreamResult(
        outcome: asPreflightError,
        reply: errorReply(429, "too many concurrent streams",
                          "rate_limit_error", "sse_capacity"))
    slotHeld = true

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

  try:
    dispatch(InboundMessage(
      userId:    request.userId,
      channel:   ckCli,
      channelId: $request.userId,
      text:      request.text,
    ))
  except CatchableError as exc:
    ## No turn is running, so close the reservation instead of abandoning it.
    discard bridge.fail(request.userId, exc.msg)
    discard bridge.poll(request.userId)
    return AgentStreamResult(
      outcome: asPreflightError,
      reply: errorReply(502, exc.msg, "server_error", "dispatch_failed"))

  if not openStream():
    discard bridge.abandon(request.userId)
    return AgentStreamResult(outcome: asClientGone)

  let created = now()
  let chosenModel =
    if model.len > 0: model
    elif request.model.len > 0: request.model
    else: "donkey/default"
  let chunkId = "chatcmpl-" & $created
  let clock = if streamNow != nil: streamNow else: defaultStreamNowMs
  let nap = if streamNap != nil: streamNap else: defaultStreamNap

  var chunksSent = 0
  var sentContent = ""
  var finished = false
  var errored = false
  var clientGone = false
  var finishReason = "stop"
  var inputTokens = 0
  var outputTokens = 0

  proc writeData(payload: string): bool =
    if send(sseData(payload)):
      inc chunksSent
      true
    else:
      clientGone = true
      false

  proc handleEvent(event: ChatBridgeEvent) =
    case event.kind
    of rkFinalAnswer:
      if event.isPartial:
        let incoming = deltaText(event.text, event.kind)
        if incoming.len > 0:
          ## Producers differ: the tool loop flushes cumulative snapshots
          ## (`"Olá, mundo"` after `"Olá, "`), while a channel-style producer
          ## sends true deltas. Normalise both to a delta so an SSE client that
          ## concatenates chunks never sees the same text twice.
          let text =
            if incoming.startsWith(sentContent): incoming[sentContent.len .. ^1]
            else: incoming
          if text.len > 0:
            if chunksSent >= MaxSseChunksPerTurn:
              finishReason = "length"
              finished = true
              return
            if not writeData(buildAgentChunk(
                chunkId, chosenModel, created, content = text)):
              return
            sentContent.add(text)
      else:
        var text = event.text
        if sentContent.len > 0:
          if text.startsWith(sentContent):
            # The terminal answer is the full text; only its unseen suffix is
            # still a delta (an identical answer adds nothing).
            text = text[sentContent.len .. ^1]
          else:
            # A stream is append-only: never append a second answer that
            # would contradict what the client already received.
            text = ""
        if text.len > 0:
          if chunksSent >= MaxSseChunksPerTurn:
            finishReason = "length"
            finished = true
            return
          if not writeData(buildAgentChunk(
              chunkId, chosenModel, created, content = text)):
            return
          sentContent.add(text)
        inputTokens = event.inputTokens
        outputTokens = event.outputTokens
        finished = true
    of rkTurnError:
      ## Diagnostics, not assistant content: redacted error event.
      discard writeData(buildAgentError(
        event.text, "provider_error", "turn_error"))
      if not clientGone:
        errored = true
    of rkToolNotice:
      if event.toolCall.name.len > 0 or event.toolCall.id.len > 0:
        if chunksSent >= MaxSseChunksPerTurn:
          finishReason = "length"
          finished = true
          return
        discard writeData(buildAgentChunk(
          chunkId, chosenModel, created, toolCall = event.toolCall))
    of rkDebug, rkChannel:
      discard

  if not writeData(buildAgentChunk(
      chunkId, chosenModel, created, role = "assistant")):
    discard bridge.abandon(request.userId)
    return AgentStreamResult(outcome: asClientGone)

  var lastPing = clock()
  while not finished and not errored and not clientGone:
    let batch = bridge.poll(request.userId, stepMs = 0)
    case batch.status
    of cbpEvents:
      for event in batch.events:
        handleEvent(event)
        if finished or errored or clientGone:
          break
    of cbpDone:
      if batch.truncated:
        finishReason = "length"
      for event in batch.events:
        handleEvent(event)
        if finished or errored or clientGone:
          break
      if not finished and not errored and not clientGone:
        finished = true
    of cbpDeadline:
      discard writeData(buildAgentError(
        "agent turn timed out", "timeout_error", "turn_timeout"))
      if not clientGone:
        errored = true
    of cbpMissing:
      discard writeData(buildAgentError(
        "agent turn is no longer pending", "server_error", "turn_missing"))
      if not clientGone:
        errored = true

    if not finished and not errored and not clientGone:
      let current = clock()
      if current - lastPing >= SseKeepaliveIntervalMs:
        if send(": ping\n\n"):
          lastPing = current
        else:
          clientGone = true
    if not finished and not errored and not clientGone:
      nap(PollStepMs)

  if clientGone:
    discard bridge.abandon(request.userId)
    return AgentStreamResult(outcome: asClientGone)
  if errored:
    return AgentStreamResult(outcome: asErrored)

  if not writeData(buildAgentChunk(
      chunkId, chosenModel, created,
      finishReason = finishReason,
      inputTokens = inputTokens,
      outputTokens = outputTokens)):
    discard bridge.abandon(request.userId)
    return AgentStreamResult(outcome: asClientGone)
  if not send(sseDone()):
    return AgentStreamResult(outcome: asClientGone)
  AgentStreamResult(outcome: asCompleted)
