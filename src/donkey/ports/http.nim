## HttpPort — concept for HTTP client transport.
## Swap StdHttpAdapter (std/httpclient + OpenSSL) for ChronosHttpAdapter (bearssl) on IoT.

import ../core/pipeops

type
  HttpResponse* = object
    status*: int
    body*:   string

  HttpHeader* = tuple[name: string, value: string]

  HttpPort* = concept h
    h.get(string, seq[HttpHeader]) is Result[HttpResponse, string]
    h.post(string, string, seq[HttpHeader]) is Result[HttpResponse, string]
    h.patch(string, string, seq[HttpHeader]) is Result[HttpResponse, string]
