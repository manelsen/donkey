## Tests for WASM-based sed via WasmToolAdapter.

import std/[unittest, os, strutils, sequtils]
import ../../src/donkey/infra/sandbox/wasm_tools

const busyboxPath = getHomeDir() / ".donkey" / "busybox"
let hasBusybox = busyboxPath.fileExists

suite "wasm sed - WasmToolAdapter":

  test "sed substitutes text in file":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_sed_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "input.txt"
    writeFile(f, "hello world\nfoo bar\nhello again\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("sed", @["s/hello/HOLA/g", f], tmpDir)
    check r.success
    check "HOLA world" in r.output
    check "HOLA again" in r.output
    check "foo bar" in r.output

  test "sed substitutes only first occurrence per line":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_sed_first"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "multi.txt"
    writeFile(f, "aaa bbb aaa\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("sed", @["s/aaa/XXX/", f], tmpDir)
    check r.success
    check "XXX bbb aaa" in r.output

  test "sed substitutes all occurrences with g flag":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_sed_global"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "multi.txt"
    writeFile(f, "aaa bbb aaa\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("sed", @["s/aaa/XXX/g", f], tmpDir)
    check r.success
    check "XXX bbb XXX" in r.output

  test "sed delete lines with d command":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_sed_del"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "lines.txt"
    writeFile(f, "keep\nremove\nkeep\nremove\nkeep\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("sed", @["/remove/d", f], tmpDir)
    check r.success
    check "keep" in r.output
    check "remove" notin r.output

  test "sed -n with p prints only matching lines":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_sed_print"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "sel.txt"
    writeFile(f, "alpha\nbeta\ngamma\nbeta\ndelta\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("sed", @["-n", "/beta/p", f], tmpDir)
    check r.success
    let lines = r.output.splitLines().filterIt(it.len > 0)
    check lines.len == 2

  test "sed with line number address":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_sed_addr"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let f = tmpDir / "addr.txt"
    writeFile(f, "line1\nline2\nline3\nline4\n")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("sed", @["2d", f], tmpDir)
    check r.success
    check "line1" in r.output
    check "line2" notin r.output
    check "line3" in r.output
