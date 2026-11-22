## A ThreadOwner records the first thread that uses a piece of thread-local
## state and reports any other thread that touches it later, so a wrong
## assumption ("only the daemon loop uses this") shows up instead of quietly
## reading another thread's empty copy.

import std/unittest
import donkey/infra/thread_owner

var gOwner: ThreadOwner
var gForeign: bool

proc fromOtherThread() {.thread.} =
  gForeign = not gOwner.isOwner()

proc runTests*() =
  suite "thread owner":
    test "the first user owns the state and stays its owner":
      var o: ThreadOwner
      check o.isOwner()
      check o.isOwner()

    test "another thread is reported as a foreign user":
      check gOwner.isOwner()
      var t: Thread[void]
      createThread(t, fromOtherThread)
      joinThread(t)
      check gForeign
      check gOwner.foreignUses() == 1

when isMainModule:
  runTests()
