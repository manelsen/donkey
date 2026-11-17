## nonblocking.nim — exception-free wrappers around chronos queues.
##
## `addLastNoWait` raises `AsyncQueueFullError` when the queue is at capacity.
## Callers that must not lose a turn (or that deliberately treat a full queue
## as a dropped signal) get a `Result` instead of a `try/except`, so the
## application layer never catches infrastructure exceptions.

import chronos/asyncsync
import ../../core/pipeops

proc tryAddLastNoWait*[T](queue: AsyncQueue[T]; value: T):
                          Result[void, string] {.gcsafe, raises: [].} =
  ## Enqueues without waiting. A full queue is reported as `Err`; the caller
  ## decides whether that is fatal or a dropped best-effort signal.
  if queue.isNil:
    return err("queue unavailable")
  try:
    queue.addLastNoWait(value)
    ok()
  except AsyncQueueFullError:
    err("queue full")
  except CatchableError as e:
    err(e.msg)
