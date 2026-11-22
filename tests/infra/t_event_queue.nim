## EventQueue hands inbound events from an adapter's receiving thread to the
## daemon loop. The producer below is a `{.thread.}` proc that touches the
## global queue with no `{.cast(gcsafe).}`: this file only compiles while the
## queue is gcsafe to share.

import std/[monotimes, times, unittest]
import donkey/infra/event_queue

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
      let deadline = getMonoTime() + initDuration(seconds = 10)
      while got < Produced and getMonoTime() < deadline:
        if gQueue.tryPop(ev):
          check ev.id == got
          check ev.text == "event " & $got
          inc got
      check got == Produced
      if got == Produced:
        joinThread(t)  ## a stuck producer is reported above, not waited on

    test "a full queue counts its drops for the consumer to report":
      ## The receiving thread must not write logs (stderr may block); it
      ## only counts, and the loop takes the count.
      var q = initEventQueue[Ev]("drops", capacity = 1)
      check q.push(Ev(id: 1))
      check not q.push(Ev(id: 2))
      check not q.push(Ev(id: 3))
      check q.takeDropped() == 2
      check q.takeDropped() == 0

    test "receiving into a reused variable keeps it intact when the queue is empty":
      var q = initEventQueue[Ev]("reuse", capacity = 2)
      var ev = Ev(id: 7, text: "kept")
      check not q.tryPop(ev)
      check ev.text == "kept"
      check q.push(Ev(id: 8, text: "next"))
      check q.tryPop(ev)
      check ev == Ev(id: 8, text: "next")

    test "waitPush waits for room instead of dropping":
      var q = initEventQueue[Ev]("full", capacity = 1)
      check q.push(Ev(id: 1))
      var t: Thread[ptr EventQueue[Ev]]
      proc drain(qp: ptr EventQueue[Ev]) {.thread.} =
        var ev: Ev
        qp[].waitPop(ev)
      createThread(t, drain, addr q)
      q.waitPush(Ev(id: 2))
      joinThread(t)
      check q.takeDropped() == 0
      var ev: Ev
      check q.tryPop(ev) and ev.id == 2

    test "waitPop blocks until an event arrives from another thread":
      var t: Thread[void]
      proc late() {.thread.} =
        var spins = 0
        while not gQueue.push(Ev(id: 42, text: "late")):
          inc spins
      createThread(t, late)
      var ev: Ev
      gQueue.waitPop(ev)
      joinThread(t)
      check ev == Ev(id: 42, text: "late")

when isMainModule:
  runTests()
