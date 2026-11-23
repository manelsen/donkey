## The DM allowlist store and the access port built on it.

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/core/types
import donkey/adapters/memory/md_file
import donkey/adapters/memory/dm_allowlist

proc freshList(name: string): DmAllowlist =
  let tmp = getTempDir() / name
  removeDir(tmp)
  dmAllowlistOf(tmp / "paddocks")

proc runTests*() =
  suite "DM allowlist":
    test "it lives in the state directory next to the paddocks":
      check dmAllowlistOf("/srv/donkey/paddocks").path ==
        "/srv/donkey/state/dm_allowlist.txt"

    test "ids with surrounding spaces are rejected":
      let list = freshList("donkey_test_dm_allowlist_spaces")
      check list.allow(UserId("u1 ")).isErr
      check not list.isAllowed(UserId("u1 ")).get

    test "unknown user is denied":
      check not freshList("donkey_test_dm_allowlist_empty").isAllowed(UserId("u1")).get

    test "added user is allowed and removed user is denied":
      let list = freshList("donkey_test_dm_allowlist_roundtrip")
      check list.allow(UserId("u1")).isOk
      check list.allow(UserId("u2")).isOk
      check list.isAllowed(UserId("u1")).get
      check list.isAllowed(UserId("u2")).get
      check list.disallow(UserId("u1")).isOk
      check not list.isAllowed(UserId("u1")).get
      check list.isAllowed(UserId("u2")).get

    test "duplicate adds are idempotent":
      let list = freshList("donkey_test_dm_allowlist_dupe")
      check list.allow(UserId("u1")).isOk
      check list.allow(UserId("u1")).isOk
      var count = 0
      for line in lines(list.path):
        if line.strip == "u1": inc count
      check count == 1

    when defined(posix):
      test "the list stays private after a removal":
        let list = freshList("donkey_test_dm_allowlist_private")
        check list.allow(UserId("u1")).isOk
        check list.allow(UserId("u2")).isOk
        check list.disallow(UserId("u1")).isOk
        check getFilePermissions(list.path) == {fpUserRead, fpUserWrite}

    test "a list path that is not a file allows nobody":
      let tmp = getTempDir() / "donkey_test_dm_allowlist_unreadable"
      removeDir(tmp)
      createDir(tmp / "state" / "dm_allowlist.txt")  ## a directory, not a file
      let list = dmAllowlistOf(tmp / "paddocks")
      check not list.isAllowed(UserId("u1")).get(true)
      let port = MdFileAdapter(paddocksDir: tmp / "paddocks").toAccessPort(list)
      check not port.dmAllowed(UserId("u1"))

  suite "access port":
    test "revocation comes from the profile, DM access from the list":
      let tmp = getTempDir() / "donkey_test_access_port"
      removeDir(tmp)
      let memory = MdFileAdapter(paddocksDir: tmp / "paddocks")
      let list = dmAllowlistOf(memory.paddocksDir)
      let port = memory.toAccessPort(list)
      let uid = UserId("u1")
      check memory.saveUserMd(uid, "# U1\n**Access:** active\n").isOk
      check not port.revoked(uid)
      check not port.dmAllowed(uid)
      check list.allow(uid).isOk
      check port.dmAllowed(uid)
      check memory.updateUserField(uid, "Access", "revoked").isOk
      check port.revoked(uid)

    test "an empty port revokes nobody and allows nobody":
      check not AccessPort().revoked(UserId("u"))
      check not AccessPort().dmAllowed(UserId("u"))

    test "a check that fails is a revoked user and a denied DM":
      let failing = proc(u: UserId): Result[bool, string] {.gcsafe, raises: [].} =
        err("unreadable")
      let port = AccessPort(isRevoked: failing, isDmAllowed: failing)
      check port.revoked(UserId("u"))
      check not port.dmAllowed(UserId("u"))

when isMainModule:
  runTests()
