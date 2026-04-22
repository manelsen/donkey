## native_tools deterministic unit tests.
## Tests procs that do not require live HTTP, LLM calls, or interactive I/O.
##
## Covered:
##   Shell      : performBash, hashline read/edit helpers, performFind, performGrep
##   Paddock    : resolveInPaddock, inPaddock, path escape rejection
##   Session    : applyTodoOps
##   via executeNativeTool: calc, checkpoint, rewind, submit_result, report_finding
##   Misc       : unknown tool → handled=false

import std/[json, options, os, strutils, tables, times, unittest]
import chronos
import chronos/asyncsync
import results
import donkey/core/pipeops
import donkey/core/log
import donkey/domain/message
import donkey/domain/more_tools
import donkey/adapters/memory/md_file
import donkey/config/clawhub_registry
import donkey/config/skills_registry
import donkey/app/session_state
import donkey/app/native_tools
import donkey/ports/http

# ── Helpers ───────────────────────────────────────────────────────────────────

proc stubComplete(req: CompletionRequest): Result[CompletionResponse, string] =
  ok(CompletionResponse(text: "stub", inputTokens: 1, outputTokens: 1))

proc makeCtx(): NativeCtx =
  NativeCtx(
    uid:         UserId("test-user"),
    channel:     ckTelegram,
    outbox:      newAsyncQueue[OutboundMessage](),
    session:     nil,
    memory:      MdFileAdapter(paddocksDir: getTempDir()).toRuntimePort(),
    completeFn:  stubComplete,
    braveApiKey: "",
    tools:       @[],
    log:         newLogger("test"),
  )

proc makeCtxWithMemory(memory: MemoryRuntimePort; uid = UserId("test-user")): NativeCtx =
  result = makeCtx()
  result.uid = uid
  result.memory = memory

proc makeTc(name, inputJson: string): ToolCallRequest =
  ToolCallRequest(id: "call-1", name: name, inputJson: inputJson)

proc mockHttp(status: int; body: string; errMsg = ""): HttpRuntimePort =
  HttpRuntimePort(
    get: proc(url: string; headers: seq[HttpHeader] = @[]): Result[HttpResponse, string] {.gcsafe.} =
      if errMsg.len > 0:
        return err(errMsg)
      ok(HttpResponse(status: status, body: body))
  )

proc setupInstalledRemoteSkill(home, slug: string;
                               scriptsToml = "";
                               scriptFile = "main.ts") =
  let skillDir = remoteSkillDir(home, slug)
  createDir(skillDir)
  writeFile(skillDir / "SKILL.md", "# " & slug & "\n")
  if scriptsToml.len > 0:
    writeFile(skillDir / "skills.toml", scriptsToml)
  writeFile(skillDir / scriptFile, "console.log('ok')\n")
  writeRemoteSkillOrigin(skillDir, RemoteSkillOrigin(
    version: 1,
    registry: ClawhubDefaultRegistry,
    slug: slug,
    installedVersion: "1.2.3",
    installedAt: getTime().toUnix(),
  ))
  var lock = readRemoteSkillLockfile(home)
  lock.skills[slug] = RemoteSkillLockEntry(version: "1.2.3", installedAt: getTime().toUnix())
  writeRemoteSkillLockfile(home, lock)

# ── resolveInPaddock / inPaddock ─────────────────────────────────────────────

suite "resolveInPaddock":

  test "relative path resolved under paddock":
    check resolveInPaddock("foo/bar", "/home/u/paddock") == "/home/u/paddock/foo/bar"

  test "absolute path returned as-is (normalized)":
    check resolveInPaddock("/etc/passwd", "/home/u/paddock") == "/etc/passwd"

  test "workspace alias maps to paddock root":
    check resolveInPaddock("/workspace", "/home/u/paddock") == "/home/u/paddock"

  test "workspace alias maps nested path into paddock":
    check resolveInPaddock("/workspace/src/app.nim", "/home/u/paddock") ==
      "/home/u/paddock/src/app.nim"

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

  test "workspace alias recognized as inside paddock":
    check inPaddock("/workspace/src/app.nim", "/home/u/paddock")

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

# ── hashline read/edit helpers ────────────────────────────────────────────────

suite "hashline file helpers":

  test "formatHashlineLine prefixes LINE#ID":
    let line = formatHashlineLine(3, "let x = 1")
    check line.startsWith("3#")
    check line.endsWith(":let x = 1")
    let anchor = line.split(":", maxsplit = 1)[0]  ## "3#xxxx"
    check anchor.split("#")[1].len == 4

  test "parseHashlineAnchor parses valid anchor":
    let parsed = parseHashlineAnchor("12#abc123")
    check parsed.isOk
    check parsed.value.line == 12
    check parsed.value.hash == "abc123"

  test "parseHashlineAnchor accepts full hashline line":
    let parsed = parseHashlineAnchor("12#abc123:let x = 1")
    check parsed.isOk
    check parsed.value.line == 12
    check parsed.value.hash == "abc123"

  test "renderHashlineSlice formats file lines":
    let rendered = renderHashlineSlice("alpha\nbeta", 1, 10)
    check rendered.contains(":alpha")
    check rendered.contains(":beta")

  test "applyEditFileOps replaces anchored line":
    let lines = @["alpha", "beta"]
    let anchor = HashlineAnchor(line: 2, hash: computeLineHash(2, "beta"))
    let applyResult = applyEditFileOps(lines, @[
      EditFileOp(kind: efokReplace, pos: some(anchor), stop: none(HashlineAnchor), lines: @["gamma"])
    ])
    check applyResult.isOk
    check applyResult.value == @["alpha", "gamma"]

  test "computeLineHash is stable across indentation changes":
    ## Anchors must survive formatter runs that only change indentation.
    let h0 = computeLineHash(5, "return x")
    let h2 = computeLineHash(5, "  return x")
    let h4 = computeLineHash(5, "    return x")
    check h0 == h2
    check h0 == h4

  test "validateHashlineAnchor accepts re-indented line":
    ## An anchor computed before formatting is still valid after indentation change.
    let reindented = @["alpha", "    return x"]
    let anchor = HashlineAnchor(line: 2, hash: computeLineHash(2, "  return x"))
    let r = validateHashlineAnchor(anchor, reindented)
    check r.isOk

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

suite "native_tools pure contexts":

  test "parseAskContext extracts required question":
    let parsed = parseAskContext(parseJson("""{"question":"where are you?"}"""))
    check parsed.isOk
    check parsed.value.question == "where are you?"

  test "parseBashContext extracts command":
    let parsed = parseBashContext(parseJson("""{"command":"pwd"}"""))
    check parsed.isOk
    check parsed.value.command == "pwd"

  test "parseReadFileContext resolves file path inside paddock":
    let parsed = parseReadFileContext(parseJson("""{"path":"src/app.nim","start_line":2}"""), "/tmp/paddock")
    check parsed.isOk
    check parsed.value.path == "/tmp/paddock/src/app.nim"
    check parsed.value.startLine == 2

  test "parseEditFileContext parses replace edit":
    let editJson = $(%*{
      "path": "src/app.nim",
      "edits": [
        {"op": "replace", "pos": "2#abc123", "lines": ["echo 1"]}
      ]
    })
    let parsed = parseEditFileContext(parseJson(editJson), "/tmp/paddock")
    check parsed.isOk
    check parsed.value.path == "/tmp/paddock/src/app.nim"
    check parsed.value.edits.len == 1
    check parsed.value.edits[0].kind == efokReplace

  test "parseFindContext resolves path inside paddock":
    let parsed = parseFindContext(parseJson("""{"path":"src","pattern":"*.nim"}"""), "/tmp/paddock")
    check parsed.isOk
    check parsed.value.path == "/tmp/paddock/src"
    check parsed.value.pattern == "*.nim"

  test "parseReadFileContext accepts workspace alias":
    let parsed = parseReadFileContext(parseJson("""{"path":"/workspace/PREFERENCES.md"}"""), "/tmp/paddock")
    check parsed.isOk
    check parsed.value.path == "/tmp/paddock/PREFERENCES.md"

  test "parseGrepContext rejects path outside paddock":
    let parsed = parseGrepContext(parseJson("""{"pattern":"x","path":"../../etc/passwd"}"""), "/tmp/paddock")
    check parsed.isErr
    check parsed.error.contains("outside paddock")

  test "parseFetchContext applies default max":
    let parsed = parseFetchContext(parseJson("""{"url":"https://example.com"}"""), 123)
    check parsed.isOk
    check parsed.value.maxCh == 123

  test "parseCalcContext extracts expression":
    let parsed = parseCalcContext(parseJson("""{"expression":"2+2"}"""))
    check parsed.isOk
    check parsed.value.expression == "2+2"

  test "parseTaskContext extracts prompt and optional context":
    let parsed = parseTaskContext(parseJson("""{"prompt":"do it","context":"extra"}"""))
    check parsed.isOk
    check parsed.value.prompt == "do it"
    check parsed.value.context == "extra"

  test "parseAwaitContext extracts job ids":
    let parsed = parseAwaitContext(parseJson("""{"job_ids":["a","b"]}"""))
    check parsed.isOk
    check parsed.value.ids == @["a", "b"]

  test "parseFindingContext extracts required finding":
    let parsed = parseFindingContext(parseJson("""{"finding":"disk full"}"""))
    check parsed.isOk
    check parsed.value.finding == "disk full"

  test "parseTodoOps rejects non-array ops":
    let parsed = parseTodoOps(parseJson("""{"ops":{}}"""))
    check parsed.isErr
    check parsed.error.startsWith("Error:")

  test "buildSubmitResult returns raw result text":
    let result = buildSubmitResult(parseJson("""{"result":"ok"}"""))
    check result.handled
    check result.text == "ok"

  test "buildTaskStartedText returns job_id and running status":
    check buildTaskStartedText("job-7") == "job_id=job-7\nstatus=running"

  test "buildCheckpointResult marks checkpointNow":
    let result = buildCheckpointResult(newSessionState())
    check result.handled
    check result.checkpointNow

  test "parseRewindIndex defaults to latest checkpoint":
    let parsed = parseRewindIndex(parseJson("{}"), 2)
    check parsed.isOk
    check parsed.value == 1

  test "buildRewindResult returns restored history":
    let state = newSessionState()
    var history = newHistory()
    history.addUser("hello")
    state.checkpoints.add(history)
    let result = buildRewindResult(state, 0)
    check result.isOk
    check result.value.newHistory.isSome
    check result.value.newHistory.get().len == 1

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

suite "executeNativeTool — manage_skills":

  test "list shows enabled skills and installed bundles":
    let home = getTempDir() / ("donkey_native_tool_skill_list_" & $epochTime().int)
    let userId = UserId("u-native-skill-list")
    let memory = MdFileAdapter(paddocksDir: home / "paddocks")
    let ctx = makeCtxWithMemory(memory.toRuntimePort(), userId)
    defer:
      if dirExists(home): removeDir(home)

    discard saveSkillEntry(memory.paddockDir(userId) / "skills" / "skills.toml", SkillManifest(
      name: "local-browser",
      version: "0.1.0",
      script: "/tmp/browser.ts",
    ))
    setupInstalledRemoteSkill(home, "remote-browser")

    let tc = makeTc("manage_skills", """{"action":"list"}""")
    let r = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check r.handled
    check r.text.contains("local-browser")
    check r.text.contains("remote-browser")

  test "enable activates installed remote bundle for the current user":
    let home = getTempDir() / ("donkey_native_tool_skill_enable_" & $epochTime().int)
    let userId = UserId("u-native-skill-enable")
    let memory = MdFileAdapter(paddocksDir: home / "paddocks")
    let ctx = makeCtxWithMemory(memory.toRuntimePort(), userId)
    defer:
      if dirExists(home): removeDir(home)

    setupInstalledRemoteSkill(
      home,
      "remote-browser",
      scriptsToml = """
[[skill]]
name = "remote-browser"
version = "1.2.3"
script = "main.ts"
permissions = ["--allow-net=clawhub.ai"]
""",
    )

    let tc = makeTc("manage_skills", """{"action":"enable","slug":"remote-browser"}""")
    let r = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    let enabled = loadSkillRegistry(memory.paddockDir(userId) / "skills" / "skills.toml")

    check r.handled
    check r.text.contains("habilitada")
    check r.text.contains("próxima mensagem sua")
    check enabled.len == 1
    check enabled[0].name == "remote-browser"
    check enabled[0].script == remoteSkillDir(home, "remote-browser") / "main.ts"

  test "invalid action returns operational error":
    let tc = makeTc("manage_skills", """{"action":"explode"}""")
    let r = waitFor executeNativeTool(tc, makeCtx(), newSessionState(), newHistory())
    check r.handled
    check r.resultKind == trkOperationalError
    check r.text.contains("unsupported manage_skills action")

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

suite "executeNativeTool — read_file and edit_file":

  var paddock: string
  var target: string

  setup:
    paddock = getTempDir() / ("donkey_edit_test_" & $epochTime().int)
    createDir(paddock)
    target = paddock / "sample.txt"
    writeFile(target, "alpha\nbeta\n")

  teardown:
    if dirExists(paddock): removeDir(paddock)

  proc ctxWithEditPaddock(pd: string): NativeCtx =
    NativeCtx(
      uid:         UserId("test-user"),
      channel:     ckTelegram,
      outbox:      newAsyncQueue[OutboundMessage](),
      session:     nil,
      memory:      MdFileAdapter(paddocksDir: pd).toRuntimePort(),
      completeFn:  stubComplete,
      braveApiKey: "",
      tools:       @[],
      log:         newLogger("test"),
      paddockDir:  pd,
    )

  test "read_file returns hashline-prefixed content":
    let ctx = ctxWithEditPaddock(paddock)
    let tc = makeTc("read_file", """{"path":"sample.txt"}""")
    let result = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check result.handled
    check result.text.contains(":alpha")
    check result.text.contains(":beta")
    check result.text.splitLines()[0].contains("#")

  test "edit_file replaces anchored line":
    let ctx = ctxWithEditPaddock(paddock)
    let readTc = makeTc("read_file", """{"path":"sample.txt"}""")
    let readResult = waitFor executeNativeTool(readTc, ctx, newSessionState(), newHistory())
    let secondAnchor = readResult.text.splitLines()[1].split(":", maxsplit = 1)[0]
    let editJson = $(%*{
      "path": "sample.txt",
      "edits": [
        {"op": "replace", "pos": secondAnchor, "lines": ["gamma"]}
      ]
    })
    let editTc = makeTc("edit_file", editJson)
    let editResult = waitFor executeNativeTool(editTc, ctx, newSessionState(), newHistory())
    check editResult.handled
    check readFile(target).strip() == "alpha\ngamma"
    ## edit_file returns updated hashline content so the model can chain edits
    check editResult.text.contains(":alpha")
    check editResult.text.contains(":gamma")
    check editResult.text.contains("#")

  test "edit_file rejects stale anchor":
    let ctx = ctxWithEditPaddock(paddock)
    let staleAnchor = formatHashlineRef(2, "beta")
    writeFile(target, "alpha\ndelta\n")
    let editJson = $(%*{
      "path": "sample.txt",
      "edits": [
        {"op": "replace", "pos": staleAnchor, "lines": ["gamma"]}
      ]
    })
    let editTc = makeTc("edit_file", editJson)
    let editResult = waitFor executeNativeTool(editTc, ctx, newSessionState(), newHistory())
    check editResult.handled
    check editResult.text.startsWith("Error: stale anchor")
    check editResult.resultKind == trkOperationalError

  test "edit_file accepts full hashline line via anchor alias":
    let ctx = ctxWithEditPaddock(paddock)
    let readTc = makeTc("read_file", """{"path":"sample.txt"}""")
    let readResult = waitFor executeNativeTool(readTc, ctx, newSessionState(), newHistory())
    let secondLine = readResult.text.splitLines()[1]
    let editJson = $(%*{
      "path": "sample.txt",
      "edits": [
        {"op": "replace", "anchor": secondLine, "lines": ["gamma"]}
      ]
    })
    let editTc = makeTc("edit_file", editJson)
    let editResult = waitFor executeNativeTool(editTc, ctx, newSessionState(), newHistory())
    check editResult.handled
    check readFile(target).strip() == "alpha\ngamma"

suite "executeNativeTool — schedule_reminder":

  var paddock: string

  setup:
    paddock = getTempDir() / ("donkey_reminder_test_" & $epochTime().int)
    createDir(paddock)

  teardown:
    if dirExists(paddock): removeDir(paddock)

  test "schedule_reminder is handled as native tool":
    let memory = MdFileAdapter(paddocksDir: paddock)
    let ctx = NativeCtx(
      uid:         UserId("test-user"),
      channel:     ckTelegram,
      outbox:      newAsyncQueue[OutboundMessage](),
      session:     nil,
      memory:      memory.toRuntimePort(),
      completeFn:  stubComplete,
      braveApiKey: "",
      tools:       @[],
      log:         newLogger("test"),
    )
    let tc = makeTc("schedule_reminder", """{"when":"in 1 minute","message":"standup"}""")
    let result = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    check result.handled
    check result.text == "Reminder scheduled."
    check result.resultKind == trkOutput
    var reminderCount = 0
    for _ in walkDirRec(memory.reminderDir(UserId("test-user"))):
      inc reminderCount
    check reminderCount == 1

suite "executeNativeTool — task jobs":

  proc extractJobId(text: string): string =
    for line in text.splitLines():
      if line.startsWith("job_id="):
        return line["job_id=".len .. ^1]
    ""

  test "task creates a background job id":
    let ctx   = makeCtx()
    let state = newSessionState()
    let tc    = makeTc("task", """{"prompt":"say hi"}""")
    let r = waitFor executeNativeTool(tc, ctx, state, newHistory())
    check r.handled
    check r.text.contains("job_id=")
    let jobId = extractJobId(r.text)
    check jobId.len > 0
    check state.jobs.hasKey(jobId)

  test "await returns result of created job":
    let ctx   = makeCtx()
    let state = newSessionState()
    let taskTc = makeTc("task", """{"prompt":"say hi"}""")
    let taskResult = waitFor executeNativeTool(taskTc, ctx, state, newHistory())
    let jobId = extractJobId(taskResult.text)
    let awaitTc = makeTc("await", $(%*{"job_ids": [jobId]}))
    let awaitResult = waitFor executeNativeTool(awaitTc, ctx, state, newHistory())
    check awaitResult.handled
    check awaitResult.text.contains(jobId & ": stub")

  test "cancel_job cancels created job":
    let ctx   = makeCtx()
    let state = newSessionState()
    let taskTc = makeTc("task", """{"prompt":"say hi"}""")
    let taskResult = waitFor executeNativeTool(taskTc, ctx, state, newHistory())
    let jobId = extractJobId(taskResult.text)
    let cancelTc = makeTc("cancel_job", $(%*{"job_id": jobId}))
    let cancelResult = waitFor executeNativeTool(cancelTc, ctx, state, newHistory())
    check cancelResult.handled
    check cancelResult.text.contains("cancelled")

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
      session:     nil,
      memory:      MdFileAdapter(paddocksDir: pd).toRuntimePort(),
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
    check r.resultKind == trkOperationalError

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

suite "executeNativeTool — structured tools":

  test "fs_list returns structured envelope":
    let paddock = getTempDir() / ("donkey_struct_exec_fs_" & $epochTime().int)
    createDir(paddock)
    defer:
      if dirExists(paddock): removeDir(paddock)
    writeFile(paddock / "alpha.txt", "alpha\n")
    var ctx = makeCtx()
    ctx.paddockDir = paddock
    let tc = makeTc(FsListToolName, """{"path":".","recursive":true}""")
    let r = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    let parsed = parseJson(r.text)
    check r.handled
    check r.resultKind == trkOutput
    check parsed["data"]["items"].len == 1
    check parsed["data"]["items"][0]["path"].getStr() == "alpha.txt"

  test "text_search returns structured matches":
    let paddock = getTempDir() / ("donkey_struct_exec_search_" & $epochTime().int)
    createDir(paddock)
    defer:
      if dirExists(paddock): removeDir(paddock)
    let target = paddock / "notes.txt"
    writeFile(target, "alpha\nneedle beta\n")
    var ctx = makeCtx()
    ctx.paddockDir = paddock
    let tc = makeTc(TextSearchToolName, """{"pattern":"needle","path":"notes.txt"}""")
    let r = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    let parsed = parseJson(r.text)
    check r.handled
    check r.resultKind == trkOutput
    check parsed["data"]["matches"][0]["line"].getInt() == 2

  test "json_query and table_query are dispatched natively":
    let jq = waitFor executeNativeTool(
      makeTc(JsonQueryToolName, """{"op":"get","input":{"user":{"name":"Ana"}},"path":["user","name"]}"""),
      makeCtx(), newSessionState(), newHistory())
    let jqParsed = parseJson(jq.text)
    check jq.handled
    check jq.resultKind == trkOutput
    check jqParsed["data"]["value"].getStr() == "Ana"

    let tq = waitFor executeNativeTool(
      makeTc(TableQueryToolName, """{"rows":[{"name":"b","score":2},{"name":"a","score":1}],"sort":[{"field":"name","order":"asc"}]}"""),
      makeCtx(), newSessionState(), newHistory())
    let tqParsed = parseJson(tq.text)
    check tq.handled
    check tq.resultKind == trkOutput
    check tqParsed["data"]["rows"][0]["name"].getStr() == "a"

  test "http_fetch uses structured web result":
    var ctx = makeCtx()
    ctx.http = mockHttp(200, """{"ok":true}""")
    let tc = makeTc(HttpFetchToolName, """{"url":"https://example.com/api","expect":"json"}""")
    let r = waitFor executeNativeTool(tc, ctx, newSessionState(), newHistory())
    let parsed = parseJson(r.text)
    check r.handled
    check r.resultKind == trkOutput
    check parsed["data"]["body"]["ok"].getBool()

  test "archive_create and archive_extract are dispatched natively":
    let paddock = getTempDir() / ("donkey_struct_exec_archive_" & $epochTime().int)
    createDir(paddock)
    createDir(paddock / "docs")
    writeFile(paddock / "docs" / "notes.txt", "archive me\n")
    defer:
      if dirExists(paddock): removeDir(paddock)
    var ctx = makeCtx()
    ctx.paddockDir = paddock

    let createTc = makeTc(ArchiveCreateToolName, """{"archive_path":"bundle.tgz","inputs":["docs"]}""")
    let created = waitFor executeNativeTool(createTc, ctx, newSessionState(), newHistory())
    let createdParsed = parseJson(created.text)
    check created.handled
    check created.resultKind == trkOutput
    check createdParsed["data"]["entry_count"].getInt() == 1

    let extractTc = makeTc(ArchiveExtractToolName, """{"archive_path":"bundle.tgz","destination":"restored"}""")
    let extracted = waitFor executeNativeTool(extractTc, ctx, newSessionState(), newHistory())
    let extractedParsed = parseJson(extracted.text)
    check extracted.handled
    check extracted.resultKind == trkOutput
    check extractedParsed["data"]["entry_count"].getInt() > 0
    check readFile(paddock / "restored" / "docs" / "notes.txt") == "archive me\n"
