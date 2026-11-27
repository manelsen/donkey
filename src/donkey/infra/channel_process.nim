## channel_process — a channel run as its own process, under the supervisor
## (E12.3).
##
## A Defect cannot be caught in the process that raises it (`--panics:on`),
## so a channel that should not take the daemon down with it runs as a child
## (`donkey channel-worker <name>`): one thread here starts it, writes the
## channel's outbound lines to its stdin and reads its stdout, where
## channel_wire frames carry inbound events and the connection's state, and
## anything else is the child's log. When the child ends, for any reason,
## the supervisor decides the wait before the next, as for a thread.

import std/[atomics, os, osproc, posix, strutils]
import ../core/log
import ../core/pipeops
import ../core/types
import ../domain/supervision_pure
import ../domain/channels/channel_wire
import ./connection_state
import ./supervisor
import ./thread_handle

type
  ChannelProcessSpec* = object
    ## Plain data, copied to the thread.
    name*:    string
    channel*: ChannelKind
    command*: string
    args*:    seq[string]

  EventSink* = proc(payload: string) {.nimcall, gcsafe, raises: [].}
  OutSource* = proc(): (bool, string) {.nimcall, gcsafe, raises: [].}

  ProcessControl = object
    stop: Atomic[bool]

  ProcessArgs = object
    spec:    ChannelProcessSpec
    sink:    EventSink
    source:  OutSource
    policy:  RestartPolicy
    logger:  LogSpec
    control: ptr ProcessControl

  ChannelProcess* = object
    control: ptr ProcessControl
    thread:  ThreadHandle[ProcessArgs]

const
  PollSliceMs = 100
  StopGraceMs = 2_000

proc sleepOrStop(control: ptr ProcessControl; ms: int): bool =
  var waited = 0
  while waited < ms and not control.stop.load():
    let slice = min(PollSliceMs, ms - waited)
    sleep(slice)
    waited += slice
  not control.stop.load()

proc writeSome(fd: cint; pending: var seq[string]; offset: var int) =
  ## Writes what the child's stdin takes now, without blocking: a child that
  ## stops reading must not hold this thread (and the daemon's stop). The
  ## line being written stays first in `pending`, `offset` bytes into its
  ## frame; a new child gets a new pipe, so it starts the frame again.
  while pending.len > 0:
    let frame = encodeFrame(WireFrame(kind: wfOut, payload: pending[0])) & "\n"
    let n = posix.write(fd, unsafeAddr frame[offset], frame.len - offset)
    if n <= 0: return   ## full (EAGAIN) or closed: the next slice, or the next child
    offset += n
    if offset < frame.len: return
    pending = pending[1 .. ^1]
    offset = 0

proc endChild(p: Process; stopping: bool): string =
  ## Ends the child (asked to stop: terminate, then kill) and says why it ended.
  try:
    if stopping and p.running:
      p.terminate()
      if p.waitForExit(StopGraceMs) == -1 or p.running:
        p.kill()
    let code = p.waitForExit(StopGraceMs)
    p.close()
    "the process exited with code " & $code
  except CatchableError as e:
    "the process: " & e.msg

proc runChild(args: ProcessArgs; log: Logger; pending: var seq[string];
              up: var bool; sup: var Supervised): string =
  ## One child, from start to end: why it ended.
  let control = args.control
  let spec = args.spec
  let p =
    try: startProcess(spec.command, args = spec.args, options = {poStdErrToStdOut})
    except CatchableError as e: return "cannot start " & spec.command & ": " & e.msg
  let outFd = p.outputHandle.cint
  let inFd = p.inputHandle.cint
  discard fcntl(inFd, F_SETFL, fcntl(inFd, F_GETFL) or O_NONBLOCK)
  var offset = 0
  var buf = ""
  var chunk: array[4096, char]
  while not control.stop.load():
    ## Outbound first: what the daemon queued, kept across a restart when
    ## the child could not take it.
    while true:
      let (got, line) = args.source()
      if not got: break
      pending.add line
    writeSome(inFd, pending, offset)
    var pfd = TPollfd(fd: outFd, events: POLLIN)
    let ready = poll(addr pfd, 1, PollSliceMs)
    if ready < 0: continue
    if ready == 0: continue
    let n = posix.read(outFd, addr chunk[0], chunk.len)
    if n <= 0: break   ## end of the stream: the child is ending
    for i in 0 ..< n: buf.add chunk[i]
    while true:
      let nl = buf.find('\n')
      if nl < 0: break
      let line = buf[0 ..< nl]
      buf = buf[nl + 1 .. ^1]
      let frame = decodeFrame(line).valueOr:
        log.warn(spec.name & ": " & error)
        continue
      case frame.kind
      of wfEvent: args.sink(frame.payload)
      of wfUp:
        if not up:
          up = true
          socketConnected(spec.channel)
          sup.started()
      of wfDown:
        if up:
          up = false
          socketDisconnected(spec.channel)
      of wfLog:
        if line.len > 0: log.info(spec.name & " (process): " & line)
      of wfOut: discard   ## only the daemon sends these
  endChild(p, control.stop.load())

proc runProcess(args: ProcessArgs) {.thread, nimcall.} =
  let log = args.logger.toLogger
  let control = args.control
  let spec = args.spec
  socketStarted(spec.channel)
  defer: socketEnded(spec.channel)
  var sup = newSupervised(spec.channel, spec.name, args.policy)
  var pending: seq[string]
  while not control.stop.load():
    var up = false
    let began = monoMs()
    let why = runChild(args, log, pending, up, sup)
    if up: socketDisconnected(spec.channel)
    if control.stop.load(): return
    log.warn(spec.name & ": " & why)
    let wait = sup.ended(why, ranMs = monoMs() - began, log)
    if not sleepOrStop(control, wait):
      return

proc startChannelProcess*(spec: ChannelProcessSpec; sink: EventSink; source: OutSource;
                          logger: Logger;
                          policy = DefaultPolicy): Result[ChannelProcess, string] =
  if spec.command.len == 0:
    return err(spec.name & ": no command to run")
  ## A child that dies mid-write must not kill the daemon: a write to its
  ## closed pipe returns EPIPE instead of raising SIGPIPE.
  discard posix.signal(SIGPIPE, SIG_IGN)
  let control = cast[ptr ProcessControl](allocShared0(sizeof(ProcessControl)))
  if control == nil:
    return err(spec.name & ": out of memory")
  try:
    ok(ChannelProcess(control: control,
      thread: spawnThread(runProcess, ProcessArgs(spec: spec, sink: sink, source: source,
                                                  policy: policy, logger: logger.spec,
                                                  control: control))))
  except CatchableError as e:
    deallocShared(control)
    err(spec.name & ": cannot start its thread: " & e.msg)

proc stop*(p: var ChannelProcess) =
  ## Ends the child and joins the thread. Safe twice, and when never started.
  if p.control == nil: return
  p.control.stop.store(true)
  joinAndFree(p.thread)
  deallocShared(p.control)
  p.control = nil
