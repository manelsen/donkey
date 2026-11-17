## fs_adapter.nim — binds the filesystem port to the concrete implementation.

import std/os
import ../../core/pipeops
import ../../ports/fs
import ./paths as fsPaths

proc readFileResult(path: string): Result[string, string] {.gcsafe, raises: [].} =
  try:
    ok(readFile(path))
  except CatchableError as e:
    err("cannot read file: " & e.msg)

proc fileSizeResult(path: string): Result[int64, string] {.gcsafe, raises: [].} =
  try:
    ok(getFileSize(path))
  except CatchableError as e:
    err("cannot inspect file: " & e.msg)

proc newFsAdapter*(): FsRuntimePort =
  FsRuntimePort(
    canonicalPath: proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
      fsPaths.canonicalPath(path),
    canonicalNearestExisting: proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
      fsPaths.canonicalNearestExisting(path),
    secureDir: proc(path: string): Result[void, string] {.gcsafe, raises: [].} =
      fsPaths.secureDir(path),
    secureFile: proc(path: string): Result[void, string] {.gcsafe, raises: [].} =
      fsPaths.secureFile(path),
    readFile: readFileResult,
    fileSize: fileSizeResult,
  )
