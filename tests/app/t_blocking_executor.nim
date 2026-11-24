## The off-loop executor: a blocking call runs on a worker thread while the
## Chronos loop keeps serving other work.

import std/[os, strutils, unittest]
import chronos
import donkey/app/blocking_executor
import donkey/core/pipeops

proc upper(input: string): Result[string, string] {.nimcall, gcsafe, raises: [].} =
  ok(input.toUpperAscii)

proc slow(input: string): Result[string, string] {.nimcall, gcsafe, raises: [].} =
  os.sleep(300)
  ok("done " & input)

proc failing(input: string): Result[string, string] {.nimcall, gcsafe, raises: [].} =
  err("refused: " & input)

proc ticker(stop: ref bool): Future[int] {.async.} =
  var ticks = 0
  while not stop[]:
    await sleepAsync(chronos.milliseconds(10))
    inc ticks
  return ticks

proc slowWhileTicking(): Future[(Result[string, string], int)] {.async.} =
  let stop = new bool
  let ticking = ticker(stop)
  let r = await runOffLoop(slow, "x")
  stop[] = true
  return (r, await ticking)

proc runTests*() =
  suite "blocking executor":

    test "the result comes back from the worker":
      check (waitFor runOffLoop(upper, "olá mundo")).get == "OLá MUNDO"

    test "an error comes back as an error":
      let r = waitFor runOffLoop(failing, "x")
      check r.isErr and r.error == "refused: x"

    test "the loop keeps running while a job blocks its worker":
      let (r, ticks) = waitFor slowWhileTicking()
      check r.get == "done x"
      ## 300 ms of work, 10 ms ticks: a blocked loop would tick once or not at all.
      check ticks >= 10

    test "jobs run side by side on the pool":
      let started = Moment.now()
      var fs: seq[Future[Result[string, string]]]
      for i in 0 ..< 3:
        fs.add(runOffLoop(slow, $i))
      waitFor allFutures(fs)
      for f in fs: check f.read.isOk
      check (Moment.now() - started).milliseconds < 800

    test "a cancelled job does not crash the worker or leak into the next one":
      let f = runOffLoop(slow, "gone")
      waitFor sleepAsync(chronos.milliseconds(20))
      waitFor f.cancelAndWait()
      check f.cancelled
      check (waitFor runOffLoop(upper, "next")).get == "NEXT"

when isMainModule:
  runTests()
