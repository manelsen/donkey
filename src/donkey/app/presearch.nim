## presearch.nim — the turn starts with the search already made.
##
## When Backtrail (`ports/backtrail`) says the incoming message is
## about the conversation's past, Donkey runs the real `session_search` with
## the message (ranked terms) and puts the call and its result in the turn's
## history, as if the model had searched first. The model cannot forget to
## look, and the result carries the "not found is not never said" hint. On
## Marta's benchmark this took the default install from 75% to 92% right
## (bench/search/RESULTS.md).
##
## A Backtrail that is missing, fails or says "not about the past" leaves
## the turn exactly as it would be without one.

import std/[json, options]
import chronos
import ../core/log
import ../core/pipeops
import ../domain/message
import ../domain/more_tools
import ../ports/backtrail
import ./native_tools
import ./session_state

proc classifyMessage*(backtrail: BacktrailPort; message: string;
                      log: Logger): Future[Option[RouteDecision]] {.async.} =
  ## The message's route, once per turn: it sets recall's policy and decides
  ## the pre-search. None when Backtrail is off or fails (the turn goes on as
  ## without it).
  if not backtrail.backtrailAvailable:
    return none(RouteDecision)
  var decision: Result[RouteDecision, string]
  try:
    decision = await backtrail.classify(message)
  except CancelledError as e:
    raise e
  except CatchableError as e:
    decision = err(Result[RouteDecision, string], e.msg)
  if decision.isErr:
    log.warn("backtrail: " & decision.error & "; the turn goes on without it")
    return none(RouteDecision)
  return some(decision.get)

proc preSearch*(decision: Option[RouteDecision]; ctx: NativeCtx; state: SessionState;
                history: ConversationHistory; message, callId: string;
                log: Logger): Future[ConversationHistory] {.async.} =
  ## `callId` is this turn's (`preSearchCallId`), unique in the session.
  if decision.isNone or not needsPreSearch(decision.get):
    return history
  let args = preSearchArgs(message)
  if args["query"].getStr.len == 0:
    return history
  let call = ToolCallRequest(id: callId, name: SessionSearchToolName,
                            inputJson: $args)
  let found = await executeNativeTool(call, ctx, state, history)
  if not found.handled:
    return history
  var h = history
  h.addAssistantWithToolCalls("", @[call])
  h.addToolResult(callId, SessionSearchToolName, found.text, found.resultKind)
  log.info("backtrail: " & $decision.get.route & " (" & $decision.get.confidence &
           "); pre-searched past sessions")
  return h
