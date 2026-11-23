## durable_file — writing state files that survive a crash: a temp file
## fsynced and renamed over the destination, then the directory fsynced;
## directories 0700 and files 0600, since state holds user ids and
## deliveries. Shared by the runtime store (sessions, delivery ledger) and
## the schedule store.

import std/os
when defined(posix):
  import std/posix
import ../../core/pipeops

when defined(posix):
  proc cRename(oldname, newname: cstring): cint {.
    importc: "rename", header: "<stdio.h>".}

when defined(macosx):
  ## On macOS a plain `fsync` only pushes data to the drive cache; `fcntl`
  ## with `F_FULLFSYNC` asks the drive to flush its own cache as well.
  var F_FULLFSYNC {.importc, header: "<fcntl.h>".}: cint

proc hardenStateDir*(dir: string): Result[void, string] {.raises: [].} =
  when defined(posix):
    if dir.len > 0 and posix.chmod(dir.cstring, posix.Mode(0o700)) != 0:
      return err("cannot restrict permissions of " & dir)
  ok()

proc hardenStateFile*(path: string): Result[void, string] {.raises: [].} =
  when defined(posix):
    if posix.chmod(path.cstring, posix.Mode(0o600)) != 0:
      return err("cannot restrict permissions of " & path)
  ok()

proc syncFile*(f: File; path: string): Result[void, string] {.raises: [].} =
  ## Flush userspace buffers, then ask the OS to persist the file contents.
  ## Best effort on filesystems that ignore `fsync` (documented in
  ## SPEC_RUNTIME.md).
  try:
    f.flushFile()
  except CatchableError as e:
    return err("flush failed for " & path & ": " & e.msg)
  when defined(posix):
    let fd = cint(f.getFileHandle())
    when defined(macosx):
      if posix.fcntl(fd, F_FULLFSYNC) == 0:
        return ok()
      ## Some filesystems do not implement F_FULLFSYNC; fall back to fsync.
    if posix.fsync(fd) != 0:
      return err("fsync failed for " & path & ": " & osErrorMsg(osLastError()))
  ok()

proc syncDir*(path: string): Result[void, string] {.raises: [].} =
  ## Persist a directory entry (needed after `rename`) on POSIX.
  when defined(posix):
    try:
      let fd = posix.open(path.cstring, posix.O_RDONLY)
      if fd < 0:
        return err("open failed for directory " & path & ": " &
                   osErrorMsg(osLastError()))
      defer: discard posix.close(fd)
      if posix.fsync(fd) != 0:
        return err("fsync failed for directory " & path & ": " &
                   osErrorMsg(osLastError()))
    except CatchableError as e:
      return err("fsync failed for directory " & path & ": " & e.msg)
  ok()

proc removeQuietly*(path: string) {.raises: [].} =
  try:
    if fileExists(path):
      removeFile(path)
  except CatchableError:
    discard

proc renamePath*(source, dest: string): Result[void, string] {.raises: [].} =
  ## Atomic replace. `std/os.moveFile` is avoided on POSIX because its effect
  ## inference includes `Exception` (from an unreachable stdlib re-raise),
  ## which would leak through `raises: []` port boundaries.
  when defined(posix):
    if cRename(source.cstring, dest.cstring) != 0:
      return err("rename failed for " & source & ": " & osErrorMsg(osLastError()))
    ok()
  else:
    try:
      {.cast(raises: []).}:
        moveFile(source, dest)
      ok()
    except CatchableError as e:
      err("rename failed for " & source & ": " & e.msg)

proc atomicWriteText*(path, content, tmpSuffix: string;
                      requireDirSync = true): Result[void, string] {.raises: [].} =
  ## Writes to a sibling temp file unique to this write, fsyncs it, renames it
  ## over the destination and fsyncs the parent directory. With
  ## `requireDirSync` false a failed directory fsync is not an error: the
  ## rename already made the content visible, and a caller that reads an
  ## error as "not written" would act on a write that happened.
  let tmp = path & ".tmp." & tmpSuffix
  try:
    let dir = parentDir(path)
    if dir.len > 0:
      createDir(dir)
      let dirHardened = hardenStateDir(dir)
      if dirHardened.isErr:
        return err(dirHardened.error)
    var syncError = ""
    var f = open(tmp, fmWrite)
    let fileHardened = hardenStateFile(tmp)
    if fileHardened.isErr:
      f.close()
      removeQuietly(tmp)
      return err(fileHardened.error)
    try:
      f.write(content)
      let synced = syncFile(f, tmp)
      if synced.isErr:
        syncError = synced.error
    finally:
      f.close()
    if syncError.len > 0:
      removeQuietly(tmp)
      return err(syncError)
    let renamed = renamePath(tmp, path)
    if renamed.isErr:
      removeQuietly(tmp)
      return err(renamed.error)
    if dir.len > 0:
      let dirSynced = syncDir(dir)
      if dirSynced.isErr and requireDirSync:
        return err(dirSynced.error)
    ok()
  except CatchableError as e:
    removeQuietly(tmp)
    err("atomic write failed for " & path & ": " & e.msg)
