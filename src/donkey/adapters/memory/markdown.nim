## MarkdownMemoryAdapter — MemoryPort backed by Markdown files in a paddock directory.
##
## Paddock root:  {paddocksDir}/{userId}/
## Files managed: USER.md, MEMORY.md, PREFERENCES.md
##
## All I/O is fallible (file system can fail) and returns Result[T, string].
## Operations are chained via >>= (railway-oriented programming).
##
## Usage example:
##   let ctx = adapter.loadContext(userId).valueOr:
##     log.error("loadContext: " & error)
##
## The >>= operator chains fallible operations:
##   ensureResult >>= writeUserMdResult

import std/[json, os, strutils, times]
import ../../core/pipeops
import ../../core/types
import ../../ports/memory
import ../../domain/message
import ../../domain/personality
export json
export memory

type
  MarkdownMemoryAdapter* = object
    paddocksDir*: string  ## base directory, e.g. ~/.donkey/paddocks

  UserSummary* = object
    userId*:      UserId
    hasProfile*:  bool
    preferredName*: string
    access*:      string

## ── Path helpers (pure) ─────────────────────────────────────────────────────

func paddockDir*(a: MarkdownMemoryAdapter; userId: UserId): string =
  a.paddocksDir / $userId

func userMdPath*(a: MarkdownMemoryAdapter; userId: UserId): string =
  a.paddockDir(userId) / "USER.md"

func memoryMdPath*(a: MarkdownMemoryAdapter; userId: UserId): string =
  a.paddockDir(userId) / "MEMORY.md"

func preferencesMdPath*(a: MarkdownMemoryAdapter; userId: UserId): string =
  a.paddockDir(userId) / "PREFERENCES.md"

func sessionsDir*(a: MarkdownMemoryAdapter; userId: UserId): string =
  a.paddockDir(userId) / "sessions"

func reminderDir*(a: MarkdownMemoryAdapter; userId: UserId): string =
  a.paddockDir(userId) / "reminders"

## ── Core I/O operations (Result-based, chainable via >>=) ───────────────────

proc ensurePaddock*(a: MarkdownMemoryAdapter; userId: UserId): Result[void, string] =
  ## Creates the paddock directory tree if it does not exist.
  try:
    createDir(a.paddockDir(userId))
    createDir(a.sessionsDir(userId))
    ok()
  except CatchableError as e:
    err("ensurePaddock: " & e.msg)

proc hasProfile*(a: MarkdownMemoryAdapter; userId: UserId): Result[bool, string] =
  ## Returns true iff USER.md exists for this user.
  let path = a.userMdPath(userId)
  if fileExists(path):
    ok(true)
  else:
    ok(false)

proc readFileResult*(path: string): Result[string, string] =
  ## Read file contents, returning error string on failure.
  try:
    if fileExists(path):
      ok(readFile(path))
    else:
      ok("")
  except CatchableError as e:
    err("readFile: " & e.msg)

proc writeFileResult*(path, content: string): Result[void, string] =
  ## Write content to file, returning error string on failure.
  try:
    writeFile(path, content)
    ok()
  except CatchableError as e:
    err("writeFile: " & e.msg)

proc loadContext*(a: MarkdownMemoryAdapter; userId: UserId): Result[UserContext, string] =
  ## Loads USER.md + MEMORY.md + PREFERENCES.md into a UserContext.
  ## Chains three read operations via >>=.
  let userMdPath = a.userMdPath(userId)
  let memoryMdPath = a.memoryMdPath(userId)
  let preferencesMdPath = a.preferencesMdPath(userId)
  let userResult = userMdPath.readFileResult
  if userResult.isErr:
    return err(userResult.error)
  let memoryResult = memoryMdPath.readFileResult
  if memoryResult.isErr:
    return err(memoryResult.error)
  let preferencesResult = preferencesMdPath.readFileResult
  if preferencesResult.isErr:
    return err(preferencesResult.error)
  ok(UserContext(
    userId:        userId,
    userMd:        userResult.get(),
    memoryMd:      memoryResult.get(),
    preferencesMd: preferencesResult.get(),
  ))

proc saveUserMd*(a: MarkdownMemoryAdapter; userId: UserId; content: string): Result[void, string] =
  ## Overwrites USER.md for the given user.
  let ensureResult = a.ensurePaddock(userId)
  if ensureResult.isErr:
    return err(ensureResult.error)
  let writeResult = a.userMdPath(userId).writeFileResult(content)
  if writeResult.isErr:
    return err(writeResult.error)
  ok()

proc appendMemory*(a: MarkdownMemoryAdapter; userId: UserId; text: string): Result[void, string] =
  ## Appends a block of text to MEMORY.md (creates if absent).
  let ensureResult = a.ensurePaddock(userId)
  if ensureResult.isErr:
    return err(ensureResult.error)
  let path = a.memoryMdPath(userId)
  let readResult = path.readFileResult
  if readResult.isErr:
    return err(readResult.error)
  let existing = readResult.get()
  let sep = if existing.len > 0 and not existing.endsWith("\n"): "\n" else: ""
  let newContent = existing & sep & text
  let writeResult = path.writeFileResult(newContent)
  if writeResult.isErr:
    return err(writeResult.error)
  ok()

proc savePreferences*(a: MarkdownMemoryAdapter; userId: UserId; content: string): Result[void, string] =
  ## Overwrites PREFERENCES.md.
  let ensureResult = a.ensurePaddock(userId)
  if ensureResult.isErr:
    return err(ensureResult.error)
  let writeResult = a.preferencesMdPath(userId).writeFileResult(content)
  if writeResult.isErr:
    return err(writeResult.error)
  ok()

proc clearMemory*(a: MarkdownMemoryAdapter; userId: UserId): Result[void, string] =
  ## Clears MEMORY.md for this user (irreversible).
  let ensureResult = a.ensurePaddock(userId)
  if ensureResult.isErr:
    return err(ensureResult.error)
  let path = a.memoryMdPath(userId)
  if fileExists(path):
    let writeResult = path.writeFileResult("")
    if writeResult.isErr:
      return err(writeResult.error)
  ok()

proc saveSession*(a: MarkdownMemoryAdapter; userId: UserId;
                  sessionId: string; history: ConversationHistory): Result[void, string] =
  ## Persists a conversation as JSONL: one JSON object per turn.
  ## Path: {paddock}/sessions/{sessionId}.jsonl
  ## Skips sessions with fewer than 2 turns.
  if history.len < 2:
    return ok()
  let ensureResult = a.ensurePaddock(userId)
  if ensureResult.isErr:
    return err(ensureResult.error)
  let dir = a.sessionsDir(userId)
  try:
    createDir(dir)
  except CatchableError as e:
    return err("saveSession: createDir: " & e.msg)
  let path = dir / sessionId & ".jsonl"
  var buf = ""
  for msg in history:
    buf.add($(%* {"role": msg.role, "text": msg.text,
                  "imageUrl": msg.imageUrl}) & "\n")
  let writeResult = path.writeFileResult(buf)
  if writeResult.isErr:
    return err(writeResult.error)
  ok()

## ── Helper procs (pure, for use with |>) ───────────────────────────────────

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

proc listSessions*(a: MarkdownMemoryAdapter; userId: UserId): Result[seq[string], string] =
  ## Returns session file names (without extension) sorted newest-first.
  let dir = a.sessionsDir(userId)
  if not dirExists(dir):
    let emptySeq: seq[string] = @[]
    return ok(emptySeq)
  var sessions: seq[string]
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".jsonl"):
      sessions.add(path.extractFilename().changeFileExt(""))
  ok(sessions)

proc listUsers*(a: MarkdownMemoryAdapter): Result[seq[UserSummary], string] =
  ## Lists all users in the paddocks directory.
  if not dirExists(a.paddocksDir):
    let empty: seq[UserSummary] = @[]
    return ok(empty)
  var users: seq[UserSummary]
  for kind, path in walkDir(a.paddocksDir):
    if kind != pcDir:
      continue
    let uid = UserId(path.extractFilename())
    let userMdPath = a.userMdPath(uid)
    let hasProfile = fileExists(userMdPath)
    let userMd = if hasProfile:
      userMdPath.readFileResult.valueOr("")
    else:
      ""
    let preferredName = parseUserField(userMd, "Preferred name")
    let accessField = block:
      let access = parseUserField(userMd, "Access")
      if access.len > 0: access else: "active"
    users.add(UserSummary(
      userId: uid,
      hasProfile: hasProfile,
      preferredName: preferredName,
      access: accessField,
    ))
  ok(users)

proc updateUserField*(a: MarkdownMemoryAdapter; userId: UserId; field, value: string): Result[void, string] =
  ## Updates a named field in USER.md (e.g. "Preferred name", "Access").
  let current = a.userMdPath(userId).readFileResult.valueOr("")
  let label =
    if field.toLowerAscii() == "preferred_name": "Preferred name"
    elif field.toLowerAscii() == "access": "Access"
    else: field
  let newContent = current.setUserFieldText(label, value)
  a.saveUserMd(userId, newContent)

proc isRevoked*(a: MarkdownMemoryAdapter; userId: UserId): Result[bool, string] =
  ## Returns true if the user's access field is "revoked".
  let content = a.userMdPath(userId).readFileResult.valueOr("")
  ok(content.isRevokedUserMd)

## ── Agent identity helpers ──────────────────────────────────────────────────

proc hasIdentity*(a: MarkdownMemoryAdapter; userId: UserId): Result[bool, string] =
  ## True when agent_name is present in PREFERENCES.md.
  let path = a.preferencesMdPath(userId)
  if not fileExists(path):
    return ok(false)
  let content = path.readFileResult.valueOr("")
  for line in content.splitLines():
    if line.startsWith("agent_name"):
      return ok(true)
  ok(false)

proc saveIdentity*(a: MarkdownMemoryAdapter; userId: UserId;
                   traits: PersonalityTraits; name: string): Result[void, string] =
  ## Merges agent identity into PREFERENCES.md (TOML key=value format).
  let ensureResult = a.ensurePaddock(userId)
  if ensureResult.isErr:
    return err(ensureResult.error)
  let path = a.preferencesMdPath(userId)
  let existing = path.readFileResult.valueOr("")
  var lines = existing.splitLines()
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
  let writeResult = path.writeFileResult(lines.join("\n"))
  if writeResult.isErr:
    return err(writeResult.error)
  ok()

proc loadIdentity*(a: MarkdownMemoryAdapter; userId: UserId): Result[(string, PersonalityTraits), string] =
  ## Returns (agent_name, PersonalityTraits) from PREFERENCES.md.
  ## Empty strings when not set.
  let path = a.preferencesMdPath(userId)
  if not fileExists(path):
    return ok(("", PersonalityTraits()))
  let content = path.readFileResult.valueOr("")
  var name = ""
  var traits = PersonalityTraits()
  for line in content.splitLines():
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
  ok((name, traits))

## ── Reminder store ─────────────────────────────────────────────────────────

proc scheduleReminder*(a: MarkdownMemoryAdapter; userId: UserId;
                       channel: string; scheduledAt: int64;
                       message: string): Result[string, string] =
  ## Writes a reminder JSON file. Returns the reminder id.
  let ensureResult = a.ensurePaddock(userId)
  if ensureResult.isErr:
    return err(ensureResult.error)
  let remDir = a.reminderDir(userId)
  try:
    createDir(remDir)
  except CatchableError as e:
    return err("scheduleReminder: createDir: " & e.msg)
  let id = $getTime().toUnix() & "_" & $userId
  let data = %* {
    "id":          id,
    "userId":      $userId,
    "channel":     channel,
    "scheduledAt": scheduledAt,
    "message":     message,
  }
  let path = remDir / id & ".json"
  let writeResult = path.writeFileResult($data)
  if writeResult.isErr:
    return err(writeResult.error)
  ok(id)

proc loadDueReminders*(a: MarkdownMemoryAdapter): Result[seq[JsonNode], string] =
  ## Scans ALL paddocks for reminders whose scheduledAt <= now (UTC seconds).
  let now = getTime().toUnix()
  if not dirExists(a.paddocksDir):
    let empty: seq[JsonNode] = @[]
    return ok(empty)
  var due: seq[JsonNode]
  for _, paddockPath in walkDir(a.paddocksDir):
    let remDir = paddockPath / "reminders"
    if not dirExists(remDir): continue
    for _, rPath in walkDir(remDir):
      if not rPath.endsWith(".json"): continue
      try:
        let content = readFile(rPath)
        let j = parseJson(content)
        if j["scheduledAt"].getBiggestInt() <= now:
          due.add(j)
      except CatchableError:
        discard
  ok(due)

proc deleteReminder*(a: MarkdownMemoryAdapter; userId: UserId; reminderId: string): Result[void, string] =
  ## Deletes a reminder file by id.
  let path = a.reminderDir(userId) / reminderId & ".json"
  if fileExists(path):
    try:
      removeFile(path)
      ok()
    except CatchableError as e:
      err("deleteReminder: " & e.msg)
  else:
    ok()

## ── RuntimePort conversion ──────────────────────────────────────────────────

proc toRuntimePort*(a: MarkdownMemoryAdapter): MemoryRuntimePort =
  MemoryRuntimePort(
    hasProfile: proc(userId: UserId): bool {.gcsafe.} =
      {.cast(gcsafe).}: result = a.hasProfile(userId).valueOr(false)
    ,
    loadContext: proc(userId: UserId): UserContext {.gcsafe.} =
      {.cast(gcsafe).}: result = a.loadContext(userId).valueOr(
        UserContext(userId: userId))
    ,
    saveUserMd: proc(userId: UserId; content: string) {.gcsafe.} =
      {.cast(gcsafe).}: discard a.saveUserMd(userId, content)
    ,
    appendMemory: proc(userId: UserId; text: string) {.gcsafe.} =
      {.cast(gcsafe).}: discard a.appendMemory(userId, text)
    ,
    savePreferences: proc(userId: UserId; content: string) {.gcsafe.} =
      {.cast(gcsafe).}: discard a.savePreferences(userId, content)
    ,
    clearMemory: proc(userId: UserId) {.gcsafe.} =
      {.cast(gcsafe).}: discard a.clearMemory(userId)
    ,
    saveSession: proc(userId: UserId; sessionId: string; history: ConversationHistory)
                      {.gcsafe.} =
      {.cast(gcsafe).}: discard a.saveSession(userId, sessionId, history)
    ,
    saveIdentity: proc(userId: UserId; traits: PersonalityTraits; name: string)
                       {.gcsafe.} =
      {.cast(gcsafe).}: discard a.saveIdentity(userId, traits, name)
    ,
    loadIdentity: proc(userId: UserId): (string, PersonalityTraits) {.gcsafe.} =
      {.cast(gcsafe).}: result = a.loadIdentity(userId).valueOr(("", PersonalityTraits()))
    ,
    paddockDir: proc(userId: UserId): string {.gcsafe.} =
      {.cast(gcsafe).}: result = a.paddockDir(userId)
    ,
    scheduleReminder: proc(userId: UserId; channel: string; scheduledAt: int64; message: string): string
                           {.gcsafe.} =
      {.cast(gcsafe).}: result = a.scheduleReminder(userId, channel, scheduledAt, message).valueOr("")
    ,
    loadDueReminders: proc(): seq[JsonNode] {.gcsafe.} =
      {.cast(gcsafe).}: result = a.loadDueReminders().valueOr(@[])
    ,
    deleteReminder: proc(userId: UserId; reminderId: string) {.gcsafe.} =
      {.cast(gcsafe).}: discard a.deleteReminder(userId, reminderId)
  )
