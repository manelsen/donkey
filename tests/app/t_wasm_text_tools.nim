## Tests for WASM-based text tools (wc, head, tail, sort, awk).

import std/[unittest, os, strutils, sequtils]
import ../../src/donkey/infra/sandbox/wasm_tools

const busyboxPath = getHomeDir() / ".donkey" / "busybox"
let hasBusybox = busyboxPath.fileExists

suite "wasm text tools - wc":

  test "wc -l counts lines":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_wc_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "f.txt", "a\nb\nc\nd\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("wc", @["-l", tmpDir / "f.txt"], tmpDir)
    check r.success
    check "4" in r.output

  test "wc -w counts words":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_wc_w"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "f.txt", "hello world foo\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("wc", @["-w", tmpDir / "f.txt"], tmpDir)
    check r.success
    check "3" in r.output

suite "wasm text tools - head":

  test "head -n 3 returns first 3 lines":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_head_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "f.txt", "l1\nl2\nl3\nl4\nl5\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("head", @["-n", "3", tmpDir / "f.txt"], tmpDir)
    check r.success
    check "l1" in r.output
    check "l3" in r.output
    check "l4" notin r.output

suite "wasm text tools - tail":

  test "tail -n 2 returns last 2 lines":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_tail_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "f.txt", "l1\nl2\nl3\nl4\nl5\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("tail", @["-n", "2", tmpDir / "f.txt"], tmpDir)
    check r.success
    check "l4" in r.output
    check "l5" in r.output
    check "l1" notin r.output

suite "wasm text tools - sort":

  test "sort orders lines alphabetically":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_sort_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "f.txt", "cherry\napple\nbanana\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("sort", @[tmpDir / "f.txt"], tmpDir)
    check r.success
    let lines = r.output.splitLines().filterIt(it.len > 0)
    check lines == @["apple", "banana", "cherry"]

  test "sort -r reverses order":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_sort_r"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "f.txt", "1\n2\n3\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("sort", @["-r", tmpDir / "f.txt"], tmpDir)
    check r.success
    let lines = r.output.splitLines().filterIt(it.len > 0)
    check lines == @["3", "2", "1"]
