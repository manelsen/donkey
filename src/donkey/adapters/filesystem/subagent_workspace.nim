## Child paddocks for subagents, behind SubagentWorkspacePort: private
## directories under {paddock}/subagents/, created without following a
## symlink, and removed (directory or symlink, never its target).

import std/os
when defined(posix):
  import std/posix
import ../../core/pipeops
import ../../ports/subagent_workspace

when defined(posix):
  const
    PosixODirectory = cint(0o200000)
    PosixONoFollow = cint(0o400000)

proc ensurePrivateDir(path: string): Result[void, string]
                                      {.gcsafe, raises: [].} =
  ## Creates or validates a real directory with 0700 permissions. The final
  ## component is opened with O_NOFOLLOW so a symlink cannot redirect chmod or
  ## the child paddock creation.
  if path.len == 0:
    return err("empty subagent paddock path")
  when defined(posix):
    if posix.mkdir(path.cstring, Mode(0o700)) != 0 and
       osLastError() != OSErrorCode(posix.EEXIST):
      return err("mkdir subagent paddock: " & osErrorMsg(osLastError()))
    let fd = posix.open(path.cstring,
                        O_RDONLY or PosixODirectory or PosixONoFollow)
    if fd < 0:
      return err("open subagent paddock: " & osErrorMsg(osLastError()))
    defer: discard posix.close(fd)
    if posix.fchmod(fd, Mode(0o700)) != 0:
      return err("chmod subagent paddock: " & osErrorMsg(osLastError()))
    ok()
  else:
    try:
      createDir(path)
      setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})
      ok()
    except CatchableError as e:
      err("create subagent paddock: " & e.msg)

proc createSubagentPaddock*(root, subagentId: string):
                           Result[string, string] {.gcsafe, raises: [].} =
  let subagentsRoot = root / "subagents"
  ?ensurePrivateDir(subagentsRoot)
  let childDir = subagentsRoot / subagentId
  ?ensurePrivateDir(childDir)
  ok(childDir)

proc removeSubagentPaddock*(path: string): Result[void, string]
                                           {.gcsafe, raises: [].} =
  if path.len == 0:
    return ok()
  try:
    if symlinkExists(path):
      removeFile(path)
    elif dirExists(path):
      removeDir(path)
    ok()
  except CatchableError as e:
    err("remove subagent paddock: " & e.msg)

proc subagentWorkspacePort*(): SubagentWorkspacePort =
  SubagentWorkspacePort(
    create: createSubagentPaddock,
    remove: removeSubagentPaddock,
  )
