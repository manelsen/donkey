## persistent_socket.nim — one way to keep a permanent WebSocket connection.
##
## The channel gateways (Slack Socket Mode, Discord, QQ official) each hold
## one connection for the daemon's whole life. That needs a thread per
## connection, but not a lifecycle per channel: this module owns the thread,
## reconnection with exponential backoff and jitter (reset once a session
## opens), the idle timeout, ping/pong and close frames, a stop that
## interrupts a blocked read, and logging.
##
## A channel plugs in its protocol (`SocketProtocol[C, S]`): plain `nimcall`
## functions that find the URL, speak on open, read a frame and act on each
## tick, each answering what the connection should do next (`SessionStep`).
## `C` is the channel's configuration, plain data copied to the thread
## (`sharesNothing`, checked at compile time). `S` is the protocol's state:
## it is created on the thread and lives there across reconnections, so it
## may hold what the thread builds itself (an HTTP port, a logger).

import std/[atomics, locks, monotimes, net, os, random, times]
when defined(posix):
  import std/posix
import ../../core/log
import ../../core/pipeops
import ../channel/ws_client
import ../../infra/thread_handle

export ws_client.WsClient, ws_client.WsFrame, ws_client.sendFrame
export ws_client.WsOpcodeText, ws_client.WsOpcodeBin

type
  SocketTarget* = object
    host*:   string
    port*:   Port
    path*:   string
    useTls*: bool

  SessionStep* = enum
    ssKeep        ## carry on
    ssReconnect   ## close and connect again (after the backoff)
    ssStop        ## a failure reconnecting cannot fix: the thread ends

  SocketProtocol*[C, S] = object
    locate*: proc(cfg: C; state: var S; log: Logger): Result[SocketTarget, string]
             {.nimcall, gcsafe, raises: [CatchableError].}
      ## Where to connect now (a lookup may call an API first).
    opened*: proc(cfg: C; state: var S; ws: WsClient; log: Logger): SessionStep
             {.nimcall, gcsafe, raises: [CatchableError].}
      ## Right after the upgrade: hello, identify, resume…
    frame*:  proc(cfg: C; state: var S; ws: WsClient; frame: WsFrame;
                  log: Logger): SessionStep
             {.nimcall, gcsafe, raises: [CatchableError].}
      ## A text, binary or close frame (the close payload starts with its
      ## code); ping and pong are handled here. After a close the socket is
      ## reopened unless this answers `ssStop`.
    tick*:   proc(cfg: C; state: var S; ws: WsClient; nowMs: int64;
                  log: Logger): SessionStep
             {.nimcall, gcsafe, raises: [CatchableError].}
      ## Before every read (at least every `recvTimeoutMs`): heartbeats.

  SocketPolicy* = object
    reconnectMinMs*: int   ## first pause, and the pause after a session ends
    reconnectMaxMs*: int   ## the backoff doubles up to this
    idleTimeoutMs*:  int   ## no frame for this long: reconnect
    recvTimeoutMs*:  int   ## how long one read waits before a tick

  SocketControl = object
    ## Shared by the daemon and the connection thread, in shared memory.
    stop:     Atomic[bool]
    exited:   Atomic[bool]
    fdLock:   Lock
    activeFd: SocketHandle

  SocketArgs[C, S] = object
    name:     string
    protocol: SocketProtocol[C, S]
    cfg:      C
    policy:   SocketPolicy
    logger:   LogSpec
    control:  ptr SocketControl

  PersistentSocket*[C, S] = object
    ## The daemon's handle: two pointers and no GC memory, so a channel can
    ## keep it in a module global and touch it from gcsafe code.
    control: ptr SocketControl
    thread:  ThreadHandle[SocketArgs[C, S]]

func defaultSocketPolicy*(): SocketPolicy =
  SocketPolicy(reconnectMinMs: 1_000, reconnectMaxMs: 60_000,
               idleTimeoutMs: 120_000, recvTimeoutMs: 1_000)

proc setActiveFd(control: ptr SocketControl; fd: SocketHandle) {.gcsafe.} =
  withLock control.fdLock:
    control.activeFd = fd

proc sleepOrStop(control: ptr SocketControl; ms: int): bool =
  ## Sleeps in short slices; false when a stop arrived meanwhile.
  var waited = 0
  while waited < ms and not control.stop.load():
    let slice = min(50, ms - waited)
    sleep(slice)
    waited += slice
  not control.stop.load()

proc runSession[C, S](args: SocketArgs[C, S]; state: var S; log: Logger;
                      opened: var bool): SessionStep =
  ## One connection, from lookup to close. Raises on transport failures; the
  ## caller logs them and reconnects.
  let control = args.control
  let target = args.protocol.locate(args.cfg, state, log).valueOr:
    log.warn(args.name & ": " & error)
    return ssReconnect
  let onSocket = proc(sock: Socket) {.gcsafe.} =
    setActiveFd(control, sock.getFd)
  var ws = wsConnect(target.host, target.port, target.path,
                     useTls = target.useTls, timeoutMs = 10_000,
                     onSocket = onSocket)
  defer:
    setActiveFd(control, SocketHandle(-1))
    wsClose(ws)
  result = args.protocol.opened(args.cfg, state, ws, log)
  if result != ssKeep:
    return
  opened = true
  log.info(args.name & ": connected")
  var lastActivity = getMonoTime()
  while not control.stop.load():
    result = args.protocol.tick(args.cfg, state, ws, epochMs(), log)
    if result != ssKeep:
      return
    let received = ws.recvFrame(args.policy.recvTimeoutMs)
    if received.isErr:
      if received.error != "timeout":
        if not control.stop.load():
          log.warn(args.name & ": " & received.error)
        return ssReconnect
      if inMilliseconds(getMonoTime() - lastActivity) >= args.policy.idleTimeoutMs:
        log.warn(args.name & ": idle for " & $args.policy.idleTimeoutMs &
                 " ms; reconnecting")
        return ssReconnect
      continue
    lastActivity = getMonoTime()
    let frame = received.get
    case frame.opcode
    of WsOpcodePing:
      ws.sendFrame(frame.data, WsOpcodePong)
    of WsOpcodePong:
      discard
    of WsOpcodeClose:
      ## The close code is the protocol's to read (a rejected token is
      ## fatal); a closed socket cannot be kept, whatever it answers.
      result = args.protocol.frame(args.cfg, state, ws, frame, log)
      return if result == ssStop: ssStop else: ssReconnect
    else:
      result = args.protocol.frame(args.cfg, state, ws, frame, log)
      if result != ssKeep:
        return
  result = ssKeep

proc runSocket[C, S](args: SocketArgs[C, S]) {.thread, nimcall.} =
  let log = args.logger.toLogger
  let control = args.control
  defer: control.exited.store(true)
  randomize()
  var state: S
  var backoff = args.policy.reconnectMinMs
  while not control.stop.load():
    var opened = false
    var step = ssReconnect
    try:
      step = runSession(args, state, log, opened)
    except CatchableError as e:
      if not control.stop.load():
        log.warn(args.name & ": " & e.msg)
    if step == ssStop:
      log.error(args.name & ": stopped; reconnecting cannot fix this")
      return
    if control.stop.load():
      return
    if opened:
      backoff = args.policy.reconnectMinMs   ## a session worked: start over
    let pause = backoff + rand(max(0, backoff div 4))
    if not sleepOrStop(control, pause):
      return
    if not opened:
      backoff = min(backoff * 2, args.policy.reconnectMaxMs)

proc startPersistentSocket*[C, S](name: string; protocol: SocketProtocol[C, S];
                                  cfg: C; policy: SocketPolicy;
                                  logger: Logger): Result[PersistentSocket[C, S], string] =
  ## Starts the connection's thread. `cfg` must be plain data: it is copied
  ## to the thread (a `ref` or a closure is refused at compile time).
  when not sharesNothing(C):
    {.error: "startPersistentSocket: the config holds a ref or a closure".}
  if protocol.locate == nil or protocol.opened == nil or
     protocol.frame == nil or protocol.tick == nil:
    return err(name & ": incomplete protocol")
  let control = cast[ptr SocketControl](allocShared0(sizeof(SocketControl)))
  if control == nil:
    return err(name & ": out of memory")
  initLock(control.fdLock)
  control.activeFd = SocketHandle(-1)
  var handle = PersistentSocket[C, S](control: control)
  try:
    handle.thread = spawnThread(runSocket[C, S], SocketArgs[C, S](
      name: name, protocol: protocol, cfg: cfg, policy: policy,
      logger: logger.spec, control: control))
  except CatchableError as e:
    deinitLock(control.fdLock)
    deallocShared(control)
    return err(name & ": cannot start its thread: " & e.msg)
  ok(handle)

proc running*[C, S](ps: PersistentSocket[C, S]): bool =
  ## False once the thread ended (a stop, or a fatal step).
  ps.control != nil and not ps.control.exited.load()

proc stop*[C, S](ps: var PersistentSocket[C, S]) =
  ## Stops the connection and joins its thread. A blocked read is woken by
  ## shutting the socket down, so this does not wait for frame timing. Safe
  ## to call twice. One owner: the handle is started and stopped by the same
  ## thread (the daemon loop); the connection thread is joined before the
  ## shared block is freed.
  if ps.control == nil:
    return
  let control = ps.control
  control.stop.store(true)
  when defined(posix):
    withLock control.fdLock:
      if control.activeFd != SocketHandle(-1):
        discard posix.shutdown(posix.SocketHandle(control.activeFd), posix.SHUT_RDWR)
  joinAndFree(ps.thread)
  deinitLock(control.fdLock)
  deallocShared(control)
  ps.control = nil
