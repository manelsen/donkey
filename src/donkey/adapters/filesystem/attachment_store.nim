## attachment_store.nim — filesystem I/O for inbound channel attachments.
##
## Guarantees: attachments stay under the paddock's `attachments/` directory,
## symlinked parents/final names are rejected, and files are private on POSIX.

import std/[os, strutils]
import ../../core/pipeops
import ../../core/media_download
import ../../ports/attachment_store
import ./paths as fsPaths

func sanitizeAttachmentName*(raw: string): string =
  ## Keeps the user-facing name but removes anything that could escape the
  ## attachments directory or confuse the filesystem.
  var name = raw.strip
  if name.len == 0:
    return "attachment"
  name = name.replace('\\', '/')
  let slash = name.rfind('/')
  if slash >= 0 and slash + 1 < name.len:
    name = name[slash + 1 .. ^1]
  var cleaned = ""
  for ch in name:
    if ch in {'/', '\\', ':', '*', '?', '"', '<', '>', '|'} or ord(ch) < 32:
      cleaned.add('_')
    else:
      cleaned.add(ch)
  cleaned = cleaned.strip(chars = {'.', ' '})
  if cleaned.len == 0 or cleaned == "." or cleaned == "..":
    return "attachment"
  cleaned

proc saveAttachment(directory, fileName: string; data: seq[byte]):
                    Result[SavedAttachment, string] =
  let paddock = parentDir(directory)
  if paddock.len > 0:
    if symlinkExists(paddock):
      return err("paddock path is a symlink: " & paddock)
    ? fsPaths.secureDir(paddock)
  if symlinkExists(directory):
    return err("attachments path is a symlink: " & directory)
  ? fsPaths.secureDir(directory)
  var download = FileDownload(
    fileName: sanitizeAttachmentName(fileName),
    fileSize: data.len.int64,
    mimeType: "",
    data: data,
  )
  let saved = ? download.saveFileToDisk(directory)
  let realDir = ? fsPaths.canonicalPath(directory)
  let realFile = ? fsPaths.canonicalPath(saved)
  if realFile != realDir and not realFile.startsWith(realDir & $DirSep):
    return err("attachment escaped the paddock: " & saved)
  ? fsPaths.secureFile(saved)
  let slash = saved.rfind('/')
  let name = if slash >= 0: saved[slash + 1 .. ^1] else: saved
  ok(SavedAttachment(fileName: name, absPath: realFile))

proc newAttachmentStore*(): AttachmentStorePort =
  AttachmentStorePort(
    save: proc(directory, fileName: string; data: seq[byte]):
            Result[SavedAttachment, string] {.gcsafe, raises: [].} =
      saveAttachment(directory, fileName, data),
  )
