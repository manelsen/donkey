## MdFileAdapter — MemoryPort backed by Markdown files in a paddock directory.
##
## Paddock root:  {paddocksDir}/{userId}/
## Files managed: USER.md, MEMORY.md, PREFERENCES.md
##
## All I/O is synchronous (proc). The domain layer (func) uses the pure
## UserContext value; this adapter is the side-effectful shell.

import std/[json, os, strutils, times]
import ../../core/types
import ../../ports/memory
import ../../domain/message

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

proc clearMemory*(a: MdFileAdapter; userId: UserId) =
  ## Clears MEMORY.md for this user (irreversible).
  let path = a.memoryMdPath(userId)
  if fileExists(path): writeFile(path, "")

proc saveSession*(a: MdFileAdapter; userId: UserId;
                  sessionId: string; history: ConversationHistory) =
  ## Persists a conversation as JSONL: one JSON object per turn.
  ## Path: {paddock}/sessions/{sessionId}.jsonl
  ## Skips sessions with fewer than 2 turns (empty/ping sessions).
  if history.len < 2: return
  a.ensurePaddock(userId)
  let dir  = a.paddockDir(userId) / "sessions"
  createDir(dir)
  let path = dir / sessionId & ".jsonl"
  var buf  = ""
  for msg in history:
    buf.add($(%* {"role": msg.role, "text": msg.text,
                  "imageUrl": msg.imageUrl}) & "\n")
  writeFile(path, buf)

proc listSessions*(a: MdFileAdapter; userId: UserId): seq[string] =
  ## Returns session file names (without extension) sorted newest-first.
  let dir = a.paddockDir(userId) / "sessions"
  if not dirExists(dir): return @[]
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".jsonl"):
      result.add(path.extractFilename().changeFileExt(""))

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
