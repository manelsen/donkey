## gatekeeper_pure.nim — the gatekeeper's decision, the pure part.
##
## Before the model's first turn, a decision model (Perplexity Decider 1.3)
## reads only the incoming message and says what kind it is. When it is about
## the conversation's past, Donkey runs `session_search` with the message
## and gives the model the result as a search it already made: the model
## cannot forget to look, and the result carries the "not found is not never
## said" hint. On Marta's benchmark (bench/search/RESULTS.md) that took the
## default install from 75% to 92% right. This module builds the request,
## reads the answer and decides; the HTTP is in
## adapters/decision/perplexity_gatekeeper. No I/O.

import std/[json, strutils]
import ../../core/pipeops
import ./session_search_pure

const
  GatekeeperModel* = "pplx-decider-v1.3"
  GatekeeperQuestion* = "route"
  GatekeeperInstructions* = "What kind of message did the person send to their assistant?"
  PreSearchMaxQueryChars* = SessionSearchMaxQueryChars
  PreSearchCallId* = "presearch"

type
  MessageRoute* = enum
    mrFact = "fact"      ## something said before
    mrRecent = "recent"  ## a recent period
    mrOrder = "order"    ## when, which came first, time between
    mrNow = "now"        ## not about the past

  RouteDecision* = object
    route*:      MessageRoute
    confidence*: float

const RouteCriteria = [
  (mrFact, "Asks about something the person told, said or agreed on earlier in the " &
           "conversation: a fact, name, number, preference, or the current state of something."),
  (mrRecent, "Asks what happened or was discussed in a recent period relative to today: " &
             "yesterday, last week, N days ago, in the last month."),
  (mrOrder, "Asks when something happened, which of two events came first, or how much " &
            "time passed between events."),
  (mrNow, "Does not ask about the conversation's past: a greeting, a comment, a new " &
          "request, or a request for advice."),
]

proc gatekeeperRequest*(message: string): JsonNode =
  ## The body of `POST /v1/decisions`: the message alone, one choice question.
  var criteria = newJObject()
  for (route, description) in RouteCriteria:
    criteria[$route] = %description
  %*{"model": GatekeeperModel, "state": message,
     "questions": {GatekeeperQuestion: {"type": "choice",
                                         "instructions": GatekeeperInstructions,
                                         "criteria": criteria}}}

proc parseGatekeeperResponse*(j: JsonNode): Result[RouteDecision, string] =
  if j.isNil or j.kind != JObject:
    return err("gatekeeper: the answer is not an object")
  let answer = j{"answers", GatekeeperQuestion}
  if answer.isNil or answer.kind != JObject:
    return err("gatekeeper: no answer to the route question")
  let choice = answer{"choice"}.getStr("")
  for route in MessageRoute:
    if $route == choice:
      return ok(RouteDecision(route: route, confidence: answer{"confidence"}.getFloat(0.0)))
  err("gatekeeper: unknown route '" & choice & "'")

func needsPreSearch*(d: RouteDecision): bool =
  d.route != mrNow

proc preSearchArgs*(message: string): JsonNode =
  ## `session_search` in ranked mode, with the message as the query, cut to
  ## the tool's limit without splitting a UTF-8 character.
  var q = message.strip
  if q.len > PreSearchMaxQueryChars:
    var cut = PreSearchMaxQueryChars
    while cut > 0 and (ord(q[cut]) and 0xC0) == 0x80:
      dec cut
    q = q[0 ..< cut].strip
  %*{"query": q}
