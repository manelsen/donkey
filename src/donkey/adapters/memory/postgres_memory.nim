## PostgresMemoryAdapter — SemanticMemoryPort backed by PostgreSQL + pgvector + Apache AGE.
##
## Compile with -d:withPostgres to activate (links libpq).
## Without the flag the module exports only a stub type so non-postgres builds are unaffected.
##
## Schema overview:
##   donkey_memories   — flat table: user_id, kind, content, embedding vector(4096)
##   donkey_graph      — Apache AGE property graph: nodes + edges for Cypher traversal
##
## AGE node labels: Memory, Person, Concept, Solution, Session, Task, Preference
## AGE edges:       MENTIONS, ABOUT, FROM, RESOLVES, USES, CONTINUED_IN, KNOWS,
##                  HAS_PREFERENCE, IS_CHILD_OF, IS_PARENT_OF
##
## Hybrid search: pgvector cosine similarity → top-k candidates →
##                AGE graph traversal to enrich with related nodes.

import ../../core/types
import ../../ports/memory
import ../../ports/embedding

when defined(withPostgres):
  import db_connector/db_postgres
  import std/[os, strutils, json, tables]
  import ../../core/app_meta
  import ../../core/pipeops
  import ./pgvector_store

  const PgMemoryTableName = "donkey_memories"
  const PgGraphName = "donkey_graph"

  # ── SQL schema ──────────────────────────────────────────────────────────────

  let schemaSql = """
  CREATE EXTENSION IF NOT EXISTS vector;
  CREATE EXTENSION IF NOT EXISTS age;

  CREATE TABLE IF NOT EXISTS """ & PgMemoryTableName & """ (
    id         BIGSERIAL PRIMARY KEY,
    user_id    TEXT        NOT NULL,
    kind       TEXT        NOT NULL,
    content    TEXT        NOT NULL,
    embedding  vector(4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    meta       JSONB       NOT NULL DEFAULT '{}'
  );

  CREATE INDEX IF NOT EXISTS idx_dm_user_kind
    ON """ & PgMemoryTableName & """ (user_id, kind);

  CREATE INDEX IF NOT EXISTS idx_dm_embed
    ON """ & PgMemoryTableName & """ USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
  """

  # ── Adapter type ────────────────────────────────────────────────────────────

  type
    PostgresMemoryAdapter* = ref object
      dsn*:    string
      embedFn: EmbedFn

    MemoryExportEntry* = object
      fileName*: string
      content*:  string

  proc newPostgresMemoryAdapter*(dsn: string; embedFn: EmbedFn): PostgresMemoryAdapter =
    PostgresMemoryAdapter(dsn: dsn, embedFn: embedFn)

  proc open(a: PostgresMemoryAdapter): DbConn =
    ## Opens a fresh connection. Caller must close().
    ## Sets AGE search_path every time (required per connection).
    let db = open(a.dsn, "", "", "")
    db.exec(sql"SET search_path = ag_catalog, public")
    db

  proc sanitizeAgeText*(text: string; maxLen = 200): string {.gcsafe, raises: [].} =
    let safe = text.replace("'", "\\'")
    if safe.len == 0:
      return ""
    safe[0 ..< min(maxLen, safe.len)]

  proc stripAgeValue*(value: string): string {.gcsafe, raises: [].} =
    value.strip(chars = {'"'})

  proc splitMemorySections*(content: string): seq[string] {.gcsafe, raises: [].} =
    for section in content.split("\n\n"):
      let s = section.strip()
      if s.len > 10:
        result.add(s)

  proc buildContextFromRows*(userId: UserId; rows: seq[Row]): UserContext {.gcsafe, raises: [].} =
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
    UserContext(
      userId: userId,
      userMd: userMd,
      memoryMd: memLines.join("\n\n"),
      preferencesMd: prefMd,
    )

  proc buildMemoryHits*(rows: seq[Row]): seq[MemoryHit] {.gcsafe, raises: [].} =
    for row in rows:
      let score = try: parseFloat(row[2]).float32 except: 0.0
      result.add MemoryHit(content: row[0], kind: row[1], score: score)

  proc buildRecentMemoryHits*(rows: seq[Row]): seq[MemoryHit] {.gcsafe, raises: [].} =
    for row in rows:
      result.add MemoryHit(content: row[0], kind: row[1], score: 0.0)

  # ── AGE graph helpers ──────────────────────────────────────────────────────

  proc ageGraphExists(db: DbConn): bool =
    let rows = db.getAllRows(
      sql"SELECT count(*) FROM ag_catalog.ag_graph WHERE name = $1",
      PgGraphName)
    rows.len > 0 and rows[0][0] != "0"

  proc ageCypher(db: DbConn; cypher: string; retCols: seq[string] = @[]): seq[Row] =
    ## Executes a Cypher query via AGE. retCols specifies the result column aliases.
    if retCols.len == 0:
      db.exec(sql("SELECT * FROM cypher('" & PgGraphName & "', $$ " & cypher & " $$) AS (r agtype)"))
      return @[]
    var cols = ""
    for i, c in retCols:
      if i > 0: cols.add(", ")
      cols.add(c & " agtype")
    let q = "SELECT * FROM cypher('" & PgGraphName & "', $$ " & cypher & " $$) AS (" & cols & ")"
    db.getAllRows(sql(q))

  # ── Migration ──────────────────────────────────────────────────────────────

  proc migrate*(a: PostgresMemoryAdapter) =
    ## Creates extensions, tables, and AGE graph. Idempotent.
    let db = a.open()
    defer: db.close()
    ## pgvector + table
    for stmt in schemaSql.split(';'):
      let s = stmt.strip()
      if s.len > 0:
        try: db.exec(sql(s))
        except DbError: discard
    ## AGE: load extension per session, then create graph if absent.
    try:
      db.exec(sql"LOAD 'age'")
      if not db.ageGraphExists():
        db.exec(sql("SELECT * FROM ag_catalog.create_graph('" & PgGraphName & "')"))
    except Exception:
      discard

  # ── MemoryPort implementation ──────────────────────────────────────────────

  proc upsert(db: DbConn; userId, kind, content: string) =
    db.exec(sql(
      "INSERT INTO " & PgMemoryTableName & " (user_id, kind, content) " &
      "VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"
    ), userId, kind, content)
    db.exec(sql(
      "UPDATE " & PgMemoryTableName & " SET content = $1, created_at = now() " &
      "WHERE user_id = $2 AND kind = $3"
    ), content, userId, kind)

  proc embedOrNull(a: PostgresMemoryAdapter; text: string): string =
    buildVectorLiteral(a.embedFn(text))

  proc hasProfile*(a: PostgresMemoryAdapter; userId: UserId): bool =
    let db = a.open()
    defer: db.close()
    let rows = db.getAllRows(
      sql("SELECT 1 FROM " & PgMemoryTableName & " WHERE user_id = $1 AND kind = 'user_profile' LIMIT 1"),
      $userId)
    rows.len > 0

  proc loadContext*(a: PostgresMemoryAdapter; userId: UserId): UserContext =
    let db = a.open()
    defer: db.close()
    let rows = db.getAllRows(
      sql("SELECT kind, content FROM " & PgMemoryTableName & " WHERE user_id = $1 ORDER BY created_at"),
      $userId)
    buildContextFromRows(userId, rows)

  proc saveUserMd*(a: PostgresMemoryAdapter; userId: UserId; content: string) =
    let db = a.open()
    defer: db.close()
    db.upsert($userId, "user_profile", content)
    try:
      db.exec(sql"LOAD 'age'")
      discard db.ageCypher(
        "MERGE (p:Person {user_id: '" & $userId & "'}) SET p.profile = '" &
        sanitizeAgeText(content) & "' RETURN p")
    except CatchableError: discard

  proc appendMemory*(a: PostgresMemoryAdapter; userId: UserId; text: string) =
    let db = a.open()
    defer: db.close()
    var nodeId = ""
    let rows = db.getAllRows(sql(
      "INSERT INTO " & PgMemoryTableName & " (user_id, kind, content) " &
      "VALUES ($1, 'memory', $2) RETURNING id"
    ), $userId, text)
    if rows.len > 0: nodeId = rows[0][0]
    let vecStr = a.embedOrNull(text)
    if vecStr.len > 0 and nodeId.len > 0:
      db.exec(sql("UPDATE " & PgMemoryTableName & " SET embedding = '" & vecStr &
                  "'::vector WHERE id = " & nodeId))
    try:
      db.exec(sql"LOAD 'age'")
      let safeText = sanitizeAgeText(text)
      discard db.ageCypher(
        "MERGE (u:Person {user_id: '" & $userId & "'}) " &
        "CREATE (m:Memory {node_id: '" & nodeId & "', user_id: '" & $userId &
        "', content: '" & safeText & "'}) " &
        "CREATE (u)-[:HAS_MEMORY]->(m) RETURN id(m)", @["id"])
    except CatchableError: discard

  proc savePreferences*(a: PostgresMemoryAdapter; userId: UserId; content: string) =
    let db = a.open()
    defer: db.close()
    db.upsert($userId, "preference", content)

  proc search*(a: PostgresMemoryAdapter; userId: UserId; query: string;
               limit: int): seq[MemoryHit] {.gcsafe.} =
    let db = a.open()
    defer: db.close()
    let vecStr = a.embedOrNull(query)
    if vecStr.len > 0:
      let rows = db.getAllRows(sql("""
        SELECT content, kind,
               1 - (embedding <=> '""" & vecStr & """'::vector) AS score
        FROM """ & PgMemoryTableName & """
        WHERE user_id = $1
          AND embedding IS NOT NULL
        ORDER BY embedding <=> '""" & vecStr & """'::vector
        LIMIT $2
      """), $userId, $limit)
      result = buildMemoryHits(rows)
      ## ── Graph enrichment: find nodes related to top hit via AGE ──
      if result.len > 0:
        let topContent = result[0].content[0 ..< min(50, result[0].content.len)]
        try:
          db.exec(sql"LOAD 'age'")
          let graphRows = db.ageCypher(
            "MATCH (m:Memory {user_id: '" & $userId & "'})-[r]-(n) " &
            "WHERE m.content STARTS WITH '" & topContent.replace("'", "\\'") & "' " &
            "RETURN n.content", @["content"])
          for gr in graphRows:
            let content = stripAgeValue(gr[0])
            if content.len > 0 and content != "null":
              result.add MemoryHit(content: content, kind: "graph", score: 0.5)
        except CatchableError: discard
    else:
      let rows = db.getAllRows(sql(
        "SELECT content, kind FROM " & PgMemoryTableName & " " &
        "WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2"
      ), $userId, $limit)
      result = buildRecentMemoryHits(rows)

  proc deleteUser*(a: PostgresMemoryAdapter; userId: UserId) =
    let db = a.open()
    defer: db.close()
    db.exec(sql("DELETE FROM " & PgMemoryTableName & " WHERE user_id = $1"), $userId)
    try:
      db.exec(sql"LOAD 'age'")
      discard db.ageCypher(
        "MATCH (n {user_id: '" & $userId & "'}) DETACH DELETE n")
    except CatchableError: discard

else:
  type
    PostgresMemoryAdapter* = ref object
      dsn*: string

  proc newPostgresMemoryAdapter*(dsn: string; embedFn: EmbedFn): PostgresMemoryAdapter =
    PostgresMemoryAdapter(dsn: dsn)
  proc migrate*(a: PostgresMemoryAdapter) = discard
  proc hasProfile*(a: PostgresMemoryAdapter; userId: UserId): bool = false
  proc loadContext*(a: PostgresMemoryAdapter; userId: UserId): UserContext = UserContext(userId: userId)
  proc saveUserMd*(a: PostgresMemoryAdapter; userId: UserId; content: string) = discard
  proc appendMemory*(a: PostgresMemoryAdapter; userId: UserId; text: string) = discard
  proc savePreferences*(a: PostgresMemoryAdapter; userId: UserId; content: string) = discard
  proc search*(a: PostgresMemoryAdapter; userId: UserId; query: string; limit: int): seq[MemoryHit] = @[]
  proc deleteUser*(a: PostgresMemoryAdapter; userId: UserId) = discard
