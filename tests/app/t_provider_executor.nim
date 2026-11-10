## Provider executor tests.

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

suite "provider executor":

  test "runs a provider call on a worker and returns its result":
    let builder = stubBuilder("from-worker", delayMs = 120)
    let res = waitFor asyncProviderComplete(
      builder, ProviderSpec(providerName: "stub"), CompletionRequest())
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
