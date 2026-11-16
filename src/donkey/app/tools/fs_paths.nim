## fs_paths.nim — small filesystem path helpers shared by tool adapters.
##
## Nim's stdlib has no portable realpath. On POSIX we use libc's realpath for
## existing paths; callers remain responsible for the nearest-existing-ancestor
## logic when the target does not exist yet.

import std/os
import results
when defined(posix):
  import std/posix

proc canonicalPath*(path: string): Result[string, string] =
  ## Resolves symlinks when `path` exists. Returns an error when the path
  ## exists as an unresolvable/dangling symlink; callers must not fall back to
  ## the lexical path in that case.
  when defined(posix):
    var buffer = newString(4096)
    let resolved = posix.realpath(path.cstring, buffer.cstring)
    if resolved != nil:
      return ok($resolved)
    if symlinkExists(path):
      return err("cannot resolve symlink: " & path)
  try:
    ok(absolutePath(path))
  except CatchableError as e:
    err(e.msg)
