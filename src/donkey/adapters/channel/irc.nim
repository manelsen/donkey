## irc — IRC as a channel (second round, front 1).
##
## One connection thread per daemon: TLS only (the SASL password and every
## message cross it), registration and SASL by irc_pure's `react`, PING/PONG,
## reconnection with backoff. Inbound PRIVMSGs the bot should answer go to
## the daemon loop through a queue; replies come back through another queue
## that the thread writes, paced so the server does not kick the bot for
## flooding. A person is their services account (IRCv3 account-tag); their
## last nick is kept on disk, for sends without a target.

import std/[atomics, json, monotimes, net, options, os, random, strutils, tables, times]
import ../../core/log
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/irc_pure
import ../../infra/event_queue
import ../../infra/thread_handle
import ../../ports/link_codes
import ../identity/identity_resolver
import ../state/durable_file

export irc_pure

const
  IrcQueueCapacity* = 256
  IrcOutCapacity* = 512
  IrcRecvSliceMs = 500
  IrcPingAfterMs = 120_000    ## silence this long: ask the server
  IrcDeadAfterMs = 240_000    ## silence this long: reconnect
  IrcBurstLines = 5
  IrcLineEveryMs = 600        ## after the burst, one line per this
  IrcReconnectMinMs = 2_000
  IrcReconnectMaxMs = 120_000
  IrcConnectTimeoutMs = 15_000

# ── Queues between the thread and the daemon loop ─────────────────────────────

var gIrcInbound* = initEventQueue[IrcPrivmsg]("irc", capacity = IrcQueueCapacity)
var gIrcOutbound* = initEventQueue[string]("irc.out", capacity = IrcOutCapacity)

proc pushIrc*(p: IrcPrivmsg): bool {.discardable.} = gIrcInbound.push(p)
proc tryRecvIrc*(): (bool, IrcPrivmsg) = gIrcInbound.tryTake()
proc pushOutLine*(line: string): bool {.discardable.} = gIrcOutbound.push(line)
proc tryTakeOutLine*(): (bool, string) = gIrcOutbound.tryTake()

# ── The connection thread ─────────────────────────────────────────────────────

type
  IrcSettings* = object
    ## Plain data, copied to the connection thread.
    host*:     string
    port*:     int
    nick*:     string
    realName*: string
    password*: string   ## SASL PLAIN; empty = no login
    channels*: seq[string]
    tls*:      bool     ## always true from the daemon; tests talk plain TCP to a fake server

  IrcControl = object
    stop:   Atomic[bool]
    exited: Atomic[bool]

  IrcArgs = object
    settings: IrcSettings
    logger:   LogSpec
    control:  ptr IrcControl

  IrcConnection* = object
    control: ptr IrcControl
    thread:  ThreadHandle[IrcArgs]

var gIrcConnection: IrcConnection

func parseIrcServer*(value: string): Result[(string, int), string] =
  ## `host` or `host:port`; 6697, the TLS port, by default.
  let v = value.strip
  if v.len == 0: return err("IRC_SERVER is empty")
  let colon = v.rfind(':')
  if colon < 0: return ok((v, 6697))
  try:
    let port = parseInt(v[colon + 1 .. ^1])
    if port <= 0 or port > 65535: return err("bad port in IRC_SERVER: " & v)
    ok((v[0 ..< colon], port))
  except ValueError:
    err("bad port in IRC_SERVER: " & v)

proc monoMs(): int64 = getMonoTime().ticks div 1_000_000

proc sleepOrStop(control: ptr IrcControl; ms: int): bool =
  var waited = 0
  while waited < ms and not control.stop.load():
    let slice = min(100, ms - waited)
    sleep(slice)
    waited += slice
  not control.stop.load()

proc sendLine(sock: Socket; line: string) =
  sock.send(line & "\r\n")

proc runSession(args: IrcArgs; log: Logger; registered: var bool) =
  ## One connection, from TCP to its end. Raises on transport failures; the
  ## caller logs them and reconnects.
  let cfg = args.settings
  var sock = newSocket()
  defer:
    try: sock.close() except CatchableError: discard
  sock.connect(cfg.host, Port(cfg.port), IrcConnectTimeoutMs)
  if cfg.tls:
    let ctx = newContext(verifyMode = CVerifyPeer)
    ctx.wrapConnectedSocket(sock, handshakeAsClient, cfg.host)
  var session = newIrcSession(cfg.nick, cfg.password, cfg.channels)
  for line in registration(cfg.nick, cfg.realName):
    sock.sendLine(line)
  var lastHeard = monoMs()
  var pinged = false
  var tokens = IrcBurstLines
  var lastToken = monoMs()
  while not args.control.stop.load():
    var raw = ""
    var timedOut = false
    try:
      raw = sock.recvLine(IrcRecvSliceMs)
    except TimeoutError:
      timedOut = true
    if not timedOut:
      if raw.len == 0:
        raise newException(IOError, "the server closed the connection")
      lastHeard = monoMs()
      pinged = false
      let parsed = parseLine(raw)
      if parsed.isSome:
        let line = parsed.get
        if line.command == "ERROR":
          raise newException(IOError, "server error: " & line.params.join(" "))
        for reply in react(session, line):
          sock.sendLine(reply)
        for problem in session.problems:
          log.warn("irc: " & problem)
        session.problems.setLen(0)
        if session.registered and not registered:
          registered = true
          log.info("irc: connected to " & cfg.host & " as " & session.nick)
        let msg = inboundPrivmsg(line, session.nick)
        if msg.isSome and not pushIrc(msg.get):
          log.warn("irc: queue full, a message from " & msg.get.nick & " was dropped")
    let now = monoMs()
    if now - lastHeard >= IrcDeadAfterMs:
      raise newException(IOError, "no word from the server in " &
                         $(IrcDeadAfterMs div 1000) & " s")
    if not pinged and now - lastHeard >= IrcPingAfterMs:
      sock.sendLine("PING :donkey")
      pinged = true
    if session.registered:
      ## Token bucket: a burst, then one line per IrcLineEveryMs.
      let earned = int((now - lastToken) div IrcLineEveryMs)
      if earned > 0:
        tokens = min(IrcBurstLines, tokens + earned)
        lastToken = now
      while tokens > 0:
        let (has, line) = tryTakeOutLine()
        if not has: break
        sock.sendLine(line)
        dec tokens
  try: sock.sendLine("QUIT :bye") except CatchableError: discard

proc runIrc(args: IrcArgs) {.thread, nimcall.} =
  let log = args.logger.toLogger
  let control = args.control
  defer: control.exited.store(true)
  randomize()
  var backoff = IrcReconnectMinMs
  while not control.stop.load():
    var registered = false
    try:
      runSession(args, log, registered)
    except CatchableError as e:
      if not control.stop.load():
        log.warn("irc: " & e.msg)
    if control.stop.load():
      return
    if registered:
      backoff = IrcReconnectMinMs
    if not sleepOrStop(control, backoff + rand(max(0, backoff div 4))):
      return
    backoff = min(backoff * 2, IrcReconnectMaxMs)

proc startIrc*(settings: IrcSettings; logger: Logger): Result[void, string] =
  if settings.host.len == 0 or settings.nick.len == 0:
    return err("IRC_SERVER and IRC_NICK are required")
  if gIrcConnection.control != nil:
    return err("IRC is already started")
  let control = cast[ptr IrcControl](allocShared0(sizeof(IrcControl)))
  if control == nil:
    return err("irc: out of memory")
  try:
    gIrcConnection = IrcConnection(control: control,
      thread: spawnThread(runIrc, IrcArgs(settings: settings, logger: logger.spec,
                                          control: control)))
  except CatchableError as e:
    deallocShared(control)
    return err("irc: cannot start its thread: " & e.msg)
  ok()

proc stopIrc*() =
  ## Stops the connection (within a read slice) and joins its thread. Safe to
  ## call when it was never started, and twice.
  if gIrcConnection.control == nil:
    return
  gIrcConnection.control.stop.store(true)
  joinAndFree(gIrcConnection.thread)
  deallocShared(gIrcConnection.control)
  gIrcConnection.control = nil

# ── The daemon's side ─────────────────────────────────────────────────────────

type
  IrcState = ref object
    nicks: Table[string, string]   ## account → last nick

  IrcAdapter* = object
    resolver*:    IdentityResolver
    linkCodes*:   LinkCodePort
    nicksPath:    string
    state:        IrcState
    configError*: string

proc loadNicks(path: string): Table[string, string] =
  result = initTable[string, string]()
  if path.len == 0 or not fileExists(path):
    return
  try:
    let j = parseJson(readFile(path))
    if j.kind == JObject:
      for key, value in j.pairs:
        if value.kind == JString:
          result[key] = value.getStr
  except CatchableError:
    discard   ## an unreadable file only costs the sends without a target until the next message

proc rememberNick*(a: IrcAdapter; account, nick: string): Result[void, string] {.discardable.} =
  if account.len == 0 or nick.len == 0:
    return ok()
  if a.state.nicks.getOrDefault(account) == nick:
    return ok()
  a.state.nicks[account] = nick
  if a.nicksPath.len == 0:
    return ok()
  var j = newJObject()
  for key, value in a.state.nicks:
    j[key] = %value
  atomicWriteText(a.nicksPath, $j, "w")

proc send*(a: IrcAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text only: one PRIVMSG per line, handed to the connection thread.
  if a.configError.len > 0:
    return err("IRC: " & a.configError)
  if msg.mediaUrl.len > 0 or msg.keyboard.len > 0:
    return err("IRC: only text is supported")
  if msg.text.strip.len == 0:
    return ok()
  var target = msg.replyTo.strip
  if target.len == 0:
    let account = a.resolver.reverseChannel(msg.userId, ckIrc)
    if account.len == 0:
      return err("IRC: no account known for user " & $msg.userId)
    target = a.state.nicks.getOrDefault(account)
    if target.len == 0:
      return err("IRC: no nick known for account " & account)
  if target.contains({' ', '\r', '\n', '\0', ',', ':'}) or target.startsWith("@"):
    return err("IRC: not a target: " & target)
  for line in privmsgLines(target, msg.text):
    if not pushOutLine(line):
      return err("IRC: the outbound queue is full")
  ok()

proc newIrcAdapter*(configured: bool; identityPath, nicksPath: string): IrcAdapter =
  result = IrcAdapter(resolver: newIdentityResolver(identityPath),
    nicksPath: nicksPath, state: IrcState(nicks: loadNicks(nicksPath)),
    configError: if configured: "" else: "IRC_SERVER and IRC_NICK are not set")
  result.linkCodes = result.resolver.linkCodePort()
