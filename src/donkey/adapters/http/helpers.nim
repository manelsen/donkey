## HTTP adapter helpers — templates for common boilerplate in adapters using std/httpclient.

import std/httpclient
import ../../core/pipeops

template withHttpClientTimeout*(timeoutSeconds: int; redirectLimit = 5;
                                proxyUrl = ""; body: untyped): untyped =
  ## Wraps body in try/except with a scoped HttpClient named `client`, built
  ## with a timeout, a redirect policy and an optional proxy URL (e.g. a
  ## filtering egress proxy). On CatchableError returns err(e.msg).
  try:
    let client {.inject.} = newHttpClient(
      timeout = timeoutSeconds * 1000,
      maxRedirects = redirectLimit,
      proxy = (if proxyUrl.len > 0: newProxy(proxyUrl) else: nil))
    defer: client.close()
    body
  except CatchableError as e:
    err(e.msg)
