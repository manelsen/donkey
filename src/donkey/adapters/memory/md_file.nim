## MdFileAdapter — MemoryPort backed by Markdown files in a paddock directory.
##
## Paddock root:  {paddocksDir}/{userId}/
## Files managed: USER.md, MEMORY.md, PREFERENCES.md
##
## All I/O is synchronous (proc). The domain layer (func) uses the pure
## UserContext value; this adapter is the side-effectful shell.

import std/[os, strutils]
import ../../core/types
import ../../ports/memory

type
  MdFileAdapter* = object
    paddocksDir*: string  ## base directory, e.g. ~/.donkey/paddocks

# ── path helpers ──────────────────────────────────────────────────────────────

func paddockDir*(a: MdFileAdapter; userId: UserId): string =
  a.paddocksDir / $userId

func userMdPath*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / "USER.md"

func memoryMdPath*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / "MEMORY.md"

func preferencesMdPath*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / "PREFERENCES.md"

# ── helpers ───────────────────────────────────────────────────────────────────

proc readOrEmpty(path: string): string =
  if fileExists(path): readFile(path) else: ""

proc ensurePaddock*(a: MdFileAdapter; userId: UserId) =
  ## Creates the paddock directory tree if it does not exist.
  createDir(a.paddockDir(userId))
  createDir(a.paddockDir(userId) / "sessions")

# ── MemoryPort implementation ─────────────────────────────────────────────────

proc hasProfile*(a: MdFileAdapter; userId: UserId): bool =
  fileExists(a.userMdPath(userId))

proc loadContext*(a: MdFileAdapter; userId: UserId): UserContext =
  UserContext(
    userId:        userId,
    userMd:        readOrEmpty(a.userMdPath(userId)),
    memoryMd:      readOrEmpty(a.memoryMdPath(userId)),
    preferencesMd: readOrEmpty(a.preferencesMdPath(userId)),
  )

proc saveUserMd*(a: MdFileAdapter; userId: UserId; content: string) =
  a.ensurePaddock(userId)
  writeFile(a.userMdPath(userId), content)

proc appendMemory*(a: MdFileAdapter; userId: UserId; text: string) =
  a.ensurePaddock(userId)
  let path = a.memoryMdPath(userId)
  let existing = readOrEmpty(path)
  let sep = if existing.len > 0 and not existing.endsWith("\n"): "\n" else: ""
  writeFile(path, existing & sep & text)

proc savePreferences*(a: MdFileAdapter; userId: UserId; content: string) =
  a.ensurePaddock(userId)
  writeFile(a.preferencesMdPath(userId), content)

# ── Scaffold USER.md from onboarding answers ──────────────────────────────────

proc bootstrapUserMd*(name, callMe, timezone, language: string): string =
  ## Pure helper (could be func but lives here for proximity to adapter).
  ## Generates the initial USER.md following the OpenClaw USER.md template.
  """---
summary: """ & name & """ — onboarded via Donkey bootstrapping.
read_when: every conversation
---

# """ & name & """

**Preferred name:** """ & callMe & """
**Timezone:** """ & timezone & """
**Language:** """ & language & """
"""
