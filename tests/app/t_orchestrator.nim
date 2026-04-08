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
      await inbox.put(newTaskMsg("req-mid-7", tkNameChoice, "u-heartbeat-mid-bootstrap", "name:Nex", ckTelegram, "555"))
      let nameReply = await outbox.get()
      let beforeHeartbeat = providerCalls
      await inbox.put(newTaskMsg("req-mid-hb", tkHeartbeat, "u-heartbeat-mid-bootstrap", "review pending"))
      await sleepAsync(chronos.milliseconds(50))
      await inbox.put(newCancelMsg())
      await orchFut
      (beforeHeartbeat, providerCalls, if nameReply.text.contains("qual é o seu nome?"): 1 else: 0)

    let (beforeHeartbeat, providerCalls, sawNamePrompt) = waitFor doTest(tmpDir)
    check providerCalls == beforeHeartbeat
    check sawNamePrompt == 1

suite "payload helpers":

  test "decodeUserPayload keeps plain text unchanged":
    let (text, mediaUrl) = decodeUserPayload("hello")
    check text == "hello"
    check mediaUrl == ""

  test "decodeUserPayload extracts JSON envelope":
    let (text, mediaUrl) = decodeUserPayload("""{"text":"hello","mediaUrl":"https://x/y.png"}""")
    check text == "hello"
    check mediaUrl == "https://x/y.png"

suite "tool loop helpers":

  test "recentRepeatCount counts matching tool and args only":
    let tc = ToolCallRequest(id: "1", name: "search", inputJson: """{"q":"nim"}""")
    let recent = @[
      ("search", """{"q":"nim"}"""),
      ("search", """{"q":"zig"}"""),
      ("bash", """{"command":"pwd"}"""),
      ("search", """{"q":"nim"}"""),
    ]
    check recentRepeatCount(recent, tc) == 2

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
    check text.contains("search")
    check text.contains("[3]")
    check not text.contains("l1")
    check text.contains("l2\nl3\nl4\nl5\nl6")

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

  test "guided pipeline reaches name choice and generates names":
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
    check ctx.onboarding.names.len > 0

  test "buildNameChoiceKeyboard maps labels and callbacks":
    let kb = buildNameChoiceKeyboard(@["Ada", "Linus"])
    check kb.len == 1
    check kb[0].len == 2
    check kb[0][0] == ("Ada", "name:Ada")
    check kb[0][1] == ("Linus", "name:Linus")

suite "user profile pipeline":

  test "name choice updates identity and requests user name":
    let res = startUserProfileContext(
      OnboardingRuntime(
        phase: opNameChoice,
        traits: PersonalityTraits(tone: "casual"),
      ),
      IdentityRuntime(),
      "Donkey",
    )
    check res.isOk
    let ctx = res.get()
    check ctx.identity.name == "Donkey"
    check ctx.saveIdentity
    check ctx.onboarding.phase == opUserName

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
