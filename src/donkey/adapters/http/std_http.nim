## StdHttpAdapter — the HttpPort every adapter uses: allowlist, per-host
## circuit breaker, retries with backoff, 429 and 409 handling. Each attempt
## runs on `deadline_transport` (Chronos + bearssl), which bounds the whole
## request by the adapter timeout: connecting, headers and every body read.
## std/httpclient bounded each read only, so a server that dripped bytes held
## the caller forever.

import std/[httpcore, strutils, os, json]
import ../../ports/http
import ../../core/pipeops
import ./circuit_breakers
import ../../core/security/net_boundary
import ../network/dns_resolver
import ./deadline_transport

type StdHttpAdapter* = object
  timeout*: int ## Timeout in seconds.
  maxRetries*: int ## Maximum number of retries.
  allowlist*: seq[string] ## Allowed hosts.
  circuitBreaker*: bool ## Record failures/check the global per-host breaker.
  proxy*: string ## Optional filtering egress proxy URL.
  retryNonIdempotent*: bool ## false → POST/PATCH make a single attempt.
  retryConflict*: bool ## true → a 409 on an idempotent call is retried.
  returnServerError*: bool ## true → once attempts run out, a 5xx response is
                           ## returned as `ok` so the caller can read its body.

proc newStdHttpAdapter*(timeout = 60, maxRetries = 3, allowlist: seq[string] = @[],
                        circuitBreaker = true, proxy = "",
                        retryNonIdempotent = true,
                        retryConflict = false,
                        returnServerError = false): StdHttpAdapter =
  StdHttpAdapter(timeout: timeout, maxRetries: maxRetries, allowlist: allowlist,
                 circuitBreaker: circuitBreaker, proxy: proxy,
                 retryNonIdempotent: retryNonIdempotent,
                 retryConflict: retryConflict,
                 returnServerError: returnServerError)

type RetryKind* = enum
  rkIdempotent
  rkNonIdempotent

func retryKind*(meth: HttpMethod): RetryKind =
  if meth in {HttpPost, HttpPatch}: rkNonIdempotent else: rkIdempotent

func shouldRetryStatus*(status: int; kind: RetryKind;
                        retryConflict: bool): bool =
  ## Behavior derived from hermes-agent (MIT) fix 488a30e879; see
  ## docs/hermes-mining/telegram/CASES.md#tg-020
  ##
  ## A second getUpdates while another poller is active answers 409 Conflict.
  ## The call is idempotent, so it is safe to retry with backoff; a send is
  ## not, and a conflict there means something else is wrong.
  if status >= 500:
    return true
  status == 409 and retryConflict and kind == rkIdempotent

func maxAttempts*(a: StdHttpAdapter; kind: RetryKind): int =
  ## Behavior derived from hermes-agent (MIT) fix 85cefc7a5a; see
  ## docs/hermes-mining/telegram/CASES.md#tg-021
  ##
  ## A POST that timed out may already have been accepted by the server.
  ## Retrying it duplicates the side effect, so channels that send messages
  ## disable retries for non-idempotent methods.
  if not a.retryNonIdempotent and kind == rkNonIdempotent:
    1
  else:
    a.maxRetries

proc requestWithRetry(a: StdHttpAdapter; meth: HttpMethod; url, body: string;
                      headers: seq[HttpHeader];
                      redirectLimit = 5;
                      timeoutSec = 0): Result[HttpResponse, string] {.gcsafe.} =
  # Extract host for circuit breaker and allowlist
  let host = if url.contains("//"): url.split("//")[1].split("/")[0] else: url

  if a.allowlist.len > 0 and not isHostAllowed(host, a.allowlist):
    return err("Network egress BLOCKED: host '" & host & "' not in allowlist")

  if a.circuitBreaker and not checkCircuit(host):
    return err("Circuit breaker OPEN for host: " & host)

  var lastError = ""
  ## One decision for the whole call: the loop, the waits and the messages all
  ## use the same budget.
  let attemptLimit = a.maxAttempts(retryKind(meth))
  for attempt in 1 .. attemptLimit:
    let effectiveTimeout = if timeoutSec > 0: timeoutSec else: a.timeout
    let res = transportRequest(TransportRequest(
      meth: $meth, url: url, body: body, headers: headers,
      redirectLimit: redirectLimit, proxy: a.proxy, allowlist: a.allowlist,
      deadlineMs: effectiveTimeout * 1000,
    )).map(proc(r: TransportResponse): HttpResponse =
      HttpResponse(status: r.status, body: r.body, headers: r.headers))

    if res.isOk:
      let val = res.get()
      # HTTP 429 Too Many Requests: respeita retry-after se presente
      if val.status == 429:
        if attemptLimit <= 1:
          ## The caller handles the penalty itself (per-chat window); hand the
          ## original response over so it can read `parameters.retry_after`.
          ## Flood control is not a transport failure, so it must not open the
          ## circuit breaker for the host.
          return ok(val)
        var retryAfterMs = 5000 # default 5s
        try:
          let j = parseJson(val.body)
          if j.hasKey("parameters") and j["parameters"].hasKey("retry_after"):
            retryAfterMs = j["parameters"]["retry_after"].getInt(5) * 1000
        except JsonParsingError:
          discard # usa default
        lastError = "HTTP 429 (rate limited)"
        if attempt < attemptLimit:
          sleep(retryAfterMs)
          continue
        ## Rate limiting is not a host failure: keep the breaker closed.
        return err("HTTP 429 rate limited after " & $attemptLimit & " attempts. Last error: " & lastError)
      if not shouldRetryStatus(val.status, retryKind(meth), a.retryConflict):
        if a.circuitBreaker:
          recordSuccess(host)
        return ok(val)
      if val.status == 409:
        ## A polling conflict is not a host failure: retry with backoff
        ## without counting it against the circuit breaker.
        lastError = "HTTP 409 (conflict)"
        if attempt < attemptLimit:
          sleep(getBackoffMs(attempt))
          continue
        return err("HTTP 409 conflict after " & $attemptLimit & " attempts")
      lastError = "HTTP " & $val.status
      if a.returnServerError and attempt == attemptLimit:
        ## Still a host failure for the breaker, but the caller gets the
        ## status and body to build its own error.
        if a.circuitBreaker:
          recordFailure(host)
        return ok(val)
    else:
      lastError = res.error

    if a.circuitBreaker:
      recordFailure(host)
    if attempt < attemptLimit:
      sleep(getBackoffMs(attempt))

  err("HTTP " & $meth & " failed after " & $attemptLimit & " attempts. Last error: " & lastError)

proc get*(a: StdHttpAdapter; url: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  a.requestWithRetry(HttpGet, url, "", headers)

proc post*(a: StdHttpAdapter; url, body: string;
           headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  a.requestWithRetry(HttpPost, url, body, headers)

proc postWithTimeout*(a: StdHttpAdapter; url, body: string;
                      headers: seq[HttpHeader] = @[];
                      timeoutSec: int): Result[HttpResponse, string] {.gcsafe.} =
  ## Behavior derived from hermes-agent (MIT) fix 85e673b4a5; see
  ## docs/hermes-mining/telegram/CASES.md#tg-030
  ##
  ## A media upload moves more bytes than a text call; it gets its own
  ## wall-clock deadline instead of the shared text timeout.
  a.requestWithRetry(HttpPost, url, body, headers, timeoutSec = timeoutSec)

proc put*(a: StdHttpAdapter; url, body: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  a.requestWithRetry(HttpPut, url, body, headers)

proc patch*(a: StdHttpAdapter; url, body: string;
            headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  a.requestWithRetry(HttpPatch, url, body, headers)

proc delete*(a: StdHttpAdapter; url: string;
             headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  a.requestWithRetry(HttpDelete, url, "", headers)

proc getNoRedirect*(a: StdHttpAdapter; url: string;
                    headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  a.requestWithRetry(HttpGet, url, "", headers, redirectLimit = 0)

proc postNoRedirect*(a: StdHttpAdapter; url, body: string;
                     headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  ## POST without following redirects, so auth headers cannot be forwarded to
  ## a different origin.
  a.requestWithRetry(HttpPost, url, body, headers, redirectLimit = 0)

proc toRuntimePort*(a: StdHttpAdapter): HttpRuntimePort =
  HttpRuntimePort(
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      result = a.get(url, headers)
    ,
    post: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      result = a.post(url, body, headers)
    ,
    put: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      result = a.put(url, body, headers)
    ,
    patch: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      result = a.patch(url, body, headers)
    ,
    delete: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      result = a.delete(url, headers)
    ,
    getNoRedirect: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      result = a.getNoRedirect(url, headers)
    ,
    postNoRedirect: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      result = a.postNoRedirect(url, body, headers)
    ,
    resolveHost: proc(host: string): Result[string, string] {.gcsafe.} =
      safeResolve(host)
    ,
  )
