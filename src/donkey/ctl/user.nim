## ctl/user.nim — `donkey ctl user` handlers.

import std/os
import ../core/types
import ../core/pipeops
import ../adapters/memory/md_file

# ── ctl user commands ──────────────────────────────────────────────────────────

proc ctlUserList*(memory: MdFileAdapter) =
  if not dirExists(memory.paddocksDir):
    echo "(no paddocks directory — no users yet)"
    return
  var found = false
  for kind, name in walkDir(memory.paddocksDir):
    if kind == pcDir:
      found = true
      let userMdPath = name / "USER.md"
      if fileExists(userMdPath):
        echo name.extractFilename() & " (profile)"
      else:
        echo name.extractFilename() & " (no profile)"
  if not found:
    echo "(no users registered)"

proc ctlUserShow*(memory: MdFileAdapter; uuid: string): Result[void, string] =
  let userId = UserId(uuid)
  if not memory.hasProfile(userId):
    return err("User not found: " & uuid)
  let ctx = memory.loadContext(userId)
  echo "=== USER.md ==="
  echo ctx.userMd
  if ctx.preferencesMd.len > 0:
    echo "=== PREFERENCES.md ==="
    echo ctx.preferencesMd
  if ctx.memoryMd.len > 0:
    echo "=== MEMORY.md (first 500 chars) ==="
    echo ctx.memoryMd[0 .. min(500, ctx.memoryMd.len - 1)]
  ok()

proc ctlUserEdit*(memory: MdFileAdapter;
                  uuid, field, value: string): Result[void, string] =
  ## An edit that was not saved is an error, so the command exits non-zero.
  ? memory.updateUserField(UserId(uuid), field, value)
  echo "Updated " & uuid & ": " & field & " = " & value
  ok()

proc ctlUserRevoke*(memory: MdFileAdapter; uuid: string; revoked: bool): Result[void, string] =
  let userId = UserId(uuid)
  # Allowlist first: a failure must not leave Access changed without the
  # corresponding allowlist entry.
  let allowlistResult =
    if revoked: memory.removeDmAllowed(userId)
    else: memory.addDmAllowed(userId)
  if allowlistResult.isErr:
    echo "Error: " & allowlistResult.error
    return err(allowlistResult.error)
  if memory.hasProfile(userId):
    let updated = memory.updateUserField(
      userId, "Access", if revoked: "revoked" else: "active")
    if updated.isErr:
      echo "Error: " & updated.error
      return err(updated.error)
  echo (if revoked: "Revoked " else: "Restored ") & uuid
  ok()
