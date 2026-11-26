## attachment_store.nim — filesystem I/O for inbound channel attachments.
##
## Guarantees: attachments stay under the paddock's `attachments/` directory,
## symlinked parents/final names are rejected, and files are private on POSIX.
##
## The file is created exclusively (O_CREAT|O_EXCL|O_NOFOLLOW, mode 0600)
## relative to the descriptor of the attachments directory, the next name
## tried on a collision, and written through that descriptor (audit of 26/11,
## finding 1): no gap between choosing a free name and writing it, and a link
## planted at a name is never followed. Writing lived in core/media_download
## (finding 4); it belongs here.

import std/[os, strutils]
when defined(posix):
  import std/posix
  proc posixUnlinkAt(dirfd: cint; path: cstring; flags: cint): cint
                    {.importc: "unlinkat", header: "<fcntl.h>".}
import ../../core/pipeops
import ../../ports/attachment_store
import ./confined_read
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

func candidateName(name: string; n: int): string =
  ## `foto.png`, then `foto_1.png`, `foto_2.png`…
  if n == 0: return name
  let dot = name.rfind('.')
  if dot > 0: name[0 ..< dot] & "_" & $n & name[dot .. ^1]
  else: name & "_" & $n

proc writeExclusive(directory, fileName: string; data: seq[byte]): Result[string, string] =
  ## Creates a new file under `directory` (never an existing one, never
  ## through a link) and writes `data` to it; its name.
  when defined(posix):
    let dirFd = posix.open(directory.cstring, O_RDONLY or PosixODirectory or PosixONoFollow)
    if dirFd < 0:
      return err("attachments directory cannot be opened")
    defer: discard posix.close(dirFd)
    for n in 0 ..< 1000:
      let name = candidateName(fileName, n)
      let fd = posixOpenAt(dirFd, name.cstring,
        O_WRONLY or O_CREAT or O_EXCL or PosixONoFollow, Mode(0o600))
      if fd < 0:
        if errno == EEXIST or errno == ELOOP: continue   ## taken, or a link: next name
        return err("attachment cannot be created")
      var written = 0
      while written < data.len:
        let got = posix.write(fd, unsafeAddr data[written], data.len - written)
        if got <= 0:
          discard posix.close(fd)
          discard posixUnlinkAt(dirFd, name.cstring, 0)
          return err("attachment cannot be written")
        written += got
      if posix.close(fd) != 0:
        return err("attachment cannot be written")
      return ok(name)
    err("no free name for the attachment")
  else:
    discard directory
    discard fileName
    discard data
    err("attachments need a POSIX system")

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
  let name = ? writeExclusive(directory, sanitizeAttachmentName(fileName), data)
  let saved = directory / name
  let realDir = ? fsPaths.canonicalPath(directory)
  let realFile = ? fsPaths.canonicalPath(saved)
  if realFile != realDir and not realFile.startsWith(realDir & $DirSep):
    return err("attachment escaped the paddock: " & saved)
  ? fsPaths.secureFile(saved)
  ok(SavedAttachment(fileName: name, absPath: realFile))

proc newAttachmentStore*(): AttachmentStorePort =
  AttachmentStorePort(
    save: proc(directory, fileName: string; data: seq[byte]):
            Result[SavedAttachment, string] {.gcsafe, raises: [].} =
      saveAttachment(directory, fileName, data),
  )
