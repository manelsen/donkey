## The file system adapter on a real directory: the operations whose
## contract is more than a std call.

import std/[os, strutils, unittest]
import donkey/core/pipeops
import donkey/adapters/filesystem/fs_adapter

proc runTests*() =
  let fs = newFsAdapter()
  let root = getTempDir() / ("donkey_fs_adapter_" & $getCurrentProcessId())
  removeDir(root)
  createDir(root)

  suite "fs adapter":
    when defined(posix):
      test "a private file is 0600 from its creation and replaces the old one":
        let path = root / "donkey.env"
        writeFile(path, "OLD=1\n")
        check fs.writePrivate(path, "OPENAI_API_KEY=sk-fake\n").isOk
        check readFile(path) == "OPENAI_API_KEY=sk-fake\n"
        let perms = getFilePermissions(path)
        check perms == {fpUserRead, fpUserWrite}
        var leftovers = 0
        for kind, entry in walkDir(root):
          if ".tmp." in entry: inc leftovers
        check leftovers == 0

    test "a capped read refuses a file over the cap and reads one within it":
      let path = root / "capped.txt"
      writeFile(path, repeat('x', 200_000))
      check fs.readCapped(path, 199_999).isErr
      check fs.readCapped(path, 200_000).get.len == 200_000

    when defined(posix):
      test "a directory that cannot be read is an error, not an empty list":
        let dir = root / "closed"
        createDir(dir)
        writeFile(dir / "a", "x")
        setFilePermissions(dir, {})
        defer: setFilePermissions(dir, {fpUserRead, fpUserWrite, fpUserExec})
        if fs.readFile(dir / "a").isErr:  ## not root: the mode applies
          check fs.listDir(dir).isErr

    test "append creates the file and then appends":
      let path = root / "log.txt"
      check fs.appendFile(path, "a").isOk
      check fs.appendFile(path, "b").isOk
      check readFile(path) == "ab"

  removeDir(root)

when isMainModule:
  runTests()
