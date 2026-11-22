## MdFileAdapter — MemoryPort backed by Markdown files in a paddock directory.
##
## Paddock root:  {paddocksDir}/{userId}/
## Files managed: USER.md, MEMORY.md, PREFERENCES.md
##
## All I/O is synchronous (proc). The domain layer (func) uses the pure
## UserContext value; this adapter is the side-effectful shell.

import std/[algorithm, json, os, strutils, times]
import ../../core/types
import ../../core/pipeops
import ../../config/environment
import ../../ports/memory
import ../filesystem/paths
import ../../domain/memory/episode_pure
import ../../domain/memory/session_search_pure
import ../../domain/memory/provenance_pure
import ../../domain/memory/transcript_pure
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
    magmaEnv*:      Environment ## what MAGMA reads from the environment snapshot
                                ## (see `magmaEnvironment`)

  UserSummary* = object
    userId*:      UserId
    hasProfile*:  bool
    preferredName*: string
    access*:      string

const
  MagmaEnvNames = ["OPENROUTER_API_KEY", "ZAI_API_KEY", "ZAI_CODING_API_KEY",
                   "ZHIPU_API_KEY", "MINIMAX_API_KEY"]
    ## Embedding and rerank keys; the knobs are the `DONKEY_MEMORY_*` names.

func magmaEnvironment*(env: Environment): Environment =
  ## The part of the snapshot MAGMA reads: embedding and rerank keys and the
  ## `DONKEY_MEMORY_*` search and rerank knobs. A subset, because the adapter
  ## is copied by value into many closures.
  for (name, value) in env.pairs:
    if name in MagmaEnvNames or name.startsWith("DONKEY_MEMORY_"):
      result = result.with(name, value)

const
  ## Search is a bounded synchronous read on purpose: 8 MiB total keeps it in
  ## the low-millisecond range for an interactive tool. Raise these caps only
  ## together with moving collection to a worker/helper process.
  SessionSearchMaxFiles* = 50
  SessionSearchMaxFileBytes* = 512 * 1024
  SessionSearchMaxTotalBytes* = 8 * 1024 * 1024
  SessionSearchMaxRecords* = 2000
  SessionSearchMaxNodeContentBytes* = 4096
  ## Part of an existing transcript compared against the live history when
  ## saving. The history holds a few dozen messages; 2 MiB of tail covers it.
  SessionTranscriptAlignBytes* = 2 * 1024 * 1024

proc hasProfile*(a: MdFileAdapter; userId: UserId): bool {.gcsafe.}
proc loadContext*(a: MdFileAdapter; userId: UserId): UserContext {.gcsafe.}
proc saveUserMd*(a: MdFileAdapter; userId: UserId;
                 content: string): Result[void, string]
                 {.discardable, gcsafe, raises: [].}
proc appendMemory*(a: MdFileAdapter; userId: UserId; text: string;
                   origin = MemoryOrigin()): Result[void, string]
                   {.discardable, gcsafe, raises: [].}
proc savePreferences*(a: MdFileAdapter; userId: UserId;
                      content: string): Result[void, string]
                      {.discardable, gcsafe, raises: [].}
proc clearMemory*(a: MdFileAdapter; userId: UserId): Result[void, string]
                  {.discardable, gcsafe, raises: [].}
proc resetBootstrap*(a: MdFileAdapter; userId: UserId): Result[void, string]
                     {.discardable, gcsafe, raises: [].}
proc saveSession*(a: MdFileAdapter; userId: UserId;
                  sessionId: string; history: ConversationHistory) {.gcsafe.}
proc saveIdentity*(a: MdFileAdapter; userId: UserId;
                   traits: PersonalityTraits; name: string): Result[void, string]
                   {.discardable, gcsafe, raises: [].}
proc loadIdentity*(a: MdFileAdapter; userId: UserId): (string, PersonalityTraits) {.gcsafe.}
func paddockDir*(a: MdFileAdapter; userId: UserId): string {.gcsafe.}
proc scheduleReminder*(a: MdFileAdapter; userId: UserId;
                       channel: string; scheduledAt: int64;
                       message: string): string {.gcsafe, raises: [CatchableError].}
proc loadDueReminders*(a: MdFileAdapter): seq[JsonNode] {.gcsafe.}
proc deleteReminder*(a: MdFileAdapter; userId: UserId; reminderId: string) {.gcsafe.}
proc searchSessions*(a: MdFileAdapter; userId: UserId;
                     query: string; limit: int;
                     includeMemory = true): Result[seq[SessionHit], string]
                     {.gcsafe, raises: [].}
proc sessionSearchRecords(a: MdFileAdapter; userId: UserId;
                          includeMemory: bool):
                          Result[seq[SessionSearchRecord], string]
                          {.gcsafe, raises: [].}

when defined(withPostgres) or defined(withSqlite):
  proc buildMagmaEmbedFn(env: Environment): EmbedFn =
    let embedKey = env.get("OPENROUTER_API_KEY")
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
            buildMagmaEmbedFn(a.magmaEnv),
            vectorExtensionPath = a.magmaSqliteVectorPath,
          )
      when defined(withPostgres):
        if a.magmaDsn.len > 0:
          return newMagmaMemoryAdapter(a.magmaDsn, buildMagmaEmbedFn(a.magmaEnv))
      nil
    except Exception:  ## effect boundary: callee raises are unannotated
      nil

  type GraphHandle = MagmaMemoryAdapter

  proc importMarkdownInto*(magma: MagmaMemoryAdapter;
                           ctx: UserContext): Result[void, string] =
    ## Imports the Markdown files of a paddock into an empty graph, all or
    ## nothing. Memories go first, because their writes are the ones that
    ## report failure; if one fails, what was written is removed, so the
    ## graph is empty again and the next access retries the whole import. The
    ## same holds for the profile and the preferences. A
    ## partial import left in place would make the graph look populated and
    ## the rest of the paddock would never be read.
    for chunk in ctx.memoryMd.split("\n\n"):
      let trimmed = chunk.strip
      if trimmed.len == 0:
        continue
      let stored = magma.appendMemory(ctx.userId, trimmed,
                                      MemoryOrigin(source: msMarkdown))
      if stored.isErr:
        magma.clearMemory(ctx.userId)
        return err("markdown import: " & stored.error)
    var written = Result[void, string].ok()
    if ctx.userMd.strip.len > 0:
      written = magma.saveUserMd(ctx.userId, ctx.userMd)
    if written.isOk and ctx.preferencesMd.strip.len > 0:
      written = magma.savePreferences(ctx.userId, ctx.preferencesMd)
    if written.isErr:
      magma.clearMemory(ctx.userId)
      magma.resetBootstrap(ctx.userId)
      return err("markdown import: " & written.error)
    ok()
else:
  type GraphHandle = ref object
    ## Stand-in for the graph adapter in builds without a graph backend.

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

func hasContextContent(ctx: UserContext): bool =
  ctx.userMd.len > 0 or ctx.memoryMd.len > 0 or ctx.preferencesMd.len > 0

proc loadMarkdownContext*(a: MdFileAdapter; userId: UserId): UserContext =
  ## What the Markdown files of the paddock say, whatever the store is. With
  ## MAGMA this is the export, or files edited for an explicit import.
  UserContext(
    userId:        userId,
    userMd:        if fileExists(a.userMdPath(userId)): readFile(a.userMdPath(userId)) else: "",
    memoryMd:      if fileExists(a.memoryMdPath(userId)): readFile(a.memoryMdPath(userId)) else: "",
    preferencesMd: if fileExists(a.preferencesMdPath(userId)): readFile(a.preferencesMdPath(userId)) else: "",
  )

# ── helpers ───────────────────────────────────────────────────────────────────

type
  GraphAccess = enum
    gaNone         ## no graph configured: the Markdown files are the store
    gaUnavailable  ## a graph is configured but cannot be opened or read
    gaReady        ## the graph is the store; the files are an export of it

when defined(withPostgres) or defined(withSqlite):
  proc openGraph(a: MdFileAdapter; userId: UserId):
                 tuple[access: GraphAccess, magma: GraphHandle]
                 {.gcsafe, raises: [].} =
    ## The single way in to the graph. Every operation of this adapter goes
    ## through here, so three rules hold everywhere:
    ##
    ## - a paddock that predates the graph is imported before anything else
    ##   touches the graph. Otherwise a first write would make the graph look
    ##   populated and the rest of the old paddock would never be imported;
    ## - the import happens only after a read that succeeded and found
    ##   nothing. A graph that cannot be read is unavailable, never empty:
    ##   importing then would lay an old export over newer data;
    ## - an import that fails leaves the graph empty and the graph
    ##   unavailable for this call, so nothing is built on half a paddock.
    if not a.hasMagmaBackend:
      return (gaNone, nil)
    try:
      let magma = a.newMagmaAdapter()
      if magma == nil:
        return (gaUnavailable, nil)
      let populated = magma.hasContext(userId)
      if populated.isErr:
        return (gaUnavailable, nil)
      if not populated.get():
        let markdownCtx = a.loadMarkdownContext(userId)
        if markdownCtx.hasContextContent and
           importMarkdownInto(magma, markdownCtx).isErr:
          return (gaUnavailable, nil)
      (gaReady, magma)
    except Exception:  ## effect boundary: callee raises are unannotated
      (gaUnavailable, nil)
else:
  proc openGraph(a: MdFileAdapter; userId: UserId):
                 tuple[access: GraphAccess, magma: GraphHandle]
                 {.gcsafe, raises: [].} =
    (gaNone, nil)

const GraphUnavailableError =
  "memory graph is configured but unavailable; nothing was written"

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
  proc searchSessionsWithMagma(a: MdFileAdapter; userId: UserId;
                               query: string; limit: int;
                               includeMemory = true):
                               Result[seq[SessionHit], string]
                               {.gcsafe, raises: [].} =
    ## MEMORY.md is an export of the memory nodes read below; searching both
    ## would return every memory twice.
    let baseRecords = ? a.sessionSearchRecords(userId, includeMemory = false)
    var records = baseRecords
    if includeMemory:
      ## Through openGraph, so a paddock that predates the graph is imported
      ## before its first search, and an unavailable graph is an error.
      let (access, magma) = a.openGraph(userId)
      if access != gaReady:
        return err("MAGMA backend unavailable for session search")
      let remaining = max(0, SessionSearchMaxRecords - records.len)
      if remaining > 0:
        try:
          ## Memories only, filtered in the query: other node types would
          ## be returned as memories and would use up the limit.
          let nodes = magma.graph.listNodesLimited(
            $userId, NtMemory, remaining, SessionSearchMaxNodeContentBytes)
          if nodes.isErr:
            return err(nodes.error)
          for node in nodes.get():
            if node.content.len == 0:
              continue
            records.add(SessionSearchRecord(
              sessionId: "memory",
              kind: shkMemory,
              role: "memory",
              text: node.content,
              timestampMs: node.timestamp * 1000,
            ))
        except Exception as e:  ## effect boundary: callee raises are unannotated
          return err("MAGMA search failed: " & e.msg)
    ok(rankSessionRecords(records, query, epochMs(), limit))

proc saveEpisodeF1(a: MdFileAdapter; userId: UserId;
                   episode: EpisodeJournal): Result[void, string] {.raises: [].} =
  try:
    let marker = "<!-- episode:" & episode.id & " -->"
    let existing =
      if fileExists(a.memoryMdPath(userId)): readFile(a.memoryMdPath(userId))
      else: ""
    if marker in existing:
      return ok()
    a.appendMemory(userId, "\n" & marker & "\n## Episode: " & episode.title &
                   "\n" & episode.summary & "\n")
  except CatchableError as e:
    err("save episode: " & e.msg)

proc saveEpisode(a: MdFileAdapter; userId: UserId;
                 episode: EpisodeJournal): Result[void, string] {.raises: [].} =
  let (access, magma) = a.openGraph(userId)
  case access
  of gaNone:
    saveEpisodeF1(a, userId, episode)
  of gaUnavailable:
    err(GraphUnavailableError)
  of gaReady:
    when defined(withPostgres) or defined(withSqlite):
      try:
        magma.saveEpisode(userId, episode)
      except Exception as e:  ## effect boundary: callee raises are unannotated
        err("save episode: " & e.msg)
    else:
      err(GraphUnavailableError)

proc toRuntimePort*(a: MdFileAdapter): MemoryRuntimePort =
  ## One set of operations for both modes: each of them decides between the
  ## graph and the files. Only the origin-aware append is specific to the
  ## graph, because MEMORY.md has no place to keep an origin.
  result = MemoryRuntimePort(
    hasProfile:       proc(userId: UserId): bool {.gcsafe.} = a.hasProfile(userId),
    loadContext:      proc(userId: UserId): UserContext {.gcsafe.} = a.loadContext(userId),
    saveUserMd:       proc(userId: UserId; content: string): Result[void, string]
                        {.gcsafe, raises: [].} =
                        a.saveUserMd(userId, content),
    appendExtractedMemory: proc(userId: UserId; text: string): Result[void, string]
                              {.gcsafe, raises: [].} =
                            a.appendMemory(userId, text,
                                           MemoryOrigin(source: msConsolidation)),
    saveEpisode: proc(userId: UserId; episode: EpisodeJournal): Result[void, string]
                   {.gcsafe, raises: [].} =
                   a.saveEpisode(userId, episode),
    appendMemory:     proc(userId: UserId; text: string): Result[void, string]
                        {.gcsafe, raises: [].} =
                        a.appendMemory(userId, text),
    savePreferences:  proc(userId: UserId; content: string): Result[void, string]
                        {.gcsafe, raises: [].} =
                        a.savePreferences(userId, content),
    clearMemory:      proc(userId: UserId): Result[void, string]
                        {.gcsafe, raises: [].} = a.clearMemory(userId),
    resetBootstrap:   proc(userId: UserId): Result[void, string]
                        {.gcsafe, raises: [].} = a.resetBootstrap(userId),
    saveSession:      proc(userId: UserId; sessionId: string; history: ConversationHistory) {.gcsafe.} =
                        a.saveSession(userId, sessionId, history),
    saveIdentity:     proc(userId: UserId; traits: PersonalityTraits;
                           name: string): Result[void, string]
                        {.gcsafe, raises: [].} =
                        a.saveIdentity(userId, traits, name),
    loadIdentity:     proc(userId: UserId): (string, PersonalityTraits) {.gcsafe.} = a.loadIdentity(userId),
    searchSessions:   proc(userId: UserId; query: string; limit: int;
                           includeMemory: bool):
                           Result[seq[SessionHit], string]
                           {.gcsafe, raises: [].} =
                        a.searchSessions(userId, query, limit, includeMemory),
    paddockDir:       proc(userId: UserId): string {.gcsafe.} = a.paddockDir(userId),
    scheduleReminder: proc(userId: UserId; channel: string; scheduledAt: int64; message: string): string {.gcsafe, raises: [CatchableError].} =
                        a.scheduleReminder(userId, channel, scheduledAt, message),
    loadDueReminders: proc(): seq[JsonNode] {.gcsafe.} = a.loadDueReminders(),
    deleteReminder:   proc(userId: UserId; reminderId: string) {.gcsafe.} = a.deleteReminder(userId, reminderId),
  )
  when defined(withPostgres) or defined(withSqlite):
    if a.hasMagmaBackend:
      result.appendMemoryFrom =
        proc(userId: UserId; text: string; origin: MemoryOrigin): Result[void, string]
            {.gcsafe, raises: [].} =
          a.appendMemory(userId, text, origin)

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

proc securePaddockTree(a: MdFileAdapter; userId: UserId) =
  ## One-time migration for paddocks created before permissions were tightened.
  ## Best effort: a permissions failure must not make the paddock unreadable.
  ## The marker is only written when every managed file was protected, so a
  ## later load retries after a partial failure.
  when defined(posix):
    try:
      let marker = a.paddockDir(userId) / ".permissions_v2"
      if fileExists(marker):
        return
      var allOk = true
      for path in [a.userMdPath(userId), a.memoryMdPath(userId),
                   a.preferencesMdPath(userId), a.heartbeatMdPath(userId)]:
        if secureFile(path).isErr:
          allOk = false
      for dirName in ["sessions", "attachments"]:
        let dir = a.paddockDir(userId) / dirName
        if dirExists(dir):
          for kind, path in walkDir(dir, checkDir = true):
            if kind == pcFile:
              if secureFile(path).isErr:
                allOk = false
      if allOk:
        writeFile(marker, "permissions v1\n")
        if secureFile(marker).isErr:
          removeFile(marker)
    except CatchableError:
      discard

proc ensurePaddock*(a: MdFileAdapter; userId: UserId) =
  ## Creates the paddock directory tree if it does not exist, and keeps
  ## memory/session/attachment files private to the service user.
  discard secureDir(a.paddockDir(userId))
  discard secureDir(a.paddockDir(userId) / "sessions")
  discard secureDir(a.paddockDir(userId) / "attachments")
  if not fileExists(a.heartbeatMdPath(userId)):
    writeFile(a.heartbeatMdPath(userId), defaultHeartbeatMd())
  discard secureFile(a.heartbeatMdPath(userId))
  securePaddockTree(a, userId)

# ── MemoryPort implementation ─────────────────────────────────────────────────

proc storedUserMd(a: MdFileAdapter; userId: UserId): Result[string, string] =
  ## USER.md for a caller that will write back what it read. Unlike
  ## currentUserMd there is no fallback to the last export: merging over an
  ## old export and saving the result would put stale data back in the graph.
  let (access, magma) = a.openGraph(userId)
  case access
  of gaUnavailable:
    err(GraphUnavailableError)
  of gaReady:
    when defined(withPostgres) or defined(withSqlite):
      magma.readUserMd(userId)
    else:
      err(GraphUnavailableError)
  of gaNone:
    ok(readOrEmpty(a.userMdPath(userId)))

proc storedPreferences*(a: MdFileAdapter; userId: UserId): Result[string, string] =
  ## PREFERENCES.md for a caller that will write back what it read; same
  ## rule as storedUserMd.
  let (access, magma) = a.openGraph(userId)
  case access
  of gaUnavailable:
    err(GraphUnavailableError)
  of gaReady:
    when defined(withPostgres) or defined(withSqlite):
      magma.readPreferences(userId)
    else:
      err(GraphUnavailableError)
  of gaNone:
    ok(readOrEmpty(a.preferencesMdPath(userId)))

proc currentUserMd(a: MdFileAdapter; userId: UserId): string =
  ## USER.md as the store holds it: the graph copy with MAGMA, the file
  ## otherwise, or the last export when the graph is unavailable.
  a.storedUserMd(userId).valueOr(readOrEmpty(a.userMdPath(userId)))

proc currentPreferences(a: MdFileAdapter; userId: UserId): string =
  ## PREFERENCES.md as the store holds it; same rule as currentUserMd.
  a.storedPreferences(userId).valueOr(readOrEmpty(a.preferencesMdPath(userId)))

proc hasProfile*(a: MdFileAdapter; userId: UserId): bool =
  let (access, magma) = a.openGraph(userId)
  when defined(withPostgres) or defined(withSqlite):
    if access == gaReady:
      return magma.hasProfile(userId)
  fileExists(a.userMdPath(userId))

proc loadContext*(a: MdFileAdapter; userId: UserId): UserContext =
  ## With MAGMA the context is the graph's. The Markdown files are read in
  ## two cases only: the graph holds nothing of this user yet (openGraph
  ## imports a paddock that predates the graph, once, tagged as markdown), or
  ## the graph cannot be read. In the second case the last export is returned
  ## as it is and nothing is written to the graph.
  a.ensurePaddock(userId)
  let (access, magma) = a.openGraph(userId)
  when defined(withPostgres) or defined(withSqlite):
    if access == gaReady:
      let graphCtx = magma.readContext(userId)
      if graphCtx.isOk:
        return graphCtx.get()
  a.loadMarkdownContext(userId)

proc exportFile(path, content: string) =
  writeFile(path, content)
  discard secureFile(path)

proc tryExport(path, content: string) {.raises: [].} =
  ## Refreshes one exported file after the graph took the write. The export
  ## is derived from the graph and can be rebuilt with `ctl memory export`,
  ## so failing to refresh it does not undo or fail the write itself.
  try:
    exportFile(path, content)
  except CatchableError:
    discard

proc saveUserMd*(a: MdFileAdapter; userId: UserId;
                 content: string): Result[void, string] =
  ## Graph first when there is one; the file is the store (F1) or the export.
  try:
    a.ensurePaddock(userId)
    let (access, magma) = a.openGraph(userId)
    case access
    of gaUnavailable:
      return err(GraphUnavailableError)
    of gaReady:
      when defined(withPostgres) or defined(withSqlite):
        ? magma.saveUserMd(userId, content)
      tryExport(a.userMdPath(userId), content)
    of gaNone:
      exportFile(a.userMdPath(userId), content)
    ok()
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("save user profile: " & e.msg)

proc listUsers*(a: MdFileAdapter): seq[UserSummary] =
  if not dirExists(a.paddocksDir):
    return @[]
  for kind, path in walkDir(a.paddocksDir):
    if kind != pcDir:
      continue
    let uid = UserId(path.extractFilename())
    let userMd = a.currentUserMd(uid)
    result.add(UserSummary(
      userId: uid,
      hasProfile: userMd.len > 0,
      preferredName: userMd.parseUserField("Preferred name"),
      access: block:
        let access = userMd.parseUserField("Access")
        if access.len > 0: access else: "active",
    ))

proc updateUserField*(a: MdFileAdapter; userId: UserId;
                      field, value: string): Result[void, string]
                      {.discardable.} =
  ## Rewrites one field of the stored profile. When the profile cannot be
  ## read nothing is saved.
  try:
    let current = ? a.storedUserMd(userId)
    let label =
      if field.toLowerAscii() == "preferred_name": "Preferred name"
      elif field.toLowerAscii() == "access": "Access"
      else: field
    a.saveUserMd(userId, current.setUserFieldText(label, value))
  except CatchableError as e:
    err("update user field: " & e.msg)

proc isRevoked*(a: MdFileAdapter; userId: UserId): bool =
  ## Whether access was revoked. This gates every inbound message, so a
  ## profile that could not be read is never taken for a profile that allows
  ## access: the last export answers in its place, and with no export either
  ## the user counts as revoked until the store can be read again.
  let stored = a.storedUserMd(userId)
  if stored.isOk:
    return isRevokedUserMd(stored.get())
  let exported = readOrEmpty(a.userMdPath(userId))
  exported.len == 0 or isRevokedUserMd(exported)

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
    discard secureFile(path)
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

proc appendToMemoryFile(a: MdFileAdapter; userId: UserId; text: string) =
  ## Append-only write: avoids the read-modify-write race where two concurrent
  ## writers (daemon + ctl) overwrite each other's chunks.
  let path = a.memoryMdPath(userId)
  var f = open(path, fmAppend)
  try:
    if getFileSize(path) > 0:
      f.write("\n")
    f.write(text)
  finally:
    f.close()
  discard secureFile(path)

proc tryAppendExport(a: MdFileAdapter; userId: UserId; text: string) {.raises: [].} =
  ## appendMemory's export after the graph took the entry: like tryExport,
  ## it cannot fail the append, so nothing it raises may reach the caller.
  try:
    a.appendToMemoryFile(userId, text)
  except CatchableError:
    discard

proc appendMemory*(a: MdFileAdapter; userId: UserId; text: string;
                   origin = MemoryOrigin()): Result[void, string] =
  ## Appends one memory.
  ##
  ## With MAGMA it goes to the graph, with its origin. The result is the
  ## graph's: once the graph has the entry the append succeeded, and adding
  ## it to MEMORY.md is a refresh of the export that cannot fail the append.
  ## Reporting an error there would invite a retry, and a retry would store
  ## the same memory twice. A graph that is configured but unavailable fails
  ## the append and writes no file: a memory confirmed only in the export
  ## would be lost, since the export is not read back.
  ##
  ## Without MAGMA, MEMORY.md is the store and has no place for the origin.
  try:
    a.ensurePaddock(userId)
    let (access, magma) = a.openGraph(userId)
    case access
    of gaUnavailable:
      return err(GraphUnavailableError)
    of gaReady:
      when defined(withPostgres) or defined(withSqlite):
        ? magma.appendMemory(userId, text, origin)
      a.tryAppendExport(userId, text)
    of gaNone:
      a.appendToMemoryFile(userId, text)
    ok()
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("append memory: " & e.msg)

proc savePreferences*(a: MdFileAdapter; userId: UserId;
                      content: string): Result[void, string] =
  try:
    a.ensurePaddock(userId)
    let (access, magma) = a.openGraph(userId)
    case access
    of gaUnavailable:
      return err(GraphUnavailableError)
    of gaReady:
      when defined(withPostgres) or defined(withSqlite):
        ? magma.savePreferences(userId, content)
      tryExport(a.preferencesMdPath(userId), content)
    of gaNone:
      exportFile(a.preferencesMdPath(userId), content)
    ok()
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("save preferences: " & e.msg)

proc clearMemory*(a: MdFileAdapter; userId: UserId): Result[void, string] =
  ## Clears the memory of this user (irreversible): the graph nodes when
  ## there is a graph, and MEMORY.md.
  ##
  ## With the graph unavailable nothing is cleared: emptying only the export
  ## would report a clean memory that comes back as soon as the graph does.
  ##
  ## With a graph the export is emptied first, and the graph is cleared only
  ## after that worked. In the other order a failed export would leave an
  ## empty graph beside the old MEMORY.md, and the next access would import
  ## the cleared memories again. An emptied export beside an intact graph is
  ## harmless: the export is derived and can be rebuilt.
  try:
    let (access, magma) = a.openGraph(userId)
    if access == gaUnavailable:
      return err(GraphUnavailableError)
    if fileExists(a.memoryMdPath(userId)):
      exportFile(a.memoryMdPath(userId), "")
    if access == gaReady:
      when defined(withPostgres) or defined(withSqlite):
        ? magma.clearMemory(userId)
    ok()
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("clear memory: " & e.msg)

proc resetBootstrap*(a: MdFileAdapter; userId: UserId): Result[void, string] =
  ## Removes profile and preferences. Same rules as clearMemory: nothing is
  ## removed with the graph unavailable, and the files go before the graph.
  try:
    let (access, magma) = a.openGraph(userId)
    if access == gaUnavailable:
      return err(GraphUnavailableError)
    for path in [a.userMdPath(userId), a.preferencesMdPath(userId)]:
      if fileExists(path):
        removeFile(path)
    if access == gaReady:
      when defined(withPostgres) or defined(withSqlite):
        ? magma.resetBootstrap(userId)
    ok()
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("reset bootstrap: " & e.msg)

proc readFileTail(path: string; maxBytes: int): string =
  ## Whole file when it fits in `maxBytes`; otherwise its last `maxBytes`,
  ## starting at the first complete line.
  let size = getFileSize(path)
  if size <= maxBytes:
    return readFile(path)
  var f: File
  if not open(f, path, fmRead):
    return ""
  defer: f.close()
  f.setFilePos(size - maxBytes)
  let tail = f.readAll()
  let firstBreak = tail.find('\n')
  if firstBreak < 0: "" else: tail[firstBreak + 1 .. ^1]

proc fileEndsWithNewline(path: string): bool {.raises: [].} =
  ## True for an empty file too: there is no open line to close. When the
  ## file cannot be read the answer is false, so the caller closes the line:
  ## an extra blank line is harmless, a message glued to a fragment is lost.
  try:
    let size = getFileSize(path)
    if size <= 0:
      return true
    var f: File
    if not open(f, path, fmRead):
      return false
    defer: f.close()
    f.setFilePos(size - 1)
    var last: array[1, char]
    f.readChars(last) == 1 and last[0] == '\n'
  except CatchableError:
    false

proc readTranscriptLines(path: string;
                         maxBytes = SessionTranscriptAlignBytes): seq[TranscriptLine] =
  ## The records at the end of the transcript, within `maxBytes`.
  if not fileExists(path):
    return
  for raw in readFileTail(path, maxBytes).splitLines():
    let trimmed = raw.strip()
    if trimmed.len == 0:
      continue
    try:
      let j = parseJson(trimmed)
      result.add(TranscriptLine(role: j{"role"}.getStr(""),
                                text: j{"text"}.getStr(""),
                                seq: j{"seq"}.getBiggestInt(0).int64,
                                high: j{"hi"}.getBiggestInt(0).int64))
    except CatchableError:
      ## A malformed line is data; it stays in the file and is not compared.
      discard

proc saveSession*(a: MdFileAdapter; userId: UserId;
                  sessionId: string; history: ConversationHistory) =
  ## Appends to the session transcript the messages it does not hold yet.
  ## JSONL, one message per line, each with the time it was first stored.
  ## Path: {paddock}/sessions/{sessionId}.jsonl
  ##
  ## `history` is the live window (trimmed, compacted or rewound); the file is
  ## the full record, so it is extended and never rewritten.
  ## Skips sessions with fewer than 2 turns (empty/ping sessions).
  if history.len < 2: return
  a.ensurePaddock(userId)
  let dir  = a.paddockDir(userId) / "sessions"
  createDir(dir)
  let path = dir / sessionId & ".jsonl"
  var current: seq[TranscriptLine]
  for msg in history:
    current.add(TranscriptLine(role: msg.role, text: msg.text, seq: msg.seq))
  ## The end of the file answers almost every save. It does not when the
  ## history holds a number from before that part (a rewind to an old
  ## checkpoint) or when no complete record fits in it; then the whole file
  ## is read, so that nothing is decided on what was not seen.
  var existing = readTranscriptLines(path)
  if fileExists(path) and getFileSize(path) > SessionTranscriptAlignBytes and
     needsWholeTranscript(existing, current):
    existing = readTranscriptLines(path, high(int))
  let fresh = messagesToAppend(existing, current)
  if fresh.len == 0:
    return
  let nowMs = epochMs()
  var highest = highestNumber(existing)
  var buf = ""
  ## A write cut short leaves a line without its newline. Close it, so the
  ## first new message starts on its own line; the fragment itself stays.
  if fileExists(path) and not fileEndsWithNewline(path):
    buf.add("\n")
  for index in fresh:
    let msg = history[index]
    var record = %* {"role": msg.role, "text": msg.text,
                     "imageUrl": transcriptImageRef(msg.imageUrl), "ts": nowMs}
    if msg.seq > 0:
      ## `hi` is the highest number in the file up to this line: after a
      ## rewind a low number can be the last line of a file that holds much
      ## higher ones, and the next save must not take those for new.
      highest = max(highest, msg.seq)
      record["seq"] = %msg.seq
      record["hi"] = %highest
    buf.add($record & "\n")
  let f = open(path, fmAppend)
  try:
    f.write(buf)
  finally:
    f.close()
  secureFile(path)


proc sessionSearchRecords(a: MdFileAdapter; userId: UserId;
                          includeMemory: bool):
                          Result[seq[SessionSearchRecord], string]
                          {.gcsafe, raises: [].} =
  try:
    var records: seq[SessionSearchRecord]
    let dir = a.paddockDir(userId) / "sessions"
    if dirExists(dir):
      var files: seq[tuple[path: string, mtimeMs: int64]]
      for kind, path in walkDir(dir):
        if kind != pcFile or not path.endsWith(".jsonl"):
          continue
        let candidate: tuple[path: string, mtimeMs: int64] =
          (path, getLastModificationTime(path).toUnix() * 1000)
        if files.len < SessionSearchMaxFiles:
          files.add(candidate)
          files.sort(proc(a, b: tuple[path: string, mtimeMs: int64]): int =
            cmp(b.mtimeMs, a.mtimeMs))
        elif candidate.mtimeMs > files[^1].mtimeMs:
          files[^1] = candidate
          files.sort(proc(a, b: tuple[path: string, mtimeMs: int64]): int =
            cmp(b.mtimeMs, a.mtimeMs))
      var loaded = 0
      var totalBytes = 0'i64
      for file in files:
        if loaded >= SessionSearchMaxFiles or
           records.len >= SessionSearchMaxRecords or
           totalBytes >= SessionSearchMaxTotalBytes:
          break
        inc loaded
        ## Transcripts are append-only and can outgrow the per-file cap; the
        ## most recent part is read instead of skipping the session.
        let size = min(getFileSize(file.path), SessionSearchMaxFileBytes.int64)
        if size <= 0 or totalBytes + size > SessionSearchMaxTotalBytes:
          continue
        totalBytes += size
        let sessionId = file.path.extractFilename.changeFileExt("")
        let content = readFileTail(file.path, SessionSearchMaxFileBytes)
        ## Newest lines first: when the record cap is reached, what is left
        ## out is the oldest part of the oldest file, never the latest lines.
        let lines = content.splitLines()
        for lineIndex in countdown(lines.high, 0):
          if records.len >= SessionSearchMaxRecords:
            break
          let trimmed = lines[lineIndex].strip()
          if trimmed.len == 0:
            continue
          try:
            let j = parseJson(trimmed)
            let text = j{"text"}.getStr("")
            if text.len == 0:
              continue
            records.add(SessionSearchRecord(
              sessionId: sessionId,
              kind: shkSession,
              role: j{"role"}.getStr(""),
              text: text,
              timestampMs: block:
                ## Lines written before per-message timestamps fall back to
                ## the file's modification time.
                let ts = j{"ts"}.getBiggestInt(0)
                if ts > 0: ts.int64 else: file.mtimeMs,
            ))
          except CatchableError:
            ## A malformed JSONL line is data, not an operational failure.
            discard

    if includeMemory:
      let memoryPath = a.memoryMdPath(userId)
      if fileExists(memoryPath):
        let size = getFileSize(memoryPath)
        if size > 0 and size <= SessionSearchMaxFileBytes and
           size <= SessionSearchMaxTotalBytes:
          let text = readFile(memoryPath)
          if text.len > 0:
            records.add(SessionSearchRecord(
              sessionId: "memory",
              kind: shkMemory,
              role: "memory",
              text: text,
              timestampMs: getLastModificationTime(memoryPath).toUnix() * 1000,
            ))
    ok(records)
  except CatchableError as e:
    err("session search read failed: " & e.msg)

proc searchSessions*(a: MdFileAdapter; userId: UserId;
                     query: string; limit: int;
                     includeMemory = true): Result[seq[SessionHit], string]
                     {.gcsafe, raises: [].} =
  ## With MAGMA the memory part of the search is the graph's nodes, never the
  ## exported MEMORY.md.
  when defined(withPostgres) or defined(withSqlite):
    if a.hasMagmaBackend:
      return a.searchSessionsWithMagma(userId, query, limit, includeMemory)
  try:
    let records = ? a.sessionSearchRecords(userId, includeMemory)
    ok(rankSessionRecords(records, query, epochMs(), limit))
  except CatchableError as e:
    err("session search failed: " & e.msg)

proc listSessions*(a: MdFileAdapter; userId: UserId): seq[string] =
  ## Returns session file names (without extension) sorted newest-first.
  let dir = a.paddockDir(userId) / "sessions"
  if not dirExists(dir): return @[]
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".jsonl"):
      result.add(path.extractFilename().changeFileExt(""))

# ── Agent identity helpers ────────────────────────────────────────────────────

proc hasIdentity*(a: MdFileAdapter; userId: UserId): bool =
  ## True when agent_name is present in the stored preferences.
  for line in a.currentPreferences(userId).splitLines():
    if line.startsWith("agent_name"): return true
  false

proc saveIdentity*(a: MdFileAdapter; userId: UserId;
                   traits: PersonalityTraits; name: string): Result[void, string] =
  ## Merges agent identity into the preferences (TOML key=value format).
  ## When the preferences cannot be read nothing is saved.
  try:
    let current = ? a.storedPreferences(userId)
    a.savePreferences(userId, mergeIdentityPrefs(current, traits, name))
  except Exception as e:  ## effect boundary: callee raises are unannotated
    err("save identity: " & e.msg)

proc loadIdentity*(a: MdFileAdapter; userId: UserId): (string, PersonalityTraits) =
  ## Returns (agent_name, PersonalityTraits) from the stored preferences.
  ## Empty strings when not set.
  parseIdentityPrefs(a.currentPreferences(userId))

# ── Reminder store ────────────────────────────────────────────────────────────

proc reminderDir*(a: MdFileAdapter; userId: UserId): string =
  a.paddockDir(userId) / "reminders"

proc scheduleReminder*(a: MdFileAdapter; userId: UserId;
                       channel: string; scheduledAt: int64;
                       message: string): string =
  ## Writes a reminder JSON file. Returns the reminder id.
  a.ensurePaddock(userId)
  discard secureDir(a.reminderDir(userId))
  let id   = $getTime().toUnix() & "_" & $userId
  let data = %* {
    "id":          id,
    "userId":      $userId,
    "channel":     channel,
    "scheduledAt": scheduledAt,
    "message":     message,
  }
  let reminderPath = a.reminderDir(userId) / id & ".json"
  writeFile(reminderPath, $data)
  discard secureFile(reminderPath)
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
