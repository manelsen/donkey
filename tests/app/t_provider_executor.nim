## Provider executor tests.
##
## The executor is a fixed worker pool: jobs are queued on a shared channel and
## consumed by a bounded number of OS threads. These tests cover sequential and
## concurrent calls, error propagation, builder thread ownership, and the
## documented non-blocking cancellation behaviour (a cancelled call returns
## immediately and the reference-counted control block is reclaimed by
## whichever thread drops the last reference).

import std/[os, strutils, unittest]
import chronos
import donkey/app/provider_executor
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/provider

var
  gStubText = ""
  gStubDelayMs = 0
  gTaggedDelayMs = 0
  gPayloadSize = 0
  gExpectedBuilderThreadId = 0

proc stubBuilderImpl(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  var text: string
  var delayMs: int
  {.cast(gcsafe).}:
    text = gStubText
    delayMs = gStubDelayMs
  let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
    if delayMs > 0:
      sleep(delayMs)
    ok(CompletionResponse(text: text))
  ProviderBundle(completeFn: complete)

proc useStub(text: string; delayMs = 0): ProviderRuntimeBuilder =
  gStubText = text
  gStubDelayMs = delayMs
  stubBuilderImpl

proc taggedBuilderImpl(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  ## Returns the requested model name as the response text, so concurrent
  ## jobs can be checked for cross-talk.
  var delayMs: int
  {.cast(gcsafe).}:
    delayMs = gTaggedDelayMs
  let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
    if delayMs > 0:
      sleep(delayMs)
    ok(CompletionResponse(text: spec.modelName))
  ProviderBundle(completeFn: complete)

proc taggedBuilder(delayMs = 0): ProviderRuntimeBuilder =
  gTaggedDelayMs = delayMs
  taggedBuilderImpl

proc payloadBuilderImpl(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  ## Returns a large, tagged GC-managed string to exercise the channel-based
  ## ownership transfer of the result between worker and caller threads.
  var payloadSize: int
  {.cast(gcsafe).}:
    payloadSize = gPayloadSize
  let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
    ok(CompletionResponse(text: spec.modelName & ":" & repeat('x', payloadSize)))
  ProviderBundle(completeFn: complete)

proc payloadBuilder(payloadSize: int): ProviderRuntimeBuilder =
  gPayloadSize = payloadSize
  payloadBuilderImpl

proc raisingBuilder(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
    raise newException(ValueError, "boom")
  ProviderBundle(completeFn: complete)

proc errorBuilder(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
    err("upstream 429")
  ProviderBundle(completeFn: complete)

proc emptyBuilder(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  ProviderBundle()

proc failingBuilder(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
    err("nope")
  ProviderBundle(completeFn: complete)

proc threadCheckBuilder(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  var expected: int
  {.cast(gcsafe).}:
    expected = gExpectedBuilderThreadId
  if getThreadId() != expected:
    raise newException(ValueError, "builder ran off the event loop thread")
  let complete: CompleteFn = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
    ok(CompletionResponse(text: "event-loop-builder"))
  ProviderBundle(completeFn: complete)

proc builderExceptionBuilder(spec: ProviderSpec): ProviderBundle {.gcsafe, nimcall.} =
  raise newException(ValueError, "builder boom")

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
    let res = await fut
    # A cancelled queued job is acknowledged with an Err instead of a raise.
    return res.isErr and "cancelled" in res.error
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
    let builder = useStub("from-worker", delayMs = 120)
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
    check providerPoolReady()
    check res.isOk
    check res.value.text == "from-worker"

  test "worker exception becomes an error Result":
    let builder: ProviderRuntimeBuilder = raisingBuilder
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
    check res.isErr
    check "boom" in res.error

  test "provider error Result passes through unchanged":
    let builder: ProviderRuntimeBuilder = errorBuilder
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
    check res.isErr
    check res.error == "upstream 429"

  test "missing provider is reported without raising":
    let builder: ProviderRuntimeBuilder = emptyBuilder
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "ghost"), CompletionRequest())
    check res.isErr
    check "provider unavailable: ghost" in res.error

  test "multiple sequential calls reuse the pool":
    let builder = useStub("ok", delayMs = 5)
    let texts = waitFor runSequential(builder, 6)
    check texts.len == 6
    for i, text in texts:
      check text == "ok"

  test "pool stays healthy after an error":
    let failing: ProviderRuntimeBuilder = failingBuilder
    let first = waitFor asyncProviderComplete(
      failing, ProviderSpec(providerName: "stub"), CompletionRequest())
    check first.isErr
    let second = waitFor asyncProviderComplete(
      useStub("recovered"), ProviderSpec(providerName: "stub"), CompletionRequest())
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

  test "GC-managed result payloads survive the thread handoff":
    const payloadSize = 4096
    let builder = payloadBuilder(payloadSize)
    let texts = waitFor runConcurrent(builder, 16)

    check texts.len == 16
    for i, text in texts:
      let prefix = "m" & $i & ":"
      check text.startsWith(prefix)
      check text.len == prefix.len + payloadSize

  test "pool configuration is bounded and fixed":
    check ProviderWorkerCount == 4
    check ProviderQueueDepth > 0

  test "builder runs on the caller thread":
    # The builder is `nimcall` (no shared environment), but the executor still
    # invokes it on the event loop before enqueuing.
    gExpectedBuilderThreadId = getThreadId()
    let builder: ProviderRuntimeBuilder = threadCheckBuilder
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
    check res.isOk
    check res.value.text == "event-loop-builder"

  test "builder exception becomes an error Result and the pool stays healthy":
    let builder: ProviderRuntimeBuilder = builderExceptionBuilder
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
    check res.isErr
    check "builder boom" in res.error

    let after = waitFor asyncProviderComplete(
      useStub("after-builder-error"), ProviderSpec(providerName: "stub"), CompletionRequest())
    check after.isOk
    check after.value.text == "after-builder-error"

  test "cancelling an in-flight call returns promptly without waiting for the worker":
    let builder = useStub("slow", delayMs = 250)
    let start = Moment.now()
    let cancelled = waitFor waitAndCancel(builder, cancelAfterMs = 40)
    let elapsedMs = (Moment.now() - start).milliseconds

    check cancelled
    # Non-blocking cancellation: the caller must not wait for the 250ms
    # provider call to return.
    check elapsedMs < 200

    let after = waitFor asyncProviderComplete(
      useStub("after-cancel"), ProviderSpec(providerName: "stub"), CompletionRequest())
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

  test "repeated cancellation drains results and keeps the pool healthy":
    # Large results may be produced after cancellation; the worker discards
    # them locally (or the last reference drains them) instead of leaking them
    # inside a channel whose consumer is gone.
    let slow = useStub(repeat('y', 4096), delayMs = 250)
    for _ in 0 ..< 6:
      let start = Moment.now()
      check waitFor waitAndCancel(slow, cancelAfterMs = 20)
      check (Moment.now() - start).milliseconds < 200

    let after = waitFor asyncProviderComplete(
      useStub("alive"), ProviderSpec(providerName: "stub"), CompletionRequest())
    check after.isOk
    check after.value.text == "alive"
