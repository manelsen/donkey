## Async provider execution tests.

import std/[os, strutils, unittest]
import chronos
import donkey/app/tool_loop_runtime
import donkey/core/pipeops
import donkey/domain/message
import donkey/ports/provider

suite "asyncComplete":

  test "slow provider does not block the event loop":
    let slow = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
      sleep(150)
      ok(CompletionResponse(text: "ok"))

    proc run(): Future[tuple[notFinished: bool, text: string]] {.async.} =
      let fut = asyncComplete(slow, CompletionRequest())
      await sleepAsync(milliseconds(30))
      let notFinished = not fut.finished()
      let res = await fut
      return (notFinished, res.value.text)

    let (notFinished, text) = waitFor run()
    check notFinished
    check text == "ok"

  test "provider exception becomes an error Result":
    let boom = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
      raise newException(ValueError, "boom")

    let res = waitFor asyncComplete(boom, CompletionRequest())
    check res.isErr
    check "boom" in res.error
