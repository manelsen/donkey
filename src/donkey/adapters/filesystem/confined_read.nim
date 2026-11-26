## confined_read — read a file inside the paddock without being fooled by a
## link, a rename or a swap between validation and the read.
##
## Moved from the Telegram adapter (E9.1), so every channel that uploads a
## local file reads it the same way: `resolveConfinedMediaPath` validates the
## name, `openPathComponent` opens it one component at a time with
## O_NOFOLLOW and checks it is still the validated file, `readPathComponent`
## reads from that descriptor, never from the name again.

import std/[os, strutils]
when defined(posix):
  import std/posix
import ../../core/pipeops
import ./paths

const UploadReadChunk = 64 * 1024

when defined(posix):
  var
    PosixONoFollow* {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
    PosixONonBlock* {.importc: "O_NONBLOCK", header: "<fcntl.h>".}: cint
    PosixODirectory* {.importc: "O_DIRECTORY", header: "<fcntl.h>".}: cint

  proc posixOpenAt*(dirfd: cint; path: cstring; flags: cint;
                   mode: Mode = Mode(0)): cint
                   {.importc: "openat", header: "<fcntl.h>", varargs.}
    ## Nim's std/posix has no `openat`, and it is the only way to open one
    ## component relative to the descriptor of the previous one.

type
  PathComponent* = object
    name*: string   ## one component, as opened; parent components are dirs
    fd*:   cint     ## descriptor opened with O_NOFOLLOW and nothing read yet

proc closeComponent*(c: var PathComponent) =
  ## Closes the descriptor. A component that already travelled to the next step
  ## holds -1.
  when defined(posix):
    if c.fd >= 0:
      discard posix.close(c.fd)
      c.fd = -1

func componentSlot*(paddockRoot, resolvedPath: string): string =
  ## Path inside the paddock, e.g. "nota.ogg" or "grupo/nota.ogg"; empty when
  ## the path is outside it.
  if resolvedPath.len == 0:
    return ""
  if resolvedPath == paddockRoot:
    return ""
  if not resolvedPath.startsWith(paddockRoot & $DirSep):
    return ""
  resolvedPath[paddockRoot.len + 1 .. ^1]

proc openPathComponent*(paddockRoot, resolvedPath: string): Result[PathComponent, string]
                       {.gcsafe, raises: [].} =
  ## Walks the path from the paddock root down to its last component, opening
  ## each level relative to the descriptor of the level above it with
  ## O_NOFOLLOW, so no component is followed through a symlink. The returned
  ## descriptor is the file itself; its device and inode are those validation
  ## saw, so a link, FIFO or directory swapped in after that call is refused
  ## instead of being opened or followed.
  when defined(posix):
    try:
      ## `resolveConfinedMediaPath` compared the file against the canonical
      ## paddock root; reuse the same reference here, otherwise a relative or
      ## symlinked paddock root would make a valid file look outside.
      var lexicalRoot = paddockRoot
      normalizePath(lexicalRoot)
      let canonicalRoot = canonicalPath(lexicalRoot)
      if canonicalRoot.isErr:
        return err("media root is unavailable")
      let root = canonicalRoot.get()
      let slot = componentSlot(root, resolvedPath)
      if slot.len == 0:
        return err("media path is outside the paddock")
      var validated: Stat
      if posix.stat(resolvedPath.cstring, validated) != 0:
        return err("media file unavailable")
      if validated.st_nlink > 1:
        ## A file with another name can be unlinked and replaced by a link
        ## without the name in the component chain ever changing.
        return err("media file has several names")
      ## The root itself is opened without following a symlink: on non-Linux
      ## POSIX there is no `/proc` check, so `O_DIRECTORY` alone would follow a
      ## root swapped for a link after validation.
      var current = PathComponent(name: root, fd: posix.open(
        root.cstring, O_RDONLY or PosixODirectory or PosixONoFollow))
      if current.fd < 0:
        return err("media root is unavailable")
      let parts = slot.split('/')
      for i, part in parts:
        let last = i == parts.high
        let flags =
          if last: O_RDONLY or PosixONoFollow or PosixONonBlock
          else: O_RDONLY or PosixODirectory or PosixONoFollow
        let opened = posixOpenAt(current.fd, part.cstring, flags)
        current.closeComponent()
        if opened < 0:
          return err("media path cannot be opened")
        current = PathComponent(name: part, fd: opened)
      when defined(linux):
        ## The descriptor must still name the path inside the root: without
        ## it the component chain alone proves nothing about where it landed.
        var linkBuf = newString(4096)
        let linkLen = posix.readlink(("/proc/self/fd/" & $current.fd).cstring,
                                     linkBuf.cstring, linkBuf.len)
        if linkLen <= 0:
          current.closeComponent()
          return err("media path cannot be verified")
        linkBuf.setLen(linkLen)
        ## The lexical root is what was checked, so the descriptor must resolve
        ## under that same name; a rename or link on the way there shows up
        ## here even when the component chain itself stayed confined.
        if linkBuf != root & $DirSep & slot:
          current.closeComponent()
          return err("media path changed after validation")
      var descriptor: Stat
      if posix.fstat(current.fd, descriptor) != 0 or
         descriptor.st_dev != validated.st_dev or
         descriptor.st_ino != validated.st_ino:
        current.closeComponent()
        return err("media file changed after validation")
      ok(current)
    except CatchableError:
      err("media path cannot be opened")
  else:
    discard paddockRoot
    discard resolvedPath
    err("media path cannot be opened")

proc readPathComponent*(c: PathComponent; limit: int64): Result[string, string]
                        {.gcsafe, raises: [].} =
  ## Reads at most `limit` bytes (plus one probe byte at the cap) from the
  ## descriptor that was validated as the file, never from its name.
  when defined(posix):
    var header: Stat
    if posix.fstat(c.fd, header) != 0 or not S_ISREG(header.st_mode):
      return err("media target is not a regular file")
    if header.st_size > limit:
      return err("media file exceeds the cap")
    var data = newStringOfCap(int(min(header.st_size, limit)))
    var chunk = newString(max(UploadReadChunk, 1))
    while data.len.int64 < limit:
      let want = int(min(int64(chunk.len), limit - data.len.int64))
      let got = posix.read(c.fd, addr chunk[0], want)
      if got < 0:
        return err("media file unreadable")
      if got == 0:
        break
      data.add(chunk[0 ..< got])
    if data.len.int64 >= limit:
      var extra: char
      if posix.read(c.fd, addr extra, 1) > 0:
        return err("media file exceeds the cap")
    ok(data)
  else:
    err("media file unreadable")

