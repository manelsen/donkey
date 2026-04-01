## Tests for WASM-based file operations (cp, mv, rm, mkdir).

import std/[unittest, os, strutils]
import ../../src/donkey/infra/sandbox/wasm_tools

const busyboxPath = getHomeDir() / ".donkey" / "busybox"
let hasBusybox = busyboxPath.fileExists

suite "wasm file tools - mkdir":

  test "mkdir creates directory":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_mkdir_test"
    defer: removeDir(tmpDir)
    createDir(tmpDir)

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("mkdir", @[tmpDir / "newdir"], tmpDir)
    check r.success or dirExists(tmpDir / "newdir")
    check dirExists(tmpDir / "newdir")

suite "wasm file tools - cp":

  test "cp copies file":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_cp_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "src.txt", "hello world")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("cp", @[tmpDir / "src.txt", tmpDir / "dst.txt"], tmpDir)
    check r.success
    check fileExists(tmpDir / "dst.txt")
    check readFile(tmpDir / "dst.txt") == "hello world"

suite "wasm file tools - mv":

  test "mv renames file":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_mv_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "old.txt", "content")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("mv", @[tmpDir / "old.txt", tmpDir / "new.txt"], tmpDir)
    check r.success
    check not fileExists(tmpDir / "old.txt")
    check fileExists(tmpDir / "new.txt")
    check readFile(tmpDir / "new.txt") == "content"

suite "wasm file tools - rm":

  test "rm removes file":
    if not hasBusybox: skip()
    let tmpDir = getTempDir() / "donkey_rm_test"
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "gone.txt", "bye")

    let adapter = newWasmToolAdapter(busyboxPath)
    let r = adapter.runApplet("rm", @[tmpDir / "gone.txt"], tmpDir)
    check r.success
    check not fileExists(tmpDir / "gone.txt")
