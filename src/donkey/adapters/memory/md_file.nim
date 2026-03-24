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
import ../../domain/personality
export json  ## re-export so callers can inspect JsonNode reminder fields
export memory

type
  MdFileAdapter* = object
    paddocksDir*: string  ## base directory, e.g. ~/.donkey/paddocks

  UserSummary* = object
    userId*:      UserId
    hasProfile*:  bool
    preferredName*: string
    access*:      string

proc hasProfile*(a: MdFileAdapter; userId: UserId): bool {.gcsafe.}
proc loadContext*(a: MdFileAdapter; userId: UserId): UserContext {.gcsafe.}
proc saveUserMd*(a: MdFileAdapter; userId: UserId; content: string) {.gcsafe.}
proc appendMemory*(a: MdFileAdapter; userId: UserId; text: string) {.gcsafe.}
proc savePreferences*(a: MdFileAdapter; userId: UserId; content: string) {.gcsafe.}
proc clearMemory*(a: MdFileAdapter; userId: UserId) {.gcsafe.}
proc saveSession*(a: MdFileAdapter; userId: UserId;
                  sessionId: string; history: ConversationHistory) {.gcsafe.}
proc saveIdentity*(a: MdFileAdapter; userId: UserId;
                   traits: PersonalityTraits; name: string) {.gcsafe.}
proc loadIdentity*(a: MdFileAdapter; userId: UserId): (string, PersonalityTraits) {.gcsafe.}
func paddockDir*(a: MdFileAdapter; userId: UserId): string {.gcsafe.}
proc scheduleReminder*(a: MdFileAdapter; userId: UserId;
                       channel: string; scheduledAt: int64;
                       message: string): string {.gcsafe.}
proc loadDueReminders*(a: MdFileAdapter): seq[JsonNode] {.gcsafe.}
proc deleteReminder*(a: MdFileAdapter; userId: UserId; reminderId: string) {.gcsafe.}

proc toRuntimePort*(a: MdFileAdapter): MemoryRuntimePort =
  MemoryRuntimePort(
    hasProfile:       proc(userId: UserId): bool {.gcsafe.} = a.hasProfile(userId),
    loadContext:      proc(userId: UserId): UserContext {.gcsafe.} = a.loadContext(userId),
    saveUserMd:       proc(userId: UserId; content: string) {.gcsafe.} = a.saveUserMd(userId, content),
    appendMemory:     proc(userId: UserId; text: string) {.gcsafe.} = a.appendMemory(userId, text),
    savePreferences:  proc(userId: UserId; content: string) {.gcsafe.} = a.savePreferences(userId, content),
    clearMemory:      proc(userId: UserId) {.gcsafe.} = a.clearMemory(userId),
    saveSession:      proc(userId: UserId; sessionId: string; history: ConversationHistory) {.gcsafe.} =
                        a.saveSession(userId, sessionId, history),
    saveIdentity:     proc(userId: UserId; traits: PersonalityTraits; name: string) {.gcsafe.} =
                        a.saveIdentity(userId, traits, name),
    loadIdentity:     proc(userId: UserId): (string, PersonalityTraits) {.gcsafe.} = a.loadIdentity(userId),
    paddockDir:       proc(userId: UserId): string {.gcsafe.} = a.paddockDir(userId),
    scheduleReminder: proc(userId: UserId; channel: string; scheduledAt: int64; message: string): string {.gcsafe.} =
                        a.scheduleReminder(userId, channel, scheduledAt, message),
    loadDueReminders: proc(): seq[JsonNode] {.gcsafe.} = a.loadDueReminders(),
    deleteReminder:   proc(userId: UserId; reminderId: string) {.gcsafe.} = a.deleteReminder(userId, reminderId),
  )

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

proc parseUserField*(content, label: string): string =
  let prefix = "**" & label & ":**"
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith(prefix):
      return trimmed[prefix.len .. ^1].strip()
  ""

proc setUserFieldText*(content, label, value: string): string =
  let prefix = "**" & label & ":** "
  var lines = content.splitLines()
  for i in 0 ..< lines.len:
    if lines[i].strip().startsWith("**" & label & ":**"):
      lines[i] = prefix & value
      return lines.join("\n")
  if lines.len > 0 and lines[^1].len > 0:
    lines.add("")
  lines.add(prefix & value)
  lines.join("\n")

proc isRevokedUserMd*(content: string): bool =
  content.parseUserField("Access").toLowerAscii() == "revoked"

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

proc listUsers*(a: MdFileAdapter): seq[UserSummary] =
  if not dirExists(a.paddocksDir):
    return @[]
  for kind, path in walkDir(a.paddocksDir):
    if kind != pcDir:
      continue
    let uid = UserId(path.extractFilename())
    let userMd = readOrEmpty(a.userMdPath(uid))
    result.add(UserSummary(
      userId: uid,
      hasProfile: userMd.len > 0,
      preferredName: userMd.parseUserField("Preferred name"),
      access: block:
        let access = userMd.parseUserField("Access")
        if access.len > 0: access else: "active",
    ))

proc updateUserField*(a: MdFileAdapter; userId: UserId; field, value: string) =
  let current = readOrEmpty(a.userMdPath(userId))
  let label =
    if field.toLowerAscii() == "preferred_name": "Preferred name"
    elif field.toLowerAscii() == "access": "Access"
    else: field
  a.saveUserMd(userId, current.setUserFieldText(label, value))

proc isRevoked*(a: MdFileAdapter; userId: UserId): bool =
  isRevokedUserMd(readOrEmpty(a.userMdPath(userId)))

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

# ── Agent identity helpers ────────────────────────────────────────────────────

proc hasIdentity*(a: MdFileAdapter; userId: UserId): bool =
  ## True when agent_name is present in PREFERENCES.md.
  let path = a.preferencesMdPath(userId)
  if not fileExists(path): return false
  for line in readFile(path).splitLines():
    if line.startsWith("agent_name"): return true
  false

proc saveIdentity*(a: MdFileAdapter; userId: UserId;
                   traits: PersonalityTraits; name: string) =
  ## Merges agent identity into PREFERENCES.md (TOML key=value format).
  a.ensurePaddock(userId)
  let path  = a.preferencesMdPath(userId)
  var lines = readOrEmpty(path).splitLines()
  proc setKey(ls: var seq[string]; key, val: string) =
    for i in 0 ..< ls.len:
      if ls[i].startsWith(key & " ") or ls[i].startsWith(key & "="):
        ls[i] = key & " = \"" & val & "\""
        return
    ls.add(key & " = \"" & val & "\"")
  lines.setKey("agent_name",       name)
  lines.setKey("agent_energy",     traits.energy)
  lines.setKey("agent_tone",       traits.tone)
  lines.setKey("agent_length",     traits.length)
  lines.setKey("agent_initiative", traits.initiative)
  writeFile(path, lines.join("\n"))

proc loadIdentity*(a: MdFileAdapter; userId: UserId): (string, PersonalityTraits) =
  ## Returns (agent_name, PersonalityTraits) from PREFERENCES.md.
  ## Empty strings when not set.
  let path = a.preferencesMdPath(userId)
  if not fileExists(path): return ("", PersonalityTraits())
  var name   = ""
  var traits = PersonalityTraits()
  for line in readFile(path).splitLines():
    let parts = line.split('=', 1)
    if parts.len != 2: continue
    let k = parts[0].strip
    let v = parts[1].strip.strip(chars = {'"'})
    case k
    of "agent_name":       name             = v
    of "agent_energy":     traits.energy    = v
    of "agent_tone":       traits.tone      = v
    of "agent_length":     traits.length    = v
    of "agent_initiative": traits.initiative = v
    else: discard
  (name, traits)

# ── Reminder store ────────────────────────────────────────────────────────────

proc reminderDir*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / "reminders"

proc scheduleReminder*(a: MdFileAdapter; userId: UserId;
                       channel: string; scheduledAt: int64;
                       message: string): string =
  ## Writes a reminder JSON file. Returns the reminder id.
  a.ensurePaddock(userId)
  createDir(a.reminderDir(userId))
  let id   = $getTime().toUnix() & "_" & $userId
  let data = %* {
    "id":          id,
    "userId":      $userId,
    "channel":     channel,
    "scheduledAt": scheduledAt,
    "message":     message,
  }
  writeFile(a.reminderDir(userId) / id & ".json", $data)
  id

proc loadDueReminders*(a: MdFileAdapter): seq[JsonNode] =
  ## Scans ALL paddocks for reminders whose scheduledAt <= now (UTC seconds).
  let now = getTime().toUnix()
  if not dirExists(a.paddocksDir): return @[]
  for _, paddockPath in walkDir(a.paddocksDir):
    let remDir = paddockPath / "reminders"
    if not dirExists(remDir): continue
    for _, rPath in walkDir(remDir):
      if not rPath.endsWith(".json"): continue
      try:
        let j = parseJson(readFile(rPath))
        if j["scheduledAt"].getBiggestInt() <= now:
          result.add(j)
      except: discard

proc deleteReminder*(a: MdFileAdapter; userId: UserId; reminderId: string) =
  ## Deletes a reminder file by id.
  let path = a.reminderDir(userId) / reminderId & ".json"
  if fileExists(path): removeFile(path)
