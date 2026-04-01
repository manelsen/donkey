## Tests for WASM-based find via WasmToolAdapter.

import std/[unittest, os, strutils]
import ../../src/donkey/infra/sandbox/wasm_tools

const busyboxPath = getHomeDir() / ".donkey" / "busybox"
let hasBusybox = busyboxPath.fileExists

suite "wasm find - WasmToolAdapter":

  test "find lists files by name pattern":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_find_test"
    createDir(tmpDir / "sub")
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "a.txt", "a")
    writeFile(tmpDir / "b.txt", "b")
    writeFile(tmpDir / "c.nim", "c")
    writeFile(tmpDir / "sub" / "d.txt", "d")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("find", @[tmpDir, "-name", "*.txt"], tmpDir)
    check r.success
    check "a.txt" in r.output
    check "b.txt" in r.output
    check "c.nim" notin r.output

  test "find -type f for files only":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_find_type"
    createDir(tmpDir / "mydir")
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "file.txt", "x")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("find", @[tmpDir, "-type", "f"], tmpDir)
    check r.success
    check "file.txt" in r.output
    check "mydir" notin r.output

  test "find -type d for directories only":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_find_dir"
    createDir(tmpDir / "subdir")
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "file.txt", "x")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("find", @[tmpDir, "-type", "d"], tmpDir)
    check r.success
    check "subdir" in r.output
    check "file.txt" notin r.output

  test "find with absolute path":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_find_abs"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "test.txt", "x")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("find", @[tmpDir, "-name", "*.txt"], tmpDir)
    check r.success
    check "test.txt" in r.output
