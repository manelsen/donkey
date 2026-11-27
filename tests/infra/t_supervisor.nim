## E12.2: the supervisor a channel's thread runs: waits from the policy, the
## state in the status, the operator told once when the channel goes down.

import std/[strutils, unittest]
import donkey/core/log
import donkey/core/types
import donkey/domain/supervision_pure
import donkey/infra/connection_state
import donkey/infra/supervisor

proc runTests*() =
  suite "channel supervisor":
    setup:
      resetConnections()

    test "a session that ends restarts with growing waits; the status says restarting":
      var s = newSupervised(ckIrc, "irc")
      s.started()
      check supervisionOf(ckIrc) == csRunning
      let w1 = s.ended("connection refused", ranMs = 10, newLogger("t", lvlError), now = 1_000)
      let w2 = s.ended("connection refused", ranMs = 10, newLogger("t", lvlError), now = 3_000)
      check w1 == DefaultPolicy.baseBackoffMs and w2 == 2 * DefaultPolicy.baseBackoffMs
      check supervisionOf(ckIrc) == csRestarting

    test "past the intensity: down, the cool-off as the wait":
      var s = newSupervised(ckNtfy, "ntfy")
      var now = 0'i64
      var wait = 0
      for _ in 0 ..< DefaultPolicy.maxRestarts + 1:
        wait = s.ended("timeout", ranMs = 10, newLogger("t", lvlError), now = now)
        now += wait
      check supervisionOf(ckNtfy) == csDown and wait == DefaultPolicy.coolOffMs

    test "a session that ran a minute or more was healthy: the waits start over":
      var s = newSupervised(ckIrc, "irc")
      discard s.ended("x", ranMs = 10, newLogger("t", lvlError), now = 1_000)
      discard s.ended("x", ranMs = 10, newLogger("t", lvlError), now = 3_000)
      check s.ended("x", ranMs = 120_000, newLogger("t", lvlError), now = 200_000) ==
        DefaultPolicy.baseBackoffMs

    test "started marks the channel up again":
      var s = newSupervised(ckIrc, "irc")
      superviseState(ckIrc, csDown)
      s.started()
      check supervisionOf(ckIrc) == csRunning

when isMainModule:
  runTests()
