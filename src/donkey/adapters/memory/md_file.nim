## MdFileAdapter — MemoryPort backed by Markdown files in a paddock directory.
##
## Paddock root:  {paddocksDir}/{userId}/
## Files managed: USER.md, MEMORY.md, PREFERENCES.md
##
## All I/O is synchronous (proc). The domain layer (func) uses the pure
## UserContext value; this adapter is the side-effectful shell.

import std/[json, os, strutils, times]
import ../../core/types
import ../../core/pipeops
import ../../ports/memory
import ../../domain/memory/episode_pure
import ../../domain/memory/lessons_pure
import ../../domain/message
import ../../domain/personality
when defined(withPostgres) or defined(withSqlite):
  import ../../ports/embedding
  import ../embedding/openrouter_embed
  import ./magma_memory_adapter
export json  ## re-export so callers can inspect JsonNode reminder fields
export memory

type
  MdFileAdapter* = object
    paddocksDir*:    string  ## base directory, e.g. ~/.donkey/paddocks
    magmaDsn*:      string   ## optional MAGMA shadow backend DSN
    magmaSqlitePath*: string ## optional MAGMA SQLite backend path
    magmaSqliteVectorPath*: string ## optional sqlite-vec extension path

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
proc resetBootstrap*(a: MdFileAdapter; userId: UserId) {.gcsafe.}
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

when defined(withPostgres) or defined(withSqlite):
  proc buildMagmaEmbedFn(): EmbedFn =
    let embedKey = getEnv("OPENROUTER_API_KEY")
    if embedKey.len == 0:
      return proc(text: string): seq[float32] {.gcsafe.} = @[]
    let embedAdapter = newOpenRouterEmbeddingAdapter(embedKey)
    result = proc(text: string): seq[float32] {.gcsafe.} =
      embedAdapter.embed(text)

  func hasMagmaBackend*(a: MdFileAdapter): bool =
    a.magmaDsn.len > 0 or a.magmaSqlitePath.len > 0

  func magmaBackendName*(a: MdFileAdapter): string =
    if a.magmaSqlitePath.len > 0:
      "magma-sqlite"
    elif a.magmaDsn.len > 0:
      "magma"
    else:
      ""

  proc newMagmaAdapter*(a: MdFileAdapter): MagmaMemoryAdapter {.gcsafe, raises: [].} =
    try:
      when defined(withSqlite):
        if a.magmaSqlitePath.len > 0:
          let dbDir = parentDir(a.magmaSqlitePath)
          if dbDir.len > 0:
            createDir(dbDir)
          return newSqliteMagmaMemoryAdapter(
            a.magmaSqlitePath,
            buildMagmaEmbedFn(),
            vectorExtensionPath = a.magmaSqliteVectorPath,
          )
      when defined(withPostgres):
        if a.magmaDsn.len > 0:
          return newMagmaMemoryAdapter(a.magmaDsn, buildMagmaEmbedFn())
      nil
    except Exception:
      nil

  template withMagmaShadow(a: MdFileAdapter; body: untyped) =
    if not a.hasMagmaBackend:
      discard
    else:
      try:
        let magma {.inject.} = a.newMagmaAdapter()
        if magma != nil:
          body
      except CatchableError:
        discard

  func hasContextContent(ctx: UserContext): bool =
    ctx.userMd.len > 0 or ctx.memoryMd.len > 0 or ctx.preferencesMd.len > 0

  func mergeContextMissing(graphCtx, markdownCtx: UserContext): UserContext =
    result = graphCtx
    if result.userMd.strip.len == 0:
      result.userMd = markdownCtx.userMd
    if result.preferencesMd.strip.len == 0:
      result.preferencesMd = markdownCtx.preferencesMd
    if result.memoryMd.strip.len == 0:
      result.memoryMd = markdownCtx.memoryMd

  proc importMarkdownContext(magma: MagmaMemoryAdapter; ctx: UserContext) =
    if ctx.userMd.strip.len > 0:
      magma.saveUserMd(ctx.userId, ctx.userMd)
    if ctx.preferencesMd.strip.len > 0:
      magma.savePreferences(ctx.userId, ctx.preferencesMd)
    for chunk in ctx.memoryMd.split("\n\n"):
      let trimmed = chunk.strip
      if trimmed.len > 0:
        magma.appendMemory(ctx.userId, trimmed)

# ── path helpers ──────────────────────────────────────────────────────────────

func paddockDir*(a: MdFileAdapter; userId: UserId): string =
  a.paddocksDir / $userId

func userMdPath*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / "USER.md"

func memoryMdPath*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / "MEMORY.md"

func preferencesMdPath*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / "PREFERENCES.md"

func heartbeatMdPath*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / HeartbeatFileName

proc loadMarkdownContext(a: MdFileAdapter; userId: UserId): UserContext =
  UserContext(
    userId:        userId,
    userMd:        if fileExists(a.userMdPath(userId)): readFile(a.userMdPath(userId)) else: "",
    memoryMd:      if fileExists(a.memoryMdPath(userId)): readFile(a.memoryMdPath(userId)) else: "",
    preferencesMd: if fileExists(a.preferencesMdPath(userId)): readFile(a.preferencesMdPath(userId)) else: "",
  )

# ── helpers ───────────────────────────────────────────────────────────────────

proc readOrEmpty(path: string): string =
  if fileExists(path): readFile(path) else: ""

proc mergeIdentityPrefs(content: string; traits: PersonalityTraits; name: string): string =
  var lines = content.splitLines()
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
  lines.join("\n")

proc parseIdentityPrefs(content: string): (string, PersonalityTraits) =
  var name   = ""
  var traits = PersonalityTraits()
  for line in content.splitLines():
    let parts = line.split('=', 1)
    if parts.len != 2: continue
    let k = parts[0].strip
    let v = parts[1].strip.strip(chars = {'"'})
    case k
    of "agent_name":       name              = v
    of "agent_energy":     traits.energy     = v
    of "agent_tone":       traits.tone       = v
    of "agent_length":     traits.length     = v
    of "agent_initiative": traits.initiative = v
    else: discard
  (name, traits)

when defined(withPostgres) or defined(withSqlite):
  proc runtimeHasProfile(a: MdFileAdapter; userId: UserId): bool =
    if a.hasMagmaBackend:
      try:
        let magma = a.newMagmaAdapter()
        return magma.hasProfile(userId) or a.hasProfile(userId)
      except CatchableError:
        discard
    a.hasProfile(userId)

  proc runtimeSaveUserMd(a: MdFileAdapter; userId: UserId; content: string) =
    if a.hasMagmaBackend:
      try:
        let magma = a.newMagmaAdapter()
        magma.saveUserMd(userId, content)
        return
      except CatchableError:
        discard
    a.saveUserMd(userId, content)

  proc runtimeAppendMemory(a: MdFileAdapter; userId: UserId; text: string) =
    if a.hasMagmaBackend:
      try:
        let magma = a.newMagmaAdapter()
        magma.appendMemory(userId, text)
        return
      except CatchableError:
        discard
    a.appendMemory(userId, text)

  proc runtimeSavePreferences(a: MdFileAdapter; userId: UserId; content: string) =
    if a.hasMagmaBackend:
      try:
        let magma = a.newMagmaAdapter()
        magma.savePreferences(userId, content)
        return
      except CatchableError:
        discard
    a.savePreferences(userId, content)

  proc runtimeClearMemory(a: MdFileAdapter; userId: UserId) =
    if a.hasMagmaBackend:
      try:
        let magma = a.newMagmaAdapter()
        magma.clearMemory(userId)
        return
      except CatchableError:
        discard
    a.clearMemory(userId)

  proc runtimeResetBootstrap(a: MdFileAdapter; userId: UserId) =
    a.resetBootstrap(userId)

  proc runtimeSaveIdentity(a: MdFileAdapter; userId: UserId;
                           traits: PersonalityTraits; name: string) =
    if a.hasMagmaBackend:
      try:
        let current = a.loadContext(userId).preferencesMd
        a.runtimeSavePreferences(userId, mergeIdentityPrefs(current, traits, name))
        return
      except CatchableError:
        discard
    a.saveIdentity(userId, traits, name)

  proc runtimeLoadIdentity(a: MdFileAdapter; userId: UserId): (string, PersonalityTraits) =
    if a.hasMagmaBackend:
      try:
        let current = a.loadContext(userId).preferencesMd
        return parseIdentityPrefs(current)
      except CatchableError:
        discard
    a.loadIdentity(userId)

proc appendExtractedMemoryF1(a: MdFileAdapter; userId: UserId;
                                text: string): Result[void, string] {.raises: [].} =
  try:
    a.appendMemory(userId, text)
    ok()
  except Exception as e:
    err("append extracted memory: " & e.msg)

proc saveEpisodeF1(a: MdFileAdapter; userId: UserId;
                   episode: EpisodeJournal): Result[void, string] {.raises: [].} =
  try:
    a.appendMemory(userId, "\n## Episode: " & episode.title & "\n" &
                   episode.summary & "\n")
    ok()
  except Exception as e:
    err("save episode: " & e.msg)

proc extractLessonsF1(a: MdFileAdapter; userId: UserId;
                      episodes: seq[EpisodeJournal]): Result[int, string] {.raises: [].} =
  var count = 0
  try:
    for episode in episodes:
      for lesson in extractLessonsFromEpisode(episode, maxLessons = 2):
        a.appendMemory(userId, "- Lesson: " & lesson.text & "\n")
        inc count
    ok(count)
  except Exception as e:
    err("extract lessons: " & e.msg)

proc toRuntimePort*(a: MdFileAdapter): MemoryRuntimePort =
  when defined(withPostgres) or defined(withSqlite):
    if a.hasMagmaBackend:
      return MemoryRuntimePort(
        hasProfile:       proc(userId: UserId): bool {.gcsafe.} = a.runtimeHasProfile(userId),
        loadContext:      proc(userId: UserId): UserContext {.gcsafe.} = a.loadContext(userId),
        saveUserMd:       proc(userId: UserId; content: string) {.gcsafe.} = a.runtimeSaveUserMd(userId, content),
        appendMemory:     proc(userId: UserId; text: string) {.gcsafe.} = a.runtimeAppendMemory(userId, text),
        savePreferences:  proc(userId: UserId; content: string) {.gcsafe.} = a.runtimeSavePreferences(userId, content),
        clearMemory:      proc(userId: UserId) {.gcsafe.} = a.runtimeClearMemory(userId),
        resetBootstrap:   proc(userId: UserId) {.gcsafe.} = a.runtimeResetBootstrap(userId),
        saveSession:      proc(userId: UserId; sessionId: string; history: ConversationHistory) {.gcsafe.} =
                            a.saveSession(userId, sessionId, history),
        saveIdentity:     proc(userId: UserId; traits: PersonalityTraits; name: string) {.gcsafe.} =
                            a.runtimeSaveIdentity(userId, traits, name),
        loadIdentity:     proc(userId: UserId): (string, PersonalityTraits) {.gcsafe.} =
                            a.runtimeLoadIdentity(userId),
        paddockDir:       proc(userId: UserId): string {.gcsafe.} = a.paddockDir(userId),
        scheduleReminder: proc(userId: UserId; channel: string; scheduledAt: int64; message: string): string {.gcsafe.} =
                            a.scheduleReminder(userId, channel, scheduledAt, message),
        loadDueReminders: proc(): seq[JsonNode] {.gcsafe.} = a.loadDueReminders(),
        deleteReminder:   proc(userId: UserId; reminderId: string) {.gcsafe.} = a.deleteReminder(userId, reminderId),
        appendExtractedMemory: proc(userId: UserId; text: string): Result[void, string]
                                  {.gcsafe, raises: [].} =
          try:
            let magma = a.newMagmaAdapter()
            if magma == nil:
              return err("MAGMA backend unavailable")
            magma.appendMemory(userId, text)
            ok()
          except Exception as e:
            err("append extracted memory: " & e.msg),
        saveEpisode: proc(userId: UserId; episode: EpisodeJournal): Result[void, string]
                       {.gcsafe, raises: [].} =
          try:
            let magma = a.newMagmaAdapter()
            if magma == nil:
              return err("MAGMA backend unavailable")
            magma.saveEpisode(userId, episode)
            ok()
          except Exception as e:
            err("save episode: " & e.msg),
        extractLessons: proc(userId: UserId; episodes: seq[EpisodeJournal]): Result[int, string]
                          {.gcsafe, raises: [].} =
          try:
            let magma = a.newMagmaAdapter()
            if magma == nil:
              return err("MAGMA backend unavailable")
            ok(magma.extractAndSaveLessons(userId, episodes, @[],
                                           maxLessonsPerSource = 2))
          except Exception as e:
            err("extract lessons: " & e.msg),
      )
  MemoryRuntimePort(
    hasProfile:       proc(userId: UserId): bool {.gcsafe.} = a.hasProfile(userId),
    loadContext:      proc(userId: UserId): UserContext {.gcsafe.} = a.loadContext(userId),
    saveUserMd:       proc(userId: UserId; content: string) {.gcsafe.} = a.saveUserMd(userId, content),
    appendExtractedMemory: proc(userId: UserId; text: string): Result[void, string]
                              {.gcsafe, raises: [].} =
                            appendExtractedMemoryF1(a, userId, text),
    saveEpisode: proc(userId: UserId; episode: EpisodeJournal): Result[void, string]
                   {.gcsafe, raises: [].} =
                   saveEpisodeF1(a, userId, episode),
    extractLessons: proc(userId: UserId; episodes: seq[EpisodeJournal]): Result[int, string]
                      {.gcsafe, raises: [].} =
                      extractLessonsF1(a, userId, episodes),
    appendMemory:     proc(userId: UserId; text: string) {.gcsafe.} = a.appendMemory(userId, text),
    savePreferences:  proc(userId: UserId; content: string) {.gcsafe.} = a.savePreferences(userId, content),
    clearMemory:      proc(userId: UserId) {.gcsafe.} = a.clearMemory(userId),
    resetBootstrap:   proc(userId: UserId) {.gcsafe.} = a.resetBootstrap(userId),
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
  if not fileExists(a.heartbeatMdPath(userId)):
    writeFile(a.heartbeatMdPath(userId), defaultHeartbeatMd())

# ── MemoryPort implementation ─────────────────────────────────────────────────

proc hasProfile*(a: MdFileAdapter; userId: UserId): bool =
  fileExists(a.userMdPath(userId))

proc loadContext*(a: MdFileAdapter; userId: UserId): UserContext =
  a.ensurePaddock(userId)
  when defined(withPostgres) or defined(withSqlite):
    if a.hasMagmaBackend:
      try:
        let magma = a.newMagmaAdapter()
        let graphCtx = magma.loadContext(userId)
        let markdownCtx = a.loadMarkdownContext(userId)
        if graphCtx.hasContextContent:
          if graphCtx.userMd.strip.len == 0 and markdownCtx.userMd.strip.len > 0:
            magma.saveUserMd(userId, markdownCtx.userMd)
          if graphCtx.preferencesMd.strip.len == 0 and markdownCtx.preferencesMd.strip.len > 0:
            magma.savePreferences(userId, markdownCtx.preferencesMd)
          if graphCtx.memoryMd.strip.len == 0 and markdownCtx.memoryMd.strip.len > 0:
            for chunk in markdownCtx.memoryMd.split("\n\n"):
              let trimmed = chunk.strip
              if trimmed.len > 0:
                magma.appendMemory(userId, trimmed)
          return mergeContextMissing(graphCtx, markdownCtx)
        if markdownCtx.hasContextContent:
          magma.importMarkdownContext(markdownCtx)
          return markdownCtx
      except CatchableError:
        discard
  a.loadMarkdownContext(userId)

proc saveUserMd*(a: MdFileAdapter; userId: UserId; content: string) =
  a.ensurePaddock(userId)
  writeFile(a.userMdPath(userId), content)
  when defined(withPostgres) or defined(withSqlite):
    a.withMagmaShadow:
      magma.saveUserMd(userId, content)

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

# ── DM allowlist ──────────────────────────────────────────────────────────────

func dmAllowlistPath*(a: MdFileAdapter): string =
  ## Instance-level allowlist, stored outside the paddocks.
  parentDir(a.paddocksDir) / "state" / "dm_allowlist.txt"

proc isDmAllowed*(a: MdFileAdapter; userId: UserId): bool =
  ## Returns true when the user id is explicitly present in the allowlist.
  let path = a.dmAllowlistPath()
  if not fileExists(path):
    return false
  try:
    for line in lines(path):
      if line.strip == $userId:
        return true
  except CatchableError:
    discard
  false

proc addDmAllowed*(a: MdFileAdapter; userId: UserId): Result[void, string] =
  let path = a.dmAllowlistPath()
  let rawId = $userId
  if rawId.len == 0 or rawId.strip != rawId or '\n' in rawId or '\r' in rawId:
    return err("dm allowlist add failed: invalid user id")
  if a.isDmAllowed(userId):
    return ok()
  try:
    createDir(parentDir(path))
    var f = open(path, fmAppend)
    defer: f.close()
    f.writeLine($userId)
    ok()
  except CatchableError as e:
    err("dm allowlist add failed: " & e.msg)

proc removeDmAllowed*(a: MdFileAdapter; userId: UserId): Result[void, string] =
  let path = a.dmAllowlistPath()
  if not fileExists(path):
    return ok()
  try:
    var kept: seq[string] = @[]
    for line in lines(path):
      let value = line.strip
      if value.len > 0 and value != $userId:
        kept.add(value)
    let tmp = path & ".tmp"
    writeFile(tmp, if kept.len > 0: kept.join("\n") & "\n" else: "")
    moveFile(tmp, path)
    ok()
  except CatchableError as e:
    err("dm allowlist remove failed: " & e.msg)

proc appendMemory*(a: MdFileAdapter; userId: UserId; text: string) =
  a.ensurePaddock(userId)
  let path = a.memoryMdPath(userId)
  let existing = readOrEmpty(path)
  let sep = if existing.len > 0 and not existing.endsWith("\n"): "\n" else: ""
  writeFile(path, existing & sep & text)
  when defined(withPostgres) or defined(withSqlite):
    a.withMagmaShadow:
      magma.appendMemory(userId, text)

proc savePreferences*(a: MdFileAdapter; userId: UserId; content: string) =
  a.ensurePaddock(userId)
  writeFile(a.preferencesMdPath(userId), content)
  when defined(withPostgres) or defined(withSqlite):
    a.withMagmaShadow:
      magma.savePreferences(userId, content)

proc clearMemory*(a: MdFileAdapter; userId: UserId) =
  ## Clears MEMORY.md for this user (irreversible).
  let path = a.memoryMdPath(userId)
  if fileExists(path): writeFile(path, "")
  when defined(withPostgres) or defined(withSqlite):
    a.withMagmaShadow:
      magma.clearMemory(userId)

proc resetBootstrap*(a: MdFileAdapter; userId: UserId) =
  for path in [a.userMdPath(userId), a.preferencesMdPath(userId)]:
    if fileExists(path):
      try:
        removeFile(path)
      except CatchableError:
        discard
  when defined(withPostgres) or defined(withSqlite):
    a.withMagmaShadow:
      magma.resetBootstrap(userId)

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
  writeFile(a.preferencesMdPath(userId),
            mergeIdentityPrefs(readOrEmpty(a.preferencesMdPath(userId)), traits, name))

proc loadIdentity*(a: MdFileAdapter; userId: UserId): (string, PersonalityTraits) =
  ## Returns (agent_name, PersonalityTraits) from PREFERENCES.md.
  ## Empty strings when not set.
  let path = a.preferencesMdPath(userId)
  if not fileExists(path): return ("", PersonalityTraits())
  parseIdentityPrefs(readFile(path))

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
      except CatchableError:
        let errMsg = getCurrentExceptionMsg()
        stderr.writeLine("WARN reminder.parse: failed to parse reminder file " &
                         rPath & " reason=" & errMsg)

proc deleteReminder*(a: MdFileAdapter; userId: UserId; reminderId: string) =
  ## Deletes a reminder file by id.
  let path = a.reminderDir(userId) / reminderId & ".json"
  if fileExists(path): removeFile(path)
