## Tests for GitTools adapter — ToolPort implementation for git introspection.
##
## Tests cover:
##   - ToolPort concept conformance (listTools, invoke)
##   - git status, git log, git diff commands
##   - Input validation for optional parameters
##   - Error handling without exceptions

import std/[json, os, sequtils, strutils, unittest]
import donkey/adapters/tools/git
import donkey/ports/tool
import donkey/core/pipeops

# ── Test fixtures ──────────────────────────────────────────────────────────────

proc cleanupTmpDir(d: string) =
  ## Cleanup helper - removes directory and all contents.
  if dirExists(d):
    for kind, path in walkDir(d, relative = false):
      if kind == pcDir:
        cleanupTmpDir(path)
      else:
        removeFile(path)
    removeDir(d)

func jsonArrayContains(arr: JsonNode; value: string): bool =
  ## Check if a JSON array contains a string value.
  assert arr.kind == JArray, "jsonArrayContains requires JArray"
  for item in arr:
    if item.kind == JString and item.getStr == value:
      return true
  false

template withTempDir*(tmpDir: untyped; body: untyped): untyped =
  ## Creates a temporary directory, runs body, cleans up.
  block:
    let d = getTempDir() / "donkey_git_test_" & $nowMs()
    createDir(d)
    defer:
      cleanupTmpDir(d)
    mixin tmpDir
    let tmpDir = d
    body

template withGitRepo*(repoDir: untyped; body: untyped): untyped =
  ## Creates a temp directory initialized as git repo, runs body, cleans up.
  block:
    let d = getTempDir() / "donkey_git_repo_" & $nowMs()
    createDir(d)
    defer:
      cleanupTmpDir(d)
    mixin repoDir
    let repoDir = d
    # Initialize git repo
    let oldDir = getCurrentDir()
    setCurrentDir(repoDir)
    discard execShellCmd("git init")
    discard execShellCmd("git config user.email \"test@test.com\"")
    discard execShellCmd("git config user.name \"Test User\"")
    try:
      body
    finally:
      setCurrentDir(oldDir)

# ── Concept conformance ───────────────────────────────────────────────────────

suite "ToolPort conformance":

  test "GitTools satisfies ToolPort concept":
    ## Compile-time proof: GitTools implements ToolPort.
    ## If this test file compiles, the concept is satisfied.
    var gt = GitTools()
    let tools = gt.listTools()
    check tools.isOk
    # invoke returns Result - even errors are isOk=false, not exceptions
    let call = ToolCall(id: "test", name: "unknown_tool", input: %* {})
    let res = gt.invoke(call)
    check res.isOk  # Result type is ok, even if the tool is unknown

  test "listTools returns exactly three schemas":
    let gt = GitTools()
    let result = gt.listTools()
    check result.isOk
    let tools = result.get()
    check tools.len == 3
    let names = tools.mapIt(it.name)
    check "git_status" in names
    check "git_log" in names
    check "git_diff" in names

  test "listTools schemas have required fields":
    let gt = GitTools()
    let tools = gt.listTools().get()
    for tool in tools:
      check tool.name.len > 0
      check tool.description.len > 0
      check tool.inputSchema.kind == JObject
      check tool.inputSchema.hasKey("type")
      check tool.inputSchema.hasKey("properties")

  test "git_status schema properties":
    let gt = GitTools()
    let tools = gt.listTools().get()
    let schema = tools.filterIt(it.name == "git_status")[0]
    # git_status has no required fields
    let required = schema.inputSchema.getOrDefault("required")
    if not required.isNil:
      check required.kind == JArray
      check required.len == 0

  test "git_log schema properties":
    let gt = GitTools()
    let tools = gt.listTools().get()
    let schema = tools.filterIt(it.name == "git_log")[0]
    check schema.inputSchema["properties"].hasKey("limit")
    check schema.inputSchema["properties"].hasKey("path")

  test "git_diff schema properties":
    let gt = GitTools()
    let tools = gt.listTools().get()
    let schema = tools.filterIt(it.name == "git_diff")[0]
    check schema.inputSchema["properties"].hasKey("path")

# ── git_status tests ─────────────────────────────────────────────────────────

suite "git_status":

  test "returns branch and status in git repo":
    withGitRepo(repoDir):
      # Create initial commit so we're on a branch
      writeFile(repoDir / "README.md", "# Test")
      discard execShellCmd("git add README.md")
      discard execShellCmd("git commit -m 'initial commit'")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-s1", name: "git_status", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.callId == "call-s1"
      check tr.isError == false
      # Should contain branch info
      check tr.output.contains("main") or tr.output.contains("master")

  test "shows staged changes":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "content")
      discard execShellCmd("git add file.txt")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-s2", name: "git_status", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      # Should show A (added) status for staged file
      check tr.output.contains("A ")

  test "shows unstaged changes":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "content")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'initial'")
      writeFile(repoDir / "file.txt", "modified")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-s3", name: "git_status", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      # Should show M (modified) status
      check tr.output.contains("M ")

  test "handles non-git directory gracefully":
    withTempDir(tmpDir):
      var gt = GitTools()
      let call = ToolCall(id: "call-s4", name: "git_status", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      # Should return empty or indicate no git repo
      check tr.isError == false

# ── git_log tests ───────────────────────────────────────────────────────────

suite "git_log":

  test "returns commit history":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "content")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'first commit'")
      writeFile(repoDir / "file.txt", "content 2")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'second commit'")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-l1", name: "git_log", input: %* {"limit": 10})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.callId == "call-l1"
      check tr.isError == false
      # Should contain both commits (format: hash short author date subject)
      check tr.output.contains("first commit")
      check tr.output.contains("second commit")

  test "respects limit parameter":
    withGitRepo(repoDir):
      for i in 1..5:
        writeFile(repoDir / "file.txt", "content " & $i)
        discard execShellCmd("git add file.txt")
        discard execShellCmd("git commit -m 'commit " & $i & "'")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-l2", name: "git_log", input: %* {"limit": 3})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      # Should have exactly 3 commits
      let lines = tr.output.split("\n")
      check lines.len == 3

  test "uses default limit of 10":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "content")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'one commit'")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-l3", name: "git_log", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      # Should contain the commit
      check tr.output.contains("one commit")

  test "handles empty repository":
    withGitRepo(repoDir):
      var gt = GitTools()
      let call = ToolCall(id: "call-l4", name: "git_log", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      # Should return empty log message
      check tr.output.contains("no commits")

# ── git_diff tests ──────────────────────────────────────────────────────────

suite "git_diff":

  test "shows unstaged changes":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "original")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'initial'")
      writeFile(repoDir / "file.txt", "modified content")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-d1", name: "git_diff", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.callId == "call-d1"
      check tr.isError == false
      # Should show the diff
      check tr.output.contains("+modified content") or tr.output.contains("-original")

  test "shows diff for specific file":
    withGitRepo(repoDir):
      writeFile(repoDir / "file1.txt", "content1")
      writeFile(repoDir / "file2.txt", "content2")
      discard execShellCmd("git add .")
      discard execShellCmd("git commit -m 'initial'")
      writeFile(repoDir / "file1.txt", "modified1")
      writeFile(repoDir / "file2.txt", "modified2")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-d2", name: "git_diff", input: %* {"path": "file1.txt"})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      # Should only show diff for file1.txt
      check tr.output.contains("file1.txt") or tr.output.contains("modified1")

  test "returns no changes when clean":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "content")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'initial'")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-d3", name: "git_diff", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      # Should indicate no changes
      check tr.output.contains("no unstaged changes")

# ── Unknown tool handling ────────────────────────────────────────────────────

suite "unknown tool":
  test "returns error for unknown tool":
    var gt = GitTools()
    let call = ToolCall(id: "call-u1", name: "git_unknown", input: %* {})
    let result = gt.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.callId == "call-u1"
    check tr.isError == true
    check tr.output.contains("unknown tool")

# ── call id preservation ─────────────────────────────────────────────────────

suite "call id preservation":
  test "git_status preserves call id":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "content")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'initial'")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-id-123", name: "git_status", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.callId == "call-id-123"

  test "git_log preserves call id":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "content")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'initial'")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-id-456", name: "git_log", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.callId == "call-id-456"

  test "git_diff preserves call id":
    withGitRepo(repoDir):
      writeFile(repoDir / "file.txt", "content")
      discard execShellCmd("git add file.txt")
      discard execShellCmd("git commit -m 'initial'")
      writeFile(repoDir / "file.txt", "modified")
      
      var gt = GitTools()
      let call = ToolCall(id: "call-id-789", name: "git_diff", input: %* {})
      let result = gt.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.callId == "call-id-789"
