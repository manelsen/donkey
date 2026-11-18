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
