## FsRuntimePort — filesystem capability consumed by the application layer.
##
## The application only consumes `Result` values; the implementation lives in
## `adapters/filesystem` and owns all exception translation (`try/except`).
## No operation raises.

import ../core/pipeops

type
  FsEntryKind* = enum
    fekMissing = "missing"
    fekFile    = "file"
    fekDir     = "dir"
    fekLink    = "link"   ## only in a listing: a symlink is not followed there

  FsEntry* = object
    path*:  string
    kind*:  FsEntryKind
    size*:  int64   ## 0 for anything but a regular file, or when unreadable
    mtime*: int64   ## Unix seconds; 0 when unreadable

  FsRuntimePort* = object
    canonicalPath*:            proc(path: string): Result[string, string] {.gcsafe, raises: [].}
    canonicalNearestExisting*: proc(path: string): Result[string, string] {.gcsafe, raises: [].}
    secureDir*:                proc(path: string): Result[void, string] {.gcsafe, raises: [].}
    secureFile*:               proc(path: string): Result[void, string] {.gcsafe, raises: [].}
    readFile*:                 proc(path: string): Result[string, string] {.gcsafe, raises: [].}
    fileSize*:                 proc(path: string): Result[int64, string] {.gcsafe, raises: [].}
    readCapped*:               proc(path: string; maxBytes: int): Result[string, string] {.gcsafe, raises: [].}
      ## The file, or an error when it holds more than `maxBytes`: never more
      ## than that is read, even if it grew since its size was checked.
    entryKind*:                proc(path: string): FsEntryKind {.gcsafe, raises: [].}
      ## File or directory, following symlinks; missing when it cannot be told.
    isSymlink*:                proc(path: string): bool {.gcsafe, raises: [].}
    listDir*:                  proc(path: string): Result[seq[FsEntry], string] {.gcsafe, raises: [].}
      ## The entries directly in `path`, in no particular order.
    writeFile*:                proc(path, content: string): Result[void, string] {.gcsafe, raises: [].}
    appendFile*:               proc(path, content: string): Result[void, string] {.gcsafe, raises: [].}
      ## Creates the file when it is missing.
    createDir*:                proc(path: string): Result[void, string] {.gcsafe, raises: [].}
      ## With its parents; an existing directory is fine.
    copyFile*:                 proc(src, dst: string): Result[void, string] {.gcsafe, raises: [].}
    copyTree*:                 proc(src, dst: string): Result[void, string] {.gcsafe, raises: [].}
      ## Refuses to write through a symlink at the destination.
    move*:                     proc(src, dst: string): Result[void, string] {.gcsafe, raises: [].}
      ## A file or a directory.
    remove*:                   proc(path: string; recursive: bool): Result[void, string] {.gcsafe, raises: [].}
      ## A file, or with `recursive` a directory and everything in it.

func unavailableFs*(): FsRuntimePort =
  ## Fail-closed default for call sites that do not wire filesystem tools.
  ## A zeroed proc field would crash; every operation reports a stable error.
  const Unavailable = "filesystem runtime unavailable"
  FsRuntimePort(
    canonicalPath: proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    canonicalNearestExisting: proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    secureDir: proc(path: string): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    secureFile: proc(path: string): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    readFile: proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    fileSize: proc(path: string): Result[int64, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    readCapped: proc(path: string; maxBytes: int): Result[string, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    entryKind: proc(path: string): FsEntryKind {.gcsafe, raises: [].} =
      fekMissing,
    isSymlink: proc(path: string): bool {.gcsafe, raises: [].} =
      false,
    listDir: proc(path: string): Result[seq[FsEntry], string] {.gcsafe, raises: [].} =
      err(Unavailable),
    writeFile: proc(path, content: string): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    appendFile: proc(path, content: string): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    createDir: proc(path: string): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    copyFile: proc(src, dst: string): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    copyTree: proc(src, dst: string): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    move: proc(src, dst: string): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
    remove: proc(path: string; recursive: bool): Result[void, string] {.gcsafe, raises: [].} =
      err(Unavailable),
  )

func orUnavailable*(fs: FsRuntimePort): FsRuntimePort =
  ## `fs` with every operation it lacks answered by `unavailableFs`: a port
  ## built field by field, or left zeroed, then fails with an error instead
  ## of calling nil.
  result = fs
  let fallback = unavailableFs()
  if result.canonicalPath == nil: result.canonicalPath = fallback.canonicalPath
  if result.canonicalNearestExisting == nil:
    result.canonicalNearestExisting = fallback.canonicalNearestExisting
  if result.secureDir == nil: result.secureDir = fallback.secureDir
  if result.secureFile == nil: result.secureFile = fallback.secureFile
  if result.readFile == nil: result.readFile = fallback.readFile
  if result.fileSize == nil: result.fileSize = fallback.fileSize
  if result.readCapped == nil: result.readCapped = fallback.readCapped
  if result.entryKind == nil: result.entryKind = fallback.entryKind
  if result.isSymlink == nil: result.isSymlink = fallback.isSymlink
  if result.listDir == nil: result.listDir = fallback.listDir
  if result.writeFile == nil: result.writeFile = fallback.writeFile
  if result.appendFile == nil: result.appendFile = fallback.appendFile
  if result.createDir == nil: result.createDir = fallback.createDir
  if result.copyFile == nil: result.copyFile = fallback.copyFile
  if result.copyTree == nil: result.copyTree = fallback.copyTree
  if result.move == nil: result.move = fallback.move
  if result.remove == nil: result.remove = fallback.remove
