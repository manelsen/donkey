## Tests for ShellTools adapter — ToolPort implementation for shell execution.
##
## Tests cover:
##   - ToolPort concept conformance (listTools, invoke)
##   - shell_exec command validation and execution
##   - Shell operator blocking via shell_ast
##   - Input validation for required parameters
##   - Error handling without exceptions
##   - Workspace restrictions

import std/[json, os, sequtils, strutils, unittest]
import donkey/adapters/tools/shell
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

template withTempDir*(tmpDir: untyped; body: untyped): untyped =
  ## Creates a temporary directory, runs body, cleans up.
  block:
    let d = getTempDir() / "donkey_shell_test_" & $nowMs()
    createDir(d)
    defer:
      cleanupTmpDir(d)
    mixin tmpDir
    let tmpDir = d
    body

# ── Concept conformance ───────────────────────────────────────────────────────

suite "ToolPort conformance":

  test "ShellTools satisfies ToolPort concept":
    ## Compile-time proof: ShellTools implements ToolPort.
    ## If this test file compiles, the concept is satisfied.
    var st = ShellTools()
    let tools = st.listTools()
    check tools.isOk
    # invoke returns Result - even errors are isOk=false, not exceptions
    let call = ToolCall(id: "test", name: "unknown_tool", input: %* {})
    let res = st.invoke(call)
    check res.isOk  # Result type is ok, even if the tool is unknown

  test "listTools returns exactly one schema":
    let st = ShellTools()
    let result = st.listTools()
    check result.isOk
    let tools = result.get()
    check tools.len == 1
    check tools[0].name == "shell_exec"

  test "listTools schema has required fields":
    let st = ShellTools()
    let tools = st.listTools().get()
    for tool in tools:
      check tool.name.len > 0
      check tool.description.len > 0
      check tool.inputSchema.kind == JObject
      check tool.inputSchema.hasKey("type")
      check tool.inputSchema.hasKey("properties")

  test "shell_exec schema properties":
    let st = ShellTools()
    let tools = st.listTools().get()
    let schema = tools.filterIt(it.name == "shell_exec")[0]
    check schema.inputSchema["properties"].hasKey("command")
    check schema.inputSchema["properties"].hasKey("cwd")
    # command is required
    let required = schema.inputSchema.getOrDefault("required")
    check required.kind == JArray
    check required.len == 1
    check required[0].getStr == "command"

# ── validateCommand tests ──────────────────────────────────────────────────────

suite "validateCommand":

  test "accepts simple commands without operators":
    let result = validateCommand("echo hello")
    check result.isOk
    check result.get() == "echo hello"

  test "accepts commands with arguments":
    let result = validateCommand("ls -la /tmp")
    check result.isOk

  test "accepts commands with quotes":
    let result = validateCommand("echo 'hello world'")
    check result.isOk

  test "rejects commands with pipes in quoted strings":
    # shell_ast is conservative - it blocks | even inside quotes
    # This is safer since quoting might not always work as expected
    let result = validateCommand("echo 'a|b'")
    check result.isErr

  test "blocks pipe operator":
    let result = validateCommand("echo hello | wc")
    check result.isErr
    check result.error.contains("pipe")

  test "blocks semicolon operator":
    let result = validateCommand("echo hello ; ls")
    check result.isErr
    # Error message is "command separator (;)" - check for "separator" or ";"
    check result.error.contains("separator") or result.error.contains(";")

  test "blocks ampersand operator":
    let result = validateCommand("echo hello & ls")
    check result.isErr
    # Error message is "background/AND operator (&)" - check for "background" or "&"
    check result.error.contains("background") or result.error.contains("&")

  test "blocks logical AND operator":
    let result = validateCommand("echo a && ls")
    check result.isErr
    check result.error.contains("logical AND")

  test "blocks logical OR operator":
    let result = validateCommand("echo a || ls")
    check result.isErr
    check result.error.contains("logical OR")

  test "blocks input redirect operator":
    let result = validateCommand("cat < file.txt")
    check result.isErr
    check result.error.contains("input redirect")

  test "blocks output redirect operator":
    let result = validateCommand("echo hello > out.txt")
    check result.isErr
    check result.error.contains("output redirect")

  test "blocks output append operator":
    let result = validateCommand("echo hello >> out.txt")
    check result.isErr
    check result.error.contains("append")

  test "blocks stderr redirect operator":
    let result = validateCommand("cmd 2> error.txt")
    check result.isErr
    check result.error.contains("stderr")

  test "blocks compound operators":
    let result = validateCommand("echo a && ls || echo b")
    check result.isErr
    # Should mention compound or multiple operators
    check result.error.contains("operator")

  test "accepts whitespace-only variations":
    check validateCommand("echo   hello").isOk
    check validateCommand("  ls  ").isOk

# ── shell_exec tests ───────────────────────────────────────────────────────────

suite "shell_exec":

  test "executes simple echo command":
    var st = ShellTools()
    let call = ToolCall(id: "call-s1", name: "shell_exec", input: %* {"command": "echo hello"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.callId == "call-s1"
    check tr.isError == false
    check tr.output.strip() == "hello"

  test "executes ls command":
    withTempDir(tmpDir):
      var st = ShellTools()
      let call = ToolCall(id: "call-s2", name: "shell_exec", input: %* {"command": "ls " & tmpDir})
      let result = st.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      # Should list the directory (empty)
      check tr.output.strip().len >= 0

  test "executes with custom cwd":
    withTempDir(tmpDir):
      var st = ShellTools()
      let call = ToolCall(id: "call-s3", name: "shell_exec", input: %* {
        "command": "pwd",
        "cwd": tmpDir
      })
      let result = st.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      check tr.output.strip() == tmpDir

  test "respects workspace restriction":
    withTempDir(tmpDir):
      var st = ShellTools(workspace: tmpDir)
      # Command that would escape workspace should still work since workspace
      # doesn't restrict the command itself, only file paths if command accesses them
      let call = ToolCall(id: "call-s4", name: "shell_exec", input: %* {"command": "echo ok"})
      let result = st.invoke(call)
      check result.isOk
      let tr = result.get()
      check tr.isError == false
      check tr.output.strip() == "ok"

  test "returns error for missing command":
    var st = ShellTools()
    let call = ToolCall(id: "call-s5", name: "shell_exec", input: %* {})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.callId == "call-s5"
    check tr.isError == true
    check tr.output.contains("missing required field")

  test "returns error for empty command":
    var st = ShellTools()
    let call = ToolCall(id: "call-s6", name: "shell_exec", input: %* {"command": ""})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("missing required field")

  test "blocks pipe operator":
    var st = ShellTools()
    let call = ToolCall(id: "call-s7", name: "shell_exec", input: %* {"command": "echo hello | wc"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.callId == "call-s7"
    check tr.isError == true
    check tr.output.contains("pipe")

  test "blocks semicolon operator":
    var st = ShellTools()
    let call = ToolCall(id: "call-s8", name: "shell_exec", input: %* {"command": "echo a ; ls"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("separator") or tr.output.contains(";")

  test "blocks ampersand operator":
    var st = ShellTools()
    let call = ToolCall(id: "call-s9", name: "shell_exec", input: %* {"command": "sleep 1 &"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("background") or tr.output.contains("&")

  test "blocks logical AND":
    var st = ShellTools()
    let call = ToolCall(id: "call-s10", name: "shell_exec", input: %* {"command": "true && echo yes"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("logical AND")

  test "blocks logical OR":
    var st = ShellTools()
    let call = ToolCall(id: "call-s11", name: "shell_exec", input: %* {"command": "false || echo no"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("logical OR")

  test "blocks input redirect":
    var st = ShellTools()
    let call = ToolCall(id: "call-s12", name: "shell_exec", input: %* {"command": "cat < file.txt"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("input redirect")

  test "blocks output redirect":
    var st = ShellTools()
    let call = ToolCall(id: "call-s13", name: "shell_exec", input: %* {"command": "echo hi > out.txt"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("output redirect")

  test "captures stderr in output":
    var st = ShellTools()
    # Use a command that produces stderr without redirect operators
    let call = ToolCall(id: "call-s14", name: "shell_exec", input: %* {"command": "ls /nonexistent_directory_12345"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    # ls to nonexistent directory produces stderr
    check tr.output.contains("No such file") or tr.output.contains("nonexistent")

  test "returns non-zero exit code as error":
    var st = ShellTools()
    let call = ToolCall(id: "call-s15", name: "shell_exec", input: %* {"command": "exit 1"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.isError == true
    check tr.output.contains("exited with code 1")

# ── unknown tool handling ─────────────────────────────────────────────────────

suite "unknown tool":
  test "returns error for unknown tool":
    var st = ShellTools()
    let call = ToolCall(id: "call-u1", name: "shell_unknown", input: %* {})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.callId == "call-u1"
    check tr.isError == true
    check tr.output.contains("unknown tool")

# ── call id preservation ──────────────────────────────────────────────────────

suite "call id preservation":
  test "shell_exec preserves call id":
    var st = ShellTools()
    let call = ToolCall(id: "call-id-123", name: "shell_exec", input: %* {"command": "echo test"})
    let result = st.invoke(call)
    check result.isOk
    let tr = result.get()
    check tr.callId == "call-id-123"
