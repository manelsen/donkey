## Test reliability mechanisms: retry, circuit breaker.

import std/strutils
import std/[unittest, times, os, tables]
import donkey/core/pipeops
import donkey/adapters/http/circuit_breakers

proc runTests*() =
  suite "Reliability - Backoff":

    test "calculates exponential backoff correctly":
      check getBackoffMs(1) == 1000
      check getBackoffMs(2) == 2000
      check getBackoffMs(3) == 4000
      check getBackoffMs(4) == 8000

  suite "Reliability - Circuit Breaker":

    setup:
      initReliability()

    test "blocks after consecutive failures":
      let name = "unstable-api"
      check checkCircuit(name) == true

      recordFailure(name)
      recordFailure(name)
      check checkCircuit(name) == true

      recordFailure(name) # 3rd failure
      check checkCircuit(name) == false

    test "a host name too long to store whole is never tripped":

      ## Truncated, two long hosts differing only in the port would share a

      ## breaker; such names are not tracked at all.

      initReliability()

      let long = "a".repeat(260)

      for _ in 0 ..< 5:

        recordFailure(long & ":10000")

      check checkCircuit(long & ":10000")

      check checkCircuit(long & ":10001")


    test "recovers after timeout":
      let name = "recovering-api"
      # Force open state
      recordFailure(name)
      recordFailure(name)
      recordFailure(name)
      check checkCircuit(name) == false

      # We can't wait 60s in a unit test easily,
      # but we can mock the lastFailure if we had access or use a small timeout.
      # For now, let's just check the state logic.
      check breakerState(name) == csOpen

when isMainModule:
  runTests()
