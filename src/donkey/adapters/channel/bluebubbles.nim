## bluebubbles — BlueBubbles (iMessage) as a channel (E13.3).
##
## A BlueBubbles Server on the operator's Mac bridges iMessage. Its webhooks
## carry no signature, so Donkey polls instead: one thread asks the message
## query for what came after the newest message seen, every few seconds,
## with the server password, and hands people's one-to-one messages to the
## daemon loop through a queue (bluebubbles_runtime). Answers go through
## `POST /api/v1/message/text`. A person is an iMessage address, linked by
## pairing or `/continue`. Text only: buttons are dropped (an approval's text
## says how to answer), a file becomes a note.

import std/[atomics, os, strutils, sysrand, times]
import ../../core/log
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/bluebubbles_pure
import ../../infra/event_queue
import ../../infra/thread_handle
import ../../infra/connection_state
import ../../infra/supervisor
import ../../domain/supervision_pure
import ../../ports/http
import ../../ports/link_codes
import ../http/std_http
import ../identity/identity_resolver

export bluebubbles_pure

const
  BlueQueueCapacity* = 256
  BlueTimeoutSec = 30
  BluePollEveryMs* = 3_000
  BlueBackoffMaxMs = 60_000
  BlueFileNote = "(o arquivo não pôde ser enviado: pelo iMessage eu só mando texto)"

type
  BlueBubblesSettings* = object
    url*:      string    ## BLUEBUBBLES_URL
    password*: string    ## BLUEBUBBLES_PASSWORD

  BlueInbound* = object
    guid*, address*, chatGuid*, text*: string
    attachments*: int

var gBlueEvents* = initEventQueue[BlueInbound]("bluebubbles", capacity = BlueQueueCapacity)

proc pushBlue*(m: BlueInbound): bool {.discardable.} = gBlueEvents.push(m)
proc tryRecvBlue*(): (bool, BlueInbound) = gBlueEvents.tryTake()

func hostOf(url: string): string =
  var rest = url
  for scheme in ["https://", "http://"]:
    if rest.startsWith(scheme): rest = rest[scheme.len .. ^1]
  if rest.startsWith("["): return rest[0 .. max(0, rest.find(']'))]
  rest.split('/')[0].split(':')[0]

proc blueHttp(settings: BlueBubblesSettings): HttpRuntimePort =
  newStdHttpAdapter(timeout = BlueTimeoutSec, allowlist = @[hostOf(settings.url)],
                    retryNonIdempotent = false).toRuntimePort()

proc pollBlueBubbles*(http: HttpRuntimePort; settings: BlueBubblesSettings;
                      after: int64): Result[tuple[messages: seq[BlueMessage], after: int64], string] =
  ## One round: the messages after `after` (ms), and where the next starts.
  let resp = ? http.post(apiUrl(settings.url, "/api/v1/message/query", settings.password),
                         queryBody(after), @[("Content-Type", "application/json")])
  if resp.status != 200:
    return err("BlueBubbles: query status " & $resp.status)
  let page = ? parseMessagePage(resp.body)
  ok((messages: page.messages, after: max(after, page.newest)))

# ── The polling thread ────────────────────────────────────────────────────────

type
  BlueControl = object
    stop:   Atomic[bool]
    exited: Atomic[bool]

  BlueArgs = object
    settings: BlueBubblesSettings
    logger:   LogSpec
    control:  ptr BlueControl

  BluePoller = object
    control: ptr BlueControl
    thread:  ThreadHandle[BlueArgs]

var gBluePoller: BluePoller

proc sleepOrStop(control: ptr BlueControl; ms: int): bool =
  var waited = 0
  while waited < ms and not control.stop.load():
    let slice = min(100, ms - waited)
    sleep(slice)
    waited += slice
  not control.stop.load()

proc runBlue(args: BlueArgs) {.thread, nimcall.} =
  let log = args.logger.toLogger
  let control = args.control
  defer: control.exited.store(true)
  socketStarted(ckBlueBubbles)
  defer: socketEnded(ckBlueBubbles)
  let http = blueHttp(args.settings)
  var after = int64(epochTime() * 1000) - 10_000   ## only what arrives from now on
  var backoff = BluePollEveryMs
  ## E12.2: a failed poll is a session that ended; a good one, the channel up.
  var restart = DefaultPolicy
  restart.baseBackoffMs = BluePollEveryMs
  restart.maxBackoffMs = BlueBackoffMaxMs
  var sup = newSupervised(ckBlueBubbles, "bluebubbles", restart)
  while not control.stop.load():
    let round = pollBlueBubbles(http, args.settings, after)
    if round.isErr:
      log.warn(round.error)
      backoff = sup.ended(round.error, ranMs = 0, log)
    else:
      sup.started()
      backoff = BluePollEveryMs
      after = round.get.after
      for m in round.get.messages:
        if not pushBlue(BlueInbound(guid: m.guid, address: m.address, chatGuid: m.chatGuid,
                                    text: m.text, attachments: m.attachments)):
          log.warn("bluebubbles: the inbound queue is full; a message was dropped")
    if not sleepOrStop(control, backoff):
      return

proc startBlueBubbles*(settings: BlueBubblesSettings; logger: Logger): Result[void, string] =
  if not validServerUrl(settings.url) or settings.password.len == 0:
    return err("BLUEBUBBLES_URL (https, or http on this machine) and BLUEBUBBLES_PASSWORD are required")
  if gBluePoller.control != nil:
    return err("BlueBubbles is already started")
  let control = cast[ptr BlueControl](allocShared0(sizeof(BlueControl)))
  if control == nil:
    return err("bluebubbles: out of memory")
  try:
    gBluePoller = BluePoller(control: control,
      thread: spawnThread(runBlue, BlueArgs(settings: settings, logger: logger.spec, control: control)))
  except CatchableError as e:
    deallocShared(control)
    return err("bluebubbles: cannot start its thread: " & e.msg)
  ok()

proc stopBlueBubbles*() =
  if gBluePoller.control == nil:
    return
  gBluePoller.control.stop.store(true)
  joinAndFree(gBluePoller.thread)
  deallocShared(gBluePoller.control)
  gBluePoller.control = nil

# ── The daemon's side ─────────────────────────────────────────────────────────

type
  BlueState = ref object
    seen: seq[string]

  BlueBubblesAdapter* = object
    settings*:    BlueBubblesSettings
    resolver*:    IdentityResolver
    linkCodes*:   LinkCodePort
    http:         HttpRuntimePort
    state:        BlueState
    configError*: string

proc markSeen*(a: BlueBubblesAdapter; guid: string): bool =
  if guid.len == 0: return true
  if guid in a.state.seen: return false
  a.state.seen.add guid
  if a.state.seen.len > 512: a.state.seen.delete(0)
  true

proc tempGuid(): string =
  var raw: array[12, byte]
  if not urandom(raw): return "donkey-" & $int64(epochTime() * 1_000_000)
  result = "donkey-"
  for b in raw: result.add b.toHex(2).toLowerAscii

proc send*(a: BlueBubblesAdapter; msg: OutboundMessage): Result[void, string] =
  ## Text to the chat (the one the person wrote from, or their address's).
  if a.configError.len > 0:
    return err("BlueBubbles: " & a.configError)
  var text = msg.text
  if msg.mediaUrl.len > 0:
    text = (if text.strip.len > 0: text & "\n\n" else: "") & BlueFileNote
  if text.strip.len == 0:
    return ok()
  let target =
    if msg.replyTo.strip.len > 0: msg.replyTo.strip
    else: a.resolver.reverseChannel(msg.userId, ckBlueBubbles)
  if target.len == 0:
    return err("BlueBubbles: no address known for user " & $msg.userId)
  let resp = ? a.http.post(apiUrl(a.settings.url, "/api/v1/message/text", a.settings.password),
                           sendTextBody(chatFor(target), text, tempGuid()),
                           @[("Content-Type", "application/json")])
  if resp.status notin 200 .. 299:
    return err("BlueBubbles: send status " & $resp.status)
  ok()

proc newBlueBubblesAdapter*(settings: BlueBubblesSettings; identityPath: string;
                            http: HttpRuntimePort = HttpRuntimePort()): BlueBubblesAdapter =
  ## `BLUEBUBBLES_URL` and `BLUEBUBBLES_PASSWORD` from the environment
  ## snapshot. A bad setting does not stop the daemon: the adapter records why.
  var s = settings
  s.url = s.url.strip
  var transport = http
  if transport.post.isNil:
    transport = blueHttp(s)
  result = BlueBubblesAdapter(settings: s, resolver: newIdentityResolver(identityPath),
    http: transport, state: BlueState(),
    configError:
      if not validServerUrl(s.url): "BLUEBUBBLES_URL must be https (or http on this machine): the password travels in the URL"
      elif s.password.len == 0: "BLUEBUBBLES_PASSWORD is required"
      else: "")
  result.linkCodes = result.resolver.linkCodePort()
