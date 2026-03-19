## native_tools deterministic unit tests.
## Tests procs that do not require live HTTP, LLM calls, or interactive I/O.
##
## Covered:
##   Shell      : performBash (with workingDir), performHashline, performFind, performGrep
##   Paddock    : resolveInPaddock, inPaddock, path escape rejection
##   Session    : applyTodoOps
##   via executeNativeTool: calc, checkpoint, rewind, submit_result, report_finding
##   Misc       : unknown tool → handled=false

import std/[json, options, os, strutils, times, unittest]
import chronos
import chronos/asyncsync
import donkey/core/pipeops
import donkey/core/log
import donkey/domain/message
import donkey/domain/agent_message
import donkey/app/session_state
import donkey/app/native_tools

# ── Helpers ───────────────────────────────────────────────────────────────────

proc stubComplete(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(text: "stub", inputTokens: 1, outputTokens: 1))

proc makeCtx(): NativeCtx =
  NativeCtx(
    uid:        UserId("test-user"),
    channel:    ckTelegram,
    outbox:     newAsyncQueue[OutboundMessage](),
    inbox:      newAsyncQueue[AgentMessage](),
    completeFn: stubComplete,
    braveApiKey: "",
    tools:      @[],
    log:        newLogger("test"),
  )

proc makeTc(name, inputJson: string): ToolCallRequest =
  ToolCallRequest(id: "call-1", name: name, inputJson: inputJson)

# ── resolveInPaddock / inPaddock ─────────────────────────────────────────────

suite "resolveInPaddock":

  test "relative path resolved under paddock":
    check resolveInPaddock("foo/bar", "/home/u/paddock") == "/home/u/paddock/foo/bar"

  test "absolute path returned as-is (normalized)":
    check resolveInPaddock("/etc/passwd", "/home/u/paddock") == "/etc/passwd"

  test "dot segments collapsed":
    check resolveInPaddock("./foo/./bar", "/home/u/paddock") == "/home/u/paddock/foo/bar"

  test "double-dot traversal collapsed":
    check resolveInPaddock("foo/../../escape", "/home/u/paddock") == "/home/u/escape"

  test "double-dot goes up two levels from paddock":
    ## ../../etc relative to /home/u/paddock → /home/u/paddock/../../etc = /home/etc
    let r = resolveInPaddock("../../etc", "/home/u/paddock")
    check r == "/home/etc"

suite "inPaddock":

  test "path inside paddock":
    check inPaddock("/home/u/paddock/work/file.nim", "/home/u/paddock")

  test "paddock root itself":
    check inPaddock("/home/u/paddock", "/home/u/paddock")

  test "path outside paddock rejected":
    check not inPaddock("/etc/passwd", "/home/u/paddock")

  test "traversal attempt rejected":
    check not inPaddock("/home/u/paddock/../secret", "/home/u/paddock")

  test "similar prefix not confused with paddock":
    check not inPaddock("/home/u/paddock-evil/file", "/home/u/paddock")

# ── performBash ───────────────────────────────────────────────────────────────

suite "performBash":

  test "echo returns output without trailing newline":
    check performBash("echo hello") == "hello"

  test "non-zero exit code appended":
    let r = performBash("exit 42")
    check r.contains("[exit 42]")

  test "stdout and stderr merged":
    let r = performBash("echo out; echo err >&2")
    check r.contains("out")
    check r.contains("err")

  test "empty stdout with non-zero exit":
    let r = performBash("exit 1")
    check r == "[exit 1]"

  test "zero exit with output has no exit marker":
    let r = performBash("echo ok")
    check not r.contains("[exit")

  test "workingDir is the CWD for the command":
    let tmpDir = getTempDir() / "donkey_bash_wd_test"
    createDir(tmpDir)
    writeFile(tmpDir / "canary.txt", "found")
    let r = performBash("cat canary.txt", tmpDir)
    check r == "found"
    removeDir(tmpDir)

  test "workingDir is created if missing":
    let tmpDir = getTempDir() / "donkey_bash_autocreate_" & $epochTime().int
    defer: (try: removeDir(tmpDir) except: discard)
    let r = performBash("pwd", tmpDir)
    check dirExists(tmpDir)
    check r.contains(tmpDir)

# ── performHashline — string ──────────────────────────────────────────────────

suite "performHashline — string input":

  test "sha256 of 'hello' is known value":
    # echo -n hello | sha256sum
    check performHashline(input = "hello") ==
      "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

  test "two different strings produce different hashes":
    let h1 = performHashline(input = "hello")
    let h2 = performHashline(input = "world")
    check h1 != h2

  test "empty input with no file returns error":
    check performHashline().startsWith("Error:")

# ── performHashline — file ────────────────────────────────────────────────────

suite "performHashline — file input":

  let tmpFile = getTempDir() / "donkey_test_hash.txt"

  setup:
    writeFile(tmpFile, "abc\ndef\n")

  teardown:
    if fileExists(tmpFile): removeFile(tmpFile)

  test "hash of file matches hash of its content":
    let content = readFile(tmpFile)
    check performHashline(file = tmpFile) == performHashline(input = content)

  test "hash of line 1":
    # line 1 = "abc"
    check performHashline(file = tmpFile, line = 1) == performHashline(input = "abc")

  test "hash of line 2":
    check performHashline(file = tmpFile, line = 2) == performHashline(input = "def")

  test "out-of-range line returns error":
    let r = performHashline(file = tmpFile, line = 99)
    check r.startsWith("Error:")

  test "missing file returns error":
    let r = performHashline(file = "/nonexistent/path/x.txt")
    check r.startsWith("Error:")

# ── performFind ───────────────────────────────────────────────────────────────

suite "performFind":

  var tmpDir: string

  setup:
    tmpDir = getTempDir() / "donkey_find_test"
    createDir(tmpDir)
    writeFile(tmpDir / "alpha.nim", "")
    writeFile(tmpDir / "beta.nim",  "")
    writeFile(tmpDir / "gamma.txt", "")

  teardown:
    if dirExists(tmpDir): removeDir(tmpDir)

  test "wildcard finds all files":
    let r = performFind(tmpDir, "*", "file", 50)
    check r.contains("alpha.nim")
    check r.contains("beta.nim")
    check r.contains("gamma.txt")

  test "extension filter finds only nim files":
    let r = performFind(tmpDir, "*.nim", "file", 50)
    check r.contains("alpha.nim")
    check r.contains("beta.nim")
    check not r.contains("gamma.txt")

  test "max limits results":
    let r = performFind(tmpDir, "*", "file", 1)
    let lines = r.splitLines()
    check lines.len == 1

  test "no matches returns sentinel":
    let r = performFind(tmpDir, "*.xyz", "file", 50)
    check r == "(no matches)"

  test "dir type finds subdirectory":
    createDir(tmpDir / "subdir")
    let r = performFind(tmpDir, "*", "dir", 50)
    check r.contains("subdir")

# ── performGrep ───────────────────────────────────────────────────────────────

suite "performGrep":

  var tmpFile: string

  setup:
    tmpFile = getTempDir() / "donkey_grep_test.txt"
    writeFile(tmpFile, "line one has foo\nline two has bar\nline three has foo again\n")

  teardown:
    if fileExists(tmpFile): removeFile(tmpFile)

  test "finds pattern in file":
    let r = performGrep("foo", tmpFile, false, 50)
    check r.contains("line one has foo")
    check r.contains("line three has foo again")

  test "does not return non-matching lines":
    let r = performGrep("foo", tmpFile, false, 50)
    check not r.contains("bar")

  test "format is file:linenum:content":
    let r = performGrep("bar", tmpFile, false, 50)
    check r.contains(":2:")

  test "no matches returns sentinel":
    let r = performGrep("ZZZZ", tmpFile, false, 50)
    check r == "(no matches)"

  test "empty pattern returns error":
    let r = performGrep("", tmpFile, false, 50)
    check r.startsWith("Error:")

  test "missing path returns error":
    let r = performGrep("foo", "/nonexistent/path.txt", false, 50)
    check r.startsWith("Error:")

  test "max caps results":
    let r = performGrep("foo", tmpFile, false, 1)
    check r.splitLines().len == 1

suite "performGrep — directory":

  var tmpDir: string

  setup:
    tmpDir = getTempDir() / "donkey_grepdir_test"
    createDir(tmpDir)
    writeFile(tmpDir / "a.txt", "needle in a\n")
    writeFile(tmpDir / "b.txt", "nothing here\n")

  teardown:
    if dirExists(tmpDir): removeDir(tmpDir)

  test "recursive finds pattern in dir":
    let r = performGrep("needle", tmpDir, true, 50)
    check r.contains("needle in a")

  test "returns only matching files":
    let r = performGrep("needle", tmpDir, true, 50)
    check not r.contains("nothing here")

# ── applyTodoOps ──────────────────────────────────────────────────────────────

suite "applyTodoOps — create":

  test "creates todo and returns it":
    let s   = newSessionState()
    let ops = parseJson("""[{"op":"create","title":"Buy milk","phase":"backlog"}]""")
    let r   = applyTodoOps(s, ops)
    check r.contains("Buy milk")
    check r.contains("[ ]")

  test "create with in_progress shows tilde marker":
    let s   = newSessionState()
    let ops = parseJson("""[{"op":"create","title":"Work item","phase":"in_progress"}]""")
    let r   = applyTodoOps(s, ops)
    check r.contains("[~]")

  test "create with completed shows x marker":
    let s   = newSessionState()
    let ops = parseJson("""[{"op":"create","title":"Done","phase":"completed"}]""")
    let r   = applyTodoOps(s, ops)
    check r.contains("[x]")

  test "notes are included in output":
    let s   = newSessionState()
    let ops = parseJson("""[{"op":"create","title":"T","notes":"important note"}]""")
    let r   = applyTodoOps(s, ops)
    check r.contains("important note")

suite "applyTodoOps — update":

  test "update title":
    let s = newSessionState()
    discard applyTodoOps(s, parseJson("""[{"op":"create","title":"Old title"}]"""))
    let r = applyTodoOps(s, parseJson("""[{"op":"update","id":"todo-0","title":"New title"}]"""))
    check r.contains("New title")
    check not r.contains("Old title")

  test "update phase from backlog to completed":
    let s = newSessionState()
    discard applyTodoOps(s, parseJson("""[{"op":"create","title":"Task"}]"""))
    let r = applyTodoOps(s, parseJson("""[{"op":"update","id":"todo-0","phase":"completed"}]"""))
    check r.contains("[x]")

  test "update nonexistent id is ignored":
    let s = newSessionState()
    discard applyTodoOps(s, parseJson("""[{"op":"create","title":"Task"}]"""))
    let r = applyTodoOps(s, parseJson("""[{"op":"update","id":"no-such-id","title":"X"}]"""))
    check r.contains("Task")  # original still there

suite "applyTodoOps — delete":

  test "delete removes item":
    let s = newSessionState()
    discard applyTodoOps(s, parseJson("""[{"op":"create","title":"Remove me"}]"""))
    let r = applyTodoOps(s, parseJson("""[{"op":"delete","id":"todo-0"}]"""))
    check r == "(empty todo list)"

  test "delete nonexistent id leaves list intact":
    let s = newSessionState()
    discard applyTodoOps(s, parseJson("""[{"op":"create","title":"Keep"}]"""))
    let r = applyTodoOps(s, parseJson("""[{"op":"delete","id":"todo-99"}]"""))
    check r.contains("Keep")

suite "applyTodoOps — misc":

  test "empty state returns empty sentinel":
    let s = newSessionState()
    let r = applyTodoOps(s, parseJson("[]"))
    check r == "(empty todo list)"

  test "multiple creates return all items":
    let s = newSessionState()
    let r = applyTodoOps(s, parseJson(
      """[{"op":"create","title":"A"},{"op":"create","title":"B"}]"""))
    check r.contains("A")
    check r.contains("B")

  test "unknown op is silently ignored":
    let s   = newSessionState()
    discard applyTodoOps(s, parseJson("""[{"op":"create","title":"X"}]"""))
    let r = applyTodoOps(s, parseJson("""[{"op":"purge"}]"""))
    check r.contains("X")   # still intact

# ── executeNativeTool — sync-friendly cases ───────────────────────────────────

suite "executeNativeTool — calc":

  test "2+2 returns 4":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("calc", """{"expression":"2+2"}""")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.text == "4"

  test "division result":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("calc", """{"expression":"10/4"}""")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.text == "2.5"

  test "missing expression returns error":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("calc", "{}")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.text.startsWith("Error:")

suite "executeNativeTool — checkpoint and rewind":

  test "checkpoint sets checkpointNow=true":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("checkpoint", "{}")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.checkpointNow

  test "checkpoint text confirms save":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("checkpoint", """{"label":"before big change"}""")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.text.contains("saved")

  test "rewind with no checkpoints returns error":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("rewind", "{}")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.text.startsWith("Error:")

  test "rewind restores saved history":
    let ctx   = makeCtx()
    let state = newSessionState()
    # Build a history, checkpoint it
    var h = newHistory()
    h.addUser("hello")
    state.checkpoints.add(h)  # simulate what orchestrator does on checkpointNow
    # Rewind
    let tc = makeTc("rewind", "{}")
    let r  = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.newHistory.isSome
    check r.newHistory.get().len == 1

  test "rewind to specific index":
    let ctx   = makeCtx()
    let state = newSessionState()
    var h0 = newHistory(); h0.addUser("turn-0")
    var h1 = newHistory(); h1.addUser("turn-1")
    state.checkpoints.add(h0)
    state.checkpoints.add(h1)
    let tc = makeTc("rewind", """{"index":0}""")
    let r  = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.newHistory.get().len == 1
    check r.newHistory.get()[0].text == "turn-0"

  test "rewind out-of-range index returns error":
    let ctx   = makeCtx()
    let state = newSessionState()
    state.checkpoints.add(newHistory())
    let tc = makeTc("rewind", """{"index":99}""")
    let r  = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.text.startsWith("Error:")

suite "executeNativeTool — submit_result":

  test "returns result verbatim":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("submit_result", """{"result":"the answer is 42"}""")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.text == "the answer is 42"

suite "executeNativeTool — report_finding":

  test "returns finding acknowledged message":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("report_finding", """{"finding":"CPU usage is high"}""")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.text.contains("CPU usage is high")

suite "executeNativeTool — unknown tool":

  test "unknown tool returns handled=false":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("nonexistent_tool_xyz", "{}")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check not r.handled

# ── executeNativeTool — paddock path enforcement ──────────────────────────────

suite "executeNativeTool — paddock path enforcement":

  var paddock: string

  setup:
    paddock = getTempDir() / "donkey_paddock_test_" & $epochTime().int
    createDir(paddock)
    writeFile(paddock / "safe.txt", "safe content\n")

  teardown:
    if dirExists(paddock): removeDir(paddock)

  proc ctxWithPaddock(pd: string): NativeCtx =
    NativeCtx(
      uid:         UserId("test-user"),
      channel:     ckTelegram,
      outbox:      newAsyncQueue[OutboundMessage](),
      inbox:       newAsyncQueue[AgentMessage](),
      completeFn:  stubComplete,
      braveApiKey: "",
      tools:       @[],
      log:         newLogger("test"),
      paddockDir:  pd,
    )

  test "bash runs in paddock — pwd shows paddock path":
    let ctx = ctxWithPaddock(paddock)
    let tc  = makeTc("bash", """{"command":"pwd"}""")
    let r   = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check r.handled
    check r.text.contains(paddock)

  test "find inside paddock works":
    let ctx = ctxWithPaddock(paddock)
    let tc  = makeTc("find", """{"path":".","pattern":"*.txt"}""")
    let r   = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check r.handled
    check r.text.contains("safe.txt")

  test "find with absolute escape rejected":
    let ctx = ctxWithPaddock(paddock)
    let tc  = makeTc("find", """{"path":"/etc","pattern":"*"}""")
    let r   = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check r.handled
    check r.text.startsWith("Error:")
    check r.text.contains("outside paddock")

  test "find with .. traversal rejected":
    let ctx = ctxWithPaddock(paddock)
    let tc  = makeTc("find", """{"path":"../../etc","pattern":"*"}""")
    let r   = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check r.handled
    check r.text.startsWith("Error:")

  test "grep inside paddock works":
    let ctx = ctxWithPaddock(paddock)
    let tc  = makeTc("grep", """{"pattern":"safe","path":"safe.txt"}""")
    let r   = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check r.handled
    check r.text.contains("safe content")

  test "grep with absolute escape rejected":
    let ctx = ctxWithPaddock(paddock)
    let tc  = makeTc("grep", """{"pattern":"root","path":"/etc/passwd"}""")
    let r   = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check r.handled
    check r.text.startsWith("Error:")
    check r.text.contains("outside paddock")
