## EventQueue hands inbound events from an adapter's receiving thread to the
## daemon loop. The producer below is a `{.thread.}` proc that touches the
## global queue with no `{.cast(gcsafe).}`: this file only compiles while the
## queue is gcsafe to share.

import std/unittest
import donkey/adapters/channel/event_queue

type Ev = object
  id: int
  text: string

const Produced = 2_000

var gQueue = initEventQueue[Ev]("test", capacity = 64)

proc producer() {.thread.} =
  var i = 0
  while i < Produced:
    if gQueue.push(Ev(id: i, text: "event " & $i)):
      inc i

proc runTests*() =
  suite "event queue":
    test "events come out in order and a full queue refuses instead of blocking":
      var q = initEventQueue[Ev]("test", capacity = 2)
      check q.push(Ev(id: 1, text: "a"))
      check q.push(Ev(id: 2, text: "b"))
      check not q.push(Ev(id: 3, text: "c"))
      var ev: Ev
      check q.tryPop(ev) and ev.id == 1 and ev.text == "a"
      check q.tryPop(ev) and ev.id == 2 and ev.text == "b"
      check not q.tryPop(ev)
      check q.push(Ev(id: 4, text: "d"))
      check q.tryTake() == (true, Ev(id: 4, text: "d"))
      check not q.tryTake()[0]

    test "a producer thread hands its events over intact":
      var t: Thread[void]
      createThread(t, producer)
      var got = 0
      var ev: Ev
      while got < Produced:
        if gQueue.tryPop(ev):
          check ev.id == got
          check ev.text == "event " & $got
          inc got
      joinThread(t)
      check got == Produced

when isMainModule:
  runTests()
