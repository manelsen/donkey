## StdHttpAdapter — HttpPort backed by std/httpclient + system OpenSSL.
## For IoT targets swap for ChronosHttpAdapter (chronos + bearssl, no system deps).

import std/[httpclient, strutils, os, json]
import ../../ports/http
import ../../core/pipeops
import ../../core/reliability
import ../../core/security/net_boundary
import ../network/dns_resolver
import ./helpers

type StdHttpAdapter* = object
  timeout*: int ## Timeout in seconds.
  maxRetries*: int ## Maximum number of retries.
  allowlist*: seq[string] ## Allowed hosts.
  circuitBreaker*: bool ## Record failures/check the global per-host breaker.
  proxy*: string ## Optional filtering egress proxy URL.

proc newStdHttpAdapter*(timeout = 60, maxRetries = 3, allowlist: seq[string] = @[],
                        circuitBreaker = true, proxy = ""): StdHttpAdapter =
  StdHttpAdapter(timeout: timeout, maxRetries: maxRetries, allowlist: allowlist,
                 circuitBreaker: circuitBreaker, proxy: proxy)

proc requestWithRetry(a: StdHttpAdapter; meth: HttpMethod; url, body: string;
                      headers: seq[HttpHeader];
                      redirectLimit = 5): Result[HttpResponse, string] {.gcsafe.} =
  # Extract host for circuit breaker and allowlist
  let host = if url.contains("//"): url.split("//")[1].split("/")[0] else: url

  if a.allowlist.len > 0 and not isHostAllowed(host, a.allowlist):
    return err("Network egress BLOCKED: host '" & host & "' not in allowlist")

  if a.circuitBreaker and not checkCircuit(host):
    return err("Circuit breaker OPEN for host: " & host)

  var lastError = ""
  for attempt in 1 .. a.maxRetries:
    let res = block:
      withHttpClientTimeout(a.timeout, redirectLimit, a.proxy):
        if headers.len > 0:
          var h = newHttpHeaders()
          for (k, v) in headers: h[k] = v
          client.headers = h
        let resp = client.request(url, httpMethod = meth, body = body)
        var responseHeaders: seq[HttpHeader]
        for key, value in resp.headers:
          responseHeaders.add((key, value))
        ok(HttpResponse(status: resp.code.int, body: resp.body,
                        headers: responseHeaders))

    if res.isOk:
      let val = res.get()
      # HTTP 429 Too Many Requests: respeita retry-after se presente
      if val.status == 429:
        var retryAfterMs = 5000 # default 5s
        try:
          let j = parseJson(val.body)
          if j.hasKey("parameters") and j["parameters"].hasKey("retry_after"):
            retryAfterMs = j["parameters"]["retry_after"].getInt(5) * 1000
        except JsonParsingError:
          discard # usa default
        lastError = "HTTP 429 (rate limited)"
        if attempt < a.maxRetries:
          sleep(retryAfterMs)
          continue
        if a.circuitBreaker:
          recordFailure(host)
        return err("HTTP 429 rate limited after " & $a.maxRetries & " attempts. Last error: " & lastError)
      if val.status < 500: # Success or client error, don't retry
        if a.circuitBreaker:
          recordSuccess(host)
        return ok(val)
      else:
        lastError = "HTTP " & $val.status
    else:
      lastError = res.error

    if a.circuitBreaker:
      recordFailure(host)
    if attempt < a.maxRetries:
      sleep(getBackoffMs(attempt))

  err("HTTP " & $meth & " failed after " & $a.maxRetries & " attempts. Last error: " & lastError)

proc get*(a: StdHttpAdapter; url: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  a.requestWithRetry(HttpGet, url, "", headers)

proc post*(a: StdHttpAdapter; url, body: string;
           headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  a.requestWithRetry(HttpPost, url, body, headers)

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
    resolveHost: proc(host: string): Result[string, string] {.gcsafe.} =
      safeResolve(host)
    ,
  )
