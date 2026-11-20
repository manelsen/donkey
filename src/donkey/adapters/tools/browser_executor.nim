## The daemon's CDP connections and subprocesses have one owner thread.
## Only the request and result cross the channel. Chronos can continue
## processing messages while the browser is starting or loading a page.

import std/[atomics, json, sequtils]
import chronos
import chronos/asyncsync
import ../../core/pipeops
import ../../domain/tools/browser_pure
import ../../ports/tool
import ../http/std_http
import ./browser

type
  BrowserJobKind = enum bjConfigure, bjInvoke, bjEvictIdle, bjStop

  BrowserJob = object
    case kind: BrowserJobKind
    of bjConfigure:
      backend: BrowserBackendKind
      executablePath, profileBaseDir, proxyServer: string
      port, timeoutMs: int
    of bjInvoke:
      id, name, inputJson, userId: string
    of bjEvictIdle, bjStop:
      discard

  BrowserWorkerState = object
    jobs: Channel[BrowserJob]
    replies: Channel[Result[ToolResult, string]]
    abort: Atomic[bool]
    exited: Atomic[bool]

  BrowserExecutor* = ref object
    worker: Thread[ptr BrowserWorkerState]
    state: ptr BrowserWorkerState
    lock: AsyncLock
    pending: bool
    closing: bool

const BrowserPollInterval = milliseconds(20)

proc browserWorker(state: ptr BrowserWorkerState) {.thread.} =
  let config = state[].jobs.recv()
  # Discovery polls a loopback endpoint during Chromium startup. Connection
  # refusals here must never open the HTTP adapter's circuit breaker.
  let http = newStdHttpAdapter(
    timeout = 2, maxRetries = 1, circuitBreaker = false).toRuntimePort()
  let runtime = newBrowserToolRuntime(
    backend = config.backend, executablePath = config.executablePath,
    profileBaseDir = config.profileBaseDir, proxyServer = config.proxyServer,
    port = config.port, timeoutMs = config.timeoutMs, http = http,
    shouldStop = proc(): bool {.gcsafe, raises: [].} = state[].abort.load())
  defer:
    discard runtime.close()
    state[].exited.store(true)
  while true:
    let job = state[].jobs.recv()
    case job.kind
    of bjInvoke:
      let reply =
        try:
          runtime.invoke(ToolCall(id: job.id, name: job.name,
            input: parseJson(job.inputJson), userId: job.userId))
        except CatchableError as e:
          discard runtime.closeUser(job.userId)
          err(Result[ToolResult, string], e.msg)
      state[].replies.send(reply)
    of bjEvictIdle:
      runtime.evictIdle()
    of bjStop:
      break
    of bjConfigure:
      discard

proc freeChannels(state: ptr BrowserWorkerState) =
  state[].jobs.close()
  state[].replies.close()
  deallocShared(state)

proc newBrowserExecutor*(backend: BrowserBackendKind; executablePath,
                         profileBaseDir, proxyServer: string; timeoutMs: int;
                         port = DefaultLightpandaPort): BrowserExecutor =
  let state = cast[ptr BrowserWorkerState](allocShared0(sizeof(BrowserWorkerState)))
  state[].jobs.open(2)
  state[].replies.open(1)
  state[].jobs.send(BrowserJob(kind: bjConfigure, backend: backend,
    executablePath: executablePath, profileBaseDir: profileBaseDir,
    proxyServer: proxyServer, port: port, timeoutMs: timeoutMs))
  result = BrowserExecutor(state: state, lock: newAsyncLock())
  try:
    createThread(result.worker, browserWorker, state)
  except CatchableError:
    freeChannels(state)
    raise

proc takeReply(executor: BrowserExecutor):
               Future[Result[ToolResult, string]] {.async.} =
  while not executor.closing:
    let reply = executor.state[].replies.tryRecv()
    if reply.dataAvailable:
      executor.pending = false
      return reply.msg
    await sleepAsync(BrowserPollInterval)
  return err(Result[ToolResult, string], "browser is shutting down")

proc invoke(executor: BrowserExecutor; call: ToolCall):
            Future[Result[ToolResult, string]] {.async.} =
  await executor.lock.acquire()
  defer: executor.lock.release()
  if executor.pending:
    # An interrupted turn may have left a reply in flight. Drain that
    # reply before sending another call. It belongs to the interrupted turn.
    discard await executor.takeReply()
  while not executor.closing:
    executor.state[].abort.store(false)
    if executor.state[].jobs.trySend(BrowserJob(kind: bjInvoke, id: call.id,
        name: call.name, inputJson: $call.input, userId: call.userId)):
      executor.pending = true
      try:
        return await executor.takeReply()
      finally:
        if executor.pending and not executor.closing:
          executor.state[].abort.store(true)
    await sleepAsync(BrowserPollInterval)
  return err(Result[ToolResult, string], "browser is shutting down")

proc evictIdle*(executor: BrowserExecutor) =
  if not executor.closing and not executor.pending:
    discard executor.state[].jobs.trySend(BrowserJob(kind: bjEvictIdle))

proc stop*(executor: BrowserExecutor) {.async.} =
  if executor.closing:
    return
  executor.closing = true
  executor.state[].abort.store(true)
  while not executor.state[].jobs.trySend(BrowserJob(kind: bjStop)):
    await sleepAsync(BrowserPollInterval)
  while not executor.state[].exited.load():
    await sleepAsync(BrowserPollInterval)
  joinThread(executor.worker)
  freeChannels(executor.state)
  executor.state = nil

proc toRuntimePort*(executor: BrowserExecutor): ToolRuntimePort =
  let schemas = BrowserTools().listTools().get()
  let names = schemas.mapIt(it.name)
  ToolRuntimePort(
    listTools: proc(): Result[seq[ToolSchema], string] {.gcsafe.} = ok(schemas),
    invokeAsync: proc(call: ToolCall): Future[Result[ToolResult, string]] {.async.} =
      if call.name notin names:
        return err(Result[ToolResult, string], "unknown browser tool: " & call.name)
      let reply = await executor.invoke(call)
      if reply.isErr:
        return ok(ToolResult(callId: call.id, output: $(%*{"error": reply.error}),
                             isError: true))
      return reply,
  )
