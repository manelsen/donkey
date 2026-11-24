## perplexity_backtrail.nim — Backtrail on Perplexity's own endpoint.
##
## `POST https://api.perplexity.ai/v1/decisions` with Perplexity Decider 1.3
## (`domain/memory/backtrail_pure` builds the body and reads the answer).
## Perplexity's own paid access, not the OpenRouter route: the model is
## pinned and Perplexity does not train on the data. The HTTP goes through
## `StdHttpAdapter`, allowed only to api.perplexity.ai, with a 2 s deadline
## and a single attempt; the per-host circuit breaker turns an outage into
## instant failures. The call blocks its caller, so the daemon runs it on a
## worker (`perplexityBacktrailJob` through app/blocking_executor). A slow or
## failed answer means no pre-search for that message.

import std/[json, strutils]
import ../../core/pipeops
import ../../ports/backtrail
import ../../ports/http
import ../http/std_http

const
  PerplexityDecisionsUrl* = "https://api.perplexity.ai/v1/decisions"
  PerplexityHost = "api.perplexity.ai"
  BacktrailTimeoutSec = 2

type
  BacktrailPost* = proc(url, body: string; headers: seq[(string, string)]):
                         Result[(int, string), string] {.gcsafe, raises: [].}
    ## (status, body) of one POST.

proc stdBacktrailPost(): BacktrailPost =
  let http = newStdHttpAdapter(timeout = BacktrailTimeoutSec, maxRetries = 1,  # one attempt: the field counts attempts
                               allowlist = @[PerplexityHost])
  result = proc(url, body: string; headers: seq[(string, string)]):
                Result[(int, string), string] {.gcsafe, raises: [].} =
    var hs: seq[HttpHeader]
    for (name, value) in headers:
      hs.add((name: name, value: value))
    try:
      let resp = ? http.post(url, body, hs)
      ok((resp.status, resp.body))
    except Exception as e:  ## effect boundary: callee raises are unannotated
      err("backtrail http: " & e.msg)

proc perplexityBacktrailCall*(apiKey, message: string;
                              post: BacktrailPost): Result[RouteDecision, string] =
  ## One classification. Blocking: callers run it off the loop
  ## (`perplexityBacktrailJob`).
  let key = apiKey.strip
  if key.len == 0:
    return err("backtrail: no Perplexity key")
  let (status, body) = ? post(PerplexityDecisionsUrl, $backtrailRequest(message),
    @[("Authorization", "Bearer " & key), ("Content-Type", "application/json")])
  if status div 100 != 2:
    return err("backtrail: HTTP " & $status)
  var j: JsonNode
  try:
    j = parseJson(body)
  except CatchableError as e:
    return err("backtrail: unreadable answer: " & e.msg)
  parseBacktrailResponse(j)

proc perplexityBacktrailJob*(input: string): Result[string, string] {.nimcall, gcsafe, raises: [].} =
  ## The worker's job (app/blocking_executor): `{"key", "message"}` in, the
  ## encoded decision out. The HTTP adapter is built here, on the worker.
  try:
    let j = parseJson(input)
    let decision = ? perplexityBacktrailCall(j{"key"}.getStr(""), j{"message"}.getStr(""),
                                             stdBacktrailPost())
    ok(encodeDecision(decision))
  except CatchableError as e:
    err("backtrail: bad job input: " & e.msg)
