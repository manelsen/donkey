## reliability — resilience patterns for providers and tools: the breaker
## types and the backoff curve. The shared breaker registry lives with its
## only user, the HTTP transport (`adapters/http/circuit_breakers`).

import std/math

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

proc getBackoffMs*(attempt: int, baseMs = 1000): int =
  ## Exponential backoff: 1s, 2s, 4s...
  baseMs * (2 ^ (attempt - 1))
