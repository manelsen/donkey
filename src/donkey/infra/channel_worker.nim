## channel_worker — the child's side of a channel run as its own process
## (E12.3).
##
## The child runs the channel as the daemon would (its own connection
## thread), and this loop carries the queues across the pipes: inbound
## events and the connection's state out on stdout as channel_wire frames,
## outbound lines in from stdin. The end of stdin means the daemon is gone:
## the loop returns and the child exits.

import std/[posix, strutils]
import ../core/pipeops
import ../core/types
import ../domain/channels/channel_wire
import ./connection_state

type
  EventSource* = proc(): (bool, string) {.nimcall, gcsafe, raises: [].}
  OutSink* = proc(line: string) {.nimcall, gcsafe, raises: [].}

const SliceMs = 100

proc writeAll(fd: cint; data: string): bool =
  var sent = 0
  while sent < data.len:
    let n = posix.write(fd, unsafeAddr data[sent], data.len - sent)
    if n <= 0: return false
    sent += n
  true

proc flushOut(channel: ChannelKind; takeEvent: EventSource; outFd: cint;
              up: var bool): bool =
  ## The connection's state and the queued events, out. False when the
  ## daemon's end is closed.
  let now = connectionCounts(channel).connected > 0
  if now != up:
    up = now
    if not writeAll(outFd, encodeFrame(WireFrame(kind: if up: wfUp else: wfDown)) & "\n"):
      return false
  while true:
    let (got, payload) = takeEvent()
    if not got: break
    if not writeAll(outFd, encodeFrame(WireFrame(kind: wfEvent, payload: payload)) & "\n"):
      return false
  true

proc runChannelWorker*(channel: ChannelKind; takeEvent: EventSource; pushOut: OutSink;
                       inFd: cint = 0; outFd: cint = 1): int =
  ## Runs until stdin ends (0) or stdout is closed (1).
  var up = false
  var buf = ""
  var chunk: array[4096, char]
  while true:
    if not flushOut(channel, takeEvent, outFd, up): return 1
    var pfd = TPollfd(fd: inFd, events: POLLIN)
    let ready = poll(addr pfd, 1, SliceMs)
    if ready <= 0: continue
    let n = posix.read(inFd, addr chunk[0], chunk.len)
    if n <= 0:
      discard flushOut(channel, takeEvent, outFd, up)
      return 0
    for i in 0 ..< n: buf.add chunk[i]
    while true:
      let nl = buf.find('\n')
      if nl < 0: break
      let line = buf[0 ..< nl]
      buf = buf[nl + 1 .. ^1]
      let frame = decodeFrame(line)
      if frame.isOk and frame.get.kind == wfOut:
        pushOut(frame.get.payload)
