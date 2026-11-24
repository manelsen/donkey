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
## full), generalised to `string -> Result[string, string]`:
##
## - the result travels through a per-job `Channel`, which moves GC-managed
##   values between threads;
## - a shared, reference-counted control block lets the caller cancel
##   without waiting: the worker sees the flag and drops its result; the
##   last reference frees the block.

import std/locks
import chronos
import ../core/pipeops
import ../infra/thread_handle

const
  BlockingWorkerCount* = 4
  BlockingQueueDepth* = 128
  BlockingPollIntervalMs = 5

type
  BlockingFn* = proc(input: string): Result[string, string] {.nimcall, gcsafe, raises: [].}
    ## Runs on a worker. `nimcall`: it captures nothing from the loop.

  BlockingJobState = object
    lock:      Lock
    cancelled: bool
    done:      bool
    refs:      int
    results:   Channel[Result[string, string]]

  BlockingJob = object
    fn:    BlockingFn
    input: string
    state: ptr BlockingJobState

static:
  doAssert sharesNothing(BlockingJob),
    "BlockingJob must hold plain data only: it crosses to a worker thread"

var
  gBlockingQueue {.global.}: Channel[BlockingJob]
  gBlockingWorkers {.global.}: array[BlockingWorkerCount, Thread[void]]
  gBlockingPoolStarted = false
  gBlockingPoolAttempted = false

proc releaseState(state: ptr BlockingJobState) {.gcsafe.} =
  ## Drops one reference; the last owner drains, closes and frees.
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

proc runJob(job: sink BlockingJob) {.gcsafe.} =
  let state = job.state
  acquire(state[].lock)
  let cancelled = state[].cancelled
  release(state[].lock)
  if cancelled:
    releaseState(state)
    return
  var value =
    try:
      job.fn(job.input)
    except Exception as e:  ## effect boundary: callee raises are unannotated
      err(Result[string, string], "blocking job raised: " & e.msg)
  acquire(state[].lock)
  let cancelledAfter = state[].cancelled
  release(state[].lock)
  if cancelledAfter:
    releaseState(state)
    return
  state[].results.send(value)
  acquire(state[].lock)
  state[].done = true
  release(state[].lock)
  releaseState(state)

proc blockingWorker() {.thread.} =
  while true:
    runJob(gBlockingQueue.recv())

proc ensurePool(): Result[void, string] =
  ## Loop thread only. A failed start is not retried, so nothing is queued
  ## where no worker will read it.
  if gBlockingPoolStarted:
    return ok()
  if gBlockingPoolAttempted:
    return err("blocking executor: worker pool failed to start")
  gBlockingPoolAttempted = true
  try:
    gBlockingQueue.open(BlockingQueueDepth)
  except CatchableError as e:
    return err("blocking executor: cannot open queue: " & e.msg)
  var started = 0
  var firstError = ""
  for i in 0 ..< BlockingWorkerCount:
    try:
      createThread(gBlockingWorkers[i], blockingWorker)
      inc started
    except CatchableError as e:
      if firstError.len == 0:
        firstError = e.msg
  if started == 0:
    return err("blocking executor: no workers started: " & firstError)
  gBlockingPoolStarted = true
  ok()

proc runOffLoop*(fn: BlockingFn; input: string): Future[Result[string, string]] {.async.} =
  ## Runs `fn(input)` on a worker and awaits the result. Cancelling the
  ## future marks the job cancelled and returns at once.
  if fn == nil:
    return err(Result[string, string], "blocking executor: no function")
  let pool = ensurePool()
  if pool.isErr:
    return err(Result[string, string], pool.error)
  let state = cast[ptr BlockingJobState](allocShared0(sizeof(BlockingJobState)))
  if state == nil:
    return err(Result[string, string], "blocking executor: out of memory")
  initLock(state[].lock)
  state[].refs = 1
  try:
    state[].results.open(1)
  except CatchableError as e:
    deinitLock(state[].lock)
    deallocShared(state)
    return err(Result[string, string], "blocking executor: cannot open result channel: " & e.msg)
  state[].refs = 2
  var job = BlockingJob(fn: fn, input: input, state: state)
  if not gBlockingQueue.trySend(job):
    state[].refs = 1
    releaseState(state)
    return err(Result[string, string],
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
        return err(Result[string, string], "blocking executor: result missing")
      await sleepAsync(milliseconds(BlockingPollIntervalMs))
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
