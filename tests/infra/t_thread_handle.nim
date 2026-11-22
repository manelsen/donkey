## spawnThread keeps the thread in shared memory behind a pointer, so a
## global handle is gcsafe: the starter below is {.gcsafe.} and touches the
## global with no cast.

import std/[atomics, unittest]
import donkey/infra/thread_handle

type Args = object
  label: string
  times: int

var gHandle: ThreadHandle[Args]
var gSeen: Atomic[int]

proc worker(args: Args) {.thread.} =
  for _ in 0 ..< args.times:
    discard gSeen.fetchAdd(args.label.len)

proc start() {.gcsafe.} =
  gHandle = spawnThread(worker, Args(label: "abc", times: 4))

proc runTests*() =
  suite "thread handle":
    test "a thread started from gcsafe code runs with its argument and is joined":
      gSeen.store(0)
      start()
      check gHandle != nil
      joinAndFree(gHandle)
      check gHandle == nil
      check gSeen.load == 12

when isMainModule:
  runTests()
