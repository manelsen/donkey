## Tests for the post-turn self-improvement review runtime.
##
## The review is exercised with a fake completion function and a capturing
## MemoryRuntimePort: no network, no filesystem beyond the skill fixtures.

import std/[os, strutils, tables, unittest]
import chronos

import donkey/config/environment
import donkey/adapters/http/std_http
import donkey/adapters/memory/md_file
import donkey/app/orchestrator
import donkey/app/provider_executor
import donkey/app/review_runtime
import donkey/app/session_manager
import donkey/app/session_state
import donkey/config/clawhub_registry
import donkey/core/log
import donkey/core/pipeops
import donkey/core/review/review
import donkey/core/types
import donkey/domain/agent_message
import donkey/domain/memory/provenance_pure
import donkey/domain/message
import donkey/ports/memory
import donkey/ports/provider

type
  Capture = ref object
    appended: seq[(string, MemoryOrigin)]
    paddock:  string

proc capturePort(cap: Capture): MemoryRuntimePort =
  MemoryRuntimePort(
    loadContext: proc(userId: UserId): UserContext {.gcsafe, raises: [].} = UserContext(),
    appendMemory: proc(userId: UserId; text: string): Result[void, string]
                    {.gcsafe, raises: [].} = ok(),
    appendMemoryFrom: proc(userId: UserId; text: string; origin: MemoryOrigin):
                         Result[void, string] {.gcsafe, raises: [].} =
                         cap.appended.add((text, origin))
                         ok(),
    paddockDir: proc(userId: UserId): string {.gcsafe, raises: [].} = cap.paddock,
  )

proc fakeComplete(answer: string; calls: ref int = nil;
                  seen: ref seq[string] = nil): AsyncCompleteFn =
  result = proc(req: CompletionRequest):
               Future[Result[CompletionResponse, string]] {.gcsafe, async.} =
    if calls != nil:
      inc calls[]
    if seen != nil:
      seen[].add(req.messages[0].text)
    ok(CompletionResponse(text: answer))

const QuietLog = lvlError

proc stubComplete(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(text: "pong", inputTokens: 1, outputTokens: 1))

proc reviewPort(adapter: MdFileAdapter; cap: Capture): MemoryRuntimePort =
  ## A real paddock, with the origin-aware append captured so the test can see
  ## what the review asked to keep.
  result = adapter.toRuntimePort()
  result.appendMemoryFrom = proc (userId: UserId; text: string;
                                  origin: MemoryOrigin):
                                     Result[void, string] {.gcsafe, raises: [].} =
    cap.appended.add((text, origin))
    adapter.appendMemory(userId, text, origin)

proc testRuntime(port: MemoryRuntimePort; home: string; complete: AsyncCompleteFn;
                 memoryInterval = 0; skillInterval = 0;
                 enabled = true): ReviewRuntime =
  newReviewRuntime(
    config = ReviewConfig(enabled: enabled, memoryInterval: memoryInterval,
                          skillInterval: skillInterval),
    completeFn = complete,
    memory = port,
    homeDir = home,
    log = newLogger("test.review", QuietLog))

func userTurn(text: string): ConversationHistory =
  @[
    ChatMessage(role: roleUser, text: text),
    ChatMessage(role: roleAssistant, text: "feito"),
  ]

type
  BlockingComplete = ref object
    blocked: bool
    gate:    Future[Result[CompletionResponse, string]]
    calls:   int

proc blockingComplete(state: BlockingComplete): AsyncCompleteFn =
  ## The first call stays in flight until the test opens the gate, so the
  ## coalescing guard is deterministic instead of a race with a timer.
  result = proc (req: CompletionRequest):
               Future[Result[CompletionResponse, string]] {.gcsafe, async.} =
    inc state.calls
    if state.blocked:
      state.blocked = false
      return await state.gate
    ok(CompletionResponse(text: """{"nothing": true}"""))

proc successResponse(text: string): Result[CompletionResponse, string] =
  ok(CompletionResponse(text: text))

proc settle(rt: ReviewRuntime; userId: UserId = UserId("u1")) =
  ## Waits for the background review to finish. Bounded so a broken runtime
  ## fails the assertion instead of hanging the suite.
  var spins = 0
  while rt.isRunning(userId) and spins < 2000:
    waitFor sleepAsync(milliseconds(1))
    inc spins
  doAssert not rt.isRunning(userId), "review did not settle"

proc installSkill(home, slug: string; lock: var RemoteSkillLockfile) =
  let dir = remoteSkillDir(home, slug)
  createDir(dir)
  writeFile(dir / "SKILL.md", "---\nname: " & slug & "\n---\n# " & slug & "\n")
  writeRemoteSkillOrigin(dir, RemoteSkillOrigin(
    version: 1, registry: "https://clawhub.example", slug: slug,
    installedVersion: "1.0.0", installedAt: 1))
  lock.skills[slug] = RemoteSkillLockEntry(version: "1.0.0", installedAt: 1)
  writeRemoteSkillLockfile(home, lock)

proc runWiringTurn(userDir: string; port: MemoryRuntimePort;
                   runtime: ReviewRuntime): Future[OutboundMessage] {.async.} =
  let inbox = newAsyncQueue[AgentMessage]()
  let outbox = newAsyncQueue[OutboundMessage]()
  var session = SessionEntry(inbox: inbox, askInbox: newAsyncQueue[string]())
  let orchFut = runOrchestrator(
    inbox, addr session, outbox, port, stubComplete,
    newStdHttpAdapter().toRuntimePort(), StreamFactory(), @[], @[],
    userDir, newSessionState(), reviewRuntime = runtime)
  await inbox.put(newTaskMsg("req-review", tkUserMsg, "u1",
                             "como fazemos o deploy?"))
  let reply = await outbox.get()
  await inbox.put(newCancelMsg())
  await orchFut
  return reply


proc runTests*() =
  suite "review config":

    test "defaults mirror the reference cadence":
      let cfg = reviewConfigFromEnv(Environment())
      check cfg.enabled
      check cfg.memoryInterval == 10
      check cfg.skillInterval == 10

    test "env overrides and invalid values fall back":
      let cfg = reviewConfigFromEnv(environmentOf({
        "DONKEY_REVIEW_ENABLED": "false",
        "DONKEY_REVIEW_MEMORY_INTERVAL": "3",
        "DONKEY_REVIEW_SKILL_INTERVAL": "nope"}))
      check not cfg.enabled
      check cfg.memoryInterval == 3
      check cfg.skillInterval == 10

    test "zero disables that half of the review":
      check reviewConfigFromEnv(environmentOf(
        {"DONKEY_REVIEW_MEMORY_INTERVAL": "0"})).memoryInterval == 0

  suite "review runtime — what gets written":

    test "keeps a grounded fact with the review origin":
      let cap = Capture()
      let runtime = testRuntime(capturePort(cap), home = "",
                                complete = fakeComplete("""{"memory": ["O deploy usa blue-green."]}"""))
      let res = waitFor runtime.runReview(UserId("u1"), "s1", userTurn("como fazemos o deploy?"))
      check res.isOk
      check res.get().memorySaved == 1
      check cap.appended.len == 1
      check cap.appended[0][0] == "O deploy usa blue-green."
      check cap.appended[0][1].source == msReview
      check cap.appended[0][1].sessionId == "s1"

    test "nothing to keep writes nothing":
      let cap = Capture()
      let runtime = testRuntime(capturePort(cap), home = "",
                                complete = fakeComplete("""{"nothing": true}"""))
      let res = waitFor runtime.runReview(UserId("u1"), "s1", userTurn("oi"))
      check res.isOk
      check res.get().nothing
      check res.get().memorySaved == 0
      check cap.appended.len == 0

    test "a profile target is rejected and never written":
      let cap = Capture()
      let runtime = testRuntime(capturePort(cap), home = "",
                                complete = fakeComplete("""{"user": ["gosta de azul"]}"""))
      let res = waitFor runtime.runReview(UserId("u1"), "s1", userTurn("eu gosto de azul"))
      check res.isOk
      check cap.appended.len == 0
      check res.get().warnings.len >= 1

    test "malformed JSON is an error and writes nothing":
      let cap = Capture()
      let runtime = testRuntime(capturePort(cap), home = "",
                                complete = fakeComplete("claro! vou pensar nisso"))
      let res = waitFor runtime.runReview(UserId("u1"), "s1", userTurn("oi"))
      check res.isErr
      check cap.appended.len == 0

    test "a failed completion is reported, not swallowed":
      let cap = Capture()
      let failing: AsyncCompleteFn = proc (req: CompletionRequest):
          Future[Result[CompletionResponse, string]] {.gcsafe, async.} =
        err("provider down")
      let runtime = testRuntime(capturePort(cap), home = "", complete = failing)
      let res = waitFor runtime.runReview(UserId("u1"), "s1", userTurn("oi"))
      check res.isErr
      check res.error.contains("provider down")

    test "an empty digest asks the model nothing":
      let cap = Capture()
      let calls = new(int)
      let runtime = testRuntime(capturePort(cap), home = "",
                                complete = fakeComplete("""{"memory": ["x"]}""", calls))
      let res = waitFor runtime.runReview(UserId("u1"), "s1", @[])
      check res.isOk
      check calls[] == 0
      check cap.appended.len == 0

  suite "review runtime — skills":

    test "a lesson lands in LEARNED.md, never in SKILL.md, and loads with the skill":
      let dir = getTempDir() / "donkey_review_skill"
      removeDir(dir)
      defer: removeDir(dir)
      var lock = defaultRemoteSkillLockfile()
      installSkill(dir, "deploy", lock)
      let skillPath = remoteSkillDir(dir, "deploy") / "SKILL.md"
      let before = readFile(skillPath)
      let cap = Capture()
      let runtime = testRuntime(capturePort(cap), home = dir,
        complete = fakeComplete("""{"skills": [{"slug": "deploy", "lesson": "Rode o gate antes do push."}]}"""))
      let res = waitFor runtime.runReview(UserId("u1"), "s1", userTurn("o push quebrou o gate"))
      check res.isOk
      check res.get().lessonsSaved == 1
      let learned = readFile(remoteSkillDir(dir, "deploy") / "LEARNED.md")
      check learned.contains("- Rode o gate antes do push.")
      check readFile(skillPath) == before
      let prompt = buildInstalledRemoteSkillPrompt(loadInstalledRemoteSkills(dir))
      check prompt.contains("Learned notes")
      check prompt.contains("Rode o gate antes do push.")

    test "the prompt offers only the installed slugs":
      let dir = getTempDir() / "donkey_review_slugs"
      removeDir(dir)
      defer: removeDir(dir)
      var lock = defaultRemoteSkillLockfile()
      installSkill(dir, "deploy", lock)
      let cap = Capture()
      let seen = new(seq[string])
      let runtime = testRuntime(capturePort(cap), home = dir,
        complete = fakeComplete("""{"nothing": true}""", seen = seen))
      discard waitFor runtime.runReview(UserId("u1"), "s1", userTurn("oi"))
      check seen[].len == 1
      check seen[][0].contains("deploy")
      check not seen[][0].contains("slug-inexistente")

    test "an unknown slug is dropped but the memory fact survives":
      let dir = getTempDir() / "donkey_review_unknown"
      removeDir(dir)
      defer: removeDir(dir)
      var lock = defaultRemoteSkillLockfile()
      installSkill(dir, "deploy", lock)
      let cap = Capture()
      let runtime = testRuntime(capturePort(cap), home = dir,
        complete = fakeComplete(
          """{"memory": ["fato real"], "skills": [{"slug": "inventada", "lesson": "x"}]}"""))
      let res = waitFor runtime.runReview(UserId("u1"), "s1", userTurn("oi"))
      check res.isOk
      check res.get().memorySaved == 1
      check res.get().lessonsSaved == 0
      check res.get().warnings.len >= 1

  suite "review runtime — cadence and coalescing":

    test "memory review fires on the Nth turn and resets":
      let cap = Capture()
      let calls = new(int)
      let runtime = testRuntime(capturePort(cap), home = "",
        complete = fakeComplete("""{"memory": ["fato"]}""", calls),
        memoryInterval = 2)
      check not runtime.afterTurn(UserId("u1"), "s1", userTurn("primeiro"), 0)
      check runtime.afterTurn(UserId("u1"), "s1", userTurn("segundo"), 0)
      runtime.settle()
      check calls[] == 1
      check not runtime.afterTurn(UserId("u1"), "s1", userTurn("terceiro"), 0)
      runtime.settle()
      check calls[] == 1

    test "skill review counts tool iterations across turns":
      let cap = Capture()
      let calls = new(int)
      let runtime = testRuntime(capturePort(cap), home = "",
        complete = fakeComplete("""{"nothing": true}""", calls),
        skillInterval = 5)
      check not runtime.afterTurn(UserId("u1"), "s1", userTurn("a"), 3)
      check runtime.afterTurn(UserId("u1"), "s1", userTurn("b"), 2)
      runtime.settle()
      check calls[] == 1

    test "counters are per user":
      let cap = Capture()
      let calls = new(int)
      let runtime = testRuntime(capturePort(cap), home = "",
        complete = fakeComplete("""{"nothing": true}""", calls),
        memoryInterval = 2)
      check not runtime.afterTurn(UserId("u1"), "s1", userTurn("a"), 0)
      check not runtime.afterTurn(UserId("u2"), "s1", userTurn("b"), 0)
      check runtime.afterTurn(UserId("u1"), "s1", userTurn("c"), 0)
      runtime.settle()
      check calls[] == 1

    test "a disabled review never fires automatically":
      let cap = Capture()
      let calls = new(int)
      let runtime = testRuntime(capturePort(cap), home = "",
        complete = fakeComplete("""{"nothing": true}""", calls),
        memoryInterval = 1, enabled = false)
      check not runtime.afterTurn(UserId("u1"), "s1", userTurn("a"), 10)
      runtime.settle()
      check calls[] == 0
      ## An explicit review still works, like /refine.
      check waitFor(runtime.runReview(UserId("u1"), "s1", userTurn("a"))).isOk
      check calls[] == 1

    test "one review per user at a time, and the due turn is not lost":
      let cap = Capture()
      let state = BlockingComplete(
        blocked: true, gate: newFuture[Result[CompletionResponse, string]]())
      let runtime = testRuntime(capturePort(cap), home = "",
                                complete = blockingComplete(state),
                                memoryInterval = 1)
      check runtime.afterTurn(UserId("u1"), "s1", userTurn("a"), 0)
      check runtime.isRunning(UserId("u1"))
      ## A turn that arrives while the review is in flight neither starts a
      ## second one nor loses its place in the cadence.
      check not runtime.afterTurn(UserId("u1"), "s1", userTurn("b"), 0)
      state.gate.complete(successResponse("""{"nothing": true}"""))
      runtime.settle()
      check not runtime.isRunning(UserId("u1"))
      check runtime.afterTurn(UserId("u1"), "s1", userTurn("c"), 0)
      runtime.settle()
      check state.calls == 2

  suite "review runtime — orchestrator wiring":

    test "a finished user turn feeds the cadence and may write memory":
      let home = getTempDir() / "donkey_review_orch"
      removeDir(home)
      defer: removeDir(home)
      let userDir = home / "paddocks" / "u1"
      createDir(userDir)
      writeFile(userDir / "USER.md", "# Bob")

      let cap = Capture(paddock: userDir)
      let port = reviewPort(MdFileAdapter(paddocksDir: home / "paddocks"), cap)

      let runtime = testRuntime(port, home = home,
        complete = fakeComplete("""{"memory": ["O deploy usa blue-green."]}"""),
        memoryInterval = 1)

      let reply = waitFor runWiringTurn(userDir, port, runtime)
      check reply.text == "pong"
      runtime.settle()
      ## The turn itself was auto-captured with the `turn` origin; the review's
      ## fact is the one carrying `review`.
      var reviewed = 0
      for (text, origin) in cap.appended:
        if origin.source == msReview:
          inc reviewed
          check text == "O deploy usa blue-green."
      check reviewed == 1
      check readFile(userDir / "MEMORY.md").contains("O deploy usa blue-green.")

when isMainModule:
  runTests()
