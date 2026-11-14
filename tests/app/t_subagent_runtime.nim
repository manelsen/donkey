## Tests for the subagent runtime: isolation, budgets, cancellation, approvals.

import std/[json, os, strutils, unittest]
import chronos
import chronos/asyncsync
import results
import donkey/app/approval_runtime
import donkey/app/native_tools
import donkey/app/session_state
import donkey/app/subagent_runtime
import donkey/core/log
import donkey/core/pipeops
import donkey/core/security/approval
import donkey/core/types
import donkey/domain/message
import donkey/domain/subagent_pure
import donkey/ports/approval
import donkey/ports/memory
import donkey/ports/provider

let subagentBase = getTempDir() / ("donkey_subagent_tests_" & $getCurrentProcessId())
let subagentLog = newLogger("test.subagent", lvlError)

proc textComplete(req: CompletionRequest):
                  Result[CompletionResponse, string] {.gcsafe.} =
  discard req
  ok(CompletionResponse(text: "child answer", inputTokens: 10, outputTokens: 5))

proc asyncTextComplete(req: CompletionRequest):
                       Future[Result[CompletionResponse, string]]
                       {.async, gcsafe.} =
  discard req
  await sleepAsync(chronos.milliseconds(5))
  return ok(CompletionResponse(text: "async child", inputTokens: 7,
                               outputTokens: 3))

proc toolLoopComplete(callCount: ref int; toolCalls: int): CompleteFn =
  result = proc(req: CompletionRequest):
                 Result[CompletionResponse, string] {.gcsafe.} =
    discard req
    inc callCount[]
    if callCount[] <= toolCalls:
      ok(CompletionResponse(
        text: "",
        toolCalls: @[ToolCallRequest(
          id: "call-" & $callCount[],
          name: "current_time",
          inputJson: "{}",
        )],
      ))
    else:
      ok(CompletionResponse(text: "finished", inputTokens: 3, outputTokens: 2))

proc testTools(): seq[ToolDescription] =
  @[
    ToolDescription(name: "current_time", description: "clock",
                    schemaJson: "{}"),
    ToolDescription(name: "read_file", description: "read",
                    schemaJson: "{}"),
    ToolDescription(name: "session_search", description: "search",
                    schemaJson: "{}"),
  ]

proc makeParent(base: string; completeFn: CompleteFn;
                tools = testTools()): NativeCtx =
  createDir(base / "paddock")
  NativeCtx(
    uid: UserId("user-a"),
    channel: ckCli,
    outbox: newAsyncQueue[OutboundMessage](),
    memory: MemoryRuntimePort(),
    completeFn: completeFn,
    log: subagentLog,
    paddockDir: base / "paddock",
    tools: tools,
  )

proc spawnCall(task: string; extra = ""): ToolCallRequest =
  let suffix = if extra.len > 0: "," & extra else: ""
  ToolCallRequest(
    id: "spawn-1",
    name: "spawn_subagent",
    inputJson: "{\"task\":\"" & task & "\"" & suffix & "}",
  )

proc awaitCall(subagentId: string): ToolCallRequest =
  ToolCallRequest(
    id: "await-1",
    name: "await_subagent",
    inputJson: "{\"subagent_id\":\"" & subagentId & "\"}",
  )

suite "subagent runtime":

  test "spawn waits and returns the structured result":
    let base = subagentBase / "structured"
    removeDir(base)
    defer: removeDir(base)
    var parent = makeParent(base, textComplete)
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)

    let res = waitFor executeNativeTool(
      spawnCall("say hi"), parent, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOutput
    let j = parseJson(res.text)
    check j["subagent_id"].getStr().startsWith("sub-")
    check j["status"].getStr() == "completed"
    check j["text"].getStr() == "child answer"
    check j["tool_calls"].getInt() == 0
    check j["input_tokens"].getInt() == 10
    check j["output_tokens"].getInt() == 5
    check not dirExists(mgr.paddockDirFor(j["subagent_id"].getStr()))

  test "async provider completion is used when available":
    let base = subagentBase / "async-provider"
    removeDir(base)
    defer: removeDir(base)
    var parent = makeParent(base, textComplete)
    parent.asyncCompleteFn = asyncTextComplete
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)

    let res = waitFor executeNativeTool(
      spawnCall("use async provider"), parent, SessionState(), @[])
    check res.handled
    let j = parseJson(res.text)
    check j["status"].getStr() == "completed"
    check j["text"].getStr() == "async child"
    check j["input_tokens"].getInt() == 7
    check j["output_tokens"].getInt() == 3

  test "wait=false is collected by await_subagent":
    let base = subagentBase / "async"
    removeDir(base)
    defer: removeDir(base)
    var parent = makeParent(base, textComplete)
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)

    let started = waitFor executeNativeTool(
      spawnCall("work in background", "\"wait\":false"),
      parent, SessionState(), @[])
    check started.handled
    let startedJson = parseJson(started.text)
    check startedJson["status"].getStr() == "running"
    let id = startedJson["subagent_id"].getStr()

    let awaited = waitFor executeNativeTool(
      awaitCall(id), parent, SessionState(), @[])
    check awaited.handled
    check parseJson(awaited.text)["status"].getStr() == "completed"
    check parseJson(awaited.text)["text"].getStr() == "child answer"

  test "list reports status and cancel is idempotent":
    let base = subagentBase / "list"
    removeDir(base)
    defer: removeDir(base)
    var parent = makeParent(base, textComplete)
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)

    let started = waitFor executeNativeTool(
      spawnCall("list me", "\"wait\":false"), parent, SessionState(), @[])
    let id = parseJson(started.text)["subagent_id"].getStr()
    discard waitFor executeNativeTool(awaitCall(id), parent, SessionState(), @[])

    let listed = waitFor executeNativeTool(
      ToolCallRequest(id: "list-1", name: "list_subagents", inputJson: "{}"),
      parent, SessionState(), @[])
    check listed.handled
    let items = parseJson(listed.text)["subagents"]
    check items.len == 1
    check items[0]["subagent_id"].getStr() == id
    check items[0]["status"].getStr() == "completed"

    let cancelled = waitFor executeNativeTool(
      ToolCallRequest(
        id: "cancel-1",
        name: "cancel_subagent",
        inputJson: "{\"subagent_id\":\"" & id & "\"}",
      ),
      parent, SessionState(), @[])
    check parseJson(cancelled.text)["cancelled"].getBool()
    let again = waitFor executeNativeTool(
      ToolCallRequest(
        id: "cancel-2",
        name: "cancel_subagent",
        inputJson: "{\"subagent_id\":\"" & id & "\"}",
      ),
      parent, SessionState(), @[])
    check parseJson(again.text)["cancelled"].getBool()

  test "cancel_subagent stops a running child and removes its paddock":
    let base = subagentBase / "cancel"
    removeDir(base)
    defer: removeDir(base)
    let callCount = new(int)
    var parent = makeParent(base, toolLoopComplete(callCount, 100))
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)

    let started = waitFor executeNativeTool(
      spawnCall("run forever", "\"wait\":false"), parent, SessionState(), @[])
    let id = parseJson(started.text)["subagent_id"].getStr()
    let before = epochMs()
    let cancelled = waitFor executeNativeTool(
      ToolCallRequest(
        id: "cancel-1",
        name: "cancel_subagent",
        inputJson: "{\"subagent_id\":\"" & id & "\"}",
      ),
      parent, SessionState(), @[])
    check epochMs() - before < 2_000
    check parseJson(cancelled.text)["cancelled"].getBool()

    let awaited = waitFor executeNativeTool(
      awaitCall(id), parent, SessionState(), @[])
    check awaited.handled
    let resultJson = parseJson(awaited.text)
    check resultJson["status"].getStr() == "cancelled"
    check not dirExists(mgr.paddockDirFor(id))

  test "tool-call budget fails closed and is reported":
    let base = subagentBase / "budget"
    removeDir(base)
    defer: removeDir(base)
    let callCount = new(int)
    var parent = makeParent(base, toolLoopComplete(callCount, 2))
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)

    let res = waitFor executeNativeTool(
      spawnCall("spend budget", "\"max_tool_calls\":1"),
      parent, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "budget exceeded" in res.text
    let j = parseJson(res.text)
    check j["status"].getStr() == "failed"
    check "tool-call budget exceeded" in j["error"].getStr()

  test "token budget fails closed and is reported":
    let base = subagentBase / "token-budget"
    removeDir(base)
    defer: removeDir(base)
    let hugeUsage = proc(req: CompletionRequest):
                       Result[CompletionResponse, string] {.gcsafe.} =
      discard req
      ok(CompletionResponse(text: "too many tokens",
                            inputTokens: 2_000, outputTokens: 10))
    var parent = makeParent(base, hugeUsage)
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)

    let res = waitFor executeNativeTool(
      spawnCall("overspend", "\"max_tokens\":1000"),
      parent, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    let j = parseJson(res.text)
    check j["status"].getStr() == "failed"
    check "token budget exceeded" in j["error"].getStr()
    check j["input_tokens"].getInt() == 2_000

  test "children cannot spawn children":
    let base = subagentBase / "nested"
    removeDir(base)
    defer: removeDir(base)
    var parent = makeParent(base, textComplete)
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)
    var child = parent
    child.subagentDepth = 1
    child.restrictTools = true
    child.allowedTools = @["current_time"]

    let res = waitFor executeNativeTool(
      spawnCall("nested"), child, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "not allowed" in res.text or "cannot spawn subagents" in res.text

    let direct = waitFor mgr.spawn(child, SubagentRequest(task: "nested"))
    check direct.error.len > 0
    check "depth" in direct.error

  test "allowlist blocks before the approval gate":
    let base = subagentBase / "allowlist"
    removeDir(base)
    defer: removeDir(base)
    var created = 0
    let store = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string]
                   {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          inc created
        ok(ApprovalRequest(id: "abcdefgh", userId: userId, channel: channel,
                           toolName: toolName, summary: summary,
                           createdAtMs: 0, expiresAtMs: 60_000,
                           status: apsPending)),
      status: proc(id: string): Result[ApprovalStatus, string]
                      {.gcsafe, raises: [].} =
        ok(apsApproved),
      decide: proc(id, userId: string; approved: bool;
                   admin: bool): Result[void, string] {.gcsafe, raises: [].} =
        ok(),
      listPending: proc(userId: string): Result[seq[ApprovalRequest], string]
                           {.gcsafe, raises: [].} =
        ok(newSeq[ApprovalRequest]()),
    )
    configureApprovalService(store, @["bash"])
    defer: resetApprovalService()

    var child = makeParent(base, textComplete)
    child.restrictTools = true
    child.allowedTools = @["read_file"]
    child.subagentId = "sub-test"
    child.approval = currentApprovalService()

    let res = waitFor executeNativeTool(
      ToolCallRequest(id: "bash-1", name: "bash",
                      inputJson: "{\"command\":\"echo hi\"}"),
      child, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "not allowed" in res.text
    check created == 0
    check child.outbox.len == 0

  test "child file reads cannot escape their paddock":
    let base = subagentBase / "escape"
    removeDir(base)
    defer: removeDir(base)
    let childPaddock = base / "child"
    createDir(childPaddock)
    var child = makeParent(base, textComplete)
    child.restrictTools = true
    child.allowedTools = @["read_file"]
    child.subagentId = "sub-escape"
    child.paddockDir = childPaddock

    let res = waitFor executeNativeTool(
      ToolCallRequest(id: "read-1", name: "read_file",
                      inputJson: "{\"path\":\"../../etc/passwd\"}"),
      child, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "outside paddock" in res.text

  test "child write tools stay denied even if the allowlist is wrong":
    let base = subagentBase / "write"
    removeDir(base)
    defer: removeDir(base)
    let childPaddock = base / "child"
    createDir(childPaddock)
    var child = makeParent(base, textComplete)
    child.restrictTools = true
    child.allowedTools = @["fs_write"]
    child.subagentId = "sub-write"
    child.paddockDir = childPaddock

    let res = waitFor executeNativeTool(
      ToolCallRequest(id: "write-1", name: "fs_write",
                      inputJson: "{\"path\":\"../escape.txt\",\"content\":\"x\"}"),
      child, SessionState(), @[])
    check res.handled
    check res.resultKind == trkOperationalError
    check "not allowed" in res.text
    check not fileExists(base / "escape.txt")
    check not fileExists(childPaddock / "escape.txt")

  test "approval is inherited and carries the child id":
    let base = subagentBase / "approval"
    removeDir(base)
    defer: removeDir(base)
    var createdSummary = ""
    var created = 0
    let store = ApprovalStorePort(
      create: proc(userId: string; channel: string; toolName, summary: string;
                   ttlMs: int64): Result[ApprovalRequest, string]
                   {.gcsafe, raises: [].} =
        {.cast(gcsafe).}:
          inc created
          createdSummary = summary
        ok(ApprovalRequest(id: "abcdefgh", userId: userId, channel: channel,
                           toolName: toolName, summary: summary,
                           createdAtMs: 0, expiresAtMs: 60_000,
                           status: apsPending)),
      status: proc(id: string): Result[ApprovalStatus, string]
                      {.gcsafe, raises: [].} =
        ok(apsApproved),
      decide: proc(id, userId: string; approved: bool;
                   admin: bool): Result[void, string] {.gcsafe, raises: [].} =
        ok(),
      listPending: proc(userId: string): Result[seq[ApprovalRequest], string]
                           {.gcsafe, raises: [].} =
        ok(newSeq[ApprovalRequest]()),
    )
    configureApprovalService(store, @["read_file"])
    defer: resetApprovalService()

    let childPaddock = base / "child"
    createDir(childPaddock)
    writeFile(childPaddock / "note.txt", "hello from child")
    var child = makeParent(base, textComplete)
    child.restrictTools = true
    child.allowedTools = @["read_file"]
    child.subagentId = "sub-approval"
    child.paddockDir = childPaddock
    child.approval = currentApprovalService()

    let res = waitFor executeNativeTool(
      ToolCallRequest(id: "read-1", name: "read_file",
                      inputJson: "{\"path\":\"note.txt\"}"),
      child, SessionState(), @[])
    check res.handled
    check res.resultKind != trkOperationalError
    check "hello from child" in res.text
    check created == 1
    check "[subagent sub-approval]" in createdSummary
    check child.outbox.len == 1

  test "eight concurrent children complete and clean up":
    let base = subagentBase / "concurrent"
    removeDir(base)
    defer: removeDir(base)
    var parent = makeParent(base, textComplete)
    let mgr = newSubagentManager(maxConcurrent = 16)
    attachSubagentRuntime(parent, mgr)

    var ids: seq[string]
    for i in 0 ..< 8:
      let started = waitFor executeNativeTool(
        spawnCall("child " & $i, "\"wait\":false"),
        parent, SessionState(), @[])
      check started.handled
      ids.add(parseJson(started.text)["subagent_id"].getStr())

    for id in ids:
      let awaited = waitFor executeNativeTool(
        awaitCall(id), parent, SessionState(), @[])
      check awaited.handled
      check parseJson(awaited.text)["status"].getStr() == "completed"
      check not dirExists(mgr.paddockDirFor(id))

  test "cancelAll stops running children on shutdown":
    let base = subagentBase / "shutdown"
    removeDir(base)
    defer: removeDir(base)
    let callCount = new(int)
    var parent = makeParent(base, toolLoopComplete(callCount, 100))
    let mgr = newSubagentManager()
    attachSubagentRuntime(parent, mgr)

    var ids: seq[string]
    for i in 0 ..< 4:
      let started = waitFor executeNativeTool(
        spawnCall("shutdown child " & $i, "\"wait\":false"),
        parent, SessionState(), @[])
      check started.handled
      ids.add(parseJson(started.text)["subagent_id"].getStr())

    waitFor mgr.cancelAll()
    for id in ids:
      check not dirExists(mgr.paddockDirFor(id))
    for info in mgr.listSubagents():
      check info.status in {ssCancelled, ssCompleted, ssFailed, ssTimedOut}
