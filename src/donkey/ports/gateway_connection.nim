## One client connection of the HTTP gateway, as the gateway's request
## handler (`app/http_gateway`) sees it: read a line, read some bytes, write.
## `adapters/http/gateway_server` implements it on a Chronos stream; a test
## can implement it on strings. Every operation is bounded by the request
## deadline the handler passes, and none raises.

import chronos
import ../core/pipeops

type
  GatewayConnection* = object
    readLine*: proc(limit: int; deadline: Moment):
                    Future[Result[string, string]].Raising([]) {.gcsafe, raises: [].}
      ## One LF-terminated line (the LF dropped, a CR kept), at most `limit`
      ## bytes read; an error when the deadline passes or the read fails.
    readSome*: proc(maxBytes: int; deadline: Moment):
                    Future[string].Raising([]) {.gcsafe, raises: [].}
      ## Up to `maxBytes` bytes; "" when nothing more will come before the
      ## deadline (end of stream, timeout or a failed read).
    write*: proc(data: string): Future[bool].Raising([]) {.gcsafe, raises: [].}
      ## False when the client is gone.
    atEof*: proc(): bool {.gcsafe, raises: [].}
      ## The client closed its side.
