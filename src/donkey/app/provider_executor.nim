## Provider executor — runs blocking provider calls on a fixed worker pool.
##
## A fixed set of worker threads consumes `ProviderJob` messages from a shared
## `Channel`. Each job carries only plain data (`ProviderSpec` +
## `CompletionRequest`), a gcsafe builder proc, and a pointer to a per-call
## control block owned by the awaiting coroutine. The session closure and
## routing state never cross the thread boundary; selection and routing hooks
## stay on the Chronos event loop.
##
## Ownership rule
## --------------
## GC-managed values only cross the thread boundary through a Nim `Channel`:
##
## 1. Job input (`ProviderSpec`, `CompletionRequest`, the builder closure)
##    travels through `Channel[ProviderJob]`.
## 2. The result (`Result[CompletionResponse, string]`, which owns strings and
##    sequences) travels through a per-job `Channel[Result[...]]`.
##
## Under `--mm:orc` + `--threads:on` a channel performs a synchronized
## ownership transfer: the producer's value is bitwise moved into shared
## channel storage and `wasMoved` at the source, then moved out on the
## consumer's side. That is Nim's supported mechanism for moving GC-managed
## values between threads.
##
## `ProviderJobState` itself contains only a `Lock` and two booleans. These are
## plain scalars and are read/written exclusively under the lock. The result is
## deliberately *not* copied directly into this slot: ARC/ORC reference
## counting is not atomic (the project does not build with `--mm:atomicArc`),
## so a direct `=sink`/`=copy` of a GC-managed value into another thread's
## frame is outside the documented memory model even when a lock serialises
## access. The channel transfer avoids that question entirely.
##
## Ordering: the worker writes the result into the channel first and only then
## publishes `done` under the lock. A caller that observes `done` therefore
## knows the send completed, and is the only consumer of the channel.
##
## Ownership / cancellation
## -------------------------
## The control block lives in the caller's coroutine frame. The caller never
## returns or unwinds before observing `done` (the `finally` block waits for
## it), so a worker can never touch a freed control block or channel. On
## cancellation the caller drains any result the worker already produced (its
## strings are destroyed on the caller's thread rather than leaked inside
## channel storage) and then closes the channel.
##
## Consequence: cancelling a call that a worker already started waits for that
## provider call to finish, exactly like the previous thread-per-call design
## (`joinThread` in `finally`). Cancelling a job that is still queued waits for
## a worker to dequeue and acknowledge it; with all workers busy on long calls
## that can take as long as the slowest in-flight call. This is a deliberate
## trade-off: reclaiming the slot earlier would require heap-allocated slots
## with cross-thread ownership, which is harder to prove safe under ORC.

import std/[locks, os]
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
    ## One per call; owned by the awaiting coroutine's frame.
    ## Only the lock and the flags are written directly across threads.
    lock:      Lock
    cancelled: bool
    done:      bool
    results:   Channel[Result[CompletionResponse, string]]

  ProviderJob = object
    builder: ProviderRuntimeBuilder
    spec:    ProviderSpec
    req:     CompletionRequest
    state:   ptr ProviderJobState

var
  gProviderQueue {.global.}: Channel[ProviderJob]
  gProviderWorkers {.global.}: array[ProviderWorkerCount, Thread[void]]
  gProviderPoolStarted = false

proc callProvider(builder: ProviderRuntimeBuilder; spec: ProviderSpec;
                  req: CompletionRequest
                 ): Result[CompletionResponse, string] {.gcsafe, raises: [].} =
  try:
    let bundle = builder(spec)
    if bundle.completeFn == nil:
      return err("provider unavailable: " & spec.providerName)
    bundle.completeFn(req)
  except Exception as e:
    err(e.msg)

proc completeJob(job: ProviderJob) {.gcsafe.} =
  acquire(job.state[].lock)
  let cancelled = job.state[].cancelled
  release(job.state[].lock)

  var value: Result[CompletionResponse, string]
  if cancelled:
    value = err(Result[CompletionResponse, string], "provider job cancelled")
  else:
    value = callProvider(job.builder, job.spec, job.req)

  # Ownership of the GC-managed result moves into the channel's shared
  # storage; see the module header.
  job.state[].results.send(value)

  # Published only after the send completed. The caller treats `done` as
  # "the worker will not touch this slot again".
  acquire(job.state[].lock)
  job.state[].done = true
  release(job.state[].lock)

proc providerWorker() {.thread.} =
  while true:
    completeJob(gProviderQueue.recv())

proc ensureProviderPool() =
  ## Called from the Chronos event loop thread only.
  if gProviderPoolStarted:
    return
  gProviderPoolStarted = true
  gProviderQueue.open(ProviderQueueDepth)
  for i in 0 ..< ProviderWorkerCount:
    createThread(gProviderWorkers[i], providerWorker)

proc providerPoolReady*(): bool =
  ## True once the worker pool has been lazily started.
  gProviderPoolStarted

proc takeResult(state: var ProviderJobState): Result[CompletionResponse, string] =
  ## Called only after `done` was observed, so the channel holds exactly one
  ## result (the worker always sends one, including for cancelled jobs).
  let received = state.results.tryRecv()
  if received.dataAvailable:
    return received.msg
  err(Result[CompletionResponse, string],
      "provider executor: result missing for completed job")

proc asyncProviderComplete*(builder: ProviderRuntimeBuilder;
                            spec: ProviderSpec;
                            req: CompletionRequest
                           ): Future[Result[CompletionResponse, string]] {.async.} =
  ## Enqueues one provider call for a worker thread and awaits its result.
  ## On cancellation the slot is marked cancelled and the caller waits until
  ## the worker acknowledges, so the slot cannot be freed under the thread.
  ensureProviderPool()

  var state: ProviderJobState
  initLock(state.lock)
  state.results.open(ProviderResultChannelDepth)
  let job = ProviderJob(builder: builder, spec: spec, req: req, state: addr state)
  if not gProviderQueue.trySend(job):
    state.results.close()
    deinitLock(state.lock)
    return err(Result[CompletionResponse, string],
               "provider executor saturated: queue full (" &
               $ProviderQueueDepth & ")")

  try:
    while true:
      acquire(state.lock)
      let done = state.done
      release(state.lock)
      if done:
        return takeResult(state)
      await sleepAsync(milliseconds(ProviderPollIntervalMs))
  finally:
    acquire(state.lock)
    var done = state.done
    if not done:
      state.cancelled = true
    release(state.lock)

    # Never leave the frame while a worker still references `state`.
    # Blocking here matches the old joinThread() cancellation semantics.
    while not done:
      sleep(1)
      acquire(state.lock)
      done = state.done
      release(state.lock)

    # Destroy a result the worker produced but this coroutine never consumed;
    # Channel.close() frees storage without running element destructors.
    let leftover = state.results.tryRecv()
    if leftover.dataAvailable:
      discard leftover.msg
    state.results.close()
    deinitLock(state.lock)
