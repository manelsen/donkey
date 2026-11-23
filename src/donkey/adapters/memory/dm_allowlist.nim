## The DM allowlist: one user id per line in `{home}/state/dm_allowlist.txt`,
## private to the service user. Instance-level, outside the paddocks.

import std/[os, strutils]
import ../../core/pipeops
import ../../core/types
import ../../ports/access
import ../filesystem/paths
import ./md_file

export access

type
  DmAllowlist* = object
    path*: string

func dmAllowlistOf*(paddocksDir: string): DmAllowlist =
  ## The allowlist sits in the state directory next to the paddocks.
  DmAllowlist(path: parentDir(paddocksDir) / "state" / "dm_allowlist.txt")

proc isAllowed*(l: DmAllowlist; userId: UserId): Result[bool, string] {.raises: [].} =
  ## Whether the id is on the list; an error when the list cannot be read.
  try:
    if not fileExists(l.path):
      return ok(false)
    for line in lines(l.path):
      if line.strip == $userId:
        return ok(true)
    ok(false)
  except CatchableError as e:
    err("dm allowlist: " & e.msg)

proc allow*(l: DmAllowlist; userId: UserId): Result[void, string] {.raises: [].} =
  let rawId = $userId
  if rawId.len == 0 or rawId.strip != rawId or '\n' in rawId or '\r' in rawId:
    return err("dm allowlist add failed: invalid user id")
  if ? l.isAllowed(userId):
    return ok()
  try:
    createDir(parentDir(l.path))
    var f = open(l.path, fmAppend)
    defer: f.close()
    f.writeLine(rawId)
    discard secureFile(l.path)
    ok()
  except CatchableError as e:
    err("dm allowlist add failed: " & e.msg)

proc disallow*(l: DmAllowlist; userId: UserId): Result[void, string] =
  try:
    if not fileExists(l.path):
      return ok()
    var kept: seq[string] = @[]
    for line in lines(l.path):
      let value = line.strip
      if value.len > 0 and value != $userId:
        kept.add(value)
    let tmp = l.path & ".tmp"
    writeFile(tmp, if kept.len > 0: kept.join("\n") & "\n" else: "")
    discard secureFile(tmp)
    moveFile(tmp, l.path)
    ok()
  except CatchableError as e:
    err("dm allowlist remove failed: " & e.msg)

proc toAccessPort*(memory: MdFileAdapter; allowlist: DmAllowlist): AccessPort =
  ## Revocation from the profile (`Access: revoked` in USER.md), DM access
  ## from the allowlist.
  AccessPort(
    isRevoked: proc(userId: UserId): Result[bool, string] {.gcsafe, raises: [].} =
      try: ok(memory.isRevoked(userId))
      except Exception as e:  ## effect boundary: callee raises are unannotated
        err(e.msg),
    isDmAllowed: proc(userId: UserId): Result[bool, string] {.gcsafe, raises: [].} =
      allowlist.isAllowed(userId),
  )
