## OrchestratorAgent async integration tests.
## Updated for the new API:
##   runOrchestrator(inbox, globalOutbox, mem, completeFn, streamFn, clients, tools, paddockDir)
##   globalOutbox: AsyncQueue[OutboundMessage]  (was AsyncQueue[AgentMessage])
##   streamFn:     StreamFn = nil for all non-streaming tests

import std/[os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/domain/agent_message
import donkey/domain/message
import donkey/domain/personality
import donkey/domain/more_tools
import donkey/core/log
import donkey/core/pipeops
import donkey/core/tooling/tool_loop
import donkey/adapters/http/std_http
import donkey/adapters/memory/md_file
import donkey/app/memory_agent
import donkey/app/tool_agent
import donkey/app/orchestrator
import donkey/app/session_manager
import donkey/app/session_state

# ── helpers ────────────────────────────────────────────────────────────────────

proc makeSessionEntry(): SessionEntry =
  SessionEntry(
    inbox: newAsyncQueue[AgentMessage](),
    askInbox: newAsyncQueue[string](),
    awaitingAsk: false,
    channels: @[],
    toolCatalogSignature: "",
  )

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

proc stubProvider500(req: CompletionRequest): Result[CompletionResponse, string] =
  err("""MiniMax API error 500 Internal Server Error: {"type":"error","error":{"type":"server_error","message":"unknown error, 520 (1000)","http_code":"500"},"request_id":"abc"}""")

proc stubErrorExplainer(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(
    text: "Desculpe, o provedor falhou temporariamente. Tente novamente em instantes.",
    inputTokens: 1,
    outputTokens: 1,
  ))

proc stubFreeConvoReady(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(
    text: """IDENTITY_READY:
energy: neutro
tone: casual
length: moderado
initiative: proativo

Beleza, já entendi quem devo ser.""",
    inputTokens: 1,
    outputTokens: 1,
  ))

proc stubNameChoiceReady(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(
    text: """NAME_READY:
name: Nex

Gostei. Nex combina comigo.""",
    inputTokens: 1,
    outputTokens: 1,
  ))

proc stubUserProfileReady(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(
    text: """USER_PROFILE_READY:
name: Manel Moura
call_me: Void
timezone: UTC-3
language: Português brasileiro
treatment: com franqueza e profundidade
about: criador do Donkey

Entendi bem quem você é.""",
    inputTokens: 1,
    outputTokens: 1,
  ))

proc stubOperationalMemoryFailure(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(
    text: "Não consigo acessar a web agora, e as ferramentas estão indisponíveis.",
    inputTokens: 1,
    outputTokens: 1,
  ))

proc longText(prefix: string; targetLen: int): string =
  result = prefix
  while result.len < targetLen:
    result &= " bloco_de_texto"

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
      asyncSpawn runMemoryAgent(inbox, outbox, mem.toRuntimePort())
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
      asyncSpawn runMemoryAgent(inbox, outbox, mem.toRuntimePort())
      await inbox.put(newTaskMsg("req2", tkSaveMem, "u1", "Likes Nim."))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      return reply
    let reply = waitFor doTest(tmpDir)

    check reply.kind == amkResult
    check fileExists(tmpDir / "u1" / "MEMORY.md")
    check readFile(tmpDir / "u1" / "MEMORY.md").contains("Likes Nim.")

  test "loadCtx injects relevant lessons after autobiographical memory and before preferences":
    let tmpDir = getTempDir() / "donkey_test_mem_lessons"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[AgentMessage] {.async.} =
      let userDir = dir / "u1"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Alice")
      writeFile(userDir / "MEMORY.md", "Investigated retry amplification.")
      writeFile(userDir / "PREFERENCES.md", "language = \"pt-BR\"")
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[AgentMessage]()
      let searchFn: SearchFn =
        proc(userId: UserId; query: string; limit: int): seq[MemoryHit] {.gcsafe, raises: [].} =
          @[
            MemoryHit(content: "Investigated retry amplification.", score: 0.9'f32, kind: "memory"),
            MemoryHit(content: "Inspect retry amplification before raising timeouts.", score: 0.95'f32, kind: "lesson"),
          ]
      asyncSpawn runMemoryAgent(inbox, outbox, mem.toRuntimePort(), searchFn)
      await inbox.put(newTaskMsg("req3", tkLoadCtx, "u1", "retry spike"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      return reply

    let reply = waitFor doTest(tmpDir)
    check reply.kind == amkResult
    let memoryPos = reply.text.find("Investigated retry amplification.")
    let lessonsPos = reply.text.find("Relevant lessons:")
    let prefsPos = reply.text.find("language = \"pt-BR\"")
    check memoryPos >= 0
    check lessonsPos > memoryPos
    check prefsPos > lessonsPos

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

    check reply.kind == amkError
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
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u42", state)
      await inbox.put(newTaskMsg("req4", tkUserMsg, "u42", "ping"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      return reply
    let reply = waitFor doTest(tmpDir)

    check reply.text == "pong"

  test "final response strips thought tags and masks leaked secrets":
    let tmpDir = getTempDir() / "donkey_test_orch_sanitize"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc leakyComplete(req: CompletionRequest): Result[CompletionResponse, string] =
      ok(CompletionResponse(
        text: "<thinking>internal plan</thinking>final key: sk-abcdefghijklmnopqrstuvwxyz1234",
        inputTokens: 1,
        outputTokens: 1,
      ))

    proc doTest(dir: string): Future[OutboundMessage] {.async.} =
      let userDir = dir / "u-sanitize"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Bob")
      let mem      = MdFileAdapter(paddocksDir: dir)
      let inbox    = newAsyncQueue[AgentMessage]()
      let outbox   = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), leakyComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u-sanitize", state)
      await inbox.put(newTaskMsg("req-sanitize", tkUserMsg, "u-sanitize", "ping"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      return reply

    let reply = waitFor doTest(tmpDir)

    check "<thinking>" notin reply.text
    check "internal plan" notin reply.text
    check "sk-abcdefghijklmnopqrstuvwxyz1234" notin reply.text
    check "[REDACTED]" in reply.text
    check "final key:" in reply.text

  test "final response with only thought tags falls back to ellipsis":
    let tmpDir = getTempDir() / "donkey_test_orch_only_thinking"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc thinkingOnly(req: CompletionRequest): Result[CompletionResponse, string] =
      ok(CompletionResponse(
        text: "<thinking>internal only</thinking>\n",
        inputTokens: 1,
        outputTokens: 1,
      ))

    proc doTest(dir: string): Future[OutboundMessage] {.async.} =
      let userDir = dir / "u-thinking"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Bob")
      let mem      = MdFileAdapter(paddocksDir: dir)
      let inbox    = newAsyncQueue[AgentMessage]()
      let outbox   = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), thinkingOnly,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u-thinking", state)
      await inbox.put(newTaskMsg("req-thinking", tkUserMsg, "u-thinking", "ping"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      return reply

    let reply = waitFor doTest(tmpDir)
    check reply.text == "..."

  test "heartbeat task is processed as an agent turn":
    let tmpDir = getTempDir() / "donkey_test_orch_heartbeat"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[OutboundMessage] {.async.} =
      let userDir = dir / "u-heartbeat"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Bob")
      let mem      = MdFileAdapter(paddocksDir: dir)
      let inbox    = newAsyncQueue[AgentMessage]()
      let outbox   = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u-heartbeat", state)
      await inbox.put(newTaskMsg("req-hb", tkHeartbeat, "u-heartbeat",
        "Heartbeat automático.\nTarefas pendentes:\n- [ ] Review the logs"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      return reply

    let reply = waitFor doTest(tmpDir)

    check reply.text == "pong"

  test "heartbeat is ignored while onboarding is still pending":
    let tmpDir = getTempDir() / "donkey_test_orch_heartbeat_onboarding_guard"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[(int, int)] {.async.} =
      let userDir = dir / "u-heartbeat-new"
      createDir(userDir)
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var providerCalls = 0
      let countingComplete =
        proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
          {.cast(gcsafe).}: inc providerCalls
          ok(CompletionResponse(text: "pong", inputTokens: 1, outputTokens: 1))
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), countingComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u-heartbeat-new", state)
      await inbox.put(newTaskMsg("req-hb", tkHeartbeat, "u-heartbeat-new",
        "Heartbeat automático.\nTarefas pendentes:\n- [ ] Review the logs"))
      await sleepAsync(chronos.milliseconds(50))
      await inbox.put(newCancelMsg())
      await orchFut
      return (outbox.len, providerCalls)

    let (outboxLen, providerCalls) = waitFor doTest(tmpDir)

    check outboxLen == 0
    check providerCalls == 0

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
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubCompleteRetry, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u1", state)
      await inbox.put(newTaskMsg("req6", tkUserMsg, "u1", "hello"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
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
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubCompleteEmpty, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u1", state)
      await inbox.put(newTaskMsg("req5", tkUserMsg, "u1", "hello"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      return reply
    let reply = waitFor doTest(tmpDir)

    ## Re-prompting exhausts MaxToolRoundsOrch → error message in reply text.
    check reply.text.contains("exceeded")

  test "auto memory capture stores long turns without the old 500-char truncation":
    let tmpDir = getTempDir() / "donkey_test_memory_capture_long"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc longComplete(req: CompletionRequest): Result[CompletionResponse, string] =
      ok(CompletionResponse(
        text: longText("Resposta longa:", 900),
        inputTokens: 1,
        outputTokens: 1,
      ))

    proc doTest(dir: string): Future[string] {.async.} =
      let userDir = dir / "u-long-memory"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Test")
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), longComplete,
        newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-long-memory", state)
      await inbox.put(newTaskMsg("req-long", tkUserMsg, "u-long-memory", longText("Pergunta longa:", 900)))
      discard await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      readFile(userDir / "MEMORY.md")

    let saved = waitFor doTest(tmpDir)
    check saved.contains("Resposta longa:")
    check saved.contains("bloco_de_texto bloco_de_texto bloco_de_texto")
    check not saved.contains("[…truncated]")

  test "auto memory capture skips operational self-reports":
    let tmpDir = getTempDir() / "donkey_test_memory_capture_skip_operational"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[bool] {.async.} =
      let userDir = dir / "u-skip-memory"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Test")
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubOperationalMemoryFailure,
        newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-skip-memory", state)
      await inbox.put(newTaskMsg("req-skip", tkUserMsg, "u-skip-memory",
        "Pesquise online por Mythos e registre na memória tudo o que descobriu."))
      discard await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      fileExists(userDir / "MEMORY.md")

    let hasMemory = waitFor doTest(tmpDir)
    check not hasMemory

  test "provider errors are explained without leaking raw payloads":
    let tmpDir = getTempDir() / "donkey_test_provider_error_explain"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[OutboundMessage] {.async.} =
      let userDir = dir / "u1"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Test")
      writeFile(userDir / "PREFERENCES.md", "provider = \"minimax\"\nmodel = \"MiniMax-M2\"\n")
      let mem    = MdFileAdapter(paddocksDir: dir)
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(
        inbox, addr session, outbox, mem.toRuntimePort(),
        stubProvider500, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
        dir / "u1", state, errorExplainFn = stubErrorExplainer)
      await inbox.put(newTaskMsg("req-err", tkUserMsg, "u1", "hello"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      reply

    let reply = waitFor doTest(tmpDir)
    check reply.text.contains("falhou temporariamente")
    check not reply.text.contains("request_id")
    check not reply.text.contains("server_error")

  test "cancel shuts down orchestrator cleanly":
    let tmpDir = getTempDir() / "donkey_test_cancel"
    removeDir(tmpDir)
    createDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string) {.async.} =
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      let mem    = MdFileAdapter(paddocksDir: dir)
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let fut    = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                   dir / "u1", state)
      await inbox.put(newCancelMsg())
      await fut
    waitFor doTest(tmpDir)
    check true

  test "reset bootstrap clears profile and returns next turn to onboarding":
    let tmpDir = getTempDir() / "donkey_test_reset_bootstrap"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[(OutboundMessage, OutboundMessage, int, seq[string])] {.async.} =
      let userDir = dir / "u-reset"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Bob")
      writeFile(userDir / "PREFERENCES.md", "language = \"pt-BR\"")
      let mem    = MdFileAdapter(paddocksDir: dir)
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var logMessages: seq[string] = @[]
      let orchLog = newLogger("test.orch", lvlInfo,
        sink = proc(e: LogEntry) {.gcsafe.} =
          if e.level == lvlInfo:
            {.cast(gcsafe).}: logMessages.add(e.message))
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-reset",
                                 state, log = orchLog)
      await inbox.put(newTaskMsg("req-reset-1", tkUserMsg, "u-reset", "ping"))
      let firstReply = await outbox.get()
      await inbox.put(newTaskMsg("req-reset-2", tkReset, "u-reset", ""))
      let resetReply = await outbox.get()
      await inbox.put(newTaskMsg("req-reset-3", tkUserMsg, "u-reset", "oi"))
      await sleepAsync(chronos.milliseconds(50))
      await inbox.put(newCancelMsg())
      await orchFut
      return (firstReply, resetReply, outbox.len, logMessages)

    let (firstReply, resetReply, pendingOutbox, logMessages) = waitFor doTest(tmpDir)

    check firstReply.text == "pong"
    check resetReply.text.contains("Bootstrap reiniciado")
    check resetReply.text.contains("Como quer definir minha personalidade?")
    check resetReply.keyboard.len > 0
    check pendingOutbox == 0
    check logMessages.anyIt(it.contains("reset bootstrap: started"))
    check logMessages.anyIt(it.contains("reset bootstrap: completed; onboarding ready"))
    check not fileExists(tmpDir / "u-reset" / "USER.md")
    check not fileExists(tmpDir / "u-reset" / "PREFERENCES.md")

  test "reset bootstrap stays in onboarding without calling provider on the next plain text":
    let tmpDir = getTempDir() / "donkey_test_reset_bootstrap_provider_guard"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[(OutboundMessage, int, int)] {.async.} =
      let userDir = dir / "u-reset-guard"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Bob")
      writeFile(userDir / "PREFERENCES.md", "language = \"pt-BR\"")
      let mem    = MdFileAdapter(paddocksDir: dir)
      let inbox  = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var providerCalls = 0
      let countingComplete =
        proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
          {.cast(gcsafe).}:
            inc providerCalls
          ok(CompletionResponse(text: "pong", inputTokens: 1, outputTokens: 1))
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), countingComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-reset-guard", state)
      await inbox.put(newTaskMsg("req-reset-1", tkReset, "u-reset-guard", ""))
      let resetReply = await outbox.get()
      await inbox.put(newTaskMsg("req-reset-2", tkUserMsg, "u-reset-guard", "oi"))
      await sleepAsync(chronos.milliseconds(50))
      await inbox.put(newCancelMsg())
      await orchFut
      return (resetReply, outbox.len, providerCalls)

    let (resetReply, pendingOutbox, providerCalls) = waitFor doTest(tmpDir)

    check resetReply.text.contains("Bootstrap reiniciado")
    check resetReply.text.contains("Como quer definir minha personalidade?")
    check pendingOutbox == 0
    check providerCalls == 0

  test "telegram onboarding callback edits the same bootstrap message":
    let tmpDir = getTempDir() / "donkey_test_tg_bootstrap_edits"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[(OutboundMessage, OutboundMessage)] {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-tg-bootstrap", state)
      await inbox.put(newTaskMsg("req-tg-1", tkUserMsg, "u-tg-bootstrap", "oi", ckTelegram, "101"))
      let wakeupReply = await outbox.get()
      await inbox.put(newTaskMsg("req-tg-2", tkPersonalityChoice, "u-tg-bootstrap",
                                 "personality:mode:guided", ckTelegram, "555"))
      let guidedReply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      (wakeupReply, guidedReply)

    let (wakeupReply, guidedReply) = waitFor doTest(tmpDir)
    check wakeupReply.keyboard.len > 0
    check wakeupReply.replacementSlot == "bootstrap"
    check guidedReply.text.contains("energia e entusiasmo")
    check guidedReply.keyboard.len > 0
    check guidedReply.replacementSlot == "bootstrap"

  test "heartbeat remains blocked after agent name choice until user profile completes":
    let tmpDir = getTempDir() / "donkey_test_orch_heartbeat_name_guard"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[(int, int, int)] {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var providerCalls = 0
      let countingComplete =
        proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.} =
          {.cast(gcsafe).}: inc providerCalls
          ok(CompletionResponse(text: "pong", inputTokens: 1, outputTokens: 1))
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), countingComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-heartbeat-mid-bootstrap", state)
      await inbox.put(newTaskMsg("req-mid-1", tkUserMsg, "u-heartbeat-mid-bootstrap", "oi", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-mid-2", tkPersonalityChoice, "u-heartbeat-mid-bootstrap", "personality:mode:guided", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-mid-3", tkPersonalityChoice, "u-heartbeat-mid-bootstrap", "personality:energy:neutro", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-mid-4", tkPersonalityChoice, "u-heartbeat-mid-bootstrap", "personality:tone:casual", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-mid-5", tkPersonalityChoice, "u-heartbeat-mid-bootstrap", "personality:length:moderado", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-mid-6", tkPersonalityChoice, "u-heartbeat-mid-bootstrap", "personality:initiative:proativo", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-mid-7", tkUserMsg, "u-heartbeat-mid-bootstrap", "Seu nome será Nex", ckTelegram, "555"))
      let nameReply = await outbox.get()
      let beforeHeartbeat = providerCalls
      await inbox.put(newTaskMsg("req-mid-hb", tkHeartbeat, "u-heartbeat-mid-bootstrap", "review pending"))
      await sleepAsync(chronos.milliseconds(50))
      await inbox.put(newCancelMsg())
      await orchFut
      (beforeHeartbeat, providerCalls, if nameReply.text.contains("me conta um pouco sobre você"): 1 else: 0)

    let (beforeHeartbeat, providerCalls, sawNamePrompt) = waitFor doTest(tmpDir)
    check providerCalls == beforeHeartbeat
    check sawNamePrompt == 1

suite "payload helpers":

  test "decodeUserPayload keeps plain text unchanged":
    let payload = decodeUserPayload("hello")
    check payload.text == "hello"
    check payload.mediaUrl == ""
    check payload.recentContext == ""

  test "decodeUserPayload extracts JSON envelope":
    let payload = decodeUserPayload("""{"text":"hello","mediaUrl":"https://x/y.png","recentContext":"User: oi"}""")
    check payload.text == "hello"
    check payload.mediaUrl == "https://x/y.png"
    check payload.recentContext == "User: oi"

  test "mergeUserPayloads keeps first recent context and merges text":
    let merged = mergeUserPayloads([
      """{"text":"hello","recentContext":"User: oi"}""",
      "world",
    ])
    let payload = decodeUserPayload(merged)
    check payload.text == "hello\n\nworld"
    check payload.recentContext == "User: oi"

suite "tool loop helpers":

  test "recentRepeatCount counts trailing matching tool and args only":
    let tc = ToolCallRequest(id: "1", name: "search", inputJson: """{"q":"nim"}""")
    let recent = @[
      ("search", """{"q":"nim"}"""),
      ("search", """{"q":"zig"}"""),
      ("bash", """{"command":"pwd"}"""),
      ("search", """{"q":"nim"}"""),
    ]
    check recentRepeatCount(recent, tc) == 1

  test "withRegisteredToolCall keeps only the last 30 entries":
    var recent: seq[(string, string)] = @[]
    for i in 0 .. 30:
      recent = withRegisteredToolCall(recent, ToolCallRequest(
        id: $i, name: "tool" & $i, inputJson: """{"i":""" & $i & "}"))
    check recent.len == 30
    check recent[0] == ("tool1", """{"i":1}""")
    check recent[^1] == ("tool30", """{"i":30}""")

  test "buildToolProgressText keeps only the last five lines and truncates":
    let toolResult = "l1\nl2\nl3\nl4\nl5\nl6"
    let text = buildToolProgressText("search", 3, toolResult)
    check text.contains("`search`")
    check text.contains("[3]")
    check text.contains("```")
    check not text.contains("l1")
    check text.contains("l2\nl3\nl4\nl5\nl6")

  test "isQuietHeartbeatText recognizes no-op heartbeat summaries":
    check isQuietHeartbeatText("Tudo quiet. Apenas atualizei o timestamp de Last memory review.\n\nSem ação necessária.")
    check isQuietHeartbeatText("Heartbeat 2026-04-23T13:46:12Z — Tudo quiet. Sem alterações.")
    check isQuietHeartbeatText("Heartbeat 2026-04-24T13:20:07Z — HEARTBEAT.md: tudo [x]. Sem tarefas pendentes.\n\n— 🫡")
    check isQuietHeartbeatText("Heartbeat 2026-04-26T14:07:52Z — Checklist limpo, sem ação.\n\n— 🫡")
    check isQuietHeartbeatText("— 🫡")
    check not isQuietHeartbeatText("Há tarefa pendente no HEARTBEAT.md.")

  test "finalizeNormalTurn suppresses quiet heartbeat replies and progress":
    proc doTest() {.async.} =
      let outbox = newAsyncQueue[OutboundMessage]()
      let loopResult = ToolLoopRunResult(
        finalText: "Tudo quiet. Apenas atualizei o timestamp de Last memory review.\n\nSem ação necessária.",
        done: true,
        toolCallCount: 2,
      )
      await finalizeNormalTurn(
        outbox, UserId("u1"), ckTelegram, "", "stream-1", nil,
        suppressProgress = true, suppressQuietFinal = true,
        showReasoning = false, loopResult = loopResult)
      doAssert not (await withTimeout(outbox.get(), 100.milliseconds))
    waitFor doTest()

suite "normal turn helpers":

  test "addUserTurn appends plain text and trims history":
    var history = newHistory()
    for i in 0 .. 19:
      history.addUser("m" & $i)
    let updated = addUserTurn(history, "latest", "")
    check updated.len == 20
    check updated[^1].text == "latest"
    check updated[0].text == "m1"

  test "addUserTurn appends image messages when media exists":
    let updated = addUserTurn(newHistory(), "look", "https://x/y.png")
    check updated.len == 1
    check updated[0].text == "look"
    check updated[0].imageUrl == "https://x/y.png"

  test "buildSystemBase includes tools suffix":
    let systemBase = buildSystemBase(PersonalityTraits(), "", "\n\n## Available tools\n- x")
    check systemBase.contains("Respond in the user's preferred language.")
    check systemBase.contains("## Available tools")

  test "orchToolsSuffix teaches manage_skills for missing capabilities":
    let suffix = orchToolsSuffix(@[
      ToolDescription(
        name: ManageSkillsToolName,
        description: ManageSkillsToolDescription,
        schemaJson: ManageSkillsToolSchema,
      )
    ])
    check suffix.contains("You can install and enable skills")
    check suffix.contains("how skill installation works")
    check suffix.contains("use `manage_skills`")
    check suffix.contains("search/install/enable a skill")
    check suffix.contains("offer to search the registry")
    check suffix.contains("toolset is fixed")
    check suffix.contains("next message")

  test "buildToolLoopDoneText formats summary":
    check buildToolLoopDoneText(3) == "✅ 3 tool call(s)"

suite "free convo pipeline":

  test "startFreeConvoContext appends user turn and trims history":
    var history = newHistory()
    for i in 0 .. 24:
      history.addUser("old-" & $i)
    let res = startFreeConvoContext(history, OnboardingRuntime(phase: opFreeConvo), "novo")
    check res.isOk
    let ctx = res.get()
    check ctx.history.len <= 20
    check ctx.history[^1].text == "novo"

  test "withFreeConvoRequest injects the onboarding system prompt":
    let ctx = FreeConvoContext(
      history: newHistory(),
      onboarding: OnboardingRuntime(phase: opFreeConvo),
    )
    let res = withFreeConvoRequest(ctx)
    check res.isOk
    check res.get().request.system == FreeConvoSystemPrompt

  test "free convo pipeline parses traits and advances to name choice":
    let res =
      startFreeConvoContext(newHistory(), OnboardingRuntime(phase: opFreeConvo), "quero algo casual") >>=
      withFreeConvoRequest >>=
      completeFreeConvo(stubFreeConvoReady) >>=
      parseFreeConvoReply >>=
      finalizeFreeConvoIdentity(stubComplete)

    check res.isOk
    let ctx = res.get()
    check ctx.parsedTraits.isSome
    check ctx.onboarding.phase == opNameChoice
    check ctx.onboarding.traits.tone == "casual"
    check ctx.visibleText.contains("Beleza")

suite "guided onboarding pipeline":

  test "guided mode advances to first dimension with keyboard":
    let res = startGuidedChoiceContext(OnboardingRuntime(phase: opModeChoice), "mode", "guided")
    check res.isOk
    let ctx = res.get()
    check ctx.onboarding.phase == opGuidedEnergy
    check ctx.keyboard.len > 0

  test "guided pipeline reaches name choice without generating suggestions":
    let res =
      startGuidedChoiceContext(
        OnboardingRuntime(
          phase: opGuidedInitiative,
          traits: PersonalityTraits(
            energy: "neutro",
            tone: "casual",
            length: "moderado",
          ),
        ),
        "initiative",
        "proativo",
      ) >>=
      finalizeGuidedChoice(stubComplete)

    check res.isOk
    let ctx = res.get()
    check ctx.onboarding.phase == opNameChoice
    check ctx.onboarding.names.len == 0

suite "user profile pipeline":

  test "name choice updates identity and opens conversational user profile onboarding":
    let res = startUserProfileContext(
      OnboardingRuntime(
        phase: opNameChoice,
        traits: PersonalityTraits(tone: "casual"),
      ),
      IdentityRuntime(),
      "Seu nome será Donkey",
    )
    check res.isOk
    let ctx = res.get()
    check ctx.identity.name == "Donkey"
    check ctx.saveIdentity
    check ctx.onboarding.phase == opUserName
    check ctx.replyText.contains("me conta um pouco sobre você")

  test "language step finalizes profile and prepares USER.md":
    let res = startUserProfileContext(
      OnboardingRuntime(
        phase: opUserLanguage,
        userName: "Micelio",
        timezone: "America/Sao_Paulo",
      ),
      IdentityRuntime(name: "Donkey"),
      "Português",
    )
    check res.isOk
    let ctx = res.get()
    check ctx.onboarding.phase == opDone
    check ctx.saveUserMd
    check ctx.userMd.contains("Micelio")

suite "control task pipeline":

  test "reset control context clears history and requests persistence":
    var history = newHistory()
    history.addUser("oi")
    let res = startResetControlContext(history, "sess-1")
    check res.isOk
    let ctx = res.get()
    check ctx.history.len == 0
    check ctx.shouldPersist
    check ctx.replyText.contains("reiniciada")

  test "debug control context flips the flag":
    let res = startDebugControlContext(false)
    check res.isOk
    let ctx = res.get()
    check ctx.debugMode
    check ctx.replyText.contains("ON")

  test "onboarding control context parses personality payload":
    let res = startOnboardingControlContext(
      newTaskMsg("1", tkPersonalityChoice, "u1", "personality:mode:guided"),
      OnboardingRuntime(phase: opModeChoice),
      IdentityRuntime(),
    )
    check res.isOk
    let ctx = res.get()
    check ctx.handled
    check ctx.dim == "mode"
    check ctx.value == "guided"

  test "onboarding control context parses chosen name":
    let res = startOnboardingControlContext(
      newTaskMsg("1", tkNameChoice, "u1", "name:Donkey"),
      OnboardingRuntime(phase: opNameChoice),
      IdentityRuntime(),
    )
    check res.isOk
    let ctx = res.get()
    check ctx.handled
    check ctx.name == "Donkey"

suite "agent name onboarding":

  test "agent name can be settled through short dialogue":
    let tmpDir = getTempDir() / "donkey_test_orch_name_dialogue"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[(OutboundMessage, OutboundMessage, OutboundMessage)] {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubNameChoiceReady,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-name-dialogue", state)
      await inbox.put(newTaskMsg("req-1", tkUserMsg, "u-name-dialogue", "oi", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-2", tkPersonalityChoice, "u-name-dialogue", "personality:mode:guided", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-3", tkPersonalityChoice, "u-name-dialogue", "personality:energy:neutro", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-4", tkPersonalityChoice, "u-name-dialogue", "personality:tone:casual", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-5", tkPersonalityChoice, "u-name-dialogue", "personality:length:moderado", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-6", tkPersonalityChoice, "u-name-dialogue", "personality:initiative:proativo", ckTelegram, "555"))
      let askName = await outbox.get()
      await inbox.put(newTaskMsg("req-7", tkUserMsg, "u-name-dialogue", "Não sei se você precisa de um nome.", ckTelegram, "101"))
      let discussReply = await outbox.get()
      let userPrompt = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      (askName, discussReply, userPrompt)

    let (askName, discussReply, userPrompt) = waitFor doTest(tmpDir)
    check askName.text.contains("Qual será meu nome?")
    check askName.replacementSlot == "bootstrap"
    check discussReply.text.contains("Nex")
    check discussReply.replacementSlot == ""
    check userPrompt.text.contains("me conta um pouco sobre você")
    check userPrompt.replacementSlot == ""

  test "user profile onboarding starts with an open conversational prompt":
    let tmpDir = getTempDir() / "donkey_test_orch_user_profile_messages"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[(OutboundMessage, OutboundMessage)] {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-profile-msgs", state)
      await inbox.put(newTaskMsg("req-1", tkUserMsg, "u-profile-msgs", "oi", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-2", tkPersonalityChoice, "u-profile-msgs", "personality:mode:guided", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-3", tkPersonalityChoice, "u-profile-msgs", "personality:energy:neutro", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-4", tkPersonalityChoice, "u-profile-msgs", "personality:tone:casual", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-5", tkPersonalityChoice, "u-profile-msgs", "personality:length:moderado", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-6", tkPersonalityChoice, "u-profile-msgs", "personality:initiative:proativo", ckTelegram, "555"))
      let askAgentName = await outbox.get()
      await inbox.put(newTaskMsg("req-7", tkUserMsg, "u-profile-msgs", "Node", ckTelegram, "101"))
      let askProfile = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      (askAgentName, askProfile)

    let (askAgentName, askProfile) = waitFor doTest(tmpDir)
    check askAgentName.text.contains("Qual será meu nome?")
    check askAgentName.replacementSlot == "bootstrap"
    check askProfile.text.contains("me conta um pouco sobre você")
    check askProfile.text.contains("como gostaria de ser chamado")
    check askProfile.replacementSlot == ""

  test "micro-onboarding can conclude user profile conversationally":
    let tmpDir = getTempDir() / "donkey_test_orch_micro_profile"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[(OutboundMessage, OutboundMessage)] {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubUserProfileReady,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-micro-profile", state)
      await inbox.put(newTaskMsg("req-1", tkUserMsg, "u-micro-profile", "oi", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-2", tkPersonalityChoice, "u-micro-profile", "personality:mode:guided", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-3", tkPersonalityChoice, "u-micro-profile", "personality:energy:neutro", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-4", tkPersonalityChoice, "u-micro-profile", "personality:tone:casual", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-5", tkPersonalityChoice, "u-micro-profile", "personality:length:moderado", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-6", tkPersonalityChoice, "u-micro-profile", "personality:initiative:proativo", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-7", tkUserMsg, "u-micro-profile", "Node", ckTelegram, "101"))
      let askProfile = await outbox.get()
      await inbox.put(newTaskMsg("req-8", tkUserMsg, "u-micro-profile", "Sou Manel, pode me chamar de Void. Gosto de franqueza. UTC-3. Português brasileiro.", ckTelegram, "101"))
      let visible = await outbox.get()
      let finalReply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      (visible, finalReply)

    let (visible, finalReply) = waitFor doTest(tmpDir)
    check visible.text.contains("Entendi bem quem você é.")
    check finalReply.text.contains("vou te chamar de Void")

  test "conversational onboarding resumes across restarts before USER.md exists":
    let tmpDir = getTempDir() / "donkey_test_orch_resume_conversational_bootstrap"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc bootIdentityPhase(dir: string) {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubFreeConvoReady,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-resume-convo", state)
      await inbox.put(newTaskMsg("req-1", tkUserMsg, "u-resume-convo", "oi", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-2", tkPersonalityChoice, "u-resume-convo", "personality:mode:free", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-3", tkUserMsg, "u-resume-convo", "Seja curioso e direto.", ckTelegram, "101"))
      discard await outbox.get()
      discard await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut

    proc bootNamePhase(dir: string): Future[OutboundMessage] {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-resume-convo", state)
      await inbox.put(newTaskMsg("req-4", tkUserMsg, "u-resume-convo", "Nex", ckTelegram, "101"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      reply

    proc bootProfilePhase(dir: string): Future[OutboundMessage] {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubUserProfileReady,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-resume-convo", state)
      await inbox.put(newTaskMsg("req-5", tkUserMsg, "u-resume-convo",
        "Sou Manel, pode me chamar de Void. Gosto de franqueza. UTC-3. Português brasileiro.",
        ckTelegram, "101"))
      discard await outbox.get()
      let finalReply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      finalReply

    waitFor bootIdentityPhase(tmpDir)
    let prefsAfterIdentity = readFile(tmpDir / "u-resume-convo" / "PREFERENCES.md")
    check prefsAfterIdentity.contains("agent_energy = \"neutro\"")
    check prefsAfterIdentity.contains("onboarding_phase = \"opNameChoice\"")
    check not fileExists(tmpDir / "u-resume-convo" / "USER.md")

    let nameReply = waitFor bootNamePhase(tmpDir)
    check nameReply.text.contains("me conta um pouco sobre você")
    check not nameReply.text.contains("Qual será meu nome?")
    let prefsAfterName = readFile(tmpDir / "u-resume-convo" / "PREFERENCES.md")
    check prefsAfterName.contains("agent_name = \"Nex\"")
    check prefsAfterName.contains("onboarding_phase = \"opUserName\"")

    let finalReply = waitFor bootProfilePhase(tmpDir)
    check finalReply.text.contains("vou te chamar de Void")
    check fileExists(tmpDir / "u-resume-convo" / "USER.md")
    let finalPrefs = readFile(tmpDir / "u-resume-convo" / "PREFERENCES.md")
    check not finalPrefs.contains("onboarding_phase")

  test "completed bootstrap does not reopen on the same channel target":
    let tmpDir = getTempDir() / "donkey_test_orch_bootstrap_target_latch"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    proc doTest(dir: string): Future[OutboundMessage] {.async.} =
      let mem = MdFileAdapter(paddocksDir: dir)
      let inbox = newAsyncQueue[AgentMessage]()
      let outbox = newAsyncQueue[OutboundMessage]()
      var session = makeSessionEntry()
      session.inbox = inbox
      let state = newSessionState()
      let orchFut = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete,
                                 newStdHttpAdapter().toRuntimePort(), nil, @[], @[], dir / "u-bootstrap-latch", state)
      await inbox.put(newTaskMsg("req-1", tkUserMsg, "u-bootstrap-latch", "oi", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-2", tkPersonalityChoice, "u-bootstrap-latch", "personality:mode:guided", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-3", tkPersonalityChoice, "u-bootstrap-latch", "personality:energy:neutro", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-4", tkPersonalityChoice, "u-bootstrap-latch", "personality:tone:casual", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-5", tkPersonalityChoice, "u-bootstrap-latch", "personality:length:moderado", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-6", tkPersonalityChoice, "u-bootstrap-latch", "personality:initiative:proativo", ckTelegram, "555"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-7", tkUserMsg, "u-bootstrap-latch", "Node", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-8", tkUserMsg, "u-bootstrap-latch", "Void", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-9", tkUserMsg, "u-bootstrap-latch", "UTC-3", ckTelegram, "101"))
      discard await outbox.get()
      await inbox.put(newTaskMsg("req-10", tkUserMsg, "u-bootstrap-latch", "Português", ckTelegram, "101"))
      discard await outbox.get()

      removeFile(dir / "u-bootstrap-latch" / "USER.md")

      await inbox.put(newTaskMsg("req-11", tkUserMsg, "u-bootstrap-latch", "olá de novo", ckTelegram, "101"))
      let reply = await outbox.get()
      await inbox.put(newCancelMsg())
      await orchFut
      reply

    let reply = waitFor doTest(tmpDir)
    check reply.text == "pong"
    check not reply.text.contains("Como quer definir minha personalidade")
    check not reply.text.contains("Qual será meu nome?")
