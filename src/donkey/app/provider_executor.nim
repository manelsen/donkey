## Provider executor — runs blocking provider calls on a fixed worker pool.
##
## A fixed set of worker threads consumes `ProviderJob` messages from a shared
## `Channel`. Each job carries only plain data (`ProviderSpec` +
## `CompletionRequest`), a gcsafe builder proc, and a pointer to a per-call
## result slot owned by the awaiting coroutine. The session closure and routing
## state never cross the thread boundary; selection and routing hooks stay on
## the Chronos event loop.
##
## Ownership / cancellation
## -------------------------
## The result slot lives on the caller's stack and is protected by a lock. A
## worker marks `done` only *after* writing the result, or after skipping a
## cancelled job. The caller never returns or unwinds its stack frame before
## observing `done` (the `finally` block waits for it), so a worker can never
## write to a freed slot.
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

type
  AsyncCompleteFn* = proc(req: CompletionRequest):
      Future[Result[CompletionResponse, string]] {.gcsafe.}

  ProviderJobState = object
    ## One per call; owned by the awaiting coroutine's stack frame.
    lock:      Lock
    cancelled: bool
    done:      bool
    value:     Result[CompletionResponse, string]

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

  acquire(job.state[].lock)
  job.state[].value = value
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
  let job = ProviderJob(builder: builder, spec: spec, req: req, state: addr state)
  if not gProviderQueue.trySend(job):
    deinitLock(state.lock)
    return err(Result[CompletionResponse, string],
               "provider executor saturated: queue full (" &
               $ProviderQueueDepth & ")")

  try:
    while true:
      acquire(state.lock)
      let done = state.done
      var value: Result[CompletionResponse, string]
      if done:
        value = state.value
      release(state.lock)
      if done:
        return value
      await sleepAsync(milliseconds(ProviderPollIntervalMs))
  finally:
    acquire(state.lock)
    var done = state.done
    if not done:
      state.cancelled = true
    release(state.lock)

    # Never leave the frame while a worker still holds a pointer to `state`.
    # Blocking here matches the old joinThread() cancellation semantics.
    while not done:
      sleep(1)
      acquire(state.lock)
      done = state.done
      release(state.lock)
    deinitLock(state.lock)
