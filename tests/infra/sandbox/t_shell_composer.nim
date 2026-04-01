## Tests for infra/sandbox/shell_composer — pipe composition via WASM applets.

import std/[unittest, os, strutils, sequtils]
import ../../../src/donkey/infra/sandbox/wasm_tools
import ../../../src/donkey/infra/sandbox/shell_composer

const busyboxPath = getHomeDir() / ".donkey" / "busybox"
let hasBusybox = busyboxPath.fileExists

suite "shell_composer - parsePipeExpr":

  test "parse single command":
    let cmds = parsePipeExpr("echo hello")
    check cmds.len == 1
    check cmds[0].applet == "echo"
    check cmds[0].args == @["hello"]

  test "parse two-stage pipe":
    let cmds = parsePipeExpr("cat file.txt | grep hello")
    check cmds.len == 2
    check cmds[0].applet == "cat"
    check cmds[0].args == @["file.txt"]
    check cmds[1].applet == "grep"
    check cmds[1].args == @["hello"]

  test "parse three-stage pipe":
    let cmds = parsePipeExpr("cat data.txt | grep foo | sort")
    check cmds.len == 3
    check cmds[0].applet == "cat"
    check cmds[1].applet == "grep"
    check cmds[2].applet == "sort"

  test "parse command with quoted args":
    let cmds = parsePipeExpr("""grep "hello world" file.txt""")
    check cmds.len == 1
    check cmds[0].applet == "grep"
    check cmds[0].args == @["hello world", "file.txt"]

  test "parse head with dash notation":
    let cmds = parsePipeExpr("cat file.txt | head -n 5")
    check cmds.len == 2
    check cmds[1].applet == "head"
    check cmds[1].args == @["-n", "5"]

  test "parse empty string returns empty":
    let cmds = parsePipeExpr("")
    check cmds.len == 0

  test "parse strips whitespace":
    let cmds = parsePipeExpr("  cat file.txt  |  grep foo  ")
    check cmds.len == 2
    check cmds[0].applet == "cat"
    check cmds[1].applet == "grep"

suite "shell_composer - PipeSegment":

  test "$segment shows applet and args":
    let seg = PipeSegment(applet: "grep", args: @["-n", "pattern"])
    let s = $seg
    check "grep" in s
    check "-n" in s

suite "shell_composer - needsStdin":

  test "cat with file arg does not need stdin":
    check needsStdin("cat", @["file.txt"]) == false

  test "cat without args needs stdin":
    check needsStdin("cat", @[]) == true

  test "grep with file arg does not need stdin":
    check needsStdin("grep", @["pattern", "file.txt"]) == false

  test "grep with only pattern needs stdin":
    check needsStdin("grep", @["pattern"]) == true

  test "head with file arg does not need stdin":
    check needsStdin("head", @["-n", "5", "file.txt"]) == false

  test "head without file needs stdin":
    check needsStdin("head", @["-n", "5"]) == true

  test "sort with file arg does not need stdin":
    check needsStdin("sort", @["file.txt"]) == false

  test "sort without file needs stdin":
    check needsStdin("sort", @[]) == true

  test "wc with file arg does not need stdin":
    check needsStdin("wc", @["-l", "file.txt"]) == false

  test "wc without file needs stdin":
    check needsStdin("wc", @["-l"]) == true

suite "shell_composer - integration":

  test "single command works":
    if not hasBusybox: skip()
    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.compose("echo hello world", "/tmp")
    check r.success
    check "hello world" in r.output

  test "cat | grep pipe works":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_compose_cat_grep"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "data.txt", "apple\nbanana\ncherry\napricot\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.compose("cat " & tmpDir / "data.txt" & " | grep ap", tmpDir)
    check r.success
    check "apple" in r.output
    check "apricot" in r.output
    check "banana" notin r.output

  test "cat | grep | sort pipe works":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_compose_3"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "data.txt", "zebra\napple\nmango\navocado\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.compose("cat " & tmpDir / "data.txt" & " | grep a | sort", tmpDir)
    check r.success
    let lines = r.output.splitLines().filterIt(it.len > 0)
    check lines == @["apple", "avocado", "mango", "zebra"]

  test "cat | grep | head pipe works":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_compose_head"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "data.txt", "a1\nb2\na3\nb4\na5\nb6\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.compose("cat " & tmpDir / "data.txt" & " | grep a | head -n 2", tmpDir)
    check r.success
    let lines = r.output.splitLines().filterIt(it.len > 0)
    check lines.len == 2
    check lines[0] == "a1"
    check lines[1] == "a3"

  test "cat | wc -l pipe works":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_compose_wc"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "data.txt", "one\ntwo\nthree\nfour\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.compose("cat " & tmpDir / "data.txt" & " | wc -l", tmpDir)
    check r.success
    check "4" in r.output

  test "error propagates from middle of pipe":
    if not hasBusybox: skip()
    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.compose("cat /nonexistent/file.txt | grep x", "/tmp")
    check not r.success
