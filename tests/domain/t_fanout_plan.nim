## Pure fan-out plan validation and deterministic aggregation.
##
## Covers US-001 (fail-closed plan) and the pure half of US-002 (aggregate,
## stop-reason precedence, sibling policy, budget/progress helpers).

import std/[strutils, unittest]
import results
import donkey/domain/subagent_pure

const availableTools = [
  "session_search",
  "fs_read",
  "text_search",
  "calc",
  "fetch",
]

func request(task: string; tools: seq[string] = @[]; context = "";
             maxTokens = 0; maxDurationMs = 0'i64): FanoutRequest =
  FanoutRequest(
    task: task,
    context: context,
    tools: tools,
    limits: SubagentLimits(
      maxTokens: maxTokens,
      maxDurationMs: maxDurationMs,
    ),
  )

func requests(n: int): seq[FanoutRequest] =
  for i in 0 ..< n:
    result.add(request("task " & $i))

func validLimits(): FanoutLimits =
  FanoutLimits(
    maxAggregateTokens: 100_000,
    maxAggregateDurationMs: 60_000,
  )

func outcome(index: int; status: SubagentStatus; tokens = 0;
             cancelledBySibling = false;
             durationMs = 0'i64): FanoutOutcome =
  FanoutOutcome(
    index: index,
    subagentId: "sub-" & $index,
    status: status,
    usage: SubagentUsage(inputTokens: tokens),
    cancelledBySibling: cancelledBySibling,
    durationMs: durationMs,
  )

proc runTests*() =
  suite "fanout plan and aggregate":

    test "plan accepts one child and keeps the input order":
      let r = planFanout(@[request("only")], validLimits(), availableTools)
      check r.isOk
      let plan = r.get()
      check plan.tasks.len == 1
      check plan.tasks[0].task == "only"
      check plan.limits.maxChildren == FanoutMaxChildren
      check plan.plannedTokens == SubagentDefaultMaxTokens

    test "plan accepts eight children and preserves stable indexes":
      let r = planFanout(requests(FanoutMaxChildren), validLimits(), availableTools)
      check r.isOk
      let plan = r.get()
      check plan.tasks.len == FanoutMaxChildren
      for i in 0 ..< plan.tasks.len:
        check plan.tasks[i].task == "task " & $i
      check plan.plannedTokens == FanoutMaxChildren * SubagentDefaultMaxTokens

    test "plan rejects zero children":
      let empty: seq[FanoutRequest] = @[]
      let r = planFanout(empty, validLimits(), availableTools)
      check r.isErr
      check "at least" in r.error

    test "plan rejects more than the absolute child ceiling":
      let r = planFanout(requests(FanoutMaxChildren + 1), validLimits(),
                         availableTools)
      check r.isErr
      check $FanoutMaxChildren in r.error

    test "plan rejects more children than the configured maxChildren":
      let limits = FanoutLimits(
        maxChildren: 2,
        maxAggregateTokens: 100_000,
        maxAggregateDurationMs: 60_000,
      )
      let r = planFanout(requests(3), limits, availableTools)
      check r.isErr
      check "2" in r.error

    test "plan rejects an empty task through subagentRequestError":
      let r = planFanout(@[request("ok"), request("   ")], validLimits(),
                         availableTools)
      check r.isErr
      check "'task' is required" in r.error

    test "plan rejects a tool absent from the parent session":
      let r = planFanout(@[request("t", @["session_search"])], validLimits(),
                         @["fs_read"])
      check r.isErr
      check r.error ==
            "tool 'session_search' is not available in this session"

    test "plan rejects a hard-denied tool before availability":
      let r = planFanout(@[request("t", @["bash"])], validLimits(),
                         availableTools)
      check r.isErr
      check "not allowed for subagents" in r.error

    test "plan rejects a zero aggregate budget":
      let limits = FanoutLimits(
        maxAggregateTokens: 0,
        maxAggregateDurationMs: 60_000,
      )
      let r = planFanout(@[request("t")], limits, availableTools)
      check r.isErr
      check "budget" in r.error

    test "plan rejects a zero aggregate duration":
      let limits = FanoutLimits(
        maxAggregateTokens: 100_000,
        maxAggregateDurationMs: 0,
      )
      let r = planFanout(@[request("t")], limits, availableTools)
      check r.isErr
      check "maxAggregateDurationMs" in r.error

    test "plan rejects a runtime budget above the absolute ceiling":
      let limits = FanoutLimits(
        maxAggregateTokens: FanoutAbsoluteMaxAggregateTokens + 1,
        maxAggregateDurationMs: 60_000,
      )
      let r = planFanout(@[request("t")], limits, availableTools)
      check r.isErr
      check "absolute" in r.error
      check $FanoutAbsoluteMaxAggregateTokens in r.error

    test "plan rejects the sum of clamped child budgets above the ceiling":
      var tasks = requests(5)
      for i in 0 ..< tasks.len:
        tasks[i].limits.maxTokens = SubagentMaxTokens
      let r = planFanout(tasks, validLimits(), availableTools)
      check r.isErr
      check r.error == "aggregate token budget exceeded: 640000 > 512000"

    test "plan is deterministic for equal input":
      let a = planFanout(requests(3), validLimits(), availableTools)
      let b = planFanout(requests(3), validLimits(), availableTools)
      check a.isOk
      check b.isOk
      check a.get() == b.get()

    test "three children with one failure stop on that failure":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let outcomes = @[
        outcome(0, ssCancelled, tokens = 2, cancelledBySibling = true),
        outcome(1, ssFailed, tokens = 5),
        outcome(2, ssCancelled, tokens = 7, cancelledBySibling = true),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal())
      check agg.stopReason == fsrChildFailed
      check agg.ok == 0
      check agg.failed == 1
      check agg.timedOut == 0
      check agg.cancelled == 2
      check agg.totalTokens == 14
      check agg.children.len == 3
      for i in 0 ..< agg.children.len:
        check agg.children[i].index == i
        check agg.children[i].subagentId == "sub-" & $i
      check fanoutShouldCancelSiblings(agg, fpFailFast)
      check not fanoutShouldCancelSiblings(agg, fpCollectAll)

    test "completion order does not change the aggregate order or totals":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let outcomes = @[
        outcome(0, ssCompleted, tokens = 10, durationMs = 30),
        outcome(1, ssFailed, tokens = 5, durationMs = 20),
        outcome(2, ssCompleted, tokens = 7, durationMs = 40),
      ]
      let forward = aggregateFanout(plan, outcomes, "fan-1", fpCollectAll,
                                    FanoutSignal())
      let reversed = aggregateFanout(plan, @[outcomes[2], outcomes[0],
                                             outcomes[1]], "fan-1",
                                     fpCollectAll, FanoutSignal())
      check forward.children.len == reversed.children.len
      for i in 0 ..< forward.children.len:
        check reversed.children[i].index == i
        check reversed.children[i].subagentId == forward.children[i].subagentId
        check reversed.children[i].status == forward.children[i].status
      check reversed.stopReason == fsrChildFailed
      check reversed.totalTokens == forward.totalTokens
      check reversed.totalDurationMs == forward.totalDurationMs
      check reversed.ok == 2
      check reversed.failed == 1
      check reversed.totalTokens == 22
      check reversed.totalDurationMs == 90

    test "sibling cancellations never become a stop reason":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let outcomes = @[
        outcome(0, ssCancelled, cancelledBySibling = true),
        outcome(1, ssCancelled, cancelledBySibling = true),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal())
      check agg.stopReason == fsrNone
      check agg.cancelled == 2
      check not fanoutShouldCancelSiblings(agg, fpFailFast)

    test "a timed-out child is reported as timed_out":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let outcomes = @[
        outcome(0, ssCompleted, tokens = 3),
        outcome(1, ssTimedOut, tokens = 4),
        outcome(2, ssCancelled, cancelledBySibling = true),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal())
      check agg.stopReason == fsrChildTimedOut
      check agg.ok == 1
      check agg.failed == 0
      check agg.timedOut == 1
      check agg.cancelled == 1
      check agg.totalTokens == 7
      check fanoutShouldCancelSiblings(agg, fpFailFast)

    test "stop reason precedence is spawn, stop, budget, failure":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let outcomes = @[outcome(0, ssFailed)]
      check aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                            FanoutSignal(spawnFailed: true,
                                         stopRequested: true,
                                         budgetExceeded: true)).stopReason ==
            fsrSpawnFailed
      check aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                            FanoutSignal(stopRequested: true,
                                         budgetExceeded: true)).stopReason ==
            fsrSessionStop
      check aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                            FanoutSignal(budgetExceeded: true)).stopReason ==
            fsrAggregateBudget
      check aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                            FanoutSignal()).stopReason == fsrChildFailed

    test "aggregate budget is exceeded mid-run":
      let plan = planFanout(requests(3), FanoutLimits(
        maxAggregateTokens: 20,
        maxAggregateDurationMs: 60_000,
      ), availableTools).get()
      check fanoutBudgetDecision(10, plan.limits) == bdOk
      check fanoutBudgetDecision(19, plan.limits) == bdOk
      check fanoutBudgetDecision(20, plan.limits) == bdTokensExceeded
      check fanoutBudgetDecision(25, plan.limits) == bdTokensExceeded

      let outcomes = @[
        outcome(0, ssCompleted, tokens = 10),
        outcome(1, ssCompleted, tokens = 15),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal(budgetExceeded: true))
      check agg.totalTokens == 25
      check fanoutBudgetDecision(agg.totalTokens, plan.limits) ==
            bdTokensExceeded
      check agg.stopReason == fsrAggregateBudget

    test "default aggregate budget is the documented 256k":
      let limits = defaultFanoutLimits()
      check limits.maxChildren == FanoutMaxChildren
      check limits.maxAggregateTokens == FanoutDefaultAggregateTokens
      check fanoutBudgetDecision(0, limits) == bdOk
      check fanoutBudgetDecision(FanoutDefaultAggregateTokens - 1, limits) ==
            bdOk
      check fanoutBudgetDecision(FanoutDefaultAggregateTokens, limits) ==
            bdTokensExceeded

    test "progress throttle is pure":
      check not fanoutProgressDue(1_000, 1_999)
      check fanoutProgressDue(1_000, 2_000)
      check fanoutProgressDue(1_000, 1_500, 500)
      check not fanoutProgressDue(2_000, 1_999)
      check fanoutProgressDue(5_000, 5_000, 0)

    test "aggregate totals include failed and cancelled usage":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let outcomes = @[
        outcome(0, ssCompleted, tokens = 10, durationMs = 30),
        outcome(1, ssFailed, tokens = 5, durationMs = 20),
        outcome(2, ssCancelled, tokens = 7, durationMs = 40,
                cancelledBySibling = true),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal())
      check agg.totalTokens == 22
      check agg.totalDurationMs == 90
      check agg.children[2].cancelledBySibling

    # Audit hardening: cases that must not be silently reordered, re-counted or
    # crash on hostile outcome sequences.

    test "task order follows input, not lexical order":
      let tasks = @[request("zeta"), request("alpha"), request("mike")]
      let plan = planFanout(tasks, validLimits(), availableTools).get()
      check plan.tasks.len == 3
      check plan.tasks[0].task == "zeta"
      check plan.tasks[1].task == "alpha"
      check plan.tasks[2].task == "mike"

    test "duplicate outcome indexes keep the first and do not double count":
      let plan = planFanout(requests(2), validLimits(), availableTools).get()
      let outcomes = @[
        FanoutOutcome(index: 0, subagentId: "first", status: ssCompleted,
                      usage: SubagentUsage(inputTokens: 10)),
        FanoutOutcome(index: 0, subagentId: "second", status: ssFailed,
                      usage: SubagentUsage(inputTokens: 999)),
        outcome(1, ssCompleted, tokens = 5),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal())
      check agg.children[0].subagentId == "first"
      check agg.children[0].status == ssCompleted
      check agg.children[1].subagentId == "sub-1"
      check agg.totalTokens == 15
      check agg.ok == 2
      check agg.failed == 0
      check agg.stopReason == fsrNone

    test "out-of-range and negative outcome indexes are ignored":
      let plan = planFanout(requests(2), validLimits(), availableTools).get()
      let outcomes = @[
        outcome(-1, ssFailed, tokens = 100),
        outcome(99, ssTimedOut, tokens = 100),
        outcome(1, ssCompleted, tokens = 3),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal())
      check agg.children.len == 2
      check agg.children[0].index == 0
      check agg.children[0].status == ssQueued
      check agg.children[1].index == 1
      check agg.children[1].status == ssCompleted
      check agg.totalTokens == 3
      check agg.failed == 0
      check agg.timedOut == 0
      check agg.stopReason == fsrNone

    test "a missing child becomes a queued placeholder at its plan index":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let outcomes = @[
        outcome(0, ssCompleted, tokens = 4),
        outcome(2, ssCompleted, tokens = 6),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal())
      check agg.children.len == 3
      check agg.children[1].index == 1
      check agg.children[1].status == ssQueued
      check agg.children[1].subagentId.len == 0
      check agg.children[1].usage == nil
      check agg.ok == 2
      check agg.totalTokens == 10
      check agg.stopReason == fsrNone

    test "aggregate duration above the 600 s cap is rejected":
      let overCap = FanoutLimits(
        maxAggregateTokens: 100_000,
        maxAggregateDurationMs: 600_001,
      )
      let r = planFanout(@[request("t")], overCap, availableTools)
      check r.isErr
      check "600000" in r.error
      let atCap = FanoutLimits(
        maxAggregateTokens: 100_000,
        maxAggregateDurationMs: 600_000,
      )
      check planFanout(@[request("t")], atCap, availableTools).isOk

    test "configured maxChildren above the absolute ceiling is rejected":
      let limits = FanoutLimits(
        maxChildren: FanoutMaxChildren + 1,
        maxAggregateTokens: 100_000,
        maxAggregateDurationMs: 60_000,
      )
      let r = planFanout(@[request("t")], limits, availableTools)
      check r.isErr
      check "maxChildren" in r.error
      check "9" in r.error
      check "8" in r.error

    test "a plain cancelled child does not stop or cancel siblings":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let outcomes = @[
        outcome(0, ssCancelled),
        outcome(1, ssCompleted),
        outcome(2, ssCompleted),
      ]
      let agg = aggregateFanout(plan, outcomes, "fan-1", fpFailFast,
                                FanoutSignal())
      check agg.cancelled == 1
      check agg.ok == 2
      check agg.failed == 0
      check agg.stopReason == fsrNone
      check not agg.children[0].cancelledBySibling
      check not fanoutShouldCancelSiblings(agg, fpFailFast)

    test "mixed failure and timeout use the first failure by index":
      let plan = planFanout(requests(3), validLimits(), availableTools).get()
      let timeoutFirst = aggregateFanout(plan, @[
        outcome(0, ssTimedOut),
        outcome(1, ssFailed),
      ], "fan-1", fpFailFast, FanoutSignal())
      check timeoutFirst.stopReason == fsrChildTimedOut
      check timeoutFirst.timedOut == 1
      check timeoutFirst.failed == 1
      check fanoutShouldCancelSiblings(timeoutFirst, fpFailFast)

      let failedFirst = aggregateFanout(plan, @[
        outcome(0, ssFailed),
        outcome(1, ssTimedOut),
      ], "fan-1", fpFailFast, FanoutSignal())
      check failedFirst.stopReason == fsrChildFailed
      check failedFirst.failed == 1
      check failedFirst.timedOut == 1
      check fanoutShouldCancelSiblings(failedFirst, fpFailFast)

    test "default limits keep the 120 s duration":
      check defaultFanoutLimits().maxAggregateDurationMs == 120_000

    test "a zero runtime budget falls back to 256k in decisions":
      let limits = FanoutLimits(maxAggregateTokens: 0)
      check fanoutBudgetDecision(FanoutDefaultAggregateTokens - 1, limits) ==
            bdOk
      check fanoutBudgetDecision(FanoutDefaultAggregateTokens, limits) ==
            bdTokensExceeded

when isMainModule:
  runTests()
