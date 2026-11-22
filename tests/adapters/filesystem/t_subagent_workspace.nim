## Child paddocks for subagents: private directories created without
## following a symlink, and removed whether they are a directory, a symlink
## or already gone.

import std/[os, unittest]
import donkey/core/pipeops
import donkey/ports/subagent_workspace
import donkey/adapters/filesystem/subagent_workspace

proc scratch(name: string): string =
  result = getTempDir() / ("donkey_subagent_ws_" & name & "_" & $getCurrentProcessId())
  removeDir(result)
  createDir(result)

proc runTests*() =
  suite "subagent workspace":
    test "the port is complete":
      check subagentWorkspacePort().hasSubagentWorkspace

    test "a child paddock is created private under subagents/":
      let root = scratch("create")
      defer: removeDir(root)
      let child = createSubagentPaddock(root, "sub-1").get
      check child == root / "subagents" / "sub-1"
      check dirExists(child)
      when defined(posix):
        check getFilePermissions(child) == {fpUserRead, fpUserWrite, fpUserExec}
        check getFilePermissions(root / "subagents") ==
          {fpUserRead, fpUserWrite, fpUserExec}

    test "an existing paddock is accepted and tightened":
      let root = scratch("existing")
      defer: removeDir(root)
      createDir(root / "subagents" / "sub-1")
      setFilePermissions(root / "subagents" / "sub-1",
                         {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpOthersRead})
      check createSubagentPaddock(root, "sub-1").isOk
      when defined(posix):
        check getFilePermissions(root / "subagents" / "sub-1") ==
          {fpUserRead, fpUserWrite, fpUserExec}

    when defined(posix):
      test "a symlink in place of the paddock is refused":
        ## Following it would let chmod and the child land elsewhere.
        let root = scratch("symlink")
        let elsewhere = scratch("elsewhere")
        defer:
          removeDir(root)
          removeDir(elsewhere)
        createDir(root / "subagents")
        createSymlink(elsewhere, root / "subagents" / "sub-1")
        check createSubagentPaddock(root, "sub-1").isErr

    test "removal handles a directory, a symlink and a missing path":
      let root = scratch("remove")
      let target = scratch("target")
      defer:
        removeDir(root)
        removeDir(target)
      let child = createSubagentPaddock(root, "sub-1").get
      writeFile(child / "notes.md", "x")
      check removeSubagentPaddock(child).isOk
      check not dirExists(child)
      when defined(posix):
        createSymlink(target, root / "link")
        check removeSubagentPaddock(root / "link").isOk
        check dirExists(target)  ## the link goes, never what it points to
      check removeSubagentPaddock(root / "never-existed").isOk
      check removeSubagentPaddock("").isOk

when isMainModule:
  runTests()
