import std/[os, unittest]
import donkey/adapters/memory/md_file
import donkey/core/types

const TestRoot = "/tmp/donkey_md_append_tests"

proc runTests*() =
  suite "MdFileAdapter appendMemory":

    setup:
      removeDir(TestRoot)
      createDir(TestRoot)

    teardown:
      removeDir(TestRoot)

    test "appends without rewriting the existing file":
      let adapter = MdFileAdapter(paddocksDir: TestRoot)
      let uid = UserId("append-user")
      adapter.appendMemory(uid, "first")
      adapter.appendMemory(uid, "second")
      let content = readFile(adapter.memoryMdPath(uid))
      check content == "first\nsecond"

    test "handles an existing file with a trailing newline":
      let adapter = MdFileAdapter(paddocksDir: TestRoot)
      let uid = UserId("append-user-2")
      adapter.ensurePaddock(uid)
      writeFile(adapter.memoryMdPath(uid), "first\n")
      adapter.appendMemory(uid, "second")
      check readFile(adapter.memoryMdPath(uid)) == "first\n\nsecond"

when isMainModule:
  runTests()
