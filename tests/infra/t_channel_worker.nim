## E12.3: the child's side, the channel run as its own process.

import std/[posix, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/channels/channel_wire
import donkey/infra/connection_state
import donkey/infra/event_queue
import donkey/infra/channel_worker

var gEvents = initEventQueue[string]("test.ev", capacity = 64)
var gSent = initEventQueue[string]("test.sent", capacity = 64)

proc takeEvent(): (bool, string) {.nimcall, gcsafe, raises: [].} = gEvents.tryTake()
proc pushOut(line: string) {.nimcall, gcsafe, raises: [].} = gSent.push(line)

proc readAllFrom(fd: cint): string =
  var chunk: array[4096, char]
  discard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) or O_NONBLOCK)
  while true:
    let n = posix.read(fd, addr chunk[0], chunk.len)
    if n <= 0: break
    for i in 0 ..< n: result.add chunk[i]

proc runTests*() =
  suite "channel worker (E12.3)":
    test "events and the connection go out as frames; outbound frames come in; EOF ends it":
      resetConnections()
      var inPipe, outPipe: array[2, cint]
      check pipe(inPipe) == 0 and pipe(outPipe) == 0
      let toChild = encodeFrame(WireFrame(kind: wfOut, payload: "PRIVMSG #a :oi")) & "\n"
      check posix.write(inPipe[1], unsafeAddr toChild[0], toChild.len) == toChild.len
      discard posix.close(inPipe[1])   ## the daemon went away
      gEvents.push("""{"text":"olá"}""")
      socketStarted(ckIrc); socketConnected(ckIrc)
      check runChannelWorker(ckIrc, takeEvent, pushOut, inPipe[0], outPipe[1]) == 0
      let (got, line) = gSent.tryTake()
      check got and line == "PRIVMSG #a :oi"
      var frames: seq[WireFrame]
      for l in readAllFrom(outPipe[0]).splitLines:
        if l.len > 0: frames.add decodeFrame(l).get
      check WireFrame(kind: wfUp) in frames
      check WireFrame(kind: wfEvent, payload: """{"text":"olá"}""") in frames

when isMainModule:
  runTests()
