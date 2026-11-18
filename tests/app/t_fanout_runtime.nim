## Tests for the fan-out runtime supervisor (US-003).
##
## Covers concurrent start, partial spawn failure, fail-fast sibling
## cancellation, the aggregate runtime ceiling, detached fan-outs on
## shutdown, and the settle-before-remove invariant with a spy port.

import std/[os, strutils, tables, unittest]
import chronos
import chronos/asyncsync
import donkey/app/native_tools
import donkey/app/provider_executor
import donkey/app/subagent_runtime
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/domain/subagent_pure
import donkey/ports/memory
import donkey/ports/provider
import donkey/ports/subagent_workspace

let fanoutBase = getTempDir() / ("donkey_fanout_runtime_" & $getCurrentProcessId())
let fanoutLog = newLogger("test.fanout", lvlError)

type
  WorkspaceSpy = ref object
    creates:       seq[string]
    removes:       seq[string]
    settledAtRemove: seq[bool]
    ## Status of every child at each `remove` call, indexed like `removes`.
    ## Used to prove that siblings are signalled before any settlement runs.
    statusesAtRemove: seq[seq[SubagentStatus]]
    failCreateAt:  int  ## 1-based create call that fails; 0 never fails
    mgr:           SubagentManager

proc spyCreate(spy: WorkspaceSpy; root, subagentId: string):
               Result[string, string] {.gcsafe, raises: [].} =
  {.cast(raises: []).}:
    spy.creates.add(subagentId)
  if spy.failCreateAt > 0 and spy.creates.len == spy.failCreateAt:
    return err("injected create failure")
  ok(root / "subagents" / subagentId)

proc spyRemove(spy: WorkspaceSpy; path: string):
               Result[void, string] {.gcsafe, raises: [].} =
  {.cast(raises: []).}:
    let id = path.split('/')[^1]
    spy.removes.add(id)
    let mgr = spy.mgr
    spy.settledAtRemove.add(if mgr.isNil: false else: mgr.childSettled(id))
    var statuses: seq[SubagentStatus]
    if not mgr.isNil:
      for info in mgr.listSubagents():
        statuses.add(info.status)
    spy.statusesAtRemove.add(statuses)
  ok()

proc spyWorkspace(spy: WorkspaceSpy): SubagentWorkspacePort =
  result = SubagentWorkspacePort(
    create: proc(root, subagentId: string): Result[string, string]
                    {.gcsafe, raises: [].} =
      spyCreate(spy, root, subagentId),
    remove: proc(path: string): Result[void, string] {.gcsafe, raises: [].} =
      spyRemove(spy, path),
  )

proc testTools(): seq[ToolDescription] =
  @[
    ToolDescription(name: "current_time", description: "clock",
                    schemaJson: "{}"),
  ]

proc makeParent(base: string; asyncComplete: AsyncCompleteFn;
                stopGeneration = 0'u64; userInterrupt = 0'u64): NativeCtx =
  createDir(base / "paddock")
  result = NativeCtx(
    uid: UserId("user-a"),
    channel: ckCli,
    outbox: newAsyncQueue[OutboundMessage](),
    memory: MemoryRuntimePort(),
    completeFn: proc(req: CompletionRequest):
        Result[CompletionResponse, string] {.gcsafe.} =
      discard req
      err("sync provider must not be used"),
    asyncCompleteFn: asyncComplete,
    log: fanoutLog,
    paddockDir: base / "paddock",
    tools: testTools(),
    stopGeneration: stopGeneration,
    userInterrupt: userInterrupt,
  )

proc task(text: string; maxTokens = 32_000): FanoutRequest =
  FanoutRequest(
    task: text,
    tools: @["current_time"],
    limits: SubagentLimits(maxToolCalls: 4, maxTokens: maxTokens,
                           maxDurationMs: 3_000),
  )

proc makePlan(tasks: seq[FanoutRequest]; aggregateTokens = 256_000;
              durationMs = 5_000'i64): FanoutPlan =
  planFanout(tasks,
             FanoutLimits(maxChildren: 8,
                          maxAggregateTokens: aggregateTokens,
                          maxAggregateDurationMs: durationMs),
             @["current_time"]).get()

proc requestText(req: CompletionRequest): string =
  for msg in req.messages:
    result.add(msg.text)
    result.add("\n")

proc waitCount(counter: ref int; expected: int) {.async, gcsafe.} =
  var attempts = 0
  while counter[] < expected and attempts < 2_000:
    await sleepAsync(chronos.milliseconds(1))
    inc attempts

proc childStatus(mgr: SubagentManager; subagentId: string): SubagentStatus =
  for info in mgr.listSubagents():
    if info.subagentId == subagentId:
      return info.status
  ssQueued

proc waitRemoves(spy: WorkspaceSpy; expected: int) {.async, gcsafe.} =
  var attempts = 0
  while spy.removes.len < expected and attempts < 2_000:
    await sleepAsync(chronos.milliseconds(1))
    inc attempts

proc waitStatus(mgr: SubagentManager; subagentId: string;
                status: SubagentStatus; attempts = 400) {.async, gcsafe.} =
  ## Bounded poll for a transition. Never asserts: the caller decides.
  var tries = 0
  while childStatus(mgr, subagentId) != status and tries < attempts:
    await sleepAsync(chronos.milliseconds(2))
    inc tries

proc waitFanoutDone(mgr: SubagentManager; fanoutId: string;
                    attempts = 1_000) {.async, gcsafe.} =
  var tries = 0
  while fanoutId in mgr.fanouts and not mgr.fanouts[fanoutId].done and
      tries < attempts:
    await sleepAsync(chronos.milliseconds(2))
    inc tries

func liveCount(statuses: seq[SubagentStatus]): int =
  for status in statuses:
    if status in {ssQueued, ssRunning}:
      inc result

suite "fanout runtime":

  test "three children start together and aggregate in plan order":
    let base = fanoutBase / "all-ok"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      {.cast(gcsafe).}:
        inc opened[]
        if 3 <= opened[]:
          gate.fire()
      var together = false
      {.cast(gcsafe).}:
        together = await withTimeout(gate.wait(),
                                     chronos.milliseconds(1_500))
      if not together:
        return err("children did not start together")
      return ok(CompletionResponse(text: "child answer",
                                   inputTokens: 10, outputTokens: 5))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("alpha"), task("beta"), task("gamma")])

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    check started.error.len == 0
    check started.failedIndex == -1
    check started.handle.childIds.len == 3
    check mgr.fanouts.hasKey(started.handle.fanoutId)
    waitFor waitCount(opened, 3)
    check opened[] == 3

    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    check agg.fanoutId == started.handle.fanoutId
    check agg.children.len == 3
    check agg.ok == 3
    check agg.stopReason == fsrNone
    check agg.totalTokens == 45
    for i, child in agg.children:
      check child.subagentId == started.handle.childIds[i]
      check child.status == ssCompleted

    waitFor waitRemoves(spy, 3)
    check spy.creates.len == 3
    check spy.removes.len == 3
    check spy.settledAtRemove == @[true, true, true]

  test "a spawn failure cancels and removes the children already created":
    let base = fanoutBase / "spawn-failure"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      {.cast(gcsafe).}:
        inc opened[]
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy(failCreateAt: 2)
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("one"), task("two"), task("three")])

    let started = waitFor mgr.startFanout(parent, plan, fpFailFast)
    check started.error.len > 0
    check "injected create failure" in started.error
    check started.failedIndex == 1
    check started.handle.childIds.len == 1
    check started.handle.childIds[0] in started.error
    check spy.creates.len == 2
    check spy.removes.len == 1
    check spy.settledAtRemove == @[true]
    let created = started.handle.childIds[0]
    check childStatus(mgr, created) == ssCancelled
    check mgr.childSettled(created)

    let spy2 = WorkspaceSpy(failCreateAt: 2)
    let mgr2 = newSubagentManager(spyWorkspace(spy2))
    spy2.mgr = mgr2
    let agg = waitFor mgr2.spawnFanout(parent, plan, fpFailFast)
    check agg.stopReason == fsrSpawnFailed
    check agg.children.len == 3
    check agg.children[0].subagentId.startsWith("sub-")
    check agg.children[0].status == ssCancelled
    check agg.children[1].status == ssQueued
    check spy2.creates.len == 2
    check spy2.removes.len == 1
    check spy2.settledAtRemove == @[true]

  test "a failing child cancels its siblings under fail-fast":
    let base = fanoutBase / "child-failure"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      let text = requestText(req)
      {.cast(gcsafe).}:
        inc opened[]
      if "boom" in text:
        return err("injected child failure")
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("first"), task("boom"), task("third")])

    let started = waitFor mgr.startFanout(parent, plan, fpFailFast)
    check started.error.len == 0
    check started.handle.childIds.len == 3
    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    check agg.stopReason == fsrChildFailed
    check agg.children[1].status == ssFailed
    check "injected child failure" in agg.children[1].error
    check agg.children[0].status == ssCancelled
    check agg.children[0].cancelledBySibling
    check agg.children[2].status == ssCancelled
    check agg.children[2].cancelledBySibling
    check agg.failed == 1
    check agg.cancelled == 2

    waitFor waitRemoves(spy, 3)
    check spy.creates.len == 3
    check spy.removes.len == 3
    for settled in spy.settledAtRemove:
      check settled

  test "the aggregate budget counts finished children and cancels the rest":
    let base = fanoutBase / "aggregate-budget"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      let text = requestText(req)
      {.cast(gcsafe).}:
        inc opened[]
      if "cheap-a" in text:
        return ok(CompletionResponse(text: "a", inputTokens: 10,
                                     outputTokens: 5))
      if "cheap-b" in text:
        return ok(CompletionResponse(text: "b", inputTokens: 6,
                                     outputTokens: 4))
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("cheap-a"), task("cheap-b"), task("blocked")],
                        aggregateTokens = 20)

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    check started.error.len == 0
    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    check agg.stopReason == fsrAggregateBudget
    check agg.children[0].status == ssCompleted
    check agg.children[1].status == ssCompleted
    check agg.children[2].status == ssCancelled
    check agg.totalTokens == 25

    waitFor waitRemoves(spy, 3)
    check spy.creates.len == spy.removes.len
    for settled in spy.settledAtRemove:
      check settled

  test "cancelAll cancels a detached fan-out and waits for settlement":
    let base = fanoutBase / "cancel-all"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      {.cast(gcsafe).}:
        inc opened[]
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("one"), task("two"), task("three")])

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    check started.error.len == 0
    waitFor waitCount(opened, 3)
    check opened[] == 3
    check mgr.fanouts.hasKey(started.handle.fanoutId)

    waitFor mgr.cancelAll()
    waitFor waitRemoves(spy, 3)
    for id in started.handle.childIds:
      check childStatus(mgr, id) == ssCancelled
      check mgr.childSettled(id)
    check mgr.fanouts[started.handle.fanoutId].signal.stopRequested
    check spy.creates.len == 3
    check spy.removes.len == 3
    check spy.settledAtRemove == @[true, true, true]

  test "removal happens only after the child is settled":
    let base = fanoutBase / "settled-remove"
    removeDir(base)
    defer: removeDir(base)
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      await sleepAsync(chronos.milliseconds(5))
      return ok(CompletionResponse(text: "done", inputTokens: 2,
                                   outputTokens: 1))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("one"), task("two")])

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    check agg.ok == 2
    waitFor waitRemoves(spy, 2)
    check spy.creates.len == 2
    check spy.removes.len == 2
    for i, settled in spy.settledAtRemove:
      check settled
      check spy.removes[i] == spy.creates[i]
    for child in agg.children:
      check child.status == ssCompleted

  # ── Deferred findings C1–C7 (tasks/reviews/deferred-findings-v4.md) ─────────

  test "awaitFanout does not publish before an in-flight shutdown settles":
    ## C1: `cancelAll` marks the fan-out done before it finishes settling the
    ## children. A concurrent consumer must wait for that settlement instead of
    ## publishing queued placeholders.
    let base = fanoutBase / "settle-before-publish"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      {.cast(gcsafe).}:
        inc opened[]
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("one"), task("two"), task("three")])

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    check started.error.len == 0
    waitFor waitCount(opened, 3)
    check opened[] == 3

    # Shutdown runs first and suspends in its settlement loop; the consumer
    # then asks for the aggregate while that settlement is still in flight.
    let shutdown = mgr.cancelAll()
    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)

    for id in started.handle.childIds:
      check mgr.childSettled(id)
    check spy.removes.len == 3
    check agg.children.len == 3
    for child in agg.children:
      check child.status == ssCancelled
    check agg.cancelled == 3
    check agg.stopReason == fsrSessionStop
    waitFor shutdown

  test "awaitFanout publishes only after every child of the fan-out settled":
    ## C1: fail-fast cancels the sibling and reports `done` as soon as its own
    ## settlement work returns. The sibling's result is still being published
    ## inside its own future then, so the consumer must wait for the child to
    ## settle instead of reading a half-cancelled fan-out.
    let base = fanoutBase / "settle-in-flight"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let lift = newAsyncEvent()
    defer: lift.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      {.cast(gcsafe).}:
        inc opened[]
      if "boom" in requestText(req):
        return err("injected child failure")
      {.cast(gcsafe).}:
        await lift.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("first"), task("boom")])

    let started = waitFor mgr.startFanout(parent, plan, fpFailFast)
    check started.error.len == 0
    var attempts = 0
    while opened[] < 1 and attempts < 2_000:
      waitFor sleepAsync(chronos.milliseconds(1))
      inc attempts
    check opened[] >= 1
    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    for id in started.handle.childIds:
      check mgr.childSettled(id)
    check agg.children[0].status == ssCancelled
    check agg.children[0].cancelledBySibling
    check agg.children[1].status == ssFailed
    check agg.stopReason == fsrChildFailed
    waitFor waitRemoves(spy, 2)
    check spy.removes.len == 2
    for settled in spy.settledAtRemove:
      check settled

  test "fail-fast signals every sibling before settling any of them":
    ## C2: the failed child's siblings are signalled in one phase; settling the
    ## first sibling must not leave the others running (they could complete in
    ## that window).
    let base = fanoutBase / "signal-all-first"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      let text = requestText(req)
      {.cast(gcsafe).}:
        inc opened[]
      if "boom" in text:
        return err("injected child failure")
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("first"), task("boom"), task("third")])

    let started = waitFor mgr.startFanout(parent, plan, fpFailFast)
    check started.error.len == 0
    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    check agg.stopReason == fsrChildFailed
    check agg.children[0].status == ssCancelled
    check agg.children[2].status == ssCancelled
    check agg.children[0].cancelledBySibling
    check agg.children[2].cancelledBySibling

    waitFor waitRemoves(spy, 3)
    let blocked = [started.handle.childIds[0], started.handle.childIds[2]]
    var checkedBlocked = 0
    for i, removedId in spy.removes:
      if removedId notin blocked:
        continue
      inc checkedBlocked
      # At the removal of a cancelled sibling, no other child may still be
      # queued or running: the signal phase ran before any settlement.
      check liveCount(spy.statusesAtRemove[i]) == 0
    check checkedBlocked == 2

  test "an awaited fan-out is removed from the registry":
    ## C3: plan, outcomes and future are dropped once the aggregate is built.
    let base = fanoutBase / "fanout-removed"
    removeDir(base)
    defer: removeDir(base)
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      await sleepAsync(chronos.milliseconds(2))
      return ok(CompletionResponse(text: "done", inputTokens: 2,
                                   outputTokens: 1))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("one"), task("two")])

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    check mgr.fanouts.hasKey(started.handle.fanoutId)
    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    check agg.ok == 2
    check not mgr.fanouts.hasKey(started.handle.fanoutId)
    waitFor waitRemoves(spy, 2)

  test "an external cancel fails fast on the siblings":
    ## C5: cancelling one child from outside is a fail-fast trigger; the flag
    ## `cancelledBySibling` belongs to the supervisor-cancelled siblings, not
    ## to the externally cancelled child.
    let base = fanoutBase / "external-cancel"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      {.cast(gcsafe).}:
        inc opened[]
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("first"), task("second"), task("third")])

    let started = waitFor mgr.startFanout(parent, plan, fpFailFast)
    check started.error.len == 0
    waitFor waitCount(opened, 3)
    check waitFor mgr.cancelSubagent(started.handle.childIds[1])

    waitFor waitStatus(mgr, started.handle.childIds[0], ssCancelled)
    waitFor waitStatus(mgr, started.handle.childIds[2], ssCancelled)
    let firstCancelled = childStatus(mgr, started.handle.childIds[0]) ==
                         ssCancelled
    let thirdCancelled = childStatus(mgr, started.handle.childIds[2]) ==
                         ssCancelled
    check firstCancelled
    check thirdCancelled
    # Without the sibling signal the blocked children never finish, so the
    # aggregate is only asked for once they are cancelled.
    if firstCancelled and thirdCancelled:
      let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                        $parent.uid, 0)
      check agg.children[1].status == ssCancelled
      check not agg.children[1].cancelledBySibling
      check agg.children[0].cancelledBySibling
      check agg.children[2].cancelledBySibling
    waitFor mgr.cancelAll()
    waitFor waitRemoves(spy, 3)

  test "an external cancel leaves the siblings alone under collect-all":
    ## C5 boundary: the fail-fast trigger is policy-scoped.
    let base = fanoutBase / "external-cancel-collect"
    removeDir(base)
    defer: removeDir(base)
    let opened = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      {.cast(gcsafe).}:
        inc opened[]
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "late"))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("first"), task("second"), task("third")])

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    check started.error.len == 0
    waitFor waitCount(opened, 3)
    check waitFor mgr.cancelSubagent(started.handle.childIds[1])
    waitFor sleepAsync(chronos.milliseconds(60))
    check childStatus(mgr, started.handle.childIds[0]) == ssRunning
    check childStatus(mgr, started.handle.childIds[2]) == ssRunning
    waitFor mgr.cancelAll()
    waitFor waitRemoves(spy, 3)

  test "the aggregate token cap is enforced at each completion":
    ## C6: A+B blow the cap at completion time, so C must not start another
    ## provider round waiting for the 100 ms tick.
    let base = fanoutBase / "cap-at-completion"
    removeDir(base)
    defer: removeDir(base)
    let fastDone = new(int)
    let secondRound = new(int)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      let text = requestText(req)
      if "cheap-a" in text:
        {.cast(gcsafe).}:
          inc fastDone[]
        return ok(CompletionResponse(text: "a", inputTokens: 10,
                                     outputTokens: 5))
      if "cheap-b" in text:
        {.cast(gcsafe).}:
          inc fastDone[]
        return ok(CompletionResponse(text: "b", inputTokens: 6,
                                     outputTokens: 4))
      var firstRound = false
      {.cast(gcsafe).}:
        inc secondRound[]
        firstRound = secondRound[] == 1
      if firstRound:
        # First round: wait for the cap to be blown by the cheap children, then
        # hand back a tool call so the loop asks the provider again — the
        # second round the completion-time check must prevent.
        {.cast(gcsafe).}:
          await gate.wait()
        return ok(CompletionResponse(
          text: "",
          toolCalls: @[ToolCallRequest(id: "call-1", name: "current_time",
                                       inputJson: "{}")],
        ))
      return ok(CompletionResponse(text: "second round", inputTokens: 1,
                                   outputTokens: 1))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("cheap-a"), task("cheap-b"), task("blocked")],
                        aggregateTokens = 20)

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    check started.error.len == 0
    waitFor waitCount(fastDone, 2)
    waitFor sleepAsync(chronos.milliseconds(10))
    gate.fire()

    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    # 0 rounds if the cancel won the start, 1 if the first round was already
    # in flight; never the second round.
    check secondRound[] < 2
    check agg.stopReason == fsrAggregateBudget
    check agg.children[0].status == ssCompleted
    check agg.children[1].status == ssCompleted
    check agg.children[2].status == ssCancelled
    check agg.totalTokens >= 25
    waitFor waitRemoves(spy, 3)

  test "a completion after the aggregate deadline is timed out":
    ## C7: the deadline is applied when the child finishes, not on the next
    ## tick; a child finishing 25 ms after a 10 ms deadline is not accepted.
    let base = fanoutBase / "deadline-at-completion"
    removeDir(base)
    defer: removeDir(base)
    let gate = newAsyncEvent()
    defer: gate.fire()
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      {.cast(gcsafe).}:
        await gate.wait()
      return ok(CompletionResponse(text: "too late", inputTokens: 2,
                                   outputTokens: 1))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)
    let plan = makePlan(@[task("late")], durationMs = 10)

    let started = waitFor mgr.startFanout(parent, plan, fpCollectAll)
    check started.error.len == 0
    # Past the 10 ms aggregate deadline but well before the 100 ms tick.
    waitFor sleepAsync(chronos.milliseconds(25))
    gate.fire()

    let agg = waitFor mgr.awaitFanout(started.handle.fanoutId, 0,
                                      $parent.uid, 0)
    check agg.children.len == 1
    check agg.children[0].status == ssTimedOut
    check "aggregate duration" in agg.children[0].error
    check agg.timedOut == 1
    check agg.ok == 0
    check agg.stopReason == fsrChildTimedOut
    waitFor waitRemoves(spy, 1)

  test "the settlement wait is a monotonic deadline, not the child's finish":
    ## C4: chronos `withTimeout` cancels *and* waits, so a future that ignores
    ## cancellation makes the 2 s bound unbounded. The bounded wait must abandon
    ## the future at the deadline instead.
    let release = new(bool)
    let stubborn = proc(release: ref bool): Future[void] {.async, gcsafe.} =
      while true:
        var done = false
        {.cast(gcsafe).}:
          done = release[]
        if done:
          return
        try:
          await sleepAsync(chronos.milliseconds(5))
        except CancelledError:
          discard
    let fut = stubborn(release)
    let started = nowMs()
    let settled = waitFor awaitSettled(fut, 100)
    let elapsed = nowMs() - started
    check not settled
    check elapsed >= 80
    check elapsed < 1_500
    check not fut.finished()
    release[] = true
    waitFor sleepAsync(chronos.milliseconds(30))

  test "completed fan-out states are pruned by count and age":
    ## C3: a detached fan-out nobody awaits is bounded by retention.
    let base = fanoutBase / "prune-fanouts"
    removeDir(base)
    defer: removeDir(base)
    let complete = proc(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
      discard req
      await sleepAsync(chronos.milliseconds(1))
      return ok(CompletionResponse(text: "done", inputTokens: 2,
                                   outputTokens: 1))
    let spy = WorkspaceSpy()
    let mgr = newSubagentManager(spyWorkspace(spy))
    spy.mgr = mgr
    var parent = makeParent(base, complete)

    let first = waitFor mgr.startFanout(parent, makePlan(@[task("first")]),
                                        fpCollectAll)
    waitFor waitFanoutDone(mgr, first.handle.fanoutId)
    let second = waitFor mgr.startFanout(parent, makePlan(@[task("second")]),
                                         fpCollectAll)
    waitFor waitFanoutDone(mgr, second.handle.fanoutId)
    check mgr.fanouts.hasKey(first.handle.fanoutId)
    check mgr.fanouts.hasKey(second.handle.fanoutId)

    mgr.pruneFanouts(retain = 1)
    check not mgr.fanouts.hasKey(first.handle.fanoutId)
    check mgr.fanouts.hasKey(second.handle.fanoutId)

    mgr.pruneFanouts(retain = SubagentFanoutRetention,
                     atMs = nowMs() + SubagentFanoutRetentionMs + 1)
    check not mgr.fanouts.hasKey(second.handle.fanoutId)
    waitFor waitRemoves(spy, 2)
