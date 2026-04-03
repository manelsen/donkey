## reliability — resilience patterns for providers and tools.

import std/[math, locks, tables]
import ./pipeops

type
  CircuitState* = enum
    csClosed
    csOpen
    csHalfOpen

  CircuitBreaker* = object
    failCount*:    int
    maxFailures*:  int
    resetTimeout*: int  ## seconds
    lastFailure*:  int64 ## ms timestamp
    state*:        CircuitState

var gBreakers* {.global.}: Table[string, CircuitBreaker]
var gBreakerLock {.global.}: Lock
var gReliabilityReady {.global.}: bool = false

proc initReliability*() {.gcsafe.} =
  initLock(gBreakerLock)
  {.cast(gcsafe).}:
    gBreakers = initTable[string, CircuitBreaker]()
    gReliabilityReady = true

proc getBackoffMs*(attempt: int, baseMs = 1000): int =
  ## Exponential backoff: 1s, 2s, 4s...
  baseMs * (2 ^ (attempt - 1))

proc checkCircuit*(name: string): bool {.gcsafe.} =
  ## Returns true if the circuit is CLOSED (allowed) or HALF-OPEN (testing).
  if not gReliabilityReady: return true
  acquire(gBreakerLock)
  defer: release(gBreakerLock)
  
  {.cast(gcsafe).}:
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
  if not gReliabilityReady: return
  acquire(gBreakerLock)
  defer: release(gBreakerLock)
  {.cast(gcsafe).}:
    if gBreakers.hasKey(name):
      let b = addr gBreakers[name]
      b.failCount = 0
      b.state = csClosed

proc recordFailure*(name: string) {.gcsafe.} =
  if not gReliabilityReady: return
  acquire(gBreakerLock)
  defer: release(gBreakerLock)
  {.cast(gcsafe).}:
    if not gBreakers.hasKey(name):
      gBreakers[name] = CircuitBreaker(maxFailures: 3, resetTimeout: 60, state: csClosed)
    
    let b = addr gBreakers[name]
    b.failCount.inc
    b.lastFailure = nowMs()
    if b.failCount >= b.maxFailures:
      b.state = csOpen
