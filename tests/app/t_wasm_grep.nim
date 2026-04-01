## Tests for WASM-based grep via WasmToolAdapter.

import std/[unittest, os, strutils]
import ../../src/donkey/infra/sandbox/wasm_tools

const busyboxPath = getHomeDir() / ".donkey" / "busybox"
let hasBusybox = busyboxPath.fileExists

suite "wasm grep - WasmToolAdapter":

  test "grep finds pattern in file":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_grep_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "sample.txt"
    writeFile(f, "hello world\nfoo bar\nhello again\nbaz\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("grep", @["hello", f], tmpDir)
    check r.success
    check "hello world" in r.output
    check "hello again" in r.output
    check "foo bar" notin r.output

  test "grep -n shows line numbers":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_grep_n"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "lines.txt"
    writeFile(f, "aaa\nbbb\nccc\nbbb\nddd\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("grep", @["-n", "bbb", f], tmpDir)
    check r.success
    check "2:bbb" in r.output
    check "4:bbb" in r.output

  test "grep -i case insensitive":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_grep_i"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "case.txt"
    writeFile(f, "Hello World\nhello world\nHELLO WORLD\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("grep", @["-i", "hello", f], tmpDir)
    check r.success
    check r.output.splitLines().len >= 3

  test "grep -v inverts match":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_grep_v"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "invert.txt"
    writeFile(f, "keep\nremove\nkeep\nremove\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("grep", @["-v", "remove", f], tmpDir)
    check r.success
    check "keep" in r.output
    check "remove" notin r.output

  test "grep -c counts matches":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_grep_c"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "count.txt"
    writeFile(f, "x\ny\nx\nz\nx\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("grep", @["-c", "x", f], tmpDir)
    check r.success
    check "3" in r.output

  test "grep returns no-match exit code":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_grep_nomatch"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "empty.txt"
    writeFile(f, "aaa\nbbb\nccc\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("grep", @["zzz", f], tmpDir)
    check not r.success
    check r.exitCode == 1  # grep returns 1 for no match
