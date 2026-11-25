## The permanent-connection facility: one lifecycle (thread, backoff, idle
## timeout, ping/pong, close, prompt stop) for every channel gateway, with
## the protocol plugged in as plain data and `nimcall` functions.
##
## A tiny WebSocket server runs on a thread over loopback; scenarios are
## chosen through a global, and what the protocol saw is counted in atomics.

import std/[atomics, monotimes, nativesockets, net, os, strutils, times, unittest]
import donkey/adapters/channel/ws_client
import donkey/adapters/network/persistent_socket
import donkey/core/log
import donkey/core/pipeops

type
  Scenario = enum
    scSendAndClose   ## two text frames, then the server closes the socket
    scHold           ## one text frame, then silence
    scFatal          ## a frame the protocol treats as fatal
    scPing           ## a ping; the server records the pong
    scCloseFatal     ## a close frame whose code the protocol treats as fatal
    scCloseOther     ## a close frame with any other code

  TestConfig = object
    port: int
    failLocate: bool

  TestState = object
    sessions: int

var
  gScenario: Atomic[int]
  gServerStop: Atomic[bool]
  gServerPort: Atomic[int]
  gOpened: Atomic[int]
  gFrames: Atomic[int]
  gLocates: Atomic[int]
  gPongSeen: Atomic[bool]

proc serverFrame(data: string; opcode = 0x1): string =
  ## Server frames are not masked; payloads here are under 126 bytes.
  result.add char(0x80 or opcode)
  result.add char(data.len)
  result.add data

proc readClientFrame(client: Socket): (int, string) =
  ## A client frame is masked; enough of a parser for short control frames.
  let head = client.recv(2, timeout = 2000)
  if head.len < 2: return (-1, "")
  let opcode = ord(head[0]) and 0x0F
  let length = ord(head[1]) and 0x7F
  let mask = client.recv(4, timeout = 2000)
  var payload = if length > 0: client.recv(length, timeout = 2000) else: ""
  for i in 0 ..< payload.len:
    payload[i] = char(ord(payload[i]) xor ord(mask[i mod 4]))
  (opcode, payload)

proc serve(client: Socket) =
  ## Upgrade, then play the scenario.
  while true:
    let line = client.recvLine(timeout = 2000)
    if line.len == 0 or line == "\r\n": break
  client.send("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n" &
              "Connection: Upgrade\r\nSec-WebSocket-Accept: x\r\n\r\n")
  case Scenario(gScenario.load())
  of scSendAndClose:
    client.send(serverFrame("a") & serverFrame("b"))
    sleep(50)
  of scHold:
    client.send(serverFrame("hello"))
    while not gServerStop.load():
      ## Read until the client goes away; nothing is sent.
      let got = try: client.recv(1, timeout = 100) except TimeoutError: "x"
      if got.len == 0: break
  of scFatal:
    client.send(serverFrame("fatal"))
    sleep(300)
  of scCloseFatal:
    client.send(serverFrame("\x0F\xA4", opcode = 0x8))   ## 4004
    sleep(300)
  of scCloseOther:
    client.send(serverFrame("\x03\xE8", opcode = 0x8))   ## 1000
    sleep(100)
  of scPing:
    client.send(serverFrame("p", opcode = 0x9))
    let (opcode, payload) = readClientFrame(client)
    if opcode == 0xA and payload == "p":
      gPongSeen.store(true)
    sleep(100)

proc serverThread() {.thread.} =
  let server = newSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(Port(0), "127.0.0.1")
  server.listen()
  gServerPort.store(server.getLocalAddr()[1].int)
  while not gServerStop.load():
    var fds = @[server.getFd]
    if selectRead(fds, 100) <= 0: continue
    var client: Socket
    try:
      server.accept(client)
      serve(client)
    except CatchableError:
      discard
    finally:
      if client != nil:
        try: client.close() except CatchableError: discard
  server.close()

proc testLocate(cfg: TestConfig; state: var TestState; log: Logger):
               Result[SocketTarget, string] {.nimcall, gcsafe, raises: [].} =
  discard gLocates.fetchAdd(1)
  if cfg.failLocate:
    return err("lookup refused")
  ok(SocketTarget(host: "127.0.0.1", port: Port(cfg.port), path: "/", useTls: false))

proc testOpened(cfg: TestConfig; state: var TestState; ws: WsClient;
                log: Logger): SessionStep {.nimcall, gcsafe, raises: [].} =
  inc state.sessions
  discard gOpened.fetchAdd(1)
  ssKeep

proc testFrame(cfg: TestConfig; state: var TestState; ws: WsClient;
               frame: WsFrame; log: Logger): SessionStep {.nimcall, gcsafe, raises: [].} =
  discard gFrames.fetchAdd(1)
  if frame.opcode == WsOpcodeClose:
    ## The close code is the protocol's to read (Discord: a bad token stops).
    if frame.data == "\x0F\xA4": ssStop else: ssKeep
  elif frame.data == "fatal": ssStop
  else: ssKeep

proc testTick(cfg: TestConfig; state: var TestState; ws: WsClient;
              nowMs: int64; log: Logger): SessionStep {.nimcall, gcsafe, raises: [].} =
  ssKeep

const TestProtocol = SocketProtocol[TestConfig, TestState](
  locate: testLocate, opened: testOpened, frame: testFrame, tick: testTick)

proc fastPolicy(idleMs = 60_000): SocketPolicy =
  SocketPolicy(reconnectMinMs: 100, reconnectMaxMs: 400,
               idleTimeoutMs: idleMs, recvTimeoutMs: 100)

proc waitFor(cond: proc(): bool; ms: int): bool =
  let deadline = getMonoTime() + initDuration(milliseconds = ms)
  while getMonoTime() < deadline:
    if cond(): return true
    sleep(10)
  cond()

proc reset(scenario: Scenario) =
  gScenario.store(ord(scenario))
  gOpened.store(0)
  gFrames.store(0)
  gLocates.store(0)
  gPongSeen.store(false)

proc runTests*() =
  let log = newLogger("test.persistent_socket", lvlError)
  var server: Thread[void]
  gServerStop.store(false)
  createThread(server, serverThread)
  check waitFor(proc(): bool = gServerPort.load() > 0, 2000)
  let port = gServerPort.load()

  suite "persistent socket":

    test "frames reach the protocol, and a closed connection reconnects":
      reset(scSendAndClose)
      var ps = startPersistentSocket("test", TestProtocol,
                                     TestConfig(port: port), fastPolicy(), log).get
      check waitFor(proc(): bool = gOpened.load() >= 2 and gFrames.load() >= 4, 5000)
      ps.stop()

    test "a fatal step stops for good":
      reset(scFatal)
      var ps = startPersistentSocket("test", TestProtocol,
                                     TestConfig(port: port), fastPolicy(), log).get
      check waitFor(proc(): bool = not ps.running, 3000)
      sleep(500)
      check gOpened.load() == 1
      ps.stop()

    test "a close frame reaches the protocol, which may stop for good":
      reset(scCloseFatal)
      var ps = startPersistentSocket("test", TestProtocol,
                                     TestConfig(port: port), fastPolicy(), log).get
      check waitFor(proc(): bool = not ps.running, 3000)
      check gFrames.load() == 1
      check gOpened.load() == 1
      ps.stop()

    test "a closed socket reconnects even when the protocol says keep":
      reset(scCloseOther)
      var ps = startPersistentSocket("test", TestProtocol,
                                     TestConfig(port: port), fastPolicy(), log).get
      check waitFor(proc(): bool = gOpened.load() >= 2, 3000)
      ps.stop()

    test "stop interrupts a blocked read promptly":
      reset(scHold)
      var policy = fastPolicy()
      policy.recvTimeoutMs = 10_000   ## a read that would block for long
      var ps = startPersistentSocket("test", TestProtocol,
                                     TestConfig(port: port), policy, log).get
      check waitFor(proc(): bool = gFrames.load() >= 1, 3000)
      let started = getMonoTime()
      ps.stop()
      check inMilliseconds(getMonoTime() - started) < 1500

    test "a silent connection is reopened after the idle timeout":
      reset(scHold)
      var ps = startPersistentSocket("test", TestProtocol,
                                     TestConfig(port: port), fastPolicy(idleMs = 500), log).get
      check waitFor(proc(): bool = gOpened.load() >= 2, 4000)
      ps.stop()

    test "a ping is answered with its pong":
      reset(scPing)
      var ps = startPersistentSocket("test", TestProtocol,
                                     TestConfig(port: port), fastPolicy(), log).get
      check waitFor(proc(): bool = gPongSeen.load(), 3000)
      ps.stop()

    test "a failing lookup retries with backoff, without spinning":
      reset(scHold)
      var ps = startPersistentSocket("test", TestProtocol,
                                     TestConfig(port: port, failLocate: true),
                                     fastPolicy(), log).get
      sleep(1200)
      ps.stop()
      ## 100, 200, 400, 400 ms…: a handful of tries, not hundreds.
      check gLocates.load() in 2 .. 8
      check gOpened.load() == 0

    test "sending to a dead peer raises instead of spinning":
      ## Nim's send(string) with its default SafeDisconn flag swallows EPIPE
      ## without advancing and loops forever; a heartbeat or a close frame
      ## to a dropped connection must fail fast instead.
      let listener = newSocket()
      listener.setSockOpt(OptReuseAddr, true)
      listener.bindAddr(Port(0), "127.0.0.1")
      listener.listen()
      let client = newSocket(buffered = false)
      client.connect("127.0.0.1", listener.getLocalAddr()[1])
      var peer: Socket
      listener.accept(peer)
      peer.close()
      listener.close()
      let ws = WsClient(sock: client)
      let started = getMonoTime()
      var raised = false
      for _ in 0 ..< 5:          ## the first sends may still land in the buffer
        try:
          ws.sendFrame("x".repeat(64 * 1024))
        except CatchableError:
          raised = true
          break
      check raised
      check inMilliseconds(getMonoTime() - started) < 2000
      client.close()

    test "a config holding a ref is refused at compile time":
      type RefConfig = object
        holder: ref int
      check not compiles(startPersistentSocket("x",
        SocketProtocol[RefConfig, TestState](), RefConfig(), fastPolicy(), log))

  gServerStop.store(true)
  joinThread(server)

when isMainModule:
  runTests()
