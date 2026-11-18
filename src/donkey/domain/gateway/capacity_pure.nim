## Pure admission rules for long-lived HTTP work.
##
## The gateway pool has 8 workers. Long-lived requests (agent turns and SSE
## streams) may occupy at most 6 of them; the remaining 2 keep `/health`,
## `/dashboard`, `/api/status`, `/api/logs` and `/v1/models` responsive.

type
  LongLivedKind* = enum
    llChatTurn
    llSseConnection

  LongLivedSnapshot* = object
    pendingTurns*:    int
    sseConnections*:  int
    longLivedWorkers*: int

  LongLivedLimits* = object
    maxPendingTurns*:             int
    maxConcurrentSseConnections*: int
    maxLongLivedWorkers*:         int

  CapacityVerdict* = enum
    cvAdmit
    cvTooManyPendingTurns
    cvTooManySseConnections
    cvNoWorker

const
  GatewayWorkerCount* = 8
  MaxLongLivedWorkers* = 6
  ReservedWorkers* = GatewayWorkerCount - MaxLongLivedWorkers
  MaxPendingTurns* = 4
  MaxConcurrentSseConnections* = 4

func defaultLongLivedLimits*(): LongLivedLimits =
  LongLivedLimits(
    maxPendingTurns:             MaxPendingTurns,
    maxConcurrentSseConnections: MaxConcurrentSseConnections,
    maxLongLivedWorkers:         MaxLongLivedWorkers,
  )

func admitted*(verdict: CapacityVerdict): bool =
  verdict == cvAdmit

func admitLongLived*(kind: LongLivedKind;
                     snapshot: LongLivedSnapshot;
                     limits = defaultLongLivedLimits()): CapacityVerdict =
  ## Decides whether one more long-lived request may block a worker.
  ## The request-class ceiling is checked before the shared worker budget so a
  ## saturated queue reports the actionable reason (429 vs. worker pressure).
  case kind
  of llChatTurn:
    if snapshot.pendingTurns >= limits.maxPendingTurns:
      return cvTooManyPendingTurns
  of llSseConnection:
    if snapshot.sseConnections >= limits.maxConcurrentSseConnections:
      return cvTooManySseConnections
  if snapshot.longLivedWorkers >= limits.maxLongLivedWorkers:
    return cvNoWorker
  # A caller that passes `max(pending, sse)` as `longLivedWorkers` would miss
  # the combined occupancy; enforce the ceiling on the actual sum as well.
  # `snapshot` is the occupancy *before* this request, so a full sum (== max)
  # already means the next request would exceed the budget.
  if snapshot.pendingTurns + snapshot.sseConnections >=
      limits.maxLongLivedWorkers:
    return cvNoWorker
  cvAdmit
