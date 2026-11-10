## Bounded socket I/O for polling channels.
##
## A blocking recv with no timeout can freeze the daemon event loop when an
## upstream server stops responding. This helper converts setsockopt failures
## into Result at the adapter boundary.

import std/[net, posix]
import ../../core/pipeops

proc applySocketTimeouts*(sock: Socket;
                          seconds: int;
                          label: string): Result[void, string] =
  var tv: Timeval
  tv.tv_sec = Time(seconds)
  tv.tv_usec = Suseconds(0)
  let recvResult = setsockopt(sock.getFd, SOL_SOCKET, SO_RCVTIMEO,
                              addr tv, SockLen(sizeof(tv)))
  let sendResult = setsockopt(sock.getFd, SOL_SOCKET, SO_SNDTIMEO,
                              addr tv, SockLen(sizeof(tv)))
  if recvResult != 0 or sendResult != 0:
    err(label & ": failed to configure socket timeout")
  else:
    ok()
