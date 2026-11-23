## The file tools on a file system made of strings: what `ports/fs` buys.
## No directory is created; every path below exists only in the table.

import std/[json, strutils, tables, unittest]
import chronos
import donkey/core/pipeops
import donkey/core/log
import donkey/core/types
import donkey/domain/message
import donkey/core/tooling/structured_tool_result
import donkey/ports/fs
import donkey/app/session_state
import donkey/app/native_tools
import donkey/app/tools/fs_tools
import donkey/app/tools/search_tools

type Disk = ref object
  files: Table[string, string]
  dirs:  seq[string]

proc fakeFs(d: Disk): FsRuntimePort =
  result = unavailableFs()
  result.entryKind = proc(path: string): FsEntryKind {.gcsafe, raises: [].} =
    if path in d.files: fekFile
    elif path in d.dirs: fekDir
    else: fekMissing
  result.fileSize = proc(path: string): Result[int64, string] {.gcsafe, raises: [].} =
    if path in d.files: ok(d.files.getOrDefault(path).len.int64) else: err("no file")
  result.readFile = proc(path: string): Result[string, string] {.gcsafe, raises: [].} =
    if path in d.files: ok(d.files.getOrDefault(path)) else: err("no file")
  result.listDir = proc(path: string): Result[seq[FsEntry], string] {.gcsafe, raises: [].} =
    var entries: seq[FsEntry]
    for f in d.files.keys:
      if f.rsplit('/', 1)[0] == path: entries.add FsEntry(path: f, kind: fekFile)
    for dir in d.dirs:
      if dir != path and dir.rsplit('/', 1)[0] == path:
        entries.add FsEntry(path: dir, kind: fekDir)
    ok(entries)
  result.writeFile = proc(path, content: string): Result[void, string] {.gcsafe, raises: [].} =
    d.files[path] = content
    ok()
  result.appendFile = proc(path, content: string): Result[void, string] {.gcsafe, raises: [].} =
    d.files[path] = d.files.getOrDefault(path) & content
    ok()

proc newDisk(): Disk =
  Disk(dirs: @["/p", "/p/docs"],
       files: {"/p/a.txt": "one\nneedle two\n", "/p/docs/b.md": "needle\n"}.toTable)

proc runTests*() =
  suite "file tools on a fake file system":
    test "grep walks the fake tree":
      let disk = newDisk()
      let found = performGrep(fakeFs(disk), "needle", "/p", true, 10)
      check "/p/a.txt:2:needle two" in found
      check "/p/docs/b.md:1:needle" in found

    test "find lists by pattern":
      check performFind(fakeFs(newDisk()), "/p", "*.md", "file", 10) == "/p/docs/b.md"

    test "fs_write appends through the port":
      let disk = newDisk()
      let res = performFsWrite(fakeFs(disk), "a.txt", "/p", "append", %"three\n")
      check res.toNode()["ok"].getBool
      check disk.files["/p/a.txt"] == "one\nneedle two\nthree\n"

    test "a write the port refuses is an error result":
      let disk = newDisk()
      var fs = fakeFs(disk)
      fs.writeFile = proc(path, content: string): Result[void, string] {.gcsafe, raises: [].} =
        err("disk full")
      let res = performFsWrite(fs, "new.txt", "/p", "create", %"x")
      check not res.toNode()["ok"].getBool
      check "disk full" in $res.toNode()

  suite "a native context without a file system":
    test "a file tool fails instead of crashing":
      let ctx = NativeCtx(uid: UserId("u"), paddockDir: "/p", log: newLogger("t", lvlError))
      let res = waitFor executeNativeTool(
        ToolCallRequest(id: "1", name: "fs_read", inputJson: """{"path": "a.txt"}"""),
        ctx, newSessionState(), newHistory())
      check res.handled
      check "unavailable" in res.text

when isMainModule:
  runTests()
