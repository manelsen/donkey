## PgvectorStoreAdapter — SemanticMemoryPort backed by PostgreSQL + pgvector.
##
## Compile with -d:withPostgres to activate (links libpq).
## Without the flag the module exports only a stub type and pure helpers.
##
## Schema:
##   donkey_memories   — flat table: user_id, kind, content, embedding vector(4096),
##                        hash, chunk_index, offset, created_at, meta JSONB
##
## All I/O is fallible (database can fail) and returns Result[T, string].
## Operations are chained via >>= (railway-oriented programming).
##
## Usage example:
##   let hits = adapter.search(userId, query, limit).valueOr:
##     log.error("search: " & error)
##     @[]
##
## The >>= operator chains fallible operations:
##   openDb >>= ensureSchema >>= storeChunk

import std/[strutils]

# ── Pure helpers (always available) ────────────────────────────────────────────

const
  DefaultTableName* = "donkey_memories"

func buildVectorLiteral*(vec: seq[float32]): string =
  ## Builds a pgvector literal string like "[0.1,0.2,0.3]" from a float32 seq.
  if vec.len == 0:
    return ""
  var allZero = true
  for v in vec:
    if v != 0.0:
      allZero = false
      break
  if allZero:
    return ""
  var buf = "["
  for i, v in vec:
    if i > 0:
      buf.add(',')
    buf.add($v)
  buf.add(']')
  buf

func parseVectorLiteral*(literal: string): seq[float32] =
  ## Parses a pgvector literal string like "[0.1,0.2,0.3]" into a float32 seq.
  let content = literal.strip(chars = {'[', ']'})
  if content.len == 0:
    return @[]
  for part in content.split(','):
    let trimmed = part.strip
    if trimmed.len > 0:
      result.add(trimmed.parseFloat.float32)

# ── Conditional PostgreSQL implementation ─────────────────────────────────────

when defined(withPostgres):
  import db_connector/db_postgres
  import ../../core/pipeops
  import ../../core/types
  import ../../core/memory/embedder
  import ../../ports/memory
  import ../../ports/embedding
  import ./pg_helpers

  type
    PgvectorStoreAdapter* = object
      dsn*:        string
      embedFn*:    EmbedFn
      tableName*:  string

  # ── SQL schema ──────────────────────────────────────────────────────────────

  func schemaSql(tableName: string): string =
    """
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS """ & tableName & """ (
  id           BIGSERIAL PRIMARY KEY,
  user_id      TEXT        NOT NULL,
  kind         TEXT        NOT NULL,
  content      TEXT        NOT NULL,
  hash         TEXT,
  chunk_index  INTEGER,
  offset       INTEGER,
  embedding    vector(4096),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  meta         JSONB       NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_pgva_user_kind
  ON """ & tableName & """ (user_id, kind);

CREATE INDEX IF NOT EXISTS idx_pgva_embed
  ON """ & tableName & """ USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
"""

  # ── Database connection helpers ───────────────────────────────────────────────

  proc openDb*(a: PgvectorStoreAdapter): Result[DbConn, string] =
    try:
      let db = open(a.dsn, "", "", "")
      ok(db)
    except CatchableError as e:
      err("openDb: " & e.msg)

  proc ensureSchema*(db: DbConn; tableName: string): Result[void, string] =
    for stmt in schemaSql(tableName).split(';'):
      let s = stmt.strip()
      if s.len > 0:
        try:
          db.exec(sql(s))
        except CatchableError as e:
          return err("ensureSchema: " & e.msg)
    ok()

  proc initStore*(a: PgvectorStoreAdapter): Result[void, string] =
    withDb(a):
      db.ensureSchema(a.tableName)

  # ── Core I/O operations (Result-based, chainable via >>=) ────────────────────

  proc hasProfile*(a: PgvectorStoreAdapter; userId: UserId): Result[bool, string] =
    withDb(a):
      let rows = db.getAllRows(
        sql("SELECT 1 FROM " & a.tableName & " WHERE user_id = $1 AND kind = 'user_profile' LIMIT 1"),
        $userId)
      ok(rows.len > 0)

  proc loadContext*(a: PgvectorStoreAdapter; userId: UserId): Result[UserContext, string] =
    withDb(a):
      let rows = db.getAllRows(
        sql("SELECT kind, content FROM " & a.tableName & " WHERE user_id = $1 ORDER BY created_at"),
        $userId)
      var userMd = ""
      var memLines: seq[string]
      var prefMd = ""
      for row in rows:
        case row[0]
        of "user_profile":
          userMd = row[1]
        of "preference":
          prefMd = row[1]
        of "memory", "fact", "solution":
          memLines.add(row[1])
        else:
          discard
      ok(UserContext(
        userId: userId,
        userMd: userMd,
        memoryMd: memLines.join("\n\n"),
        preferencesMd: prefMd,
      ))

  proc saveUserMd*(a: PgvectorStoreAdapter; userId: UserId; content: string): Result[void, string] =
    withDb(a):
      db.exec(sql(
        "INSERT INTO " & a.tableName & " (user_id, kind, content) " &
        "VALUES ($1, 'user_profile', $2) " &
        "ON CONFLICT DO NOTHING"
      ), $userId, content)
      db.exec(sql(
        "UPDATE " & a.tableName & " SET content = $1, created_at = now() " &
        "WHERE user_id = $2 AND kind = 'user_profile'"
      ), content, $userId)
      ok()

  proc appendMemory*(a: PgvectorStoreAdapter; userId: UserId; text: string): Result[void, string] =
    withDb(a):
      db.exec(sql(
        "INSERT INTO " & a.tableName & " (user_id, kind, content) " &
        "VALUES ($1, 'memory', $2)"
      ), $userId, text)
      ok()

  proc savePreferences*(a: PgvectorStoreAdapter; userId: UserId; content: string): Result[void, string] =
    withDb(a):
      db.exec(sql(
        "INSERT INTO " & a.tableName & " (user_id, kind, content) " &
        "VALUES ($1, 'preference', $2) " &
        "ON CONFLICT DO NOTHING"
      ), $userId, content)
      db.exec(sql(
        "UPDATE " & a.tableName & " SET content = $1, created_at = now() " &
        "WHERE user_id = $2 AND kind = 'preference'"
      ), content, $userId)
      ok()

  proc clearMemory*(a: PgvectorStoreAdapter; userId: UserId): Result[void, string] =
    withDb(a):
      db.exec(sql(
        "DELETE FROM " & a.tableName & " WHERE user_id = $1 AND kind = 'memory'"
      ), $userId)
      ok()

  # ── Vector storage operations ─────────────────────────────────────────────────

  proc storeChunk*(a: PgvectorStoreAdapter; userId: UserId;
                   chunk: EmbeddedChunk): Result[void, string] =
    withDb(a):
      let vecStr = buildVectorLiteral(chunk.vector)
      if vecStr.len > 0:
        db.exec(sql(
          "INSERT INTO " & a.tableName & " (user_id, kind, content, hash, chunk_index, offset, embedding) " &
          "VALUES ($1, 'chunk', $2, $3, $4, $5, $6::vector)"
        ), $userId, chunk.chunk, chunk.hash, chunk.index, chunk.offset, vecStr)
      else:
        db.exec(sql(
          "INSERT INTO " & a.tableName & " (user_id, kind, content, hash, chunk_index, offset) " &
          "VALUES ($1, 'chunk', $2, $3, $4, $5)"
        ), $userId, chunk.chunk, chunk.hash, chunk.index, chunk.offset)
      ok()

  proc storeChunks*(a: PgvectorStoreAdapter; userId: UserId;
                    chunks: seq[EmbeddedChunk]): Result[void, string] =
    withDb(a):
      for chunk in chunks:
        let vecStr = buildVectorLiteral(chunk.vector)
        if vecStr.len > 0:
          db.exec(sql(
            "INSERT INTO " & a.tableName & " (user_id, kind, content, hash, chunk_index, offset, embedding) " &
            "VALUES ($1, 'chunk', $2, $3, $4, $5, $6::vector)"
          ), $userId, chunk.chunk, chunk.hash, chunk.index, chunk.offset, vecStr)
        else:
          db.exec(sql(
            "INSERT INTO " & a.tableName & " (user_id, kind, content, hash, chunk_index, offset) " &
            "VALUES ($1, 'chunk', $2, $3, $4, $5)"
          ), $userId, chunk.chunk, chunk.hash, chunk.index, chunk.offset)
      ok()

  proc search*(a: PgvectorStoreAdapter; userId: UserId; query: string;
              limit: int): Result[seq[MemoryHit], string] =
    withDb(a):
      let vec = a.embedFn(query)
      let vecStr = buildVectorLiteral(vec)
      if vecStr.len == 0:
        return ok(newSeq[MemoryHit]())
      let rows = db.getAllRows(sql("""
        SELECT content, kind,
               1 - (embedding <=> $2::vector) AS score
        FROM """ & a.tableName & """
        WHERE user_id = $1
          AND embedding IS NOT NULL
        ORDER BY embedding <=> $2::vector
        LIMIT $3
      """), $userId, vecStr, $limit)
      var hits: seq[MemoryHit]
      for row in rows:
        let score = try: parseFloat(row[2]).float32 except: 0.0
        hits.add(MemoryHit(content: row[0], kind: row[1], score: score))
      ok(hits)

  proc searchByHash*(a: PgvectorStoreAdapter; userId: UserId;
                    hash: string): Result[seq[MemoryHit], string] =
    withDb(a):
      let rows = db.getAllRows(sql("""
        SELECT content, kind, hash, chunk_index, offset
        FROM """ & a.tableName & """
        WHERE user_id = $1 AND hash = $2
        ORDER BY chunk_index
      """), $userId, hash)
      var hits: seq[MemoryHit]
      for row in rows:
        hits.add(MemoryHit(content: row[0], kind: row[1], score: 1.0))
      ok(hits)

  proc getChunksByHash*(a: PgvectorStoreAdapter; userId: UserId;
                        hash: string): Result[seq[(string, int, int)], string] =
    withDb(a):
      let rows = db.getAllRows(sql("""
        SELECT content, chunk_index, offset
        FROM """ & a.tableName & """
        WHERE user_id = $1 AND hash = $2
        ORDER BY chunk_index
      """), $userId, hash)
      var results: seq[(string, int, int)]
      for row in rows:
        let content = row[0]
        let idx = try: parseInt(row[1]) except: 0
        let offset = try: parseInt(row[2]) except: 0
        results.add((content, idx, offset))
      ok(results)

  # ── MemoryPort search (SemanticMemoryPort extension) ──────────────────────────

  proc searchMemory*(a: PgvectorStoreAdapter; userId: UserId; query: string;
                     limit: int): Result[seq[MemoryHit], string] =
    a.search(userId, query, limit)

  # ── Utility operations ───────────────────────────────────────────────────────

  proc deleteUser*(a: PgvectorStoreAdapter; userId: UserId): Result[void, string] =
    withDb(a):
      db.exec(sql("DELETE FROM " & a.tableName & " WHERE user_id = $1"), $userId)
      ok()

  proc countMemories*(a: PgvectorStoreAdapter; userId: UserId): Result[int, string] =
    withDb(a):
      let rows = db.getAllRows(sql(
        "SELECT COUNT(*) FROM " & a.tableName & " WHERE user_id = $1 AND kind = 'chunk'"
      ), $userId)
      if rows.len > 0:
        ok(rows[0][0].parseInt)
      else:
        ok(0)

  proc getMemoryKinds*(a: PgvectorStoreAdapter; userId: UserId): Result[seq[string], string] =
    withDb(a):
      let rows = db.getAllRows(sql(
        "SELECT DISTINCT kind FROM " & a.tableName & " WHERE user_id = $1"
      ), $userId)
      var kinds: seq[string]
      for row in rows:
        kinds.add(row[0])
      ok(kinds)

  # ── Reconstruct text from chunks ──────────────────────────────────────────────

  proc reconstructFromChunks*(a: PgvectorStoreAdapter; userId: UserId;
                                hash: string): Result[string, string] =
    let chunksResult = a.getChunksByHash(userId, hash)
    if chunksResult.isErr:
      return err(chunksResult.error)
    let chunks = chunksResult.get
    if chunks.len == 0:
      return ok("")
    var sortedChunks = chunks
    # Sort by chunk_index using bubble sort (small seq)
    for i in 0 ..< sortedChunks.len:
      for j in i + 1 ..< sortedChunks.len:
        if sortedChunks[j][1] < sortedChunks[i][1]:
          swap(sortedChunks[i], sortedChunks[j])
    var reconstructed = ""
    for chunk in sortedChunks:
      if reconstructed.len > 0:
        reconstructed.add("\n")
      reconstructed.add(chunk[0])
    ok(reconstructed)

  # ── Constructor ───────────────────────────────────────────────────────────────

  proc newPgvectorStoreAdapter*(dsn: string; embedFn: EmbedFn;
                                tableName = DefaultTableName): PgvectorStoreAdapter =
    PgvectorStoreAdapter(dsn: dsn, embedFn: embedFn, tableName: tableName)

else:
  ## Stub — non-postgres builds import this module without activating any code.
  type PgvectorStoreAdapter* = object
