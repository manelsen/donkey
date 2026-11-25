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

type
  Mailbox = object
    host: string
    port: int
  Letter = object
    sender, text: string

proc fetchLetters(box: Mailbox): Result[seq[Letter], string] {.nimcall, gcsafe, raises: [].} =
  ok(@[Letter(sender: "ana@" & box.host, text: "porta " & $box.port)])

type Holder = ref object
  value: string

proc givesRef(input: string): Result[Holder, string] {.nimcall, gcsafe, raises: [].} =
  ok(Holder(value: input))

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

    test "a job takes and returns any plain data, not only strings":
      ## Channels poll with their own types (a mailbox in, messages out)
      ## without writing a codec for the trip.
      let r = waitFor runOffLoop(fetchLetters, Mailbox(host: "x.org", port: 993))
      check r.get == @[Letter(sender: "ana@x.org", text: "porta 993")]

    test "a ref can not cross to a worker":
      check not compiles(runOffLoop(givesRef, "x"))

    test "streams have their own workers: a busy stream pool leaves calls alone":
      ## Long streams must never take the workers per-message calls
      ## (Backtrail, recall) need, and the other way round.
      var streams: seq[Future[Result[string, string]]]
      for i in 0 ..< StreamWorkerCount:
        streams.add(runOffLoop(slow, "s" & $i, pool = opStream))
      let started = Moment.now()
      check (waitFor runOffLoop(upper, "call")).get == "CALL"
      check (Moment.now() - started).milliseconds < 200
      waitFor allFutures(streams)

    test "a pool's capacity is the workers that started":
      ## Both pools have run jobs above, so they are started.
      check poolCapacity(opBlocking) == BlockingWorkerCount
      check poolCapacity(opStream) == StreamWorkerCount

    test "and a busy call pool leaves streams alone":
      var calls: seq[Future[Result[string, string]]]
      for i in 0 ..< BlockingWorkerCount:
        calls.add(runOffLoop(slow, "c" & $i))
      let started = Moment.now()
      check (waitFor runOffLoop(upper, "stream", pool = opStream)).get == "STREAM"
      check (Moment.now() - started).milliseconds < 200
      waitFor allFutures(calls)

    test "a cancelled job does not crash the worker or leak into the next one":
      let f = runOffLoop(slow, "gone")
      waitFor sleepAsync(chronos.milliseconds(20))
      waitFor f.cancelAndWait()
      check f.cancelled
      check (waitFor runOffLoop(upper, "next")).get == "NEXT"

when isMainModule:
  runTests()
