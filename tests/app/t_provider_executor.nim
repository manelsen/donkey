## Provider executor tests.
##
## The executor is a fixed worker pool: jobs are queued on a shared channel and
## consumed by a bounded number of OS threads. These tests cover sequential and
## concurrent calls, error propagation, and the documented cancellation
## behaviour (a cancelled in-flight call waits for the worker to acknowledge
## before the caller's result slot is released).

import std/[os, strutils, unittest]
import chronos
import donkey/app/provider_executor
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/provider

proc stubBuilder(text: string; delayMs = 0): ProviderRuntimeBuilder =
  result = proc(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
    let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
      if delayMs > 0:
        sleep(delayMs)
      ok(CompletionResponse(text: text))
    ProviderBundle(completeFn: complete)

proc taggedBuilder(delayMs = 0): ProviderRuntimeBuilder =
  ## Returns the requested model name as the response text, so concurrent
  ## jobs can be checked for cross-talk.
  result = proc(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
    let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
      if delayMs > 0:
        sleep(delayMs)
      ok(CompletionResponse(text: spec.modelName))
    ProviderBundle(completeFn: complete)

proc runSequential(builder: ProviderRuntimeBuilder; n: int): Future[seq[string]] {.async.} =
  var texts: seq[string]
  for i in 0 ..< n:
    let res = await asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub", modelName: "seq" & $i),
      CompletionRequest())
    if res.isErr:
      return @["error: " & res.error]
    texts.add res.value.text
  return texts

proc runConcurrent(builder: ProviderRuntimeBuilder; n: int): Future[seq[string]] {.async.} =
  var futures: seq[Future[Result[CompletionResponse, string]]]
  for i in 0 ..< n:
    futures.add asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub", modelName: "m" & $i),
      CompletionRequest())
  var texts: seq[string]
  for fut in futures:
    let res = await fut
    if res.isErr:
      return @["error: " & res.error]
    texts.add res.value.text
  return texts

proc waitAndCancel(builder: ProviderRuntimeBuilder; cancelAfterMs: int): Future[bool] {.async.} =
  ## Returns true when the cancelled call raises CancelledError.
  let fut = asyncProviderComplete(
    builder, ProviderSpec(providerName: "stub"), CompletionRequest())
  await sleepAsync(milliseconds(cancelAfterMs))
  fut.cancelSoon()
  try:
    discard await fut
    return false
  except CancelledError:
    return true

proc cancelQueued(builder: ProviderRuntimeBuilder; model: string): Future[bool] {.async.} =
  let fut = asyncProviderComplete(
    builder, ProviderSpec(providerName: "stub", modelName: model), CompletionRequest())
  await sleepAsync(milliseconds(10))
  fut.cancelSoon()
  try:
    discard await fut
    return false
  except CancelledError:
    return true

proc collectTexts(futures: seq[Future[Result[CompletionResponse, string]]]): Future[seq[string]] {.async.} =
  var texts: seq[string]
  for fut in futures:
    let res = await fut
    if res.isErr:
      return @["error: " & res.error]
    texts.add res.value.text
  return texts

suite "provider executor":

  test "runs a provider call on a worker and returns its result":
    check not providerPoolReady()
    let builder = stubBuilder("from-worker", delayMs = 120)
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
    check providerPoolReady()
    check res.isOk
    check res.value.text == "from-worker"

  test "worker exception becomes an error Result":
    let builder: ProviderRuntimeBuilder = proc(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
      let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
        raise newException(ValueError, "boom")
      ProviderBundle(completeFn: complete)
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
    check res.isErr
    check "boom" in res.error

  test "provider error Result passes through unchanged":
    let builder: ProviderRuntimeBuilder = proc(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
      let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
        err("upstream 429")
      ProviderBundle(completeFn: complete)
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
    check res.isErr
    check res.error == "upstream 429"

  test "missing provider is reported without raising":
    let builder: ProviderRuntimeBuilder = proc(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
      ProviderBundle()
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "ghost"), CompletionRequest())
    check res.isErr
    check "provider unavailable: ghost" in res.error

  test "multiple sequential calls reuse the pool":
    let builder = stubBuilder("ok", delayMs = 5)
    let texts = waitFor runSequential(builder, 6)
    check texts.len == 6
    for i, text in texts:
      check text == "ok"

  test "pool stays healthy after an error":
    let failing: ProviderRuntimeBuilder = proc(spec: ProviderSpec): ProviderBundle {.gcsafe.} =
      let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
        err("nope")
      ProviderBundle(completeFn: complete)
    let first = waitFor asyncProviderComplete(
      failing, ProviderSpec(providerName: "stub"), CompletionRequest())
    check first.isErr
    let second = waitFor asyncProviderComplete(
      stubBuilder("recovered"), ProviderSpec(providerName: "stub"), CompletionRequest())
    check second.isOk
    check second.value.text == "recovered"

  test "concurrent jobs run in parallel but bounded by the pool":
    let builder = taggedBuilder(delayMs = 120)
    let start = Moment.now()
    let texts = waitFor runConcurrent(builder, 8)
    let elapsedMs = (Moment.now() - start).milliseconds

    check texts.len == 8
    for i, text in texts:
      check text == "m" & $i

    # 8 jobs of 120ms on a pool of 4 workers need at least two batches.
    # A thread-per-call executor would finish in roughly one batch (~120ms).
    check elapsedMs >= 200

  test "pool configuration is bounded and fixed":
    check providerPoolReady()
    check ProviderWorkerCount == 4
    check ProviderQueueDepth > 0

  test "cancelling an in-flight call raises CancelledError and waits for the worker":
    let builder = stubBuilder("slow", delayMs = 250)
    let start = Moment.now()
    let cancelled = waitFor waitAndCancel(builder, cancelAfterMs = 40)
    let elapsedMs = (Moment.now() - start).milliseconds

    check cancelled
    # Documented limitation: the slot is not freed until the worker acknowledges,
    # so cancellation waits for the in-flight provider call.
    check elapsedMs >= 150

    let after = waitFor asyncProviderComplete(
      stubBuilder("after-cancel"), ProviderSpec(providerName: "stub"), CompletionRequest())
    check after.isOk
    check after.value.text == "after-cancel"

  test "cancelling a queued job is acknowledged without leaking its slot":
    # Occupy every worker, then queue and cancel a job behind them. The queued
    # job must be skipped by a worker and its slot released safely.
    let builder = taggedBuilder(delayMs = 120)
    var busy: seq[Future[Result[CompletionResponse, string]]]
    for i in 0 ..< ProviderWorkerCount:
      busy.add asyncProviderComplete(
        builder, ProviderSpec(providerName: "stub", modelName: "busy" & $i),
        CompletionRequest())

    check waitFor cancelQueued(builder, "queued")

    let busyTexts = waitFor collectTexts(busy)
    check busyTexts.len == ProviderWorkerCount
    for i, text in busyTexts:
      check text == "busy" & $i
