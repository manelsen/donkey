## HTTP adapter helpers — templates for common boilerplate in adapters using std/httpclient.

import std/httpclient
import ../../core/pipeops

template withHttpClient*(body: untyped): untyped =
  ## Wraps body in try/except, providing a scoped HttpClient named `client` via {.inject.}.
  ## On CatchableError returns err(e.msg) from the calling proc.
  try:
    let client {.inject.} = newHttpClient()
    defer: client.close()
    body
  except CatchableError as e:
    err(e.msg)

template checkApiStatus*(resp: untyped; apiName: string) =
  ## Returns err from the calling proc if HTTP status is not 2xx.
  if resp.status[0] != '2':
    return err(apiName & " API error " & resp.status & ": " & resp.body)
