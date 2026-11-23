## Attachment retention: files in each paddock's `attachments/` (inbound
## media, synthesized speech) older than a number of days are removed. Off
## unless `DONKEY_ATTACHMENT_RETENTION_DAYS` is set, so nothing is deleted
## that an operator did not ask to delete.

import std/[os, strutils]
import ../core/pipeops
import ../core/log
import ../ports/fs
import ../ports/attachment_store

const AttachmentRetentionEnv* = "DONKEY_ATTACHMENT_RETENTION_DAYS"

func retentionDays*(raw: string): int =
  ## Whole days; empty, negative or not a number means keep everything (0).
  try: max(0, parseInt(raw.strip))
  except ValueError: 0

func attachmentExpired*(mtimeSec, nowSec: int64; days: int): bool =
  ## Older than `days`. An unknown modification time (0) is never expired.
  days > 0 and mtimeSec > 0 and nowSec - mtimeSec > int64(days) * 86_400

proc pruneAttachments*(fs: FsRuntimePort; paddocksDir: string; nowSec: int64;
                       days: int; log: Logger): int {.gcsafe, raises: [].} =
  ## Removes the expired regular files directly in each paddock's
  ## attachments directory and returns how many. Symlinks and directories are
  ## left alone; a paddock that cannot be listed is skipped and logged.
  if days <= 0 or fs.entryKind(paddocksDir) != fekDir:
    return 0
  let paddocks = fs.listDir(paddocksDir).valueOr:
    log.warn("attachment retention: cannot list " & paddocksDir & ": " & error)
    return 0
  for paddock in paddocks:
    if paddock.kind != fekDir: continue
    let dir = paddock.path / AttachmentDirName
    if fs.entryKind(dir) != fekDir: continue
    let files = fs.listDir(dir).valueOr:
      log.warn("attachment retention: cannot list " & dir & ": " & error)
      continue
    for file in files:
      if file.kind == fekFile and attachmentExpired(file.mtime, nowSec, days):
        let removed = fs.remove(file.path, false)
        if removed.isOk:
          inc result
        else:
          log.warn("attachment retention: cannot remove " & file.path &
                   ": " & removed.error)
