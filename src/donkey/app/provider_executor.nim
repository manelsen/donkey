## Provider executor — runs blocking provider calls on a fixed worker pool.
##
## A fixed set of worker threads consumes `ProviderJob` messages from a shared
## `Channel`. Each job carries only plain data (`ProviderBundle` built on the
## event loop + `CompletionRequest`) plus a pointer to a shared, reference
## counted control block owned jointly by the awaiting coroutine and the
## worker. The session closure and routing state never cross the thread
## boundary; selection and routing hooks stay on the Chronos event loop.
##
## Builder ownership rule
## ----------------------
## `ProviderRuntimeBuilder` is declared `{.nimcall.}`, so it cannot capture an
## environment. `asyncProviderComplete` still runs it on the event loop thread
## before enqueuing and sends only the resulting `ProviderBundle`. The bundle's
## `completeFn`/`streamFn` closures are freshly constructed by the builder and
## are owned exclusively by the job after the channel transfer, so no builder
## environment is shared with workers or with other in-flight calls.
##
## GC-managed values only cross the thread boundary through a Nim `Channel`:
##
## 1. Job input (`ProviderBundle`, `CompletionRequest`) travels through
##    `Channel[ProviderJob]`.
## 2. The result (`Result[CompletionResponse, string]`, which owns strings and
##    sequences) travels through a per-job `Channel[Result[...]]`.
##
## Under `--mm:orc` + `--threads:on` a channel performs a synchronized
## ownership transfer: the producer's value is bitwise moved into shared
## channel storage and `wasMoved` at the source, then moved out on the
## consumer's side. That is Nim's supported mechanism for moving GC-managed
## values between threads.
##
## Control block and cancellation
## ------------------------------
## `ProviderJobState` is allocated with `allocShared0` and is reference
## counted:
##
## - The caller starts with one reference (`refs = 1`).
## - Before a successful `trySend` the count is raised to 2 (caller + worker).
##   If the send fails it stays at 1 and the caller frees the block.
## - The worker drops its reference when the job finishes (result sent, or job
##   skipped because it was cancelled).
## - The caller drops its reference in its `finally` block.
##
## The reference that decrements `refs` to 0 is the last owner: it drains any
## value left in the result channel (destroying it on its own thread), closes
## the channel, deinitializes the lock and frees the block. Only the lock and
## the plain scalar fields are touched under the lock; the result is never
## copied directly into this slot because ARC/ORC reference counting is not
## atomic (the project does not build with `--mm:atomicArc`).
##
## Cancellation is non-blocking. The caller sets `cancelled` under the lock
## and returns immediately; the worker notices it (before calling the provider
## or after it returns) and discards the result locally instead of sending it
## into a channel whose consumer may be gone. The refcount guarantees the
## block outlives every thread that still holds a reference, so there is no
## use-after-free and no need to wait for the in-flight provider call.
##
## Ordering: the worker writes the result into the channel first and only then
## publishes `done` under the lock. A caller that observes `done` therefore
## knows the send completed, and is the only consumer of the channel.

import std/locks
import chronos
import ../core/pipeops
import ../ports/provider
import ../domain/message

const
  ProviderWorkerCount* = 4
  ProviderQueueDepth* = 64
  ProviderPollIntervalMs = 10
  ProviderResultChannelDepth = 1

type
  AsyncCompleteFn* = proc(req: CompletionRequest):
      Future[Result[CompletionResponse, string]] {.gcsafe.}

  ProviderJobState = object
    ## Shared-heap control block; see the module header.
    lock:      Lock
    cancelled: bool
    done:      bool
    refs:      int
    results:   Channel[Result[CompletionResponse, string]]

  ProviderJob = object
    bundle: ProviderBundle
    req:    CompletionRequest
    state:  ptr ProviderJobState

var
  gProviderQueue {.global.}: Channel[ProviderJob]
  gProviderWorkers {.global.}: array[ProviderWorkerCount, Thread[void]]
  gProviderPoolStarted = false
  gProviderPoolAttempted = false

proc releaseJobState(state: ptr ProviderJobState) {.gcsafe.} =
  ## Drops one reference to the control block. The owner that drops the last
  ## reference drains any leftover result, closes the channel, destroys the
  ## lock and frees the block. No other thread can touch `state` afterwards.
  acquire(state[].lock)
  dec state[].refs
  let remaining = state[].refs
  release(state[].lock)
  if remaining > 0:
    return

  let leftover = state[].results.tryRecv()
  if leftover.dataAvailable:
    discard leftover.msg
  state[].results.close()
  deinitLock(state[].lock)
  deallocShared(state)

proc callProvider(bundle: sink ProviderBundle; req: sink CompletionRequest
                 ): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try:
    if bundle.completeFn == nil:
      return err("provider unavailable")
    bundle.completeFn(req)
  except Exception as e:
    err(e.msg)

proc completeJob(job: sink ProviderJob) {.gcsafe.} =
  let state = job.state

  acquire(state[].lock)
  let cancelled = state[].cancelled
  release(state[].lock)
  if cancelled:
    # The caller is gone; nothing may be sent into its channel.
    releaseJobState(state)
    return

  var value = callProvider(move(job.bundle), move(job.req))

  acquire(state[].lock)
  let cancelledAfter = state[].cancelled
  release(state[].lock)
  if cancelledAfter:
    # Discard the GC-managed result on this thread; the channel has no
    # consumer left.
    releaseJobState(state)
    return

  # Ownership of the GC-managed result moves into the channel's shared
  # storage; see the module header.
  state[].results.send(value)

  # Published only after the send completed. The caller treats `done` as
  # "the result is available in the channel".
  acquire(state[].lock)
  state[].done = true
  release(state[].lock)
  releaseJobState(state)

proc providerWorker() {.thread.} =
  while true:
    completeJob(gProviderQueue.recv())

proc ensureProviderPool(): Result[void, string] =
  ## Called from the Chronos event loop thread only. Marks the pool ready only
  ## after at least one worker started; a failed attempt is not retried, so a
  ## later call cannot enqueue into a queue with no consumers.
  if gProviderPoolStarted:
    return ok()
  if gProviderPoolAttempted:
    return err(Result[void, string],
               "provider executor: worker pool initialization already failed")
  gProviderPoolAttempted = true
  try:
    gProviderQueue.open(ProviderQueueDepth)
  except CatchableError as e:
    return err(Result[void, string],
               "provider executor: cannot open queue: " & e.msg)
  var started = 0
  var firstError = ""
  for i in 0 ..< ProviderWorkerCount:
    try:
      createThread(gProviderWorkers[i], providerWorker)
      inc started
    except CatchableError as e:
      if firstError.len == 0:
        firstError = e.msg
  if started == 0:
    return err(Result[void, string],
               "provider executor: no workers started: " & firstError)
  gProviderPoolStarted = true
  ok()

proc providerPoolReady*(): bool =
  ## True once the worker pool has been lazily started.
  gProviderPoolStarted

proc takeResult(state: ptr ProviderJobState): Result[CompletionResponse, string] =
  ## Called only after `done` was observed, so the channel holds exactly one
  ## result for an uncancelled job.
  let received = state[].results.tryRecv()
  if received.dataAvailable:
    return received.msg
  err(Result[CompletionResponse, string],
      "provider executor: result missing for completed job")

proc asyncProviderComplete*(builder: ProviderRuntimeBuilder;
                            spec: ProviderSpec;
                            req: sink CompletionRequest
                           ): Future[Result[CompletionResponse, string]] {.async.} =
  ## Runs `builder` on the event loop, then enqueues the resulting bundle for
  ## a worker thread and awaits its result. Cancellation marks the job
  ## cancelled without waiting for the worker; see the module header.
  let pool = ensureProviderPool()
  if pool.isErr:
    return err(Result[CompletionResponse, string], pool.error)

  # The builder may capture event-loop state, so it must not run on a worker.
  var bundle: ProviderBundle
  try:
    bundle = builder(spec)
  except CatchableError as e:
    return err(Result[CompletionResponse, string],
               "provider executor: builder failed: " & e.msg)
  except Exception as e:
    return err(Result[CompletionResponse, string],
               "provider executor: builder failed: " & e.msg)

  if bundle.completeFn == nil:
    return err(Result[CompletionResponse, string],
               "provider unavailable: " & spec.providerName)

  let state = cast[ptr ProviderJobState](allocShared0(sizeof(ProviderJobState)))
  if state == nil:
    return err(Result[CompletionResponse, string],
               "provider executor: out of memory")
  initLock(state[].lock)
  state[].refs = 1
  try:
    state[].results.open(ProviderResultChannelDepth)
  except CatchableError as e:
    deinitLock(state[].lock)
    deallocShared(state)
    return err(Result[CompletionResponse, string],
               "provider executor: cannot open result channel: " & e.msg)

  # Caller + (future) worker. Set before the send so a worker that dequeues
  # immediately already has its reference accounted for.
  state[].refs = 2
  var job = ProviderJob(bundle: move(bundle), req: move(req), state: state)
  if not gProviderQueue.trySend(job):
    state[].refs = 1
    releaseJobState(state)
    return err(Result[CompletionResponse, string],
               "provider executor saturated: queue full (" &
               $ProviderQueueDepth & ")")

  var completed = false
  try:
    while true:
      acquire(state[].lock)
      let done = state[].done
      release(state[].lock)
      if done:
        let value = takeResult(state)
        completed = true
        return value
      await sleepAsync(milliseconds(ProviderPollIntervalMs))
  finally:
    if not completed:
      acquire(state[].lock)
      let done = state[].done
      if not done:
        # Do not wait for the worker: it holds its own reference and will
        # notice the flag and clean up.
        state[].cancelled = true
      release(state[].lock)
      if done:
        # The worker published a result, but this coroutine never consumed
        # it. Drain it here so the GC-managed payload is destroyed on the
        # caller's thread instead of inside closed channel storage.
        let leftover = state[].results.tryRecv()
        if leftover.dataAvailable:
          discard leftover.msg
    releaseJobState(state)
