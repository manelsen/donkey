## simplex — SimpleX as a channel (E13.2).
##
## One connection thread per daemon talks to a `simplex-chat` CLI running as
## a local WebSocket server (`simplex-chat -p 5225`, bots API): it hands the
## direct text messages contacts send to the daemon loop through a queue
## (simplex_runtime), and sends the commands that answer them. A person is
## a direct contact of the bot (its contactId in that CLI's database),
## linked by pairing or `/continue`. Text only: buttons are dropped (an
## approval's text says how to answer), a file becomes a note. The bot's
## address and auto-accept are set up by the operator in the CLI.

import std/[atomics, json, net, os, random, strutils, times]
import ../../core/log
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/simplex_pure
import ../../infra/event_queue
import ../../infra/thread_handle
import ../../infra/connection_state
import ../../infra/supervisor
import ../../domain/supervision_pure
import ../../ports/link_codes
import ../identity/identity_resolver
import ./ws_client

export simplex_pure

const
  SimplexQueueCapacity* = 256
  SimplexOutCapacity* = 512
  SimplexRecvSliceMs = 500
  SimplexReconnectMinMs = 2_000
  SimplexReconnectMaxMs = 120_000
  SimplexMaxFrameBytes = 4 * 1024 * 1024
  SimplexFileNote = "(o arquivo não pôde ser enviado: pelo SimpleX eu só mando texto)"

type
  SimplexSettings* = object
    host*: string
    port*: int

  SimplexInbound* = object
    contactId*: int64
    name*, text*, itemId*: string
    unreadKind*: string   ## not text (an image, a file): answered with a note

  SimplexOut* = object
    contactId*: int64
    text*: string

var gSimplexInbound* = initEventQueue[SimplexInbound]("simplex", capacity = SimplexQueueCapacity)
var gSimplexOutbound* = initEventQueue[SimplexOut]("simplex.out", capacity = SimplexOutCapacity)

proc pushSimplex*(m: SimplexInbound): bool {.discardable.} = gSimplexInbound.push(m)
proc tryRecvSimplex*(): (bool, SimplexInbound) = gSimplexInbound.tryTake()
proc pushSimplexOut*(m: SimplexOut): bool {.discardable.} = gSimplexOutbound.push(m)
proc tryTakeSimplexOut*(): (bool, SimplexOut) = gSimplexOutbound.tryTake()

# ── The connection thread ─────────────────────────────────────────────────────

type
  SimplexControl = object
    stop:   Atomic[bool]
    exited: Atomic[bool]

  SimplexArgs = object
    settings: SimplexSettings
    logger:   LogSpec
    control:  ptr SimplexControl

  SimplexConnection = object
    control: ptr SimplexControl
    thread:  ThreadHandle[SimplexArgs]

var gSimplexConnection: SimplexConnection

proc sleepOrStop(control: ptr SimplexControl; ms: int): bool =
  var waited = 0
  while waited < ms and not control.stop.load():
    let slice = min(100, ms - waited)
    sleep(slice)
    waited += slice
  not control.stop.load()

proc handleFrame(data: string; log: Logger) =
  let event = parseSimplexEvent(data)
  for m in event.messages:
    if not pushSimplex(SimplexInbound(contactId: m.contactId, name: m.name, text: m.text,
                                      itemId: $m.itemId)):
      log.warn("simplex: the inbound queue is full; a message was dropped")
  for u in event.unread:
    discard pushSimplex(SimplexInbound(contactId: u.contactId, name: u.name, unreadKind: u.kind,
                                       itemId: $u.itemId))

proc runSession(args: SimplexArgs; log: Logger; connected: var bool) =
  let ws = wsConnect(args.settings.host, Port(args.settings.port), "/", useTls = false)
  defer: ws.wsClose()
  connected = true
  socketConnected(ckSimplex)
  var corrId = 0
  while not args.control.stop.load():
    let frame = ws.recvFrame(timeoutMs = SimplexRecvSliceMs, maxPayloadBytes = SimplexMaxFrameBytes)
    if frame.isErr:
      if frame.error != "timeout":
        raise newException(IOError, "simplex-chat: " & frame.error)
    else:
      case frame.get.opcode
      of WsOpcodeText: handleFrame(frame.get.data, log)
      of WsOpcodePing: ws.sendFrame(frame.get.data, WsOpcodePong)
      of WsOpcodeClose: raise newException(IOError, "simplex-chat closed the connection")
      else: discard
    while true:
      let (has, outgoing) = tryTakeSimplexOut()
      if not has: break
      inc corrId
      ws.sendFrame(sendCommand($corrId, outgoing.contactId, outgoing.text))

proc runSimplex(args: SimplexArgs) {.thread, nimcall.} =
  let log = args.logger.toLogger
  let control = args.control
  defer: control.exited.store(true)
  socketStarted(ckSimplex)
  defer: socketEnded(ckSimplex)
  randomize()
  ## E12.2: a permanent child, under the supervisor's waits and escalation.
  var restart = DefaultPolicy
  restart.baseBackoffMs = SimplexReconnectMinMs
  restart.maxBackoffMs = SimplexReconnectMaxMs
  var sup = newSupervised(ckSimplex, "simplex", restart)
  while not control.stop.load():
    var connected = false
    var why = "the connection ended"
    let began = epochTime()
    try:
      runSession(args, log, connected)
    except CatchableError as e:
      why = e.msg
      if not control.stop.load():
        log.warn("simplex: " & e.msg)
    if connected:
      socketDisconnected(ckSimplex)
    if control.stop.load():
      return
    let wait = sup.ended(why, ranMs = int64((epochTime() - began) * 1000), log)
    if not sleepOrStop(control, wait + rand(max(0, wait div 4))):
      return

proc startSimplex*(settings: SimplexSettings; logger: Logger): Result[void, string] =
  if settings.host.len == 0 or settings.port <= 0:
    return err("SIMPLEX_URL is not valid")
  if gSimplexConnection.control != nil:
    return err("SimpleX is already started")
  let control = cast[ptr SimplexControl](allocShared0(sizeof(SimplexControl)))
  if control == nil:
    return err("simplex: out of memory")
  try:
    gSimplexConnection = SimplexConnection(control: control,
      thread: spawnThread(runSimplex, SimplexArgs(settings: settings, logger: logger.spec,
                                                  control: control)))
  except CatchableError as e:
    deallocShared(control)
    return err("simplex: cannot start its thread: " & e.msg)
  ok()

proc stopSimplex*() =
  if gSimplexConnection.control == nil:
    return
  gSimplexConnection.control.stop.store(true)
  joinAndFree(gSimplexConnection.thread)
  deallocShared(gSimplexConnection.control)
  gSimplexConnection.control = nil

# ── The daemon's side ─────────────────────────────────────────────────────────

type
  SimplexState = ref object
    seen: seq[string]

  SimplexAdapter* = object
    settings*:    SimplexSettings
    resolver*:    IdentityResolver
    linkCodes*:   LinkCodePort
    state:        SimplexState
    configError*: string

proc markSeen*(a: SimplexAdapter; itemId: string): bool =
  if itemId.len == 0: return true
  if itemId in a.state.seen: return false
  a.state.seen.add itemId
  if a.state.seen.len > 512: a.state.seen.delete(0)
  true

proc send*(a: SimplexAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text to the contact, handed to the connection thread.
  if a.configError.len > 0:
    return err("SimpleX: " & a.configError)
  var text = msg.text
  if msg.mediaUrl.len > 0:
    text = (if text.strip.len > 0: text & "\n\n" else: "") & SimplexFileNote
  if text.strip.len == 0:
    return ok()
  let raw =
    if msg.replyTo.strip.len > 0: msg.replyTo.strip
    else: a.resolver.reverseChannel(msg.userId, ckSimplex)
  if raw.len == 0:
    return err("SimpleX: no contact known for user " & $msg.userId)
  var contactId = 0'i64
  try: contactId = parseBiggestInt(raw)
  except ValueError: return err("SimpleX: not a contact id: " & raw)
  for piece in simplexPieces(text):
    if not pushSimplexOut(SimplexOut(contactId: contactId, text: piece)):
      return err("SimpleX: the outbound queue is full")
  ok()

proc newSimplexAdapter*(url, identityPath: string): SimplexAdapter =
  ## `SIMPLEX_URL` from the environment snapshot (ws://127.0.0.1:5225 by
  ## default). A bad one does not stop the daemon: the adapter records why.
  let parsed = parseSimplexUrl(url)
  result = SimplexAdapter(resolver: newIdentityResolver(identityPath), state: SimplexState())
  if parsed.isErr:
    result.configError = parsed.error
  else:
    result.settings = SimplexSettings(host: parsed.get.host, port: parsed.get.port)
  result.linkCodes = result.resolver.linkCodePort()
