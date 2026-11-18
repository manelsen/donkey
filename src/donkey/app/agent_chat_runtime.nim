## agent_chat_runtime.nim — the non-streaming agent turn behind `/v1/chat/completions`.
##
## The request runs the same turn as a channel (dispatch → ingress → actor →
## memory/tools → outbox) and answers with the terminal event only. Streaming
## (`stream: true`) is parsed for compatibility; this runtime still returns a
## single `chat.completion` and leaves SSE to the streaming endpoint.
##
## Every wait goes through the injected `ChatBridge` clock (`now`/`nap`), so a
## deadline test never sleeps for real.

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

type
  AgentDispatchFn* = proc(msg: InboundMessage) {.gcsafe.}
    ## Starts one turn through the session ingress (same path as `/api/chat`).

  AgentNowFn* = proc(): int64 {.gcsafe, raises: [].}
    ## Unix seconds, injected so `created` is deterministic in tests.

  AgentChatReply* = object
    status*: int    ## HTTP status code
    body*:   string ## serialised JSON body

func errorReply(status: int; message: string; errorType = "server_error";
                code = ""): AgentChatReply =
  AgentChatReply(
    status: status,
    body:   buildAgentError(message, errorType, code),
  )

func isTerminalEvent(event: ChatBridgeEvent): bool =
  event.kind in {rkFinalAnswer, rkTurnError} and not event.isPartial

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
  if not tokenConfigured:
    return errorReply(503, "agent endpoint requires DONKEY_HTTP_TOKEN")
  if body.len > MaxApiRequestBytes:
    return errorReply(
      413, "request body exceeds " & $MaxApiRequestBytes & " bytes",
      "invalid_request_error", "payload_too_large")

  let parsed = parseAgentChatRequest(body)
  if parsed.isErr:
    return AgentChatReply(status: parsed.error.status, body: parsed.error.body)
  let request = parsed.get()

  ## Authorization runs before dispatch: an ingress refusal must never be
  ## reached, and no refusal text may become assistant content.
  if bridge == nil or dispatch == nil or authorize == nil:
    return errorReply(503, "agent runtime is not available")
  case authorize(request.userId)
  of avRevoked, avNotAllowed:
    return errorReply(403, "permission_error", "permission_error")
  of avAllowed:
    discard

  let effectiveTimeout =
    if timeoutMs > 0: timeoutMs else: DefaultAgentTurnTimeoutMs
  let registered = bridge.register(
    request.userId, timeoutMs = effectiveTimeout.int64)
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
  while true:
    let batch = bridge.poll(request.userId)
    case batch.status
    of cbpEvents:
      ## Partials (including streamed deltas) are never concatenated; keep
      ## waiting for the one event that closes the turn.
      discard
    of cbpDone:
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
    ),
  )
