## Attachment retention on a fake file system: what expires, what stays.

import std/[tables, unittest]
import donkey/core/pipeops
import donkey/core/log
import donkey/ports/fs
import donkey/app/attachment_retention

const Day = 86_400'i64
const Now = 100 * Day

type Disk = ref object
  entries: Table[string, seq[FsEntry]]
  removed: seq[string]

proc fakeFs(d: Disk): FsRuntimePort =
  result = unavailableFs()
  result.entryKind = proc(path: string): FsEntryKind {.gcsafe, raises: [].} =
    if path in d.entries: fekDir else: fekMissing
  result.listDir = proc(path: string): Result[seq[FsEntry], string] {.gcsafe, raises: [].} =
    if path notin d.entries: return err("no dir")
    ok(d.entries.getOrDefault(path))
  result.remove = proc(path: string; recursive: bool): Result[void, string] {.gcsafe, raises: [].} =
    d.removed.add path
    ok()

func entry(path: string; kind: FsEntryKind; ageDays: int64): FsEntry =
  FsEntry(path: path, kind: kind, mtime: Now - ageDays * Day)

proc disk(): Disk =
  Disk(entries: {
    "/p": @[entry("/p/u1", fekDir, 0), entry("/p/u2", fekDir, 0)],
    "/p/u1/attachments": @[entry("/p/u1/attachments/old.png", fekFile, 40),
                           entry("/p/u1/attachments/new.png", fekFile, 2),
                           entry("/p/u1/attachments/link", fekLink, 90)],
  }.toTable)

proc runTests*() =
  let log = newLogger("t", lvlError)
  suite "attachment retention":
    test "the retention setting: whole days, anything else means keep":
      check retentionDays("30") == 30
      check retentionDays(" 7 ") == 7
      check retentionDays("") == 0
      check retentionDays("-3") == 0
      check retentionDays("soon") == 0

    test "a file is expired once it is older than the retention":
      check attachmentExpired(Now - 31 * Day, Now, 30)
      check not attachmentExpired(Now - 29 * Day, Now, 30)
      check not attachmentExpired(0, Now, 30)  ## unknown mtime is kept
      check not attachmentExpired(Now - 400 * Day, Now, 0)

    test "old files go; recent files, links and paddocks without attachments stay":
      let d = disk()
      check pruneAttachments(fakeFs(d), "/p", Now, 30, log) == 1
      check d.removed == @["/p/u1/attachments/old.png"]

    test "retention 0 removes nothing":
      let d = disk()
      check pruneAttachments(fakeFs(d), "/p", Now, 0, log) == 0
      check d.removed.len == 0

when isMainModule:
  runTests()
