## Tests for infra/sandbox/wasm_tools — WasmToolAdapter for go-busybox applets.
##
## WasmToolAdapter wraps wasmtime execution of individual go-busybox applets
## (grep, find, sed, cat, etc.) as sandboxed tool calls.

import std/[unittest, os, strutils]
import ../../../src/donkey/infra/sandbox/wasm_tools

# ── Pure tests (no wasm binary needed) ────────────────────────────────────────

suite "infra/sandbox/wasm_tools - WasmToolAdapter":

  test "newWasmToolAdapter creates adapter with default busybox path":
    let adapter = newWasmToolAdapter()
    check adapter.busyboxPath.len > 0

  test "newWasmToolAdapter with custom path":
    let adapter = newWasmToolAdapter("/opt/busybox")
    check adapter.busyboxPath == "/opt/busybox"

suite "infra/sandbox/wasm_tools - buildAppletCmd":

  test "buildAppletCmd for simple applet no args":
    let cmd = buildAppletCmd("/usr/bin/busybox", "echo", @[], "/tmp")
    check "wasmtime" in cmd
    check "--dir=/tmp" in cmd
    check "/usr/bin/busybox" in cmd
    check "echo" in cmd

  test "buildAppletCmd for grep with pattern and file":
    let cmd = buildAppletCmd("/usr/bin/busybox", "grep", @["-n", "hello", "file.txt"], "/workspace")
    check "wasmtime" in cmd
    check "--dir=/workspace" in cmd
    check "--dir=/tmp" in cmd
    check "busybox" in cmd
    check "grep" in cmd
    check "-n" in cmd
    check "hello" in cmd
    check "file.txt" in cmd

  test "buildAppletCmd for find with path":
    let cmd = buildAppletCmd("/home/user/.donkey/busybox", "find", @[".", "-name", "*.txt"], "/project")
    check "--dir=/project" in cmd
    check "find" in cmd

  test "buildAppletCmd for sed with expression":
    let cmd = buildAppletCmd("/busybox", "sed", @["s/foo/bar/g", "input.txt"], "/work")
    check "sed" in cmd
    check "s/foo/bar/g" in cmd
    check "input.txt" in cmd

  test "buildAppletCmd quotes shell metacharacters in args":
    let cmd = buildAppletCmd("/busybox", "grep", @["hello world", "file name.txt"], "/tmp")
    check "hello world" in cmd

  test "buildAppletCmd includes /tmp dir by default":
    let cmd = buildAppletCmd("/busybox", "cat", @["file.txt"], "/work")
    check "--dir=/tmp" in cmd

suite "infra/sandbox/wasm_tools - AppletResult":

  test "$result shows exit code and output":
    let r = AppletResult(exitCode: 0, output: "hello\n", success: true)
    let s = $r
    check "exitCode=0" in s
    check "success=true" in s
    check "output.len=6" in s

  test "$result shows failure":
    let r = AppletResult(exitCode: 1, output: "error", success: false)
    let s = $r
    check "success=false" in s

suite "infra/sandbox/wasm_tools - buildAppletArgs":

  test "buildAppletArgs joins args with spaces":
    let args = buildAppletArgs(@["-n", "pattern", "file.txt"])
    check args == "-n pattern file.txt"

  test "buildAppletArgs empty returns empty string":
    let args = buildAppletArgs(@[])
    check args == ""

  test "buildAppletArgs single arg":
    let args = buildAppletArgs(@["hello"])
    check args == "hello"

suite "infra/sandbox/wasm_tools - applet name validation":

  test "isValidAppletName returns true for known applets":
    check isValidAppletName("grep") == true
    check isValidAppletName("find") == true
    check isValidAppletName("sed") == true
    check isValidAppletName("cat") == true
    check isValidAppletName("echo") == true
    check isValidAppletName("ls") == true
    check isValidAppletName("wc") == true
    check isValidAppletName("sort") == true

  test "isValidAppletName returns false for unknown":
    check isValidAppletName("nonexistent") == false
    check isValidAppletName("") == false
    check isValidAppletName("sh") == false  # stubbed under WASI
    check isValidAppletName("ash") == false # stubbed under WASI

suite "infra/sandbox/wasm_tools - availableApplets":

  test "availableApplets returns non-empty list":
    let applets = availableApplets()
    check applets.len > 0
    check "grep" in applets
    check "find" in applets
    check "sed" in applets
    check "cat" in applets

  test "availableApplets excludes stubbed applets":
    let applets = availableApplets()
    check "ash" notin applets
    check "sh" notin applets
    check "top" notin applets

suite "infra/sandbox/wasm_tools - formatAppletResult":

  test "formatAppletResult trims trailing newline":
    let r = formatAppletResult("hello\n", 0)
    check r == "hello"

  test "formatAppletResult adds exit code on failure":
    let r = formatAppletResult("not found\n", 1)
    check "[exit 1]" in r

  test "formatAppletResult empty output with failure":
    let r = formatAppletResult("", 2)
    check r == "[exit 2]"

  test "formatAppletResult empty output with success":
    let r = formatAppletResult("", 0)
    check r == ""

# ── Integration tests (require busybox binary) ───────────────────────────────

const busyboxPath = getHomeDir() / ".donkey" / "busybox"
let hasBusybox = busyboxPath.fileExists

suite "infra/sandbox/wasm_tools - integration":

  test "runApplet echo works":
    if not hasBusybox: skip()
    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("echo", @["hello wasm"], "/tmp")
    check r.success
    check "hello wasm" in r.output

  test "runApplet cat works on temp file":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_wasm_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let testFile = tmpDir / "test.txt"
    writeFile(testFile, "line1\nline2\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("cat", @[testFile], tmpDir)
    check r.success
    check "line1" in r.output
    check "line2" in r.output

  test "runApplet wc counts lines":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_wasm_test_wc"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let dataFile = tmpDir / "data.txt"
    writeFile(dataFile, "aaa\nbbb\nccc\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("wc", @["-l", dataFile], tmpDir)
    check r.success
    check "3" in r.output
