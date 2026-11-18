## paths.nim — filesystem path helpers for adapters.
##
## Nim's stdlib has no portable realpath. On POSIX we use libc's realpath for
## existing paths; callers remain responsible for the nearest-existing-ancestor
## logic when the target does not exist yet.
##
## Exception translation belongs here, at the I/O boundary: callers receive
## `Result` and never see filesystem exceptions.

import std/[os, strutils]
import ../../core/pipeops
import ../../domain/tools/path_guard
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

proc canonicalNearestExisting*(path: string): Result[string, string] {.gcsafe, raises: [].} =
  ## Resolves symlinks in the nearest existing ancestor and reattaches the
  ## non-existing suffix. A dangling or unresolvable symlink is an error: the
  ## lexical fallback would let a write follow it outside the paddock.
  try:
    var current = absolutePath(path)
    var suffix: seq[string] = @[]
    while current.len > 0:
      if symlinkExists(current):
        let resolved = canonicalPath(current)
        if resolved.isErr:
          return err("unresolvable symlink: " & current)
        var base = resolved.get()
        for i in countdown(suffix.high, 0):
          base = base / suffix[i]
        return ok(base)
      if fileExists(current) or dirExists(current):
        let resolved = canonicalPath(current)
        if resolved.isErr:
          return err("cannot resolve path: " & current)
        var base = resolved.get()
        for i in countdown(suffix.high, 0):
          base = base / suffix[i]
        return ok(base)
      let parent = parentDir(current)
      if parent.len == 0 or parent == current:
        break
      suffix.add(extractFilename(current))
      current = parent
  except CatchableError as e:
    return err(e.msg)
  try:
    ok(absolutePath(path))
  except CatchableError as e:
    err(e.msg)

proc resolveConfinedMediaPath*(paddockRoot, raw: string): Result[string, string]
                               {.gcsafe, raises: [].} =
  ## Resolves outbound media inside the paddock. The lexical policy decides
  ## first; the canonical root and target are then re-checked so a symlink
  ## cannot move the read outside. Every failure is closed: the caller sends
  ## the neutral notice and never touches the file.
  try:
    let decision = classifyOutboundMediaPath(paddockRoot, raw)
    if decision.kind != mpkLocal:
      return err(decision.reason)
    let rootResult = canonicalPath(normalizePath(paddockRoot))
    if rootResult.isErr:
      return err("cannot resolve media root")
    let root = rootResult.get()
    if not dirExists(root):
      return err("media root is unavailable")
    let targetResult = canonicalNearestExisting(decision.lexicalPath)
    if targetResult.isErr:
      return err("cannot resolve media path")
    let target = targetResult.get()
    if target != root and not target.startsWith(root & $DirSep):
      return err("media path is outside the paddock")
    ok(target)
  except CatchableError:
    err("cannot resolve media path")

proc secureDir*(path: string): Result[void, string] {.discardable.} =
  try:
    createDir(path)
    when defined(posix):
      setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})
    ok()
  except CatchableError as e:
    err(e.msg)

proc secureFile*(path: string): Result[void, string] {.discardable.} =
  try:
    when defined(posix):
      if fileExists(path):
        setFilePermissions(path, {fpUserRead, fpUserWrite})
    ok()
  except CatchableError as e:
    err(e.msg)
