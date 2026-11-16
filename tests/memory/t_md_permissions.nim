import std/[os, unittest]
import donkey/adapters/memory/md_file
import donkey/core/types
import donkey/domain/message

const TestRoot = "/tmp/donkey_md_permissions_tests"

when defined(posix):
  suite "paddock permissions":

    setup:
      removeDir(TestRoot)
      createDir(TestRoot)

    teardown:
      removeDir(TestRoot)

    test "loadContext tightens an existing paddock":
      let uid = UserId("perm-user")
      let paddock = TestRoot / "perm-user"
      createDir(paddock)
      createDir(paddock / "sessions")
      createDir(paddock / "attachments")
      writeFile(paddock / "USER.md", "profile")
      writeFile(paddock / "MEMORY.md", "memory")
      writeFile(paddock / "PREFERENCES.md", "provider = \"auto\"\n")
      writeFile(paddock / "sessions" / "s1.jsonl", "{}")
      writeFile(paddock / "attachments" / "a.md", "x")

      let looseDir = {fpUserRead, fpUserWrite, fpUserExec,
                      fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec}
      let looseFile = {fpUserRead, fpUserWrite, fpGroupRead, fpOthersRead}
      for dir in [paddock, paddock / "sessions", paddock / "attachments"]:
        setFilePermissions(dir, looseDir)
      for path in [paddock / "USER.md", paddock / "MEMORY.md",
                   paddock / "PREFERENCES.md", paddock / "sessions" / "s1.jsonl",
                   paddock / "attachments" / "a.md"]:
        setFilePermissions(path, looseFile)

      let adapter = MdFileAdapter(paddocksDir: TestRoot)
      discard adapter.loadContext(uid)

      let privateDir = {fpUserRead, fpUserWrite, fpUserExec}
      let privateFile = {fpUserRead, fpUserWrite}
      check getFilePermissions(paddock) == privateDir
      check getFilePermissions(paddock / "sessions") == privateDir
      check getFilePermissions(paddock / "attachments") == privateDir
      check getFilePermissions(paddock / "USER.md") == privateFile
      check getFilePermissions(paddock / "MEMORY.md") == privateFile
      check getFilePermissions(paddock / "PREFERENCES.md") == privateFile
      check getFilePermissions(paddock / "sessions" / "s1.jsonl") == privateFile
      check getFilePermissions(paddock / "attachments" / "a.md") == privateFile

    test "writes and sessions are private after save":
      let uid = UserId("save-user")
      let adapter = MdFileAdapter(paddocksDir: TestRoot)
      adapter.saveUserMd(uid, "profile")
      adapter.savePreferences(uid, "provider = \"auto\"\n")
      adapter.appendMemory(uid, "note")
      adapter.saveSession(uid, "s2", @[
        ChatMessage(role: "user", text: "oi"),
        ChatMessage(role: "assistant", text: "olá"),
      ])

      let privateFile = {fpUserRead, fpUserWrite}
      check getFilePermissions(adapter.userMdPath(uid)) == privateFile
      check getFilePermissions(adapter.preferencesMdPath(uid)) == privateFile
      check getFilePermissions(adapter.memoryMdPath(uid)) == privateFile
      check getFilePermissions(adapter.paddockDir(uid) / "sessions" / "s2.jsonl") == privateFile
else:
  suite "paddock permissions":
    test "skipped on non-posix":
      check true
