## HTTP transport with a wall-clock deadline for the whole request.
##
## `std/httpclient` times out each read, not the request: connecting and
## reading a chunk-size line are not covered, and a server that sends a byte
## now and then never trips it. A provider or channel call could hold its
## caller forever.
##
## Here every request runs on a small pool of worker threads, each with its
## own Chronos loop, under `wait(deadline)`: when the deadline passes the
## request future is cancelled, which closes its connection. The caller blocks
## as before, but only until the deadline (plus a short grace for the reply):
## it never waits on a request that does not end.
##
## The caller never runs a Chronos loop itself. Callers include code that
## already runs inside the daemon's loop, and a nested `waitFor` there would
## re-enter it.
##
## Not covered by the deadline: name resolution (Chronos resolves with the
## blocking getaddrinfo in the worker). The caller still returns at the
## deadline; the worker is held until the resolver answers.

import std/[locks, monotimes, os, strutils, uri]
import chronos
import chronos/apps/http/httpclient
import threading/channels
import ../../core/pipeops
import ../../core/security/net_boundary
import ../../infra/[event_queue, fixed, thread_handle]

const
  TransportWorkers* = 8
  TransportQueueDepth = 256
  DefaultDeadlineMs = 60_000
  ReplyGraceMs = 1_000
    ## Past the deadline the worker cancels and replies; the caller waits this
    ## much longer for that reply before giving up on its own.

type
  TransportRequest* = object
    meth*:          string   ## GET, POST, PUT, PATCH or DELETE
    url*:           string
    body*:          string
    headers*:       seq[(string, string)]
    redirectLimit*: int      ## 0: a 3xx comes back as the response
    proxy*:         string   ## egress proxy URL, tunnelled with CONNECT
    allowlist*:     seq[string]
      ## hosts every hop may reach (empty: any). Checked before each
      ## connection, so a redirect cannot lead outside it.
    deadlineMs*:    int      ## the whole request; <= 0 uses the default

  TransportResponse* = object
    status*:  int
    body*:    string
    headers*: seq[(string, string)]  ## lower-case names

  TransportReply = Result[TransportResponse, string]

  TransportJob = object
    request:   TransportRequest
    expiresAt: int64  ## monotonic nanoseconds; a job dequeued after it is dropped
    reply:     Chan[TransportReply]  ## capacity 1, counted atomically

  WorkerArg = object
    id: int

static:
  doAssert sharesNothing(TransportJob),
    "transport jobs cross to worker threads: plain data only"

proc newJobQueue(): ptr EventQueue[TransportJob] =
  ## In shared memory, never freed: the workers wait on it for the life of
  ## the process. A global value would be destroyed at exit while they wait,
  ## and destroying a condition variable with waiters blocks the exit.
  result = cast[ptr EventQueue[TransportJob]](allocShared0(sizeof(EventQueue[TransportJob])))
  result[] = initEventQueue[TransportJob]("http transport", TransportQueueDepth)

let gJobs = newJobQueue()
var gPoolLock: Lock
var gPoolStarted = false
var gPoolError: FixedText[256]  ## why the pool did not start; not GC memory
var gWorkers: array[TransportWorkers, ThreadHandle[WorkerArg]]
initLock(gPoolLock)

func deadlineOf(request: TransportRequest): int =
  if request.deadlineMs > 0: request.deadlineMs else: DefaultDeadlineMs

func deadlineError(request: TransportRequest): string =
  let ms = request.deadlineOf
  "HTTP request exceeded its deadline of " &
    (if ms mod 1000 == 0: $(ms div 1000) & "s" else: $ms & "ms") &
    " (" & request.meth & " " & request.url & ")"

func methodOf(name: string): Result[HttpMethod, string] =
  case name
  of "GET": ok(MethodGet)
  of "POST": ok(MethodPost)
  of "PUT": ok(MethodPut)
  of "PATCH": ok(MethodPatch)
  of "DELETE": ok(MethodDelete)
  of "HEAD": ok(MethodHead)
  else: err("unsupported HTTP method: " & name)

type Hop = object
  ## What one request of a redirect chain sends. Each hop is derived from the
  ## previous one, never from the original request, so a change a redirect
  ## made (a 303 turning a POST into a GET, credentials dropped at another
  ## host) holds for the rest of the chain.
  address: HttpAddress
  meth:    HttpMethod
  body:    string
  headers: seq[(string, string)]

const CredentialHeaders = ["authorization", "cookie", "proxy-authorization"]

func sameHost(a, b: HttpAddress): bool =
  a.hostname == b.hostname and a.port == b.port

func authority(address: HttpAddress): string =
  ## host:port as a URL writes it: an IPv6 host keeps its brackets.
  let host = if ':' in address.hostname: "[" & address.hostname & "]"
             else: address.hostname
  host & ":" & $address.port

proc hopAllowed*(address: HttpAddress; allowlist: seq[string]): bool =
  ## Whether a hop may connect: an allowlist entry names the host alone or
  ## with its port (a test server, a self-hosted API), as StdHttpAdapter
  ## matches the URL's authority. An empty allowlist allows any host.
  allowlist.len == 0 or isHostAllowed(address.hostname, allowlist) or
    isHostAllowed(authority(address), allowlist)

func isDowngrade*(current, target: HttpAddress): bool =
  ## A redirect from https to http would send the next request, its headers
  ## and (for 307/308) its body in cleartext.
  current.scheme == HttpClientScheme.Secure and
    target.scheme == HttpClientScheme.NonSecure

func requestHeaders(headers: seq[(string, string)]): seq[(string, string)] =
  ## The caller's headers without the ones Chronos derives per request.
  for (name, value) in headers:
    if name.toLowerAscii notin ["host", "content-length"]:
      result.add((name, value))

func nextHop*(current: Hop; status: int; target: HttpAddress): Hop =
  ## 307 and 308 repeat the current method and body; 301, 302 and 303 become
  ## a GET without a body (and without its Content-Type), as browsers and
  ## std/httpclient do, except a HEAD, which stays a HEAD. Credentials do not follow to another host, and once
  ## dropped they stay dropped.
  let keepBody = status in [307, 308]
  let crossHost = not sameHost(target, current.address)
  result = Hop(address: target,
               meth: if keepBody or current.meth == MethodHead: current.meth
                     else: MethodGet,
               body: if keepBody: current.body else: "")
  for (name, value) in requestHeaders(current.headers):
    let lower = name.toLowerAscii
    if not keepBody and lower == "content-type": continue
    if crossHost and lower in CredentialHeaders: continue
    result.headers.add((name, value))

proc nowNs(): int64 = getMonoTime().ticks

proc readyToConnect(address: var HttpAddress; expiresAt: int64;
                    proxied: bool; request: TransportRequest): Result[void, string] =
  ## Resolves the name before connecting, then checks the deadline: the
  ## resolver blocks this thread, and no connection or send may start after
  ## the caller was told the request failed. With an egress proxy the proxy
  ## resolves the target. Resolved addresses keep Chronos from resolving again.
  if not proxied and address.addresses.len == 0:
    try:
      address.addresses = resolveTAddress(address.hostname, Port(address.port))
    except TransportAddressError as e:
      return err("name lookup failed for " & address.hostname & ": " & e.msg)
  if nowNs() >= expiresAt:
    return err(deadlineError(request))
  ok()

proc perform(request: TransportRequest; expiresAt: int64): Future[TransportReply] {.
    async: (raises: [CancelledError]).} =
  let meth = methodOf(request.meth).valueOr:
    return err(error)
  var hop = Hop(meth: meth, body: request.body,
                headers: requestHeaders(request.headers))
  hop.address = getHttpAddress(request.url).valueOr:
    return err("invalid request URL: " & $error)
  var flags: HttpClientFlags = {HttpClientFlag.NoAutomaticRedirect}
  var provider: HttpConnectionProvider = nil
  if request.proxy.len > 0:
    let proxy = getHttpAddress(request.proxy).valueOr:
      return err("invalid proxy URL: " & $error)
    provider = httpConnectProvider(proxy)
  let proxied = provider != nil
  let phase = chronos.milliseconds(max(1, int((expiresAt - nowNs()) div 1_000_000)))
  let session = HttpSessionRef.new(
    flags = flags, maxRedirections = max(request.redirectLimit, 0),
    connectTimeout = phase, headersTimeout = phase, provider = provider)
  var exchange: HttpClientRequestRef = nil
  var response: HttpClientResponseRef = nil
  try:
    var hops = 0
    while true:
      if not hopAllowed(hop.address, request.allowlist):
        return err("Network egress BLOCKED: host '" & hop.address.hostname &
                   "' not in allowlist" & (if hops > 0: " (redirect)" else: ""))
      ? readyToConnect(hop.address, expiresAt, proxied, request)
      exchange = HttpClientRequestRef.new(
        session, hop.address, hop.meth, headers = hop.headers,
        body = hop.body.toOpenArrayByte(0, hop.body.high))
      response = await exchange.send()
      ## Redirects are followed here, up to the limit: send() returns them.
      let location = response.headers.getString("location")
      if response.status notin 300 .. 399 or hops >= request.redirectLimit or
         location.len == 0:
        break
      let target = session.redirect(hop.address, parseUri(location)).valueOr:
        return err("redirect: " & error)
      if isDowngrade(hop.address, target):
        return err("redirect from https to http refused: " & location)
      hop = nextHop(hop, response.status, target)
      await response.closeWait()
      response = nil
      await exchange.closeWait()
      exchange = nil
      inc hops
    let bytes = await response.getBodyBytes()
    var reply = TransportResponse(status: response.status,
                                  body: newString(bytes.len))
    for i, b in bytes: reply.body[i] = char(b)
    for key, value in response.headers.stringItems():
      reply.headers.add((key, value))
    return ok(reply)
  except HttpError as e:
    return err(e.msg)
  finally:
    if response != nil: await response.closeWait()
    if exchange != nil: await exchange.closeWait()
    await session.closeWait()

proc runJob(job: TransportJob) =
  ## Runs only within what is left of the deadline. A job that waited in the
  ## queue past it is dropped: its caller was already told it failed, and
  ## sending it now (a POST, say) would act after that.
  let leftMs = int((job.expiresAt - nowNs()) div 1_000_000)
  if leftMs <= 0:
    job.reply.send(TransportReply.err(deadlineError(job.request)))
    return
  var reply: TransportReply
  try:
    reply = waitFor perform(job.request, job.expiresAt).wait(chronos.milliseconds(leftMs))
  except AsyncTimeoutError:
    reply = TransportReply.err(deadlineError(job.request))
  except CancelledError as e:
    reply = TransportReply.err("HTTP request cancelled: " & e.msg)
  except CatchableError as e:
    reply = TransportReply.err(e.msg)
  job.reply.send(reply)

proc transportWorker(arg: WorkerArg) {.thread.} =
  while true:
    var job: TransportJob
    gJobs[].waitPop(job)
    runJob(job)

proc ensurePool(): Result[void, string] {.gcsafe.} =
  ## Starts the workers once, from whichever thread asks first.
  withLock gPoolLock:
    if not gPoolStarted and $gPoolError == "":
      var started = 0
      for i in 0 ..< TransportWorkers:
        try:
          gWorkers[i] = spawnThread(transportWorker, WorkerArg(id: i))
          inc started
        except CatchableError as e:
          gPoolError = toFixed[256]("HTTP transport: cannot start workers: " & e.msg)
      if started > 0:
        gPoolStarted = true
        gPoolError = toFixed[256]("")
    if not gPoolStarted:
      return err($gPoolError)
  ok()

proc transportRequest*(request: TransportRequest): Result[TransportResponse, string] {.gcsafe.} =
  ## Performs `request` and returns its response, or an error no later than
  ## its deadline (plus a short grace for the worker's reply).
  ? ensurePool()
  let reply = newChan[TransportReply](1)
  let expiresAt = nowNs() + int64(request.deadlineOf) * 1_000_000
  ## threading's isolate/destroy of a job holding a Chan is not annotated
  ## with what it raises; nothing in the job can raise on destruction.
  {.push warning[Effect]: off.}
  let queued = gJobs[].push(TransportJob(request: request, expiresAt: expiresAt,
                                         reply: reply))
  {.pop.}
  if not queued:
    return err("HTTP transport saturated: " & $TransportQueueDepth & " requests queued")
  ## Monotonic: a wall-clock step back must not stretch the wait.
  let giveUpAt = expiresAt + int64(ReplyGraceMs) * 1_000_000
  while true:
    var received: TransportReply  ## fresh each time: see EventQueue.tryPop
    if reply.tryRecv(received):
      return received
    if nowNs() >= giveUpAt:
      return err(deadlineError(request))
    sleep(5)
