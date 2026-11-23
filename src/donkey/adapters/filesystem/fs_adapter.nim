## fs_adapter.nim — binds the filesystem port to the concrete implementation.

import std/[os, times]
import ../../core/pipeops
import ../../ports/fs
import ../../infra/fs/copy as fsCopy
import ./paths as fsPaths

export fs

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

proc readCappedResult(path: string; maxBytes: int): Result[string, string]
                     {.gcsafe, raises: [].} =
  try:
    var f: File
    if not open(f, path, fmRead):
      return err("cannot read file: " & path)
    defer: close(f)
    ## In chunks, so the buffer grows with the file, not with the cap.
    var data = ""
    var chunk = newString(64 * 1024)
    while data.len <= maxBytes:
      let want = min(chunk.len, maxBytes + 1 - data.len)
      let got = readBuffer(f, addr chunk[0], want)
      if got <= 0: break
      data.add chunk[0 ..< got]
    if data.len > maxBytes:
      return err("file exceeds " & $maxBytes & " bytes")
    ok(data)
  except CatchableError as e:
    err("cannot read file: " & e.msg)

proc entryKindOf(path: string): FsEntryKind {.gcsafe, raises: [].} =
  try:
    if dirExists(path): fekDir
    elif fileExists(path): fekFile
    else: fekMissing
  except CatchableError:
    fekMissing

proc isSymlinkAt(path: string): bool {.gcsafe, raises: [].} =
  try: symlinkExists(path)
  except CatchableError: false

proc listDirResult(path: string): Result[seq[FsEntry], string] {.gcsafe, raises: [].} =
  var entries: seq[FsEntry]
  try:
    for kind, entry in walkDir(path, checkDir = true):  ## an unreadable directory is an error, not empty
      var item = FsEntry(path: entry)
      item.kind = case kind
        of pcDir: fekDir
        of pcFile: fekFile
        of pcLinkToFile, pcLinkToDir: fekLink
      try:
        if fileExists(entry): item.size = getFileSize(entry)
        item.mtime = getLastModificationTime(entry).toUnix()
      except CatchableError:
        discard  ## size and mtime stay 0: the entry is still listed
      entries.add item
    ok(entries)
  except CatchableError as e:
    err("cannot list directory: " & e.msg)

proc writeFileResult(path, content: string): Result[void, string] {.gcsafe, raises: [].} =
  try:
    writeFile(path, content)
    ok()
  except CatchableError as e:
    err("cannot write file: " & e.msg)

proc appendFileResult(path, content: string): Result[void, string] {.gcsafe, raises: [].} =
  try:
    var f = open(path, fmAppend)
    defer: f.close()
    f.write(content)
    ok()
  except CatchableError as e:
    err("cannot append to file: " & e.msg)

proc createDirResult(path: string): Result[void, string] {.gcsafe, raises: [].} =
  try:
    createDir(path)
    ok()
  except CatchableError as e:
    err("cannot create directory: " & e.msg)

proc copyFileResult(src, dst: string): Result[void, string] {.gcsafe, raises: [].} =
  try:
    copyFile(src, dst)
    ok()
  except CatchableError as e:
    err("cannot copy file: " & e.msg)

proc copyTreeResult(src, dst: string): Result[void, string] {.gcsafe, raises: [].} =
  try:
    fsCopy.copyTreeResult(src, dst)
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("cannot copy directory: " & e.msg)

proc moveResult(src, dst: string): Result[void, string] {.gcsafe, raises: [].} =
  try:
    if dirExists(src): moveDir(src, dst)
    else: moveFile(src, dst)
    ok()
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("cannot move: " & e.msg)

proc removeResult(path: string; recursive: bool): Result[void, string] {.gcsafe, raises: [].} =
  try:
    if dirExists(path):
      if not recursive:
        return err("cannot remove a directory without recursive")
      removeDir(path)
    else:
      removeFile(path)
    ok()
  except CatchableError as e:
    err("cannot remove: " & e.msg)

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
    readCapped: readCappedResult,
    entryKind: entryKindOf,
    isSymlink: isSymlinkAt,
    listDir: listDirResult,
    writeFile: writeFileResult,
    appendFile: appendFileResult,
    createDir: createDirResult,
    copyFile: copyFileResult,
    copyTree: copyTreeResult,
    move: moveResult,
    remove: removeResult,
  )
