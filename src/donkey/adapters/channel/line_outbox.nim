## line_outbox.nim — the adapter-side queue for LINE replies produced by the
## inbound drain.
##
## The LINE drain runs on the daemon loop. Delivering a reply from there means
## a LINE POST on the daemon loop, and that call can wait for the whole
## transport timeout, stalling every other channel and the scheduler. The drain
## therefore only enqueues the reply, with its conversation in `replyTo`; the
## owner of the transport drains the queue and performs the POST where a slow
## endpoint is tolerable.
##
## The queue is bounded: under pressure the enqueue fails instead of growing
## without limit, and the caller decides what to log. The lock has to be
## explicit because webhook threads and the daemon reach the same instance.

import std/locks
import ../../core/pipeops
import ../../core/channels/flood_gate
import ../../domain/message
import ./line

const LineReplyCapacity* = 256

type
  LineReplyQueue* = ref object
    lock:  Lock
    limit: int
    items: seq[OutboundMessage]

proc newLineReplyQueue*(capacity = LineReplyCapacity): LineReplyQueue =
  ## `capacity` cannot exceed `LineReplyCapacity`: the bound is a constant so
  ## the enqueue and the advertised capacity can never disagree.
  new(result)
  initLock(result.lock)
  result.limit = min(capacity, LineReplyCapacity)
  result.items = newSeqOfCap[OutboundMessage](result.limit)

proc deinit*(q: LineReplyQueue) =
  if q == nil:
    return
  deinitLock(q.lock)

func capacity*(q: LineReplyQueue): int =
  if q == nil: 0 else: q.limit

proc len*(q: LineReplyQueue): int =
  ## Pending replies; tests and telemetry only.
  if q == nil:
    return 0
  acquire(q.lock)
  try:
    result = q.items.len
  finally:
    release(q.lock)

proc enqueueReply*(q: LineReplyQueue;
                   msg: OutboundMessage): Result[void, string] {.gcsafe, raises: [].} =
  ## Hands a reply to the queue without contacting the channel. The drain
  ## passes this as `enqueueReply`; `replyTo` carries the conversation, so the
  ## drain does not need to know it at delivery time.
  if q == nil:
    return err("LINE: no reply queue")
  acquire(q.lock)
  try:
    if q.items.len >= q.limit:
      return err("LINE: reply queue full")
    q.items.add msg
  finally:
    release(q.lock)
  ok()

proc tryDequeue*(q: LineReplyQueue): (bool, OutboundMessage) =
  ## Non-blocking poll for the owner of the transport. The reply is removed
  ## before the POST: a LINE push has no idempotency key, so a retry of a reply
  ## already accepted would duplicate it.
  if q == nil:
    return (false, OutboundMessage())
  acquire(q.lock)
  try:
    if q.items.len == 0:
      return (false, OutboundMessage())
    result = (true, q.items[0])
    q.items.delete(0)
  finally:
    release(q.lock)

proc tryDequeue*(q: LineReplyQueue; msg: var OutboundMessage): bool =
  ## Same poll with an out parameter, for callers that cannot tuple-unpack
  ## inside a `while` condition.
  let (has, item) = q.tryDequeue()
  msg = item
  has

proc deliverQueuedReplies*(q: LineReplyQueue; a: LineAdapter;
                           onResult: proc(msg: OutboundMessage;
                                          res: Result[void, string]) {.gcsafe.} = nil): int
                           {.gcsafe.} =
  ## Delivers every queued reply through `a` and returns how many were
  ## attempted. Call this only from the thread that owns the transport:
  ## `a.send` is the blocking POST this queue exists to move off the daemon
  ## loop. `onResult` carries the per-reply outcome to the delivery ledger.
  if q == nil:
    return 0
  var msg: OutboundMessage
  ## A flood window is already known before the POST: do not remove the head,
  ## or `a.send` would refuse without attempting and the reply would be lost.
  while a.flood.remainingMs(0, epochMs()) == 0 and q.tryDequeue(msg):
    inc result
    var sent: Result[void, string]
    try:
      sent = a.send(msg)
    except Exception:
      sent = Result[void, string].err("LINE: reply delivery failed")
    if onResult != nil:
      onResult(msg, sent)
