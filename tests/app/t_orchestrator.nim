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
import donkey/core/pipeops
import donkey/core/tooling/tool_loop
import donkey/adapters/http/std_http
import donkey/adapters/memory/md_file
import donkey/app/memory_agent
import donkey/app/tool_agent
import donkey/app/orchestrator
import donkey/app/session_manager

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
      asyncSpawn(runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u42"))
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
      var session = makeSessionEntry()
      session.inbox = inbox
      asyncSpawn(runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubCompleteRetry, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u1"))
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
      var session = makeSessionEntry()
      session.inbox = inbox
      asyncSpawn(runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubCompleteEmpty, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                 dir / "u1"))
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
      var session = makeSessionEntry()
      session.inbox = inbox
      let fut    = runOrchestrator(inbox, addr session, outbox, mem.toRuntimePort(), stubComplete, newStdHttpAdapter().toRuntimePort(), nil, @[], @[],
                                   dir / "u1")
      await inbox.put(newCancelMsg())
      await fut
    waitFor doTest(tmpDir)
    check true

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
