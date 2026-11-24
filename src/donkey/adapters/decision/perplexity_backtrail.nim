## perplexity_backtrail.nim — Backtrail on Perplexity's own endpoint.
##
## `POST https://api.perplexity.ai/v1/decisions` with Perplexity Decider 1.3
## (`domain/memory/backtrail_pure` builds the body and reads the answer).
## Perplexity's own paid access, not the OpenRouter route: the model is
## pinned and Perplexity does not train on the data. The HTTP goes through
## `StdHttpAdapter`, allowed only to api.perplexity.ai. The call blocks the
## event loop (as recall's embedding does), so it is bounded: a 2 s deadline,
## no retry, and the per-host circuit breaker turns an outage into instant
## failures. A slow or failed answer means no pre-search for that message.

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

proc perplexityBacktrail*(apiKey: string; post: BacktrailPost = nil): BacktrailPort =
  ## No key, no Backtrail (the field stays nil).
  let key = apiKey.strip
  if key.len == 0:
    return BacktrailPort()
  let send = if post != nil: post else: stdBacktrailPost()
  BacktrailPort(classify: proc(message: string): Result[RouteDecision, string]
                               {.gcsafe, raises: [].} =
    let (status, body) = ? send(PerplexityDecisionsUrl, $backtrailRequest(message),
      @[("Authorization", "Bearer " & key), ("Content-Type", "application/json")])
    if status div 100 != 2:
      return err("backtrail: HTTP " & $status)
    var j: JsonNode
    try:
      j = parseJson(body)
    except CatchableError as e:
      return err("backtrail: unreadable answer: " & e.msg)
    parseBacktrailResponse(j))
