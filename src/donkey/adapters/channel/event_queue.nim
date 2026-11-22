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
## queue refuses the event and logs the drop, instead of growing without
## limit while the daemon loop is stalled.

import threading/channels
import ../../core/log

const DefaultEventCapacity* = 1024

type EventQueue*[T] = object
  name: cstring  ## a compile-time literal: static memory, so the queue holds
                 ## nothing the GC owns and a global one stays gcsafe
  chan: Chan[T]

proc initEventQueue*[T](name: static string;
                        capacity: Positive = DefaultEventCapacity): EventQueue[T] =
  const literal: cstring = name
  EventQueue[T](name: literal, chan: newChan[T](capacity))

proc push*[T](q: EventQueue[T]; event: sink T): bool {.discardable.} =
  ## Hands `event` over without blocking; false (and a warning) when full.
  result = q.chan.trySend(event)
  if not result:
    newLogger("event_queue").warn($q.name & " queue full: event dropped")

proc tryPop*[T](q: EventQueue[T]; event: var T): bool =
  ## Takes the oldest event, if any.
  q.chan.tryRecv(event)

proc tryTake*[T](q: EventQueue[T]): (bool, T) =
  ## `tryPop` in the `(found, event)` shape the adapters' pollers return.
  result[0] = q.chan.tryRecv(result[1])
