## line_admission.nim — a queue slot reserved before the event is enqueued.
##
## The webhook worker refuses a payload when the event queue is full, and LINE
## then redelivers it. A redelivery of an event the daemon already accepted is
## not worth a slot: under saturation it takes the slot a new event needs, the
## new event is refused, and its redelivery is dropped as a duplicate.
##
## The decision belongs to the runtime, which owns the replay cache and the
## clock, so it arrives here as a `LineAdmit` callback and runs *before* any
## space is asked for. Only a first-seen event reserves; a refusal costs
## nothing, and the caller settles the reservation once the enqueue answered.

import std/atomics
import ../../core/pipeops
import ../../domain/channels/line_pure
import ../../domain/channels/line_policy

const
  LineAdmissionCapacity* = 256
    ## Reservations that may be in flight at once; the event queue is bounded
    ## the same way.

type
  LineAdmission* = enum
    laFresh           ## the runtime has not seen this event: it may take a slot
    laRemembered      ## the runtime already accepted it: no slot
    laRefused         ## the runtime drops it (policy or no room): no slot

  LineAdmit* = proc(ev: LineParseResult; nowSec: int64): LineAdmission
                {.gcsafe, raises: [].}
    ## Runtime-owned admission policy. It must not mutate the replay cache:
    ## the drain records the event only after the enqueue succeeded.

  LineAdmissionState* = ref object
    ## Reservations still being made. Slots carry no identity: the reservation
    ## exists to consult the runtime before space is asked for, and the enqueue
    ## itself is what refuses when the queue is full.
    inflight: Atomic[int]

proc newLineAdmissionState*(): LineAdmissionState =
  new(result)
  result.inflight.store(0)

proc admissionFor*(replay: LineReplayCache; eventId: string; nowSec: int64): LineAdmission
                   {.raises: [].} =
  ## What the runtime remembers, without touching the cache: an event the cache
  ## still holds was accepted before and needs no slot again.
  if eventId.len > 0 and not replayDecision(replay, eventId, nowSec):
    return laRemembered
  laFresh

proc reserve*(s: LineAdmissionState; admit: LineAdmit; ev: LineParseResult;
              nowSec: int64; verdict: var LineAdmission): bool =
  ## Consults the runtime first and only then asks for space, so a replay can
  ## never occupy the room a new event needs. Returns false with no reservation
  ## held; `verdict` says why.
  verdict = laFresh
  if s == nil or admit == nil:
    verdict = laRefused
    return false
  verdict = admit(ev, nowSec)
  if verdict != laFresh:
    return false
  discard s.inflight.fetchAdd(1)
  true

proc settle*(s: LineAdmissionState) =
  ## Releases the reservation taken by `reserve`. Whether the event made it into
  ## the queue is the caller's business: the queue tracks its own occupancy.
  if s != nil:
    discard s.inflight.fetchSub(1)

proc inFlight*(s: LineAdmissionState): int =
  if s == nil: 0 else: s.inflight.load()
