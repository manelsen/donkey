## StdHttpAdapter — HttpPort backed by std/httpclient + system OpenSSL.
## For IoT targets swap for ChronosHttpAdapter (chronos + bearssl, no system deps).

import std/httpclient
import ../../ports/http
import ../../core/pipeops
import ./helpers

type StdHttpAdapter* = object
  timeout*: int  ## Timeout in seconds.

proc newStdHttpAdapter*(timeout = 60): StdHttpAdapter =
  StdHttpAdapter(timeout: timeout)

proc get*(a: StdHttpAdapter; url: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
proc post*(a: StdHttpAdapter; url, body: string;
           headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
proc put*(a: StdHttpAdapter; url, body: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
proc patch*(a: StdHttpAdapter; url, body: string;
            headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}

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

proc get*(a: StdHttpAdapter; url: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  withHttpClientTimeout(a.timeout):
    if headers.len > 0:
      var h = newHttpHeaders()
      for (k, v) in headers: h[k] = v
      client.headers = h
    let resp = client.get(url)
    ok(HttpResponse(status: resp.code.int, body: resp.body))

proc post*(a: StdHttpAdapter; url, body: string;
           headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  withHttpClientTimeout(a.timeout):
    if headers.len > 0:
      var h = newHttpHeaders()
      for (k, v) in headers: h[k] = v
      client.headers = h
    let resp = client.post(url, body = body)
    ok(HttpResponse(status: resp.code.int, body: resp.body))

proc put*(a: StdHttpAdapter; url, body: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  withHttpClientTimeout(a.timeout):
    if headers.len > 0:
      var h = newHttpHeaders()
      for (k, v) in headers: h[k] = v
      client.headers = h
    let resp = client.request(url, httpMethod = HttpPut, body = body)
    ok(HttpResponse(status: resp.code.int, body: resp.body))

proc patch*(a: StdHttpAdapter; url, body: string;
            headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
  withHttpClientTimeout(a.timeout):
    if headers.len > 0:
      var h = newHttpHeaders()
      for (k, v) in headers: h[k] = v
      client.headers = h
    let resp = client.request(url, httpMethod = HttpPatch, body = body)
    ok(HttpResponse(status: resp.code.int, body: resp.body))
