## PostgresMemoryAdapter — SemanticMemoryPort backed by PostgreSQL.
##
## Compile with -d:withPostgres to enable; without the flag only type stubs
## are exported and libpq is never linked.
##
## Extensions required in the database:
##   CREATE EXTENSION vector;   -- pgvector
##   CREATE EXTENSION age;      -- Apache AGE graph
##
## migrate() creates the schema on first run (idempotent).
##
## Node kinds stored in memory_nodes:
##   'user_profile' — singleton, replaced on saveUserMd
##   'memory'       — multi-row, appended on appendMemory
##   'preference'   — singleton, replaced on savePreferences
##
## Embedding: provided as an EmbedFn closure (proc(string): seq[float32]).
## Nodes without embeddings store NULL in the embedding column.
##
## AGE graph 'donkey': each memory_node is mirrored as a (:Memory) vertex.
## Edges between vertices are added in future phases.

type
  EmbedFn* = proc(text: string): seq[float32]
  ## Closure matching the EmbeddingPort embed proc signature.

when not defined(withPostgres):

  type
    PostgresMemoryAdapter* = ref object
      dsn*: string  ## stub — not functional without -d:withPostgres

else:

  import std/[json, os, strutils]
  import db_connector/db_postgres
  import ../../core/types
  import ../../ports/memory

  # ── Types ───────────────────────────────────────────────────────────────────

  type
    PostgresMemoryAdapter* = ref object
      dsn*:    string
      db:      DbConn
      embedFn: EmbedFn

  # ── DSN parsing ─────────────────────────────────────────────────────────────

  func dsnField(dsn, key: string): string =
    let prefix = key & "="
    let start = dsn.find(prefix)
    if start < 0: return ""
    let vstart = start + prefix.len
    let sp = dsn.find(' ', vstart)
    if sp < 0: dsn[vstart..^1] else: dsn[vstart..<sp]

  # ── Constructor ─────────────────────────────────────────────────────────────

  proc newPostgresMemoryAdapter*(dsn: string; embedFn: EmbedFn): PostgresMemoryAdapter =
    let host  = dsnField(dsn, "host")
    let port  = dsnField(dsn, "port")
    let host2 = if port.len > 0: host & ":" & port else: host
    let db    = open(host2, dsnField(dsn, "user"),
                     dsnField(dsn, "password"), dsnField(dsn, "dbname"))
    PostgresMemoryAdapter(dsn: dsn, db: db, embedFn: embedFn)

  # ── Schema migration ─────────────────────────────────────────────────────────

  proc migrate*(a: PostgresMemoryAdapter) =
    ## Creates extensions, tables, and indexes. Idempotent.
    a.db.exec(sql"CREATE EXTENSION IF NOT EXISTS vector")
    a.db.exec(sql"CREATE EXTENSION IF NOT EXISTS age")
    a.db.exec(sql"LOAD 'age'")
    a.db.exec(sql"""SET search_path = ag_catalog, "$user", public""")
    try:
      a.db.exec(sql"SELECT ag_catalog.create_graph('donkey')")
    except DbError:
      discard  ## graph already exists
    a.db.exec(sql"""
      CREATE TABLE IF NOT EXISTS memory_nodes (
        id         UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id    TEXT    NOT NULL,
        kind       TEXT    NOT NULL,
        content    TEXT    NOT NULL,
        embedding  vector(4096),
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    """)
    a.db.exec(sql"""
      CREATE INDEX IF NOT EXISTS idx_mn_user_kind
        ON memory_nodes(user_id, kind)
    """)
    a.db.exec(sql"""
      CREATE INDEX IF NOT EXISTS idx_mn_embedding
        ON memory_nodes USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100)
    """)

  # ── Helpers ──────────────────────────────────────────────────────────────────

  proc embedOrNull(a: PostgresMemoryAdapter; text: string): string =
    let vec = a.embedFn(text)
    if vec.len == 0: return ""
    var parts = newSeq[string](vec.len)
    for i, f in vec: parts[i] = $f
    "[" & parts.join(",") & "]"

  proc createAgeNode(a: PostgresMemoryAdapter; id, userId, kind: string) =
    try:
      a.db.exec(sql"LOAD 'age'")
      a.db.exec(sql"""SET search_path = ag_catalog, "$user", public""")
      let params = $ %* {"id": id, "uid": userId, "kind": kind}
      a.db.exec(sql"""
        SELECT * FROM ag_catalog.cypher('donkey', $$
          CREATE (:Memory {id: $id, user_id: $uid, kind: $kind})
        $$, $1::ag_catalog.agtype) AS (v ag_catalog.agtype)
      """, params)
    except DbError:
      discard

  proc saveSingleton(a: PostgresMemoryAdapter; userId: UserId;
                     kind, content: string) =
    a.db.exec(sql"DELETE FROM memory_nodes WHERE user_id=$1 AND kind=$2",
              $userId, kind)
    let emb = a.embedOrNull(content)
    let newId =
      if emb.len > 0:
        a.db.getValue(sql"""
          INSERT INTO memory_nodes(user_id, kind, content, embedding)
            VALUES ($1, $2, $3, $4::vector)
          RETURNING id::text""", $userId, kind, content, emb)
      else:
        a.db.getValue(sql"""
          INSERT INTO memory_nodes(user_id, kind, content)
            VALUES ($1, $2, $3)
          RETURNING id::text""", $userId, kind, content)
    a.createAgeNode(newId, $userId, kind)

  # ── MemoryPort implementation ─────────────────────────────────────────────────

  proc hasProfile*(a: PostgresMemoryAdapter; userId: UserId): bool =
    a.db.getValue(
      sql"SELECT EXISTS(SELECT 1 FROM memory_nodes WHERE user_id=$1 AND kind='user_profile')",
      $userId) == "t"

  proc loadContext*(a: PostgresMemoryAdapter; userId: UserId): UserContext =
    let userMd = a.db.getValue(sql"""
      SELECT content FROM memory_nodes
      WHERE user_id=$1 AND kind='user_profile'
      ORDER BY created_at DESC LIMIT 1""", $userId)
    let prefMd = a.db.getValue(sql"""
      SELECT content FROM memory_nodes
      WHERE user_id=$1 AND kind='preference'
      ORDER BY created_at DESC LIMIT 1""", $userId)
    var memParts: seq[string]
    for row in a.db.fastRows(sql"""
        SELECT content FROM memory_nodes
        WHERE user_id=$1 AND kind='memory'
        ORDER BY created_at ASC""", $userId):
      memParts.add(row[0])
    UserContext(
      userId:        userId,
      userMd:        userMd,
      memoryMd:      memParts.join("\n"),
      preferencesMd: prefMd,
    )

  proc saveUserMd*(a: PostgresMemoryAdapter; userId: UserId; content: string) =
    a.saveSingleton(userId, "user_profile", content)

  proc appendMemory*(a: PostgresMemoryAdapter; userId: UserId; text: string) =
    let emb = a.embedOrNull(text)
    let newId =
      if emb.len > 0:
        a.db.getValue(sql"""
          INSERT INTO memory_nodes(user_id, kind, content, embedding)
            VALUES ($1, 'memory', $2, $3::vector)
          RETURNING id::text""", $userId, text, emb)
      else:
        a.db.getValue(sql"""
          INSERT INTO memory_nodes(user_id, kind, content)
            VALUES ($1, 'memory', $2)
          RETURNING id::text""", $userId, text)
    a.createAgeNode(newId, $userId, "memory")

  proc savePreferences*(a: PostgresMemoryAdapter; userId: UserId; content: string) =
    a.saveSingleton(userId, "preference", content)

  # ── Semantic search ───────────────────────────────────────────────────────────

  proc search*(a: PostgresMemoryAdapter; userId: UserId;
               query: string; limit = 10): seq[MemoryHit] =
    let vec = a.embedFn(query)
    if vec.len == 0: return @[]
    var parts = newSeq[string](vec.len)
    for i, f in vec: parts[i] = $f
    let vecSql = "[" & parts.join(",") & "]"
    let qry = sql("""
      SELECT content, kind,
             1 - (embedding <=> $1::vector) AS score
      FROM   memory_nodes
      WHERE  user_id = $2 AND embedding IS NOT NULL
      ORDER  BY embedding <=> $1::vector
      LIMIT  """ & $limit)
    for row in a.db.fastRows(qry, vecSql, $userId):
      result.add(MemoryHit(
        content: row[0],
        kind:    row[1],
        score:   parseFloat(row[2]).float32,
      ))

  # ── Test / admin helpers ──────────────────────────────────────────────────────

  proc deleteUser*(a: PostgresMemoryAdapter; userId: UserId) =
    a.db.exec(sql"DELETE FROM memory_nodes WHERE user_id=$1", $userId)

  # ── Migration from .md files ──────────────────────────────────────────────────

  proc importFromMd*(a: PostgresMemoryAdapter; paddocksDir: string;
                     userId: UserId) =
    ## One-shot import: reads paddock .md files and stores in Postgres.
    let base = paddocksDir / $userId
    proc readOr(path: string): string =
      try: readFile(path) except: ""
    let userMd = readOr(base / "USER.md")
    let memMd  = readOr(base / "MEMORY.md")
    let prefMd = readOr(base / "PREFERENCES.md")
    if userMd.len > 0: a.saveUserMd(userId, userMd)
    if memMd.len  > 0: a.appendMemory(userId, memMd)
    if prefMd.len > 0: a.savePreferences(userId, prefMd)
