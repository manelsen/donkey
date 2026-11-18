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

const
  MediaReadChunkDefault* = 64 * 1024
    ## Chunk size for `readConfinedMediaFile`. It bounds the peak allocation of
    ## a read, never the accepted file size (that is the caller's cap).

when defined(posix):
  var PosixONoFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
    ## Not exported by Nim's std/posix. Importing it keeps the value correct on
    ## every POSIX target instead of hard-coding per-platform numbers.

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

proc readConfinedMediaFile*(paddockRoot, resolvedPath: string; limit: int64;
                            chunkSize = MediaReadChunkDefault):
                            Result[string, string] {.gcsafe, raises: [].} =
  ## Reads outbound media through the descriptor that was validated, never by
  ## re-opening the name and trusting it.
  ##
  ## `resolvedPath` is expected to be the value returned by
  ## `resolveConfinedMediaPath` for `paddockRoot`, but it is still treated as
  ## untrusted: a symlink (or a different file) swapped in after that call must
  ## not be read.
  ##
  ## POSIX contract:
  ##   1. the canonical root is resolved again and `resolvedPath` must still be
  ##      lexically inside it;
  ##   2. `open(O_RDONLY|O_NOFOLLOW|O_NONBLOCK)` — a final symlink is refused
  ##      and a FIFO substituted for the file cannot block the caller;
  ##   3. `fstat` must report a regular file whose device/inode matches a fresh
  ##      `stat` of `resolvedPath`, and (on Linux) the descriptor's own path in
  ##      `/proc/self/fd` must remain inside the root;
  ##   4. only then bytes are read from the descriptor, at most `limit` (+ one
  ##      probe byte at the cap to detect growth).
  ##
  ## Every failure is a path-free error string, so the caller can replace it
  ## with the neutral notice. The file is never modified, truncated or removed.
  ## On non-POSIX the name-based read is kept (with its TOCTOU window) because
  ## there is no descriptor to validate.
  if resolvedPath.len == 0 or paddockRoot.len == 0 or limit <= 0:
    return err("media file unavailable")
  when defined(posix):
    var fd: cint = -1
    try:
      let rootResult = canonicalPath(normalizePath(paddockRoot))
      if rootResult.isErr:
        return err("media root is unavailable")
      let root = rootResult.get()
      if resolvedPath != root and not resolvedPath.startsWith(root & $DirSep):
        return err("media path is outside the paddock")
      fd = posix.open(resolvedPath.cstring,
                      O_RDONLY or PosixONoFollow or O_NONBLOCK)
      if fd < 0:
        return err("media file unreadable")
      var opened: Stat
      if posix.fstat(fd, opened) != 0 or not S_ISREG(opened.st_mode):
        return err("media target is not a regular file")
      var named: Stat
      if posix.stat(resolvedPath.cstring, named) != 0 or
         named.st_dev != opened.st_dev or named.st_ino != opened.st_ino:
        ## The name no longer designates the descriptor we validated.
        return err("media file changed after validation")
      when defined(linux):
        var linkBuf = newString(4096)
        let linkLen = posix.readlink(("/proc/self/fd/" & $fd).cstring,
                                     linkBuf.cstring, linkBuf.len)
        if linkLen > 0:
          linkBuf.setLen(linkLen)
          if linkBuf != root and not linkBuf.startsWith(root & $DirSep):
            return err("media path is outside the paddock")
      if opened.st_size > limit:
        return err("media file exceeds the cap")
      var data = ""
      var chunk = newString(max(chunkSize, 1))
      while data.len.int64 < limit:
        let want = int(min(int64(chunk.len), limit - data.len.int64))
        let got = posix.read(fd, addr chunk[0], want)
        if got < 0:
          return err("media file unreadable")
        if got == 0:
          break
        data.add(chunk[0 ..< got])
      if data.len.int64 >= limit:
        var extra: char
        if posix.read(fd, addr extra, 1) > 0:
          return err("media file exceeds the cap")
      ok(data)
    except CatchableError:
      err("media file unreadable")
    finally:
      if fd >= 0:
        discard posix.close(fd)
  else:
    ## Windows and other non-POSIX targets: no descriptor-level confinement, so
    ## this keeps the previous name-based behaviour and its race window.
    try:
      if not fileExists(resolvedPath) or dirExists(resolvedPath):
        return err("media file unavailable")
      if getFileSize(resolvedPath) > limit:
        return err("media file exceeds the cap")
      var file: File
      if not open(file, resolvedPath, fmRead):
        return err("media file unreadable")
      defer: close(file)
      var data = ""
      var chunk = newString(max(chunkSize, 1))
      while data.len.int64 < limit:
        let want = int(min(int64(chunk.len), limit - data.len.int64))
        let got = readBuffer(file, addr chunk[0], want)
        if got <= 0:
          break
        data.add(chunk[0 ..< got])
      if data.len.int64 >= limit:
        var extra: char
        if readBuffer(file, addr extra, 1) > 0:
          return err("media file exceeds the cap")
      ok(data)
    except CatchableError:
      err("media file unreadable")

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
