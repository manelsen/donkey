## supervision_pure — a supervisor's decisions, in the manner of OTP (E12.2).
##
## Each child (a channel's connection, a drain) is supervised on its own
## (`one_for_one`): when it ends, its kind says whether it comes back
## (`permanent`: always; `transient`: only after an error; `temporary`:
## never), with a wait that doubles at each restart within the window. Past
## the intensity (at most `maxRestarts` in `withinMs`), the supervisor
## escalates: the child is `down`, the operator is told, and everything else
## goes on. Pure: the clock comes in.
##
## Unlike OTP, restarts here wait (2 s doubling to a minute: a channel's
## server may be away), so the intensity is 5 restarts in 5 minutes, reached
## after about a minute of failing; and `down` is a cool-off, not the end:
## after it the child is tried again, so a long outage does not leave a
## channel off until the daemon restarts. A Defect, which no in-process
## supervisor can catch, is E12.3's: a channel run as its own process.

type
  RestartKind* = enum
    rkPermanent, rkTransient, rkTemporary

  RestartPolicy* = object
    kind*: RestartKind
    maxRestarts*: int
    withinMs*: int64
    baseBackoffMs*: int
    maxBackoffMs*: int
    coolOffMs*: int        ## how long a child stays down before it is tried again

  ChildState* = enum
    csRunning, csRestarting, csDown, csStopped

  ExitKind* = enum
    exNormal, exError

  RestartAction* = enum
    raRestart, raStop, raDown

  RestartDecision* = object
    action*: RestartAction
    afterMs*: int
    firstDown*: bool      ## this exit took the child down: tell the operator

  ChildRecord* = object
    state*: ChildState
    restarts: seq[int64]   ## when each restart was decided, oldest first
    lastError*: string

const DefaultPolicy* = RestartPolicy(kind: rkPermanent, maxRestarts: 5, withinMs: 300_000,
                                     baseBackoffMs: 2_000, maxBackoffMs: 60_000,
                                     coolOffMs: 300_000)

func restartsInWindow*(rec: ChildRecord; now: int64; policy: RestartPolicy): int =
  for t in rec.restarts:
    if now - t < policy.withinMs: inc result

func markRunning*(rec: var ChildRecord; now: int64) =
  ## a child that connects again is up, whatever it went through
  rec.state = csRunning

func onExit*(rec: var ChildRecord; policy: RestartPolicy; exit: ExitKind;
             now: int64; error = ""): RestartDecision =
  if error.len > 0: rec.lastError = error
  let wanted =
    case policy.kind
    of rkPermanent: true
    of rkTransient: exit == exError
    of rkTemporary: false
  if not wanted:
    rec.state = csStopped
    return RestartDecision(action: raStop)
  var recent: seq[int64]
  for t in rec.restarts:
    if now - t < policy.withinMs: recent.add t
  rec.restarts = recent
  if recent.len >= policy.maxRestarts:
    let first = rec.state != csDown
    rec.state = csDown
    rec.restarts = @[]   ## after the cool-off, the count starts afresh
    return RestartDecision(action: raDown, afterMs: policy.coolOffMs, firstDown: first)
  var wait = policy.baseBackoffMs
  for _ in 0 ..< recent.len:
    wait = min(wait * 2, policy.maxBackoffMs)
  rec.restarts.add now
  rec.state = csRestarting
  RestartDecision(action: raRestart, afterMs: min(wait, policy.maxBackoffMs))

func healthyRun*(rec: var ChildRecord) =
  ## The child ran well for a while: earlier restarts no longer count.
  rec.restarts = @[]
  rec.state = csRunning
