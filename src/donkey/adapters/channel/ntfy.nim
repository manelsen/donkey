## ntfy — ntfy as a channel (E13.1).
##
## One polling thread per daemon asks the topic for what came since the last
## message seen (`/json?poll=1&since=…`), every few seconds, and hands the
## person's messages to the daemon loop through a queue (ntfy_runtime).
## Answers are published on the same topic, tagged `donkey`, so the poll
## never reads them back. The topic is the secret: whoever can write to it
## is its person, linked like on any channel (pairing, `/continue`). Text
## only: buttons are dropped (an approval's text says how to answer) and a
## file becomes a note.

import std/[atomics, os, strutils]
import ../../core/log
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../domain/channels/ntfy_pure
import ../../infra/event_queue
import ../../infra/thread_handle
import ../../infra/connection_state
import ../../infra/supervisor
import ../../domain/supervision_pure
import ../../ports/http
import ../../ports/link_codes
import ../http/std_http
import ../identity/identity_resolver

export ntfy_pure

const
  NtfyQueueCapacity* = 256
  NtfyTimeoutSec = 30
  NtfyPollEveryMs* = 3_000
  NtfyBackoffMaxMs = 60_000
  NtfyFileNote = "(o arquivo não pôde ser enviado: o ntfy só recebe texto)"

type
  NtfySettings* = object
    ## Plain data, copied to the polling thread.
    url*:   string    ## NTFY_URL (https://ntfy.sh by default)
    topic*: string    ## NTFY_TOPIC
    token*: string    ## NTFY_TOKEN, for a protected topic

  NtfyInbound* = object
    id*, text*, topic*: string

var gNtfyEvents* = initEventQueue[NtfyInbound]("ntfy", capacity = NtfyQueueCapacity)

proc pushNtfy*(m: NtfyInbound): bool {.discardable.} = gNtfyEvents.push(m)
proc tryRecvNtfy*(): (bool, NtfyInbound) = gNtfyEvents.tryTake()

func hostOf(url: string): string =
  var rest = url
  for scheme in ["https://", "http://"]:
    if rest.startsWith(scheme): rest = rest[scheme.len .. ^1]
  rest.split('/')[0].split(':')[0]

proc ntfyHttp(settings: NtfySettings): HttpRuntimePort =
  newStdHttpAdapter(timeout = NtfyTimeoutSec, allowlist = @[hostOf(settings.url)],
                    retryNonIdempotent = false).toRuntimePort()

proc pollNtfy*(http: HttpRuntimePort; settings: NtfySettings;
               since: string): Result[tuple[messages: seq[NtfyMessage], since: string], string] =
  ## One round: what the topic got since `since`, and where the next starts.
  var headers: seq[HttpHeader]
  if settings.token.len > 0: headers.add(("Authorization", "Bearer " & settings.token))
  let resp = ? http.get(pollUrl(settings.url, settings.topic, since), headers)
  if resp.status != 200:
    return err("ntfy: poll status " & $resp.status)
  let last = lastNtfyId(resp.body)
  ok((messages: parseNtfyLines(resp.body), since: if last.len > 0: last else: since))

# ── The polling thread ────────────────────────────────────────────────────────

type
  NtfyControl = object
    stop:   Atomic[bool]
    exited: Atomic[bool]

  NtfyArgs = object
    settings: NtfySettings
    logger:   LogSpec
    control:  ptr NtfyControl

  NtfyPoller = object
    control: ptr NtfyControl
    thread:  ThreadHandle[NtfyArgs]

var gNtfyPoller: NtfyPoller

proc sleepOrStop(control: ptr NtfyControl; ms: int): bool =
  var waited = 0
  while waited < ms and not control.stop.load():
    let slice = min(100, ms - waited)
    sleep(slice)
    waited += slice
  not control.stop.load()

proc runNtfy(args: NtfyArgs) {.thread, nimcall.} =
  let log = args.logger.toLogger
  let control = args.control
  defer: control.exited.store(true)
  socketStarted(ckNtfy)
  defer: socketEnded(ckNtfy)
  let http = ntfyHttp(args.settings)
  var since = ""
  var backoff = NtfyPollEveryMs
  ## E12.2: a failed poll is a session that ended; a good one, the channel up.
  var restart = DefaultPolicy
  restart.baseBackoffMs = NtfyPollEveryMs
  restart.maxBackoffMs = NtfyBackoffMaxMs
  var sup = newSupervised(ckNtfy, "ntfy", restart)
  while not control.stop.load():
    let round = pollNtfy(http, args.settings, since)
    if round.isErr:
      log.warn(round.error)
      backoff = sup.ended(round.error, ranMs = 0, log)
    else:
      sup.started()
      backoff = NtfyPollEveryMs
      since = round.get.since
      for m in round.get.messages:
        if not pushNtfy(NtfyInbound(id: m.id, text: m.text, topic: args.settings.topic)):
          log.warn("ntfy: the inbound queue is full; a message was dropped")
    if not sleepOrStop(control, backoff):
      return

proc startNtfy*(settings: NtfySettings; logger: Logger): Result[void, string] =
  if not validNtfyTopic(settings.topic):
    return err("NTFY_TOPIC is required: letters, digits, _ and -, at most 64")
  if not settings.url.startsWith("https://") and not settings.url.startsWith("http://"):
    return err("NTFY_URL must be http(s)")
  if gNtfyPoller.control != nil:
    return err("ntfy is already started")
  let control = cast[ptr NtfyControl](allocShared0(sizeof(NtfyControl)))
  if control == nil:
    return err("ntfy: out of memory")
  try:
    gNtfyPoller = NtfyPoller(control: control,
      thread: spawnThread(runNtfy, NtfyArgs(settings: settings, logger: logger.spec,
                                            control: control)))
  except CatchableError as e:
    deallocShared(control)
    return err("ntfy: cannot start its thread: " & e.msg)
  ok()

proc stopNtfy*() =
  if gNtfyPoller.control == nil:
    return
  gNtfyPoller.control.stop.store(true)
  joinAndFree(gNtfyPoller.thread)
  deallocShared(gNtfyPoller.control)
  gNtfyPoller.control = nil

# ── The daemon's side ─────────────────────────────────────────────────────────

type
  NtfyState = ref object
    seen: seq[string]   ## message ids, oldest first

  NtfyAdapter* = object
    settings*:    NtfySettings
    resolver*:    IdentityResolver
    linkCodes*:   LinkCodePort
    http:         HttpRuntimePort
    state:        NtfyState
    configError*: string

proc markSeen*(a: NtfyAdapter; id: string): bool =
  ## True the first time a message id comes (a poll may overlap the last).
  if id.len == 0: return true
  if id in a.state.seen: return false
  a.state.seen.add id
  if a.state.seen.len > 512:
    a.state.seen.delete(0)
  true

proc send*(a: NtfyAdapter; msg: OutboundMessage): Result[void, string] =
  ## Published on the topic, in pieces ntfy accepts.
  if a.configError.len > 0:
    return err("ntfy: " & a.configError)
  var text = msg.text
  if msg.mediaUrl.len > 0:
    text = (if text.strip.len > 0: text & "\n\n" else: "") & NtfyFileNote
  if text.strip.len == 0:
    return ok()
  for piece in ntfyPieces(text):
    let resp = ? a.http.post(publishUrl(a.settings.url, a.settings.topic), piece,
                             publishHeaders(a.settings.token))
    if resp.status notin 200 .. 299:
      return err("ntfy: publish status " & $resp.status)
  ok()

proc newNtfyAdapter*(settings: NtfySettings; identityPath: string;
                     http: HttpRuntimePort = HttpRuntimePort()): NtfyAdapter =
  ## `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN` from the environment snapshot. A
  ## bad setting does not stop the daemon: the adapter records why.
  var s = settings
  if s.url.strip.len == 0: s.url = "https://ntfy.sh"
  var transport = http
  if transport.post.isNil:
    transport = ntfyHttp(s)
  result = NtfyAdapter(settings: s, resolver: newIdentityResolver(identityPath),
    http: transport, state: NtfyState(),
    configError:
      if not validNtfyTopic(s.topic): "NTFY_TOPIC must be letters, digits, _ and - (at most 64)"
      elif not s.url.startsWith("https://") and not s.url.startsWith("http://"): "NTFY_URL must be http(s)"
      else: "")
  result.linkCodes = result.resolver.linkCodePort()
