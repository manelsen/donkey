## StdHttpAdapter — HttpPort backed by std/httpclient + system OpenSSL.
## For IoT targets swap for ChronosHttpAdapter (chronos + bearssl, no system deps).

import std/httpclient
import ../../ports/http
import ../../core/pipeops

type StdHttpAdapter* = object  ## Stateless — safe to copy into adapter structs.

proc newStdHttpAdapter*(): StdHttpAdapter = StdHttpAdapter()

proc get*(a: StdHttpAdapter; url: string;
          headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    if headers.len > 0:
      var h = newHttpHeaders()
      for (k, v) in headers: h[k] = v
      client.headers = h
    let resp = client.get(url)
    ok(HttpResponse(status: resp.code.int, body: resp.body))
  except CatchableError as e:
    err(e.msg)

proc post*(a: StdHttpAdapter; url, body: string;
           headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    if headers.len > 0:
      var h = newHttpHeaders()
      for (k, v) in headers: h[k] = v
      client.headers = h
    let resp = client.post(url, body = body)
    ok(HttpResponse(status: resp.code.int, body: resp.body))
  except CatchableError as e:
    err(e.msg)

proc patch*(a: StdHttpAdapter; url, body: string;
            headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    if headers.len > 0:
      var h = newHttpHeaders()
      for (k, v) in headers: h[k] = v
      client.headers = h
    let resp = client.request(url, httpMethod = HttpPatch, body = body)
    ok(HttpResponse(status: resp.code.int, body: resp.body))
  except CatchableError as e:
    err(e.msg)
