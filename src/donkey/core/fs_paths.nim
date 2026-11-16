## fs_paths.nim — small filesystem path helpers shared by tool adapters.
##
## Nim's stdlib has no portable realpath. On POSIX we use libc's realpath for
## existing paths; callers remain responsible for the nearest-existing-ancestor
## logic when the target does not exist yet.

import std/os
when defined(posix):
  import std/posix

proc canonicalPath*(path: string): string =
  ## Resolves symlinks when `path` exists; otherwise returns an absolute path.
  when defined(posix):
    var buffer = newString(4096)
    let resolved = posix.realpath(path.cstring, buffer.cstring)
    if resolved != nil:
      return $resolved
  try:
    absolutePath(path)
  except CatchableError:
    path
