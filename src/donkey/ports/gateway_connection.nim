## One client connection of the HTTP gateway, as the gateway's request
## handler (`app/http_gateway`) sees it: read a line, read some bytes, write.
## `adapters/http/gateway_server` implements it on a Chronos stream; a test
## can implement it on strings. None of the operations raises.
##
## The reads take the request deadline and never outlive it. `write` takes
## none: a response or an SSE stream keeps writing after the request was read,
## so a write can still be pending after that deadline.

import chronos
import ../core/pipeops

type
  GatewayConnection* = object
    readLine*: proc(limit: int; deadline: Moment):
                    Future[Result[string, string]].Raising([]) {.gcsafe, raises: [].}
      ## The next line, reading at most `limit` bytes: the LF is dropped and a
      ## CR before it kept. Without an LF it returns what it read: `limit`
      ## bytes when the line is longer (the handler asks for one byte over
      ## its maximum to tell a long line apart), or a shorter prefix, possibly
      ## empty, at end of stream (`atEof` then says so). An error when the
      ## deadline passes or the read fails.
    readSome*: proc(maxBytes: int; deadline: Moment):
                    Future[Result[string, string]].Raising([]) {.gcsafe, raises: [].}
      ## Some bytes, at most `maxBytes` (possibly fewer: a bounded read).
      ## `ok("")` at end of stream; an error when the deadline passes or the
      ## read fails.
    write*: proc(data: string): Future[Result[void, string]].Raising([])
                {.gcsafe, raises: [].}
      ## An error when the client is gone or the write fails.
    atEof*: proc(): bool {.gcsafe, raises: [].}
      ## The client closed its side.
