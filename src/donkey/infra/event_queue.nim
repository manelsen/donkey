## EventQueue — hands inbound events from an adapter's receiving thread (a
## webhook server, a gateway socket) to the daemon loop.
##
## Backed by `threading/channels`: the buffer lives in shared memory behind a
## pointer and events are moved, not deep-copied, so the queue is gcsafe to
## share and a global `EventQueue` needs no `{.cast(gcsafe).}`. Events must be
## plain values (strings, numbers, enums); a `ref` inside would be shared, not
## moved.
##
## The queue is bounded. `push` never blocks the receiving thread: a full
## queue refuses the event and counts the drop, instead of growing without
## limit while the daemon loop is stalled. The receiving thread never logs
## (a write to a full stderr pipe would block it); the consumer reports the
## drops when it polls.

import std/atomics
import threading/channels
import ../core/log

const DefaultEventCapacity* = 1024

type EventQueue*[T] = object
  name: cstring  ## a compile-time literal: static memory, so the queue holds
                 ## nothing the GC owns and a global one stays gcsafe
  chan: Chan[T]
  dropped: ptr Atomic[int]  ## shared counter, outside the GC as well

proc initEventQueue*[T](name: static string;
                        capacity: Positive = DefaultEventCapacity): EventQueue[T] =
  const literal: cstring = name
  let dropped = cast[ptr Atomic[int]](allocShared0(sizeof(Atomic[int])))
  EventQueue[T](name: literal, chan: newChan[T](capacity), dropped: dropped)

proc push*[T](q: EventQueue[T]; event: sink T): bool {.discardable.} =
  ## Hands `event` over without blocking; false when full, and the drop is
  ## counted for the consumer to report.
  result = q.chan.trySend(event)
  if not result:
    discard q.dropped[].fetchAdd(1)

proc waitPush*[T](q: EventQueue[T]; event: sink T) =
  ## Blocks until there is room (for control messages, such as a stop
  ## sentinel, that must not be dropped).
  q.chan.send(event)

proc takeDropped*[T](q: EventQueue[T]): int =
  ## Drops since the last call, resetting the count.
  q.dropped[].exchange(0)

proc reportDrops[T](q: EventQueue[T]) =
  ## Runs on the consumer (the daemon loop), never on the receiving thread.
  let dropped = q.takeDropped()
  if dropped > 0:
    newLogger("event_queue").warn($q.name & " queue full: " & $dropped &
                                  " event(s) dropped")

proc tryPop*[T](q: EventQueue[T]; event: var T): bool =
  ## Takes the oldest event, if any. `threading` writes the received value
  ## over the destination without destroying it, so it lands in a fresh
  ## temporary first and is moved in only on success; `event` is left as it
  ## was when the queue is empty.
  q.reportDrops()
  var received: T
  result = q.chan.tryRecv(received)
  if result:
    event = move(received)

proc waitPop*[T](q: EventQueue[T]; event: var T) =
  ## Blocks until an event arrives (for worker threads that only wait on the
  ## queue). Same fresh-temporary receive as `tryPop`.
  q.reportDrops()
  var received: T
  q.chan.recv(received)
  event = move(received)

proc tryTake*[T](q: EventQueue[T]): (bool, T) =
  ## `tryPop` in the `(found, event)` shape the adapters' pollers return.
  result[0] = q.tryPop(result[1])
