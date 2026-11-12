## HttpPort — concept for HTTP client transport.
## Swap StdHttpAdapter (std/httpclient + OpenSSL) for ChronosHttpAdapter (bearssl) on IoT.

import ../core/pipeops

type
  HttpHeader* = tuple[name: string, value: string]

  HttpResponse* = object
    status*:  int
    body*:    string
    headers*: seq[HttpHeader]

  HttpPort* = concept h
    h.get(string, seq[HttpHeader]) is Result[HttpResponse, string]
    h.post(string, string, seq[HttpHeader]) is Result[HttpResponse, string]
    h.put(string, string, seq[HttpHeader]) is Result[HttpResponse, string]
    h.patch(string, string, seq[HttpHeader]) is Result[HttpResponse, string]
    h.delete(string, seq[HttpHeader]) is Result[HttpResponse, string]

  HttpRuntimePort* = object
    get*:   proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
    post*:  proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
    put*:   proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
    patch*: proc(url, body: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
    delete*: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
    getNoRedirect*: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.}
    resolveHost*: proc(host: string): Result[string, string] {.gcsafe.}
