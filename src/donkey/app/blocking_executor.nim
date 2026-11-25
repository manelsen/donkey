## blocking_executor.nim — any blocking call, off the Chronos loop.
##
## The HTTP stack blocks its caller until the request's deadline. On the
## daemon's loop that stalls every session while it waits, so calls made on
## every message (Backtrail's classification, recall's query embedding) run
## here instead: a fixed pool of worker threads takes jobs from a queue and
## the caller awaits the result.
##
## A job is plain data: a `nimcall` function and a string. The function
## builds whatever closures it needs (an HTTP adapter, a provider) on the
## worker, so no closure or `ref` built on the loop crosses the thread
## boundary (`sharesNothing` checks it at compile time). The design is the
## provider executor's (app/provider_executor, whose header explains it in
## full), generalised to `I -> Result[O, string]`:
##
## - input and result travel through per-job `Channel`s, which copy
##   GC-managed values between threads; any plain type works (`OffLoopFn[I,
##   O]`), so a channel's poll returns its own messages without a codec;
## - a shared, reference-counted control block lets the caller cancel
##   without waiting: the worker sees the flag and drops its result; the
##   last reference frees the block.

import std/locks
import chronos
import ../core/pipeops
import ../infra/thread_handle

const
  BlockingWorkerCount* = 4
    ## Per-message calls (Backtrail, recall's embedding, channel polls).
  StreamWorkerCount* = 8
    ## Streamed replies, which hold a worker for their whole length: their
    ## own pool, so they can never take the workers calls need.
  BlockingQueueDepth* = 128
  BlockingPollIntervalMs = 5

type
  OffLoopFn*[I, O] = proc(input: I): Result[O, string] {.nimcall, gcsafe, raises: [].}
    ## Runs on a worker. `nimcall`: it captures nothing from the loop.
    ## `I` and `O` are plain data (`sharesNothing`), copied across.

  BlockingFn* = OffLoopFn[string, string]

  OffLoopPool* = enum
    opBlocking  ## short calls
    opStream    ## streamed replies

  BlockingJobState[I, O] = object
    lock:      Lock
    cancelled: bool
    done:      bool
    refs:      int
    fn:        OffLoopFn[I, O]
    inputs:    Channel[I]
    results:   Channel[Result[O, string]]

  BlockingJob = object
    ## What the queue carries: a typed runner, erased to one shape so one
    ## pool serves every job type. `state` is a `ptr BlockingJobState[I, O]`
    ## that only the matching `runJob[I, O]` reads.
    run:   proc(state: pointer) {.nimcall, gcsafe, raises: [].}
    state: pointer

static:
  doAssert sharesNothing(BlockingJob),
    "BlockingJob must hold plain data only: it crosses to a worker thread"

var
  gQueues {.global.}: array[OffLoopPool, Channel[BlockingJob]]
  gBlockingWorkers {.global.}: array[BlockingWorkerCount, Thread[OffLoopPool]]
  gStreamWorkers {.global.}: array[StreamWorkerCount, Thread[OffLoopPool]]
  gPoolStarted: array[OffLoopPool, bool]
  gPoolAttempted: array[OffLoopPool, bool]
  gPoolWorkers: array[OffLoopPool, int]   ## workers that actually started

proc releaseState[I, O](state: ptr BlockingJobState[I, O]) {.gcsafe.} =
  ## Drops one reference; the last owner drains, closes and frees.
  acquire(state[].lock)
  dec state[].refs
  let remaining = state[].refs
  release(state[].lock)
  if remaining > 0:
    return
  let input = state[].inputs.tryRecv()
  if input.dataAvailable:
    discard input.msg
  let leftover = state[].results.tryRecv()
  if leftover.dataAvailable:
    discard leftover.msg
  state[].inputs.close()
  state[].results.close()
  deinitLock(state[].lock)
  deallocShared(state)

proc isCancelled[I, O](state: ptr BlockingJobState[I, O]): bool {.gcsafe.} =
  acquire(state[].lock)
  result = state[].cancelled
  release(state[].lock)

proc runJob[I, O](p: pointer) {.nimcall, gcsafe, raises: [].} =
  let state = cast[ptr BlockingJobState[I, O]](p)
  if state.isCancelled:
    releaseState(state)
    return
  let input = state[].inputs.tryRecv()
  var value =
    if not input.dataAvailable:
      err(Result[O, string], "blocking executor: input missing")
    else:
      try:
        state[].fn(input.msg)
      except Exception as e:  ## effect boundary: callee raises are unannotated
        err(Result[O, string], "blocking job raised: " & e.msg)
  if state.isCancelled:
    releaseState(state)
    return
  state[].results.send(value)
  acquire(state[].lock)
  state[].done = true
  release(state[].lock)
  releaseState(state)

proc poolWorker(pool: OffLoopPool) {.thread.} =
  while true:
    let job = gQueues[pool].recv()
    job.run(job.state)

proc ensurePool(pool: OffLoopPool): Result[void, string] =
  ## Loop thread only. A failed start is not retried, so nothing is queued
  ## where no worker will read it.
  if gPoolStarted[pool]:
    return ok()
  if gPoolAttempted[pool]:
    return err("blocking executor: " & $pool & " pool failed to start")
  gPoolAttempted[pool] = true
  try:
    gQueues[pool].open(BlockingQueueDepth)
  except CatchableError as e:
    return err("blocking executor: cannot open queue: " & e.msg)
  var started = 0
  var firstError = ""
  let count = if pool == opStream: StreamWorkerCount else: BlockingWorkerCount
  for i in 0 ..< count:
    try:
      if pool == opStream: createThread(gStreamWorkers[i], poolWorker, pool)
      else: createThread(gBlockingWorkers[i], poolWorker, pool)
      inc started
    except CatchableError as e:
      if firstError.len == 0:
        firstError = e.msg
  if started == 0:
    return err("blocking executor: no workers started: " & firstError)
  gPoolWorkers[pool] = started
  gPoolStarted[pool] = true
  ok()

proc poolCapacity*(pool: OffLoopPool): int =
  ## How many jobs the pool runs at once: the workers that started (a
  ## partial start gives fewer), or the configured size before first use.
  if gPoolStarted[pool]: gPoolWorkers[pool]
  elif gPoolAttempted[pool]: 0
  elif pool == opStream: StreamWorkerCount
  else: BlockingWorkerCount

proc awaitOffLoop[I, O](fn: OffLoopFn[I, O]; input: I;
                        pool: OffLoopPool): Future[Result[O, string]] {.async.} =
  if fn == nil:
    return err(Result[O, string], "blocking executor: no function")
  let started = ensurePool(pool)
  if started.isErr:
    return err(Result[O, string], started.error)
  let state = cast[ptr BlockingJobState[I, O]](allocShared0(sizeof(BlockingJobState[I, O])))
  if state == nil:
    return err(Result[O, string], "blocking executor: out of memory")
  initLock(state[].lock)
  state[].refs = 1
  state[].fn = fn
  try:
    state[].inputs.open(1)
    state[].results.open(1)
  except CatchableError as e:
    releaseState(state)
    return err(Result[O, string], "blocking executor: cannot open channels: " & e.msg)
  state[].inputs.send(input)
  state[].refs = 2
  let job = BlockingJob(run: runJob[I, O], state: state)
  if not gQueues[pool].trySend(job):
    state[].refs = 1
    releaseState(state)
    return err(Result[O, string],
               "blocking executor saturated: queue full (" & $BlockingQueueDepth & ")")
  var completed = false
  try:
    while true:
      acquire(state[].lock)
      let done = state[].done
      release(state[].lock)
      if done:
        let received = state[].results.tryRecv()
        completed = true
        if received.dataAvailable:
          return received.msg
        return err(Result[O, string], "blocking executor: result missing")
      await sleepAsync(chronos.milliseconds(BlockingPollIntervalMs))
  finally:
    if not completed:
      acquire(state[].lock)
      let done = state[].done
      if not done:
        state[].cancelled = true
      release(state[].lock)
      if done:
        let leftover = state[].results.tryRecv()
        if leftover.dataAvailable:
          discard leftover.msg
    releaseState(state)

proc runOffLoop*[I, O](fn: OffLoopFn[I, O]; input: I;
                       pool = opBlocking): Future[Result[O, string]] =
  ## Runs `fn(input)` on a worker and awaits the result. Cancelling the
  ## future marks the job cancelled and returns at once. `I` and `O` must
  ## hold no `ref` and no closure: refused at compile time.
  when not sharesNothing(I):
    {.error: "runOffLoop: the input type holds a ref or a closure".}
  when not sharesNothing(O):
    {.error: "runOffLoop: the result type holds a ref or a closure".}
  awaitOffLoop(fn, input, pool)
