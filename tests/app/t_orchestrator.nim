## OrchestratorAgent async integration tests.
## Updated for the new API:
##   runOrchestrator(inbox, globalOutbox, mem, completeFn, streamFn, clients, tools)
##   globalOutbox: AsyncQueue[OutboundMessage]  (was AsyncQueue[AgentMessage])
##   streamFn:     StreamFn = nil for all non-streaming tests

import std/[os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/domain/agent_message
import donkey/domain/message
import donkey/core/pipeops
import donkey/adapters/memory/md_file
import donkey/app/memory_agent
import donkey/app/tool_agent
import donkey/app/orchestrator

# ── helpers ────────────────────────────────────────────────────────────────────

proc stubComplete(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(text: "pong", inputTokens: 1, outputTokens: 1))

proc stubCompleteEmpty(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(text: "", inputTokens: 1, outputTokens: 1))

var retryStubCalls = 0

proc stubCompleteRetry(req: CompletionRequest): Result[CompletionResponse, string] =
  inc retryStubCalls
  if retryStubCalls == 1:
    ok(CompletionResponse(text: "", inputTokens: 1, outputTokens: 1))
  else:
    ok(CompletionResponse(text: "pong", inputTokens: 1, outputTokens: 1))

# ── AsyncQueue round-trip ──────────────────────────────────────────────────────

suite "AsyncQueue round-trip":

  test "put and get a task message":
    proc doTest(): Future[AgentMessage] {.async.} =
      let q = newAsyncQueue[AgentMessage]()
      await q.put(newTaskMsg("1", tkUserMsg, "u1", "hello"))
      return await q.get()
    let got = waitFor doTest()
    check got.kind    == amkTask
    check got.payload == "hello"

  test "cancel message survives queue":
    proc doTest(): Future[AgentMessage] {.async.} =
      let q = newAsyncQueue[AgentMessage]()
      await q.put(newCancelMsg())
      return await q.get()
    let got = waitFor doTest()
    check got.kind == amkCancel

# ── MemoryAgent ────────────────────────────────────────────────────────────────

suite "MemoryAgent":

  test "loadCtx task returns USER.md content":
    let tmpDir = getTempDir() / "donkey_test_mem"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[AgentMessage] {.async.} =
      let userDir = dir / "u1"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Alice")
      let mem   = MdFileAdapter(paddocksDir: dir)
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[AgentMessage]()
      asyncSpawn runMemoryAgent(inbox, outbox, mem)
      await inbox.put(newTaskMsg("req1", tkLoadCtx, "u1", ""))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      return reply
    let reply = waitFor doTest(tmpDir)

    check reply.kind == amkResult
    check reply.id   == "req1"
    check reply.text.contains("Alice")

  test "saveMem task persists to MEMORY.md":
    let tmpDir = getTempDir() / "donkey_test_savemem"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[AgentMessage] {.async.} =
      let userDir = dir / "u1"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Alice")
      let mem    = MdFileAdapter(paddocksDir: dir)
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[AgentMessage]()
      asyncSpawn runMemoryAgent(inbox, outbox, mem)
      await inbox.put(newTaskMsg("req2", tkSaveMem, "u1", "Likes Nim."))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      return reply
    let reply = waitFor doTest(tmpDir)

    check reply.kind == amkResult
    check fileExists(tmpDir / "u1" / "MEMORY.md")
    check readFile(tmpDir / "u1" / "MEMORY.md").contains("Likes Nim.")

# ── ToolAgent ─────────────────────────────────────────────────────────────────

suite "ToolAgent":

  test "invokeTool with empty clients returns not-found message":
    proc doTest(): Future[AgentMessage] {.async.} =
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[AgentMessage]()
      asyncSpawn runToolAgent(inbox, outbox, @[])
      let payload = """{"name":"search","id":"","inputJson":"{}"}"""
      await inbox.put(newTaskMsg("req3", tkInvokeTool, "", payload))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      return reply
    let reply = waitFor doTest()

    check reply.kind == amkResult
    check reply.text.contains("not found")

# ── OrchestratorAgent ─────────────────────────────────────────────────────────

suite "OrchestratorAgent":

  test "userMsg produces a text reply":
    let tmpDir = getTempDir() / "donkey_test_orch"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[OutboundMessage] {.async.} =
      let userDir = dir / "u42"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Bob")
      let mem      = MdFileAdapter(paddocksDir: dir)
      let inbox    = newAsyncQueue[AgentMessage]()
      let outbox   = newAsyncQueue[OutboundMessage]()
      asyncSpawn(runOrchestrator(inbox, outbox, mem, stubComplete, nil, @[], @[]))
      await inbox.put(newTaskMsg("req4", tkUserMsg, "u42", "ping"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      return reply
    let reply = waitFor doTest(tmpDir)

    check reply.text == "pong"

  test "empty LLM text triggers re-prompt — second call returns real answer":
    let tmpDir = getTempDir() / "donkey_test_retry"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)
    retryStubCalls = 0

    proc doTest(dir: string): Future[OutboundMessage] {.async.} =
      let userDir = dir / "u1"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Test")
      let mem    = MdFileAdapter(paddocksDir: dir)
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      asyncSpawn(runOrchestrator(inbox, outbox, mem, stubCompleteRetry, nil, @[], @[]))
      await inbox.put(newTaskMsg("req6", tkUserMsg, "u1", "hello"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      return reply
    let reply = waitFor doTest(tmpDir)

    check reply.text    == "pong"
    check retryStubCalls == 2

  test "model that always returns empty exhausts retries and replies with error":
    let tmpDir = getTempDir() / "donkey_test_empty"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[OutboundMessage] {.async.} =
      let userDir = dir / "u1"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Test")
      let mem    = MdFileAdapter(paddocksDir: dir)
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      asyncSpawn(runOrchestrator(inbox, outbox, mem, stubCompleteEmpty, nil, @[], @[]))
      await inbox.put(newTaskMsg("req5", tkUserMsg, "u1", "hello"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      return reply
    let reply = waitFor doTest(tmpDir)

    ## Re-prompting exhausts MaxToolRoundsOrch → error message in reply text.
    check reply.text.contains("exceeded")

  test "cancel shuts down orchestrator cleanly":
    let tmpDir = getTempDir() / "donkey_test_cancel"
    removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string) {.async.} =
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      let mem    = MdFileAdapter(paddocksDir: dir)
      let fut    = runOrchestrator(inbox, outbox, mem, stubComplete, nil, @[], @[])
      await inbox.put(newCancelMsg())
      await fut
    waitFor doTest(tmpDir)
    check true
