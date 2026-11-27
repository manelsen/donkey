## supervisor — the supervision a channel's own thread runs (E12.2).
##
## Each connection thread (persistent_socket's, IRC's, ntfy's, SimpleX's,
## BlueBubbles') is a `permanent` child: when its session ends, `ended`
## says how long to wait before the next (supervision_pure's decision),
## sets the channel's state for the status, and tells the operator once when
## the channel goes down. A session that ran a minute or more was healthy:
## the restarts before it no longer count. Thread-local: each thread owns
## its own `Supervised`.

import std/[options, times]
import ../core/log
import ../core/types
import ../domain/supervision_pure
import ./connection_state

const HealthyRunMs* = 60_000

type Supervised* = object
  channel: Option[ChannelKind]
  name: string
  policy: RestartPolicy
  rec: ChildRecord

proc newSupervised*(channel: ChannelKind; name: string;
                    policy = DefaultPolicy): Supervised =
  Supervised(channel: some(channel), name: name, policy: policy)

proc newSupervised*(name: string; policy = DefaultPolicy): Supervised =
  ## A child that is not a channel (no state in the status).
  Supervised(name: name, policy: policy)

proc nowMs(): int64 = int64(epochTime() * 1000)

proc started*(s: var Supervised; now = nowMs()) =
  ## A session opened: the channel is up.
  s.rec.markRunning(now)
  if s.channel.isSome: superviseState(s.channel.get, csRunning)

proc ended*(s: var Supervised; error: string; ranMs: int64; log: Logger;
            now = nowMs()): int =
  ## The session ended: how long to wait before the next one (ms).
  if ranMs >= HealthyRunMs:
    s.rec.healthyRun()
  let d = s.rec.onExit(s.policy, exError, now, error)
  case d.action
  of raRestart:
    if s.channel.isSome: superviseState(s.channel.get, csRestarting)
  of raDown:
    if s.channel.isSome: superviseState(s.channel.get, csDown)
    if d.firstDown:
      log.error(s.name & ": down: restarted " & $s.policy.maxRestarts & " times in " &
                $(s.policy.withinMs div 60_000) & " min; trying again in " &
                $(d.afterMs div 60_000) & " min. Last error: " & s.rec.lastError)
  of raStop:
    if s.channel.isSome: superviseState(s.channel.get, csStopped)
  d.afterMs
