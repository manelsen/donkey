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

  ## Enumerate with `checkDir = true`: the default silently swallows a failed
  ## `opendir`, which would let the copy report success after skipping a whole
  ## subtree. Collect the entries so the iterator completes inside the `try`.
  var entries: seq[(PathComponent, string)]
  try:
    createDir(dst)
    for kind, entry in walkDir(src, checkDir = true):
      entries.add((kind, entry))
  except CatchableError as e:
    return err("cannot enumerate " & src & ": " & e.msg)

  for (kind, entry) in entries:
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
