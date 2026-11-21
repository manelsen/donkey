## Provider transport — the one HTTP path every LLM provider adapter uses.
##
## Every request goes through `HttpRuntimePort`, backed in production by
## `StdHttpAdapter`:
##   - a deadline (`ProviderHttpTimeoutSec`): a stalled provider must not hang
##     the turn forever;
##   - no redirects: the API key must not be forwarded to another host;
##   - no repeated POST: a retried completion may already have been accepted
##     and billed;
##   - the per-host circuit breaker.
## Tests inject a fake port through the adapter's `http` field.

import std/[httpcore, streams]
import ../../core/pipeops
import ../../ports/http
import ../http/std_http

const ProviderHttpTimeoutSec* = 120

proc providerHttpAdapter*(): StdHttpAdapter =
  newStdHttpAdapter(timeout = ProviderHttpTimeoutSec, maxRetries = 3,
                    circuitBreaker = true, retryNonIdempotent = false)

proc transport*(http: HttpRuntimePort): HttpRuntimePort =
  ## The injected port, or the production transport when none was set.
  if http.postNoRedirect != nil: http
  else: providerHttpAdapter().toRuntimePort()

func apiError*(apiName: string; status: int; body: string): string =
  ## Same text the callers classify on ("MiniMax API error 400 Bad Request: …").
  apiName & " API error " & $HttpCode(status) & ": " & body

proc postProvider*(http: HttpRuntimePort; apiName, url, body: string;
                   headers: seq[HttpHeader]): Result[string, string] {.gcsafe.} =
  ## POSTs a provider request and returns the body of a 2xx response.
  let resp = ? transport(http).postNoRedirect(url, body, headers)
  if resp.status < 200 or resp.status >= 300:
    return err(apiError(apiName, resp.status, resp.body))
  ok(resp.body)

proc postProviderStream*(http: HttpRuntimePort; apiName, url, body: string;
                         headers: seq[HttpHeader]): Result[Stream, string] {.gcsafe.} =
  ## Same request for a streaming call. The transport returns the whole body,
  ## so the SSE lines are read from it after the response completes.
  let text = ? postProvider(http, apiName, url, body, headers)
  ok(Stream(newStringStream(text)))

template providerGuard*(body: untyped): untyped =
  ## Parsing a provider body may raise (malformed JSON, stream errors): turn it
  ## into `err` in the calling proc, like every adapter must.
  try:
    body
  except CatchableError as e:
    err(e.msg)
