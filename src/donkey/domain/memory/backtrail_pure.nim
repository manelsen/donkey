## backtrail_pure.nim — Backtrail's decision, the pure part.
##
## Backtrail checks the trail already walked: before the model's first turn,
## a decision model (Perplexity Decider 1.3) reads only the incoming message
## and says whether it points back along the conversation, and how. When it
## does, Donkey runs `session_search` with the message and gives the model
## the result as a search it already made: the model cannot forget to look,
## and the result carries the "not found is not never said" hint. On Marta's
## benchmark (bench/search/RESULTS.md) that took the default install from
## 75% to 92% right. This module builds the request, reads the answer and
## decides; the HTTP is in adapters/decision/perplexity_backtrail. No I/O.

import std/[json, options, strutils]
import ../../core/pipeops
import ./session_search_pure
import ./query_policy_pure

const
  BacktrailModel* = "pplx-decider-v1.3"
  BacktrailQuestion* = "route"
  BacktrailInstructions* = "What kind of message did the person send to their assistant?"
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

proc backtrailRequest*(message: string): JsonNode =
  ## The body of `POST /v1/decisions`: the message alone, one choice question.
  var criteria = newJObject()
  for (route, description) in RouteCriteria:
    criteria[$route] = %description
  %*{"model": BacktrailModel, "state": message,
     "questions": {BacktrailQuestion: {"type": "choice",
                                         "instructions": BacktrailInstructions,
                                         "criteria": criteria}}}

proc parseBacktrailResponse*(j: JsonNode): Result[RouteDecision, string] =
  if j.isNil or j.kind != JObject:
    return err("backtrail: the answer is not an object")
  let answer = j{"answers", BacktrailQuestion}
  if answer.isNil or answer.kind != JObject:
    return err("backtrail: no answer to the route question")
  let choice = answer{"choice"}.getStr("")
  for route in MessageRoute:
    if $route == choice:
      return ok(RouteDecision(route: route, confidence: answer{"confidence"}.getFloat(0.0)))
  err("backtrail: unknown route '" & choice & "'")

proc encodeDecision*(d: RouteDecision): string =
  ## The decision as text, to cross from the worker thread to the loop.
  $(%*{"route": $d.route, "confidence": d.confidence})

proc decodeDecision*(text: string): Result[RouteDecision, string] =
  var j: JsonNode
  try:
    j = parseJson(text)
  except CatchableError as e:
    return err("backtrail: unreadable decision: " & e.msg)
  let route = j{"route"}.getStr("")
  for r in MessageRoute:
    if $r == route:
      return ok(RouteDecision(route: r, confidence: j{"confidence"}.getFloat(0.0)))
  err("backtrail: unknown route '" & route & "'")

func preSearchCallId*(messageId: string): string =
  ## One id per turn: providers reject a conversation where two tool calls
  ## share an id, and every pre-searched turn adds one.
  if messageId.len == 0: PreSearchCallId else: PreSearchCallId & "-" & messageId

func recallPolicyFor*(route: MessageRoute): QueryPolicy =
  ## Recall's policy for a route: recency weighs only for a recent period;
  ## a fact, an order or a date, or a message not about the past, ranks by
  ## meaning and words.
  if route == mrRecent: temporalPolicy() else: defaultPolicy()

func recallPolicyForRoute*(name: string): Option[QueryPolicy] =
  ## From the route's name, as it travels on a recall request. No route
  ## (Backtrail off or failed): none, and recall decides by the words.
  for route in MessageRoute:
    if $route == name:
      return some(recallPolicyFor(route))
  none(QueryPolicy)

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
