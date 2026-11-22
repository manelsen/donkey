## circuit_breakers — the process-wide circuit breaker registry used by the
## HTTP transport. Shared by every thread that makes HTTP calls (provider
## workers, webhook threads, the daemon loop), so it is guarded by a lock;
## `core/reliability` keeps only the types and the backoff curve.

import std/locks
import ../../core/pipeops
import ../../core/reliability
import ../../infra/fixed
export reliability

const
  BreakerHosts = 128      ## hosts tracked; beyond that a host is never tripped
  BreakerHostBytes = 256  ## a DNS name is at most 253 bytes

## Plain values (no GC memory), so every thread that makes HTTP calls shares
## them under gBreakerLock with no cast.
var gBreakers: FixedTable[BreakerHosts, BreakerHostBytes, CircuitBreaker]
var gBreakerLock: Lock
var gReliabilityReady: bool = false
initLock(gBreakerLock)  ## module init: before any thread can check a circuit

template withBreakers(body: untyped) =
  ## The one way to touch the breakers, from any thread (provider workers,
  ## webhook threads, the daemon loop).
  acquire(gBreakerLock)
  try:
    body
  finally:
    release(gBreakerLock)

proc trackable(name: string): bool =
  ## A known host, or room for a new one. The table's overflow bucket is
  ## never used: unrelated hosts must not share one breaker.
  name in gBreakers or gBreakers.len < BreakerHosts - 1

proc breaker(name: string): ptr CircuitBreaker =
  ## The breaker for `name`, created closed on first use. Call only when
  ## `trackable(name)`, under gBreakerLock.
  let fresh = name notin gBreakers
  result = addr gBreakers.mgetOrPut(name)
  if fresh:
    result[] = CircuitBreaker(maxFailures: 3, resetTimeout: 60, state: csClosed)

proc initReliability*() {.gcsafe.} =
  ## Enables (or resets) circuit breaking.
  withBreakers:
    gBreakers.clear()
    gReliabilityReady = true

proc breakerState*(name: string): CircuitState {.gcsafe.} =
  ## The current state of one breaker (closed when unknown).
  withBreakers:
    result = gBreakers.get(name).state

proc checkCircuit*(name: string): bool {.gcsafe.} =
  ## Returns true if the circuit is CLOSED (allowed) or HALF-OPEN (testing).
  withBreakers:
    if not gReliabilityReady or not trackable(name): return true
    if name notin gBreakers:
      discard breaker(name)
      return true
    let b = breaker(name)
    if b.state == csOpen:
      if (nowMs() - b.lastFailure) > (b.resetTimeout * 1000):
        b.state = csHalfOpen
        return true
      return false
    return true

proc recordSuccess*(name: string) {.gcsafe.} =
  withBreakers:
    if not gReliabilityReady: return
    if name in gBreakers:
      let b = breaker(name)
      b.failCount = 0
      b.state = csClosed

proc recordFailure*(name: string) {.gcsafe.} =
  withBreakers:
    if not gReliabilityReady or not trackable(name): return
    let b = breaker(name)
    b.failCount.inc
    b.lastFailure = nowMs()
    if b.failCount >= b.maxFailures:
      b.state = csOpen
