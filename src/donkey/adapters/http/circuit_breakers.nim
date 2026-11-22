## circuit_breakers — the process-wide circuit breaker registry used by the
## HTTP transport. Shared by every thread that makes HTTP calls (provider
## workers, webhook threads, the daemon loop), so it is guarded by a lock;
## `core/reliability` keeps only the types and the backoff curve.

import std/[locks, tables]
import ../../core/pipeops
import ../../core/reliability
export reliability

var gBreakers {.global.}: Table[string, CircuitBreaker]
var gBreakerLock {.global.}: Lock
var gReliabilityReady {.global.}: bool = false
initLock(gBreakerLock)  ## module init: before any thread can check a circuit

template withBreakers(body: untyped) =
  ## The one way to touch the breakers, from any thread (provider workers,
  ## webhook threads, the daemon loop).
  ## gcsafe: gBreakers and gReliabilityReady are only read or written here, under gBreakerLock; names and breakers are copied in and out
  {.cast(gcsafe).}:
    acquire(gBreakerLock)
    try:
      body
    finally:
      release(gBreakerLock)

proc initReliability*() {.gcsafe.} =
  ## Enables (or resets) circuit breaking.
  withBreakers:
    gBreakers = initTable[string, CircuitBreaker]()
    gReliabilityReady = true

proc breakerState*(name: string): CircuitState {.gcsafe.} =
  ## The current state of one breaker (closed when unknown).
  withBreakers:
    result = gBreakers.getOrDefault(name).state

proc checkCircuit*(name: string): bool {.gcsafe.} =
  ## Returns true if the circuit is CLOSED (allowed) or HALF-OPEN (testing).
  withBreakers:
    if not gReliabilityReady: return true
    if not gBreakers.hasKey(name):
      gBreakers[name] = CircuitBreaker(maxFailures: 3, resetTimeout: 60, state: csClosed)
      return true
    let b = addr gBreakers[name]
    if b.state == csOpen:
      if (nowMs() - b.lastFailure) > (b.resetTimeout * 1000):
        b.state = csHalfOpen
        return true
      return false
    return true

proc recordSuccess*(name: string) {.gcsafe.} =
  withBreakers:
    if not gReliabilityReady: return
    if gBreakers.hasKey(name):
      let b = addr gBreakers[name]
      b.failCount = 0
      b.state = csClosed

proc recordFailure*(name: string) {.gcsafe.} =
  withBreakers:
    if not gReliabilityReady: return
    if not gBreakers.hasKey(name):
      gBreakers[name] = CircuitBreaker(maxFailures: 3, resetTimeout: 60, state: csClosed)
    let b = addr gBreakers[name]
    b.failCount.inc
    b.lastFailure = nowMs()
    if b.failCount >= b.maxFailures:
      b.state = csOpen
