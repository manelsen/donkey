## SqliteStoreAdapter — fast local session cache backed by SQLite.
##
## Compile with -d:withSqlite to activate (links libsqlite3).
## Without the flag the module exports only a stub type.
##
## Schema:
##   users         — (user_id TEXT PK, user_md TEXT, memory_md TEXT,
##                    preferences_md TEXT, access TEXT DEFAULT 'active',
##                    created_at INTEGER, updated_at INTEGER)
##   sessions      — (session_id TEXT PK, user_id TEXT FK, history_jsonl TEXT,
##                    created_at INTEGER)
##   reminders     — (id TEXT PK, user_id TEXT FK, channel TEXT,
##                    scheduled_at INTEGER, message TEXT, created_at INTEGER)
##
## All I/O returns Result[T, string] and is chained via >>= where applicable.
##
## Usage example:
##   let ctx = adapter.loadContext(userId).valueOr:
##     log.error("loadContext: " & error)

when defined(withSqlite):
  import db_connector/db_sqlite
  import std/[json, os, strutils, times]
  import ../../core/pipeops
  import ../../core/types
  import ../../domain/message
  import ../../domain/personality
  import ../../ports/memory

  type
    SqliteStoreAdapter* = object
      dbPath*: string  ## path to the SQLite database file

    UserSummary* = object
      userId*:        UserId
      hasProfile*:     bool
      preferredName*:  string
      access*:        string

  # ── Database connection helpers ───────────────────────────────────────────────

  proc openDb*(a: SqliteStoreAdapter): Result[DbConn, string] =
    try:
      let db = db_sqlite.open(a.dbPath, "", "", "")
      ok(db)
    except CatchableError as e:
      err("openDb: " & e.msg)

  proc initSchema*(db: DbConn): Result[void, string] =
    try:
      db.exec(sql"""CREATE TABLE IF NOT EXISTS users (
          user_id         TEXT PRIMARY KEY,
          user_md         TEXT NOT NULL DEFAULT '',
          memory_md       TEXT NOT NULL DEFAULT '',
          preferences_md  TEXT NOT NULL DEFAULT '',
          access          TEXT NOT NULL DEFAULT 'active',
          created_at      INTEGER NOT NULL,
          updated_at      INTEGER NOT NULL
        )""")
      db.exec(sql"""CREATE TABLE IF NOT EXISTS sessions (
          session_id    TEXT PRIMARY KEY,
          user_id       TEXT NOT NULL,
          history_jsonl TEXT NOT NULL DEFAULT '',
          created_at    INTEGER NOT NULL,
          FOREIGN KEY (user_id) REFERENCES users(user_id)
        )""")
      db.exec(sql"""CREATE TABLE IF NOT EXISTS reminders (
          id           TEXT PRIMARY KEY,
          user_id      TEXT NOT NULL,
          channel      TEXT NOT NULL DEFAULT '',
          scheduled_at INTEGER NOT NULL,
          message      TEXT NOT NULL DEFAULT '',
          created_at   INTEGER NOT NULL,
          FOREIGN KEY (user_id) REFERENCES users(user_id)
        )""")
      db.exec(sql"CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id)")
      db.exec(sql"CREATE INDEX IF NOT EXISTS idx_reminders_user ON reminders(user_id)")
      db.exec(sql"CREATE INDEX IF NOT EXISTS idx_reminders_scheduled ON reminders(scheduled_at)")
      ok()
    except CatchableError as e:
      err("initSchema: " & e.msg)

  proc ensureDatabase*(a: SqliteStoreAdapter): Result[void, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    db.initSchema

  # ── Core I/O operations (Result-based, chainable via >>=) ────────────────────

  proc hasProfile*(a: SqliteStoreAdapter; userId: UserId): Result[bool, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    try:
      let row = db.getRow(sql"SELECT 1 FROM users WHERE user_id = ?", $userId)
      ok(row[0].len > 0)
    except CatchableError as e:
      err("hasProfile: " & e.msg)

  proc loadContext*(a: SqliteStoreAdapter; userId: UserId): Result[UserContext, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    try:
      let row = db.getRow(sql"SELECT user_md, memory_md, preferences_md FROM users WHERE user_id = ?", $userId)
      ok(UserContext(
        userId:        userId,
        userMd:        if row.len >= 1: row[0] else: "",
        memoryMd:      if row.len >= 2: row[1] else: "",
        preferencesMd: if row.len >= 3: row[2] else: "",
      ))
    except CatchableError as e:
      err("loadContext: " & e.msg)

  proc saveUserMd*(a: SqliteStoreAdapter; userId: UserId; content: string): Result[void, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    try:
      db.exec(sql"""INSERT INTO users (user_id, user_md, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET user_md = excluded.user_md, updated_at = excluded.updated_at""",
              $userId, content, now, now)
      ok()
    except CatchableError as e:
      err("saveUserMd: " & e.msg)

  proc appendMemory*(a: SqliteStoreAdapter; userId: UserId; text: string): Result[void, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    try:
      let existing = db.getRow(sql"SELECT memory_md FROM users WHERE user_id = ?", $userId)
      let current = if existing.len > 0 and existing[0].len > 0: existing[0] else: ""
      let sep = if current.len > 0 and not current.endsWith("\n"): "\n" else: ""
      let newContent = current & sep & text
      db.exec(sql"""INSERT INTO users (user_id, memory_md, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET memory_md = excluded.memory_md, updated_at = excluded.updated_at""",
              $userId, newContent, now, now)
      ok()
    except CatchableError as e:
      err("appendMemory: " & e.msg)

  proc savePreferences*(a: SqliteStoreAdapter; userId: UserId; content: string): Result[void, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    try:
      db.exec(sql"""INSERT INTO users (user_id, preferences_md, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET preferences_md = excluded.preferences_md, updated_at = excluded.updated_at""",
              $userId, content, now, now)
      ok()
    except CatchableError as e:
      err("savePreferences: " & e.msg)

  proc clearMemory*(a: SqliteStoreAdapter; userId: UserId): Result[void, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    try:
      db.exec(sql"""INSERT INTO users (user_id, memory_md, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET memory_md = excluded.memory_md, updated_at = excluded.updated_at""",
              $userId, "", now, now)
      ok()
    except CatchableError as e:
      err("clearMemory: " & e.msg)

  proc saveSession*(a: SqliteStoreAdapter; userId: UserId;
                    sessionId: string; history: ConversationHistory): Result[void, string] =
    if history.len < 2:
      return ok()
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    var buf = ""
    for msg in history:
      buf.add($(%* {"role": msg.role, "text": msg.text,
                    "imageUrl": msg.imageUrl}) & "\n")
    try:
      db.exec(sql"""INSERT INTO sessions (session_id, user_id, history_jsonl, created_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(session_id) DO UPDATE SET history_jsonl = excluded.history_jsonl""",
              sessionId, $userId, buf, now)
      ok()
    except CatchableError as e:
      err("saveSession: " & e.msg)

  proc listSessions*(a: SqliteStoreAdapter; userId: UserId): Result[seq[string], string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    try:
      var sessions: seq[string]
      for row in db.fastRows(sql"SELECT session_id FROM sessions WHERE user_id = ? ORDER BY created_at DESC", $userId):
        sessions.add(row[0])
      ok(sessions)
    except CatchableError as e:
      err("listSessions: " & e.msg)

  # ── User management ───────────────────────────────────────────────────────────

  proc updateUserField*(a: SqliteStoreAdapter; userId: UserId; field, value: string): Result[void, string] =
    let col =
      if field.toLowerAscii() == "access": "access"
      else: ""
    if col.len == 0:
      return ok()
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    let query = "INSERT INTO users (user_id, created_at, updated_at, " & col & ") VALUES (?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET " & col & " = excluded." & col & ", updated_at = excluded.updated_at"
    try:
      db.exec(sql query, $userId, now, now, value)
      ok()
    except CatchableError as e:
      err("updateUserField: " & e.msg)

  proc isRevoked*(a: SqliteStoreAdapter; userId: UserId): Result[bool, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    try:
      let row = db.getRow(sql"SELECT access FROM users WHERE user_id = ?", $userId)
      let access = if row.len > 0: row[0].toLowerAscii else: "active"
      ok(access == "revoked")
    except CatchableError as e:
      err("isRevoked: " & e.msg)

  proc listUsers*(a: SqliteStoreAdapter): Result[seq[UserSummary], string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    try:
      var users: seq[UserSummary]
      for row in db.fastRows(sql"SELECT user_id, user_md, access FROM users"):
        let uid = UserId(row[0])
        let hasProfile = row[1].len > 0
        let access = if row[2].len > 0: row[2] else: "active"
        # Extract preferred name from user_md if available
        var preferredName = ""
        if hasProfile:
          let content = row[1]
          let prefix = "**Preferred name:**"
          for line in content.splitLines():
            let trimmed = line.strip()
            if trimmed.startsWith(prefix):
              preferredName = trimmed[prefix.len .. ^1].strip()
              break
        users.add(UserSummary(
          userId: uid,
          hasProfile: hasProfile,
          preferredName: preferredName,
          access: access,
        ))
      ok(users)
    except CatchableError as e:
      err("listUsers: " & e.msg)

  # ── Identity helpers ─────────────────────────────────────────────────────────

  proc hasIdentity*(a: SqliteStoreAdapter; userId: UserId): Result[bool, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    try:
      let row = db.getRow(sql"SELECT preferences_md FROM users WHERE user_id = ?", $userId)
      if row.len == 0 or row[0].len == 0:
        return ok(false)
      let content = row[0]
      for line in content.splitLines():
        if line.startsWith("agent_name"):
          return ok(true)
      ok(false)
    except CatchableError as e:
      err("hasIdentity: " & e.msg)

  proc saveIdentity*(a: SqliteStoreAdapter; userId: UserId;
                     traits: PersonalityTraits; name: string): Result[void, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    # Load existing preferences
    let existing = block:
      let row = db.getRow(sql"SELECT preferences_md FROM users WHERE user_id = ?", $userId)
      if row.len > 0: row[0] else: ""
    var lines = if existing.len > 0: existing.splitLines else: newSeq[string]()
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
    let newContent = lines.join("\n")
    try:
      db.exec(sql"""INSERT INTO users (user_id, preferences_md, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(user_id) DO UPDATE SET preferences_md = excluded.preferences_md, updated_at = excluded.updated_at""",
              $userId, newContent, now, now)
      ok()
    except CatchableError as e:
      err("saveIdentity: " & e.msg)

  proc loadIdentity*(a: SqliteStoreAdapter; userId: UserId): Result[(string, PersonalityTraits), string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    try:
      let row = db.getRow(sql"SELECT preferences_md FROM users WHERE user_id = ?", $userId)
      if row.len == 0 or row[0].len == 0:
        return ok(("", PersonalityTraits()))
      let content = row[0]
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
    except CatchableError as e:
      err("loadIdentity: " & e.msg)

  # ── Reminder store ─────────────────────────────────────────────────────────────

  var reminderCounter*: int = 0  ## Global counter for unique reminder IDs. Exported for testing.

  proc scheduleReminder*(a: SqliteStoreAdapter; userId: UserId;
                         channel: string; scheduledAt: int64;
                         message: string): Result[string, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    inc reminderCounter
    let id = $now & "_" & $userId & "_" & $reminderCounter
    try:
      db.exec(sql"""INSERT INTO reminders (id, user_id, channel, scheduled_at, message, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)""",
              id, $userId, channel, scheduledAt, message, now)
      ok(id)
    except CatchableError as e:
      err("scheduleReminder: " & e.msg)

  proc loadDueReminders*(a: SqliteStoreAdapter): Result[seq[JsonNode], string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    let now = getTime().toUnix()
    try:
      var due: seq[JsonNode]
      for row in db.fastRows(sql"SELECT id, user_id, channel, scheduled_at, message FROM reminders WHERE scheduled_at <= ?", now):
        let j = %* {
          "id":          row[0],
          "userId":      row[1],
          "channel":     row[2],
          "scheduledAt": row[3].parseBiggestInt,
          "message":     row[4],
        }
        due.add(j)
      ok(due)
    except CatchableError as e:
      err("loadDueReminders: " & e.msg)

  proc deleteReminder*(a: SqliteStoreAdapter; userId: UserId; reminderId: string): Result[void, string] =
    let dbResult = a.openDb
    if dbResult.isErr:
      return err(dbResult.error)
    let db = dbResult.get
    defer: db.close()
    try:
      db.exec(sql"DELETE FROM reminders WHERE id = ? AND user_id = ?", reminderId, $userId)
      ok()
    except CatchableError as e:
      err("deleteReminder: " & e.msg)

else:
  ## Stub — non-sqlite builds import this module without activating any code.
  type SqliteStoreAdapter* = object
