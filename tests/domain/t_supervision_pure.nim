## E12.2: a supervisor's decisions, OTP-style, pure: restart a child that
## ended (one_for_one), by its kind, within an intensity, with growing
## waits; past the intensity, escalate: the child is down, the rest goes on.

import std/unittest
import donkey/domain/supervision_pure

const P = RestartPolicy(kind: rkPermanent, maxRestarts: 3, withinMs: 60_000,
                        baseBackoffMs: 1_000, maxBackoffMs: 8_000, coolOffMs: 300_000)

proc runTests*() =
  suite "supervision":
    test "permanent: restarted whether it failed or ended, with growing waits":
      var rec = ChildRecord()
      var d = rec.onExit(P, exError, 1_000)
      check d.action == raRestart and d.afterMs == 1_000 and rec.state == csRestarting
      d = rec.onExit(P, exNormal, 2_000)
      check d.action == raRestart and d.afterMs == 2_000
      d = rec.onExit(P, exError, 3_000)
      check d.action == raRestart and d.afterMs == 4_000

    test "past the intensity the child is down for a cool-off, then tries again":
      var rec = ChildRecord()
      for t in [1_000'i64, 2_000, 3_000]:
        check rec.onExit(P, exError, t).action == raRestart
      let d = rec.onExit(P, exError, 4_000)
      check d.action == raDown and d.afterMs == 300_000 and rec.state == csDown
      ## after the cool-off a new attempt counts afresh
      check rec.onExit(P, exError, 304_000).action == raRestart
      check rec.state == csRestarting

    test "running again after a cool-off is no longer down":
      var rec = ChildRecord()
      for t in [1_000'i64, 2_000, 3_000, 4_000]: discard rec.onExit(P, exError, t)
      check rec.state == csDown
      rec.markRunning(305_000)
      check rec.state == csRunning

    test "down is said once per episode":
      var rec = ChildRecord()
      for t in [1_000'i64, 2_000, 3_000]: discard rec.onExit(P, exError, t)
      check rec.onExit(P, exError, 4_000).firstDown
      rec.markRunning(400_000)
      for t in [401_000'i64, 402_000, 403_000]: discard rec.onExit(P, exError, t)
      check rec.onExit(P, exError, 404_000).firstDown

    test "restarts older than the window do not count":
      var rec = ChildRecord()
      for t in [1_000'i64, 2_000, 3_000]:
        discard rec.onExit(P, exError, t)
      check rec.onExit(P, exError, 70_000).action == raRestart
      check rec.restartsInWindow(70_000, P) == 1

    test "a long healthy run resets the waits":
      var rec = ChildRecord()
      discard rec.onExit(P, exError, 1_000)
      discard rec.onExit(P, exError, 2_000)
      rec.markRunning(2_500)
      check rec.onExit(P, exError, 200_000).afterMs == 1_000   ## the window has passed

    test "a healthy run forgets the restarts before it":
      var rec = ChildRecord()
      for t in [1_000'i64, 2_000, 3_000]: discard rec.onExit(P, exError, t)
      rec.healthyRun()
      check rec.restartsInWindow(4_000, P) == 0
      check rec.onExit(P, exError, 4_000).afterMs == 1_000

    test "transient: restarted only after an error; temporary: never":
      var t = ChildRecord()
      let transient = RestartPolicy(kind: rkTransient, maxRestarts: 3, withinMs: 60_000,
                                    baseBackoffMs: 1_000, maxBackoffMs: 8_000)
      check t.onExit(transient, exNormal, 1_000).action == raStop
      var t2 = ChildRecord()
      check t2.onExit(transient, exError, 1_000).action == raRestart
      var tmp = ChildRecord()
      let temporary = RestartPolicy(kind: rkTemporary)
      check tmp.onExit(temporary, exError, 1_000).action == raStop
      check tmp.state == csStopped

    test "the defaults: 5 restarts in 5 minutes, then 5 minutes down":
      check DefaultPolicy.maxRestarts == 5 and DefaultPolicy.withinMs == 300_000
      check DefaultPolicy.coolOffMs == 300_000 and DefaultPolicy.kind == rkPermanent
      ## with the growing waits, an outage reaches it after about a minute
      var rec = ChildRecord()
      var now = 0'i64
      var downAt = -1'i64
      for _ in 0 ..< 10:
        let d = rec.onExit(DefaultPolicy, exError, now)
        if d.action == raDown:
          downAt = now
          break
        now += d.afterMs
      check downAt in 50_000'i64 .. 130_000

when isMainModule:
  runTests()
