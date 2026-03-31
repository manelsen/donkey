## StdHttpAdapter — HttpPort backed by std/httpclient + system OpenSSL.
## For IoT targets swap for ChronosHttpAdapter (chronos + bearssl, no system deps).

import std/[httpclient, strutils, os]
import ../../ports/http
import ../../core/pipeops
import ../../core/reliability
import ./helpers

type StdHttpAdapter* = object
  timeout*: int  ## Timeout in seconds.
  maxRetries*: int ## Maximum number of retries.

proc newStdHttpAdapter*(timeout = 60, maxRetries = 3): StdHttpAdapter =
  StdHttpAdapter(timeout: timeout, maxRetries: maxRetries)

proc requestWithRetry(a: StdHttpAdapter; meth: HttpMethod; url, body: string; 
                      headers: seq[HttpHeader]): Result[HttpResponse, string] {.gcsafe.} =
  # Extract host for circuit breaker
  let host = if url.contains("//"): url.split("//")[1].split("/")[0] else: url
  
  if not checkCircuit(host):
    return err("Circuit breaker OPEN for host: " & host)

  var lastError = ""
  for attempt in 1 .. a.maxRetries:
    let res = block:
      withHttpClientTimeout(a.timeout):
        if headers.len > 0:
          var h = newHttpHeaders()
          for (k, v) in headers: h[k] = v
          client.headers = h
        let resp = client.request(url, httpMethod = meth, body = body)
        ok(HttpResponse(status: resp.code.int, body: resp.body))
    
    if res.isOk:
      let val = res.get()
      if val.status < 500: # Success or client error, don't retry
        recordSuccess(host)
        return ok(val)
      else:
        lastError = "HTTP " & $val.status
    else:
      lastError = res.error
    
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
  )
