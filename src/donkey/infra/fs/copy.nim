## copy.nim — recursive directory copy with one error contract.
##
## Every fallible filesystem step, including symlink refusals, reports through
## `Result[void, string]`. Application code converts that into its own tool
## result type and never catches filesystem exceptions.

import std/os
import ../../core/pipeops

proc copyTreeResult*(src, dst: string): Result[void, string] =
  ## Copies `src` into `dst`. A symlink at any destination path is refused:
  ## `copyFile` would follow it and write outside the paddock. This check
  ## narrows, but does not close, the race between validation and the write.
  if symlinkExists(dst):
    return err("destination is a symlink: " & dst)
  try:
    createDir(dst)
  except CatchableError as e:
    return err("cannot create directory " & dst & ": " & e.msg)

  for kind, entry in walkDir(src):
    let target = dst / entry.extractFilename
    case kind
    of pcDir:
      ? copyTreeResult(entry, target)
    of pcFile:
      if symlinkExists(target):
        return err("destination is a symlink: " & target)
      try:
        let parent = parentDir(target)
        if parent.len > 0 and not dirExists(parent):
          createDir(parent)
        copyFile(entry, target)
      except CatchableError as e:
        return err("cannot copy " & entry & ": " & e.msg)
    of pcLinkToFile, pcLinkToDir:
      discard
  ok()
