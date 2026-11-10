## DM allowlist persistence tests.

import std/[os, strutils, unittest]
import donkey/adapters/memory/md_file
import donkey/core/types

suite "MdFileAdapter — DM allowlist":

  test "unknown user is denied":
    let tmp = getTempDir() / "donkey_test_dm_allowlist_empty"
    removeDir(tmp)
    defer: removeDir(tmp)
    let memory = MdFileAdapter(paddocksDir: tmp / "paddocks")
    check not memory.isDmAllowed(UserId("u1"))

  test "added user is allowed and removed user is denied":
    let tmp = getTempDir() / "donkey_test_dm_allowlist_roundtrip"
    removeDir(tmp)
    defer: removeDir(tmp)
    let memory = MdFileAdapter(paddocksDir: tmp / "paddocks")
    memory.addDmAllowed(UserId("u1"))
    memory.addDmAllowed(UserId("u2"))
    check memory.isDmAllowed(UserId("u1"))
    check memory.isDmAllowed(UserId("u2"))
    memory.removeDmAllowed(UserId("u1"))
    check not memory.isDmAllowed(UserId("u1"))
    check memory.isDmAllowed(UserId("u2"))

  test "duplicate adds are idempotent":
    let tmp = getTempDir() / "donkey_test_dm_allowlist_dupe"
    removeDir(tmp)
    defer: removeDir(tmp)
    let memory = MdFileAdapter(paddocksDir: tmp / "paddocks")
    memory.addDmAllowed(UserId("u1"))
    memory.addDmAllowed(UserId("u1"))
    var count = 0
    for line in lines(memory.dmAllowlistPath()):
      if line.strip == "u1": inc count
    check count == 1
