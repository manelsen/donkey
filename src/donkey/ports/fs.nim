## FsRuntimePort — filesystem capability consumed by the application layer.
##
## The application only consumes `Result` values; the implementation lives in
## `adapters/filesystem` and owns all exception translation (`try/except`).

import ../core/pipeops

type
  FsRuntimePort* = object
    canonicalPath*:            proc(path: string): Result[string, string] {.gcsafe, raises: [].}
    canonicalNearestExisting*: proc(path: string): Result[string, string] {.gcsafe, raises: [].}
    secureDir*:                proc(path: string): Result[void, string] {.gcsafe, raises: [].}
    secureFile*:               proc(path: string): Result[void, string] {.gcsafe, raises: [].}
    readFile*:                 proc(path: string): Result[string, string] {.gcsafe, raises: [].}
    fileSize*:                 proc(path: string): Result[int64, string] {.gcsafe, raises: [].}

func unavailableFs*(): FsRuntimePort =
  ## Fail-closed default for call sites that do not wire filesystem tools.
  ## A zeroed proc field would crash; every operation reports a stable error.
  FsRuntimePort(
    canonicalPath: proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
      err("filesystem runtime unavailable"),
    canonicalNearestExisting: proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
      err("filesystem runtime unavailable"),
    secureDir: proc(path: string): Result[void, string] {.gcsafe, raises: [].} =
      err("filesystem runtime unavailable"),
    secureFile: proc(path: string): Result[void, string] {.gcsafe, raises: [].} =
      err("filesystem runtime unavailable"),
    readFile: proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
      err("filesystem runtime unavailable"),
    fileSize: proc(path: string): Result[int64, string] {.gcsafe, raises: [].} =
      err("filesystem runtime unavailable"),
  )
