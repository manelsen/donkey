## presearch.nim — the turn starts with the search already made.
##
## When the gatekeeper (`ports/gatekeeper`) says the incoming message is
## about the conversation's past, Donkey runs the real `session_search` with
## the message (ranked terms) and puts the call and its result in the turn's
## history, as if the model had searched first. The model cannot forget to
## look, and the result carries the "not found is not never said" hint. On
## Marta's benchmark this took the default install from 75% to 92% right
## (bench/search/RESULTS.md).
##
## A gatekeeper that is missing, fails or says "not about the past" leaves
## the turn exactly as it would be without one.

import std/json
import chronos
import ../core/log
import ../core/pipeops
import ../domain/message
import ../domain/more_tools
import ../ports/gatekeeper
import ./native_tools
import ./session_state

proc preSearch*(gatekeeper: GatekeeperPort; ctx: NativeCtx; state: SessionState;
                history: ConversationHistory; message: string;
                log: Logger): Future[ConversationHistory] {.async.} =
  if not gatekeeper.gatekeeperAvailable:
    return history
  let decision = gatekeeper.classify(message)
  if decision.isErr:
    log.warn("gatekeeper: " & decision.error & "; the turn goes on without a pre-search")
    return history
  if not needsPreSearch(decision.get):
    return history
  let args = preSearchArgs(message)
  if args["query"].getStr.len == 0:
    return history
  let call = ToolCallRequest(id: PreSearchCallId, name: SessionSearchToolName,
                            inputJson: $args)
  let found = await executeNativeTool(call, ctx, state, history)
  if not found.handled:
    return history
  var h = history
  h.addAssistantWithToolCalls("", @[call])
  h.addToolResult(PreSearchCallId, SessionSearchToolName, found.text, found.resultKind)
  log.info("gatekeeper: " & $decision.get.route & " (" & $decision.get.confidence &
           "); pre-searched past sessions")
  return h
