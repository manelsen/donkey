## sqlite_magma_store — SQLite-backed MAGMA store.
##
## Embeddings are stored as BLOBs so the store can use sqlite-vec when the
## extension is available. The graph layout remains relational for now.

import ../../core/pipeops
import ../../ports/multigraph_store
import ./magma_stats_sql

when defined(withSqlite):
  import db_connector/db_sqlite
  import std/[algorithm, json, math, options, os, strutils, times]
  import ./pgvector_store
  import ./sqlite_embedded

  type
    SqliteMagmaStoreAdapter* = ref object
      dbPath*: string
      vectorExtensionPath*: string

  const
    SqliteNodesTable = "magma_nodes"
    SqliteEdgesTable = "magma_edges"
    SqliteVecTable = "magma_node_vec"
    SqliteLegacyEmbeddingColumn = "embedding"
    SqliteVectorEmbeddingColumn = "embedding_vec"
    SqliteVectorDimension = 4096
    SqliteVectorBytes = SqliteVectorDimension * sizeof(float32)
    BlobSchemaMigration = "embedding-blobs-v1"
    CosineIndexMigration = "cosine-index-v1"
    CosineIndexFailed = "cosine-index-v1-failed"
      ## The rebuild failed: reads stop retrying it under the write lock
      ## until a write changes the nodes (updateVecIndex clears it).

  func sqliteVecPlatformDir*(): string =
    when defined(macosx):
      when defined(amd64):
        "macos-x86_64"
      elif defined(arm64) or defined(aarch64):
        "macos-aarch64"
      else:
        "macos"
    elif defined(windows):
      when defined(amd64):
        "windows-x86_64"
      elif defined(arm64) or defined(aarch64):
        "windows-aarch64"
      else:
        "windows"
    else:
      when defined(amd64):
        "linux-x86_64"
      elif defined(arm64) or defined(aarch64):
        "linux-aarch64"
      else:
        "linux"

  func sqliteVecExtensionFileName*(): string =
    when defined(macosx):
      "vec0.dylib"
    elif defined(windows):
      "vec0.dll"
    else:
      "vec0.so"

  proc resolveVecExtensionPath*(explicitPath = "";
                                cwd = getCurrentDir();
                                appPath = getAppFilename()): string =
    ## The configured path (DONKEY_SQLITE_VEC_PATH, read by the caller from
    ## the environment snapshot) wins when it exists; otherwise autodetect.
    if explicitPath.len > 0 and fileExists(explicitPath):
      return explicitPath
    let rel = joinPath("vendor", "sqlite-vec", sqliteVecPlatformDir(), sqliteVecExtensionFileName())
    let appDir = appPath.parentDir()
    let candidates = @[
      cwd / rel,
      appDir / rel,
      appDir.parentDir() / rel,
      appDir.parentDir().parentDir() / rel,
    ]
    for candidate in candidates:
      if candidate.len > 0 and fileExists(candidate):
        return candidate
    ""

  proc newSqliteMagmaStoreAdapter*(dbPath: string;
                                   vectorExtensionPath = ""): SqliteMagmaStoreAdapter =
    SqliteMagmaStoreAdapter(
      dbPath: dbPath,
      vectorExtensionPath: resolveVecExtensionPath(vectorExtensionPath),
    )

  proc openDb*(a: SqliteMagmaStoreAdapter): DbConn =
    ensureEmbeddedSqliteVecRegistered()
    result = db_sqlite.open(a.dbPath, "", "", "")
    ## WAL lets readers proceed while a writer commits; NORMAL avoids an
    ## fsync per statement while staying durable across process crashes; the
    ## busy timeout makes a second writer wait instead of failing at once.
    result.exec(sql"PRAGMA busy_timeout = 5000")
    result.exec(sql"PRAGMA journal_mode = WAL")
    result.exec(sql"PRAGMA synchronous = NORMAL")
    result.exec(sql"PRAGMA foreign_keys = ON")
    if not hasEmbeddedSqliteVec() and a.vectorExtensionPath.len > 0:
      try:
        result.enableLoadExtension()
        result.loadExtension(a.vectorExtensionPath)
      except CatchableError:
        discard

  func buildVectorJson(vec: seq[float32]): string =
    if vec.len == 0:
      return "[]"
    var buf = "["
    for i, v in vec:
      if i > 0:
        buf.add(",")
      buf.add($v)
    buf.add("]")
    buf

  func encodeVectorBlob(vec: seq[float32]): string =
    if vec.len == 0:
      return ""
    result.setLen(vec.len * sizeof(float32))
    copyMem(addr result[0], unsafeAddr vec[0], result.len)

  func decodeVectorBlob(raw: string): seq[float32] =
    if raw.len == 0 or raw.len mod sizeof(float32) != 0:
      return @[]
    result.setLen(raw.len div sizeof(float32))
    copyMem(addr result[0], unsafeAddr raw[0], raw.len)

  func blobBytes(raw: string): seq[byte] =
    result.setLen(raw.len)
    for i in 0 ..< raw.len:
      result[i] = byte(raw[i])

  proc hasLoadedVec(db: DbConn): bool =
    try:
      discard db.getValue(sql"SELECT vec_version()")
      true
    except CatchableError:
      return false

  template writeTransaction(db: DbConn; body: untyped) =
    db.exec(sql"BEGIN IMMEDIATE")
    try:
      body
      db.exec(sql"COMMIT")
    except CatchableError:
      discard db.tryExec(sql"ROLLBACK")
      raise

  proc createNodesTable(db: DbConn) =
    db.exec(sql("""CREATE TABLE IF NOT EXISTS """ & SqliteNodesTable & """ (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      node_type TEXT NOT NULL DEFAULT 'memory',
      content TEXT NOT NULL,
      embedding TEXT NOT NULL DEFAULT '',
      embedding_vec BLOB NOT NULL DEFAULT X'',
      ts INTEGER NOT NULL DEFAULT 0,
      meta TEXT NOT NULL DEFAULT '{}'
    )"""))
    db.exec(sql("""CREATE INDEX IF NOT EXISTS idx_sqlite_mn_user_type
      ON """ & SqliteNodesTable & """ (user_id, node_type)"""))
    db.exec(sql("""CREATE INDEX IF NOT EXISTS idx_sqlite_mn_user_ts
      ON """ & SqliteNodesTable & """ (user_id, ts)"""))

  proc ensureVectorColumn(db: DbConn) =
    var hasVectorColumn = false
    for row in db.getAllRows(sql("PRAGMA table_info(" & SqliteNodesTable & ")")):
      if row.len > 1 and row[1] == SqliteVectorEmbeddingColumn:
        hasVectorColumn = true
        break
    if not hasVectorColumn:
      db.exec(sql(
        "ALTER TABLE " & SqliteNodesTable &
        " ADD COLUMN " & SqliteVectorEmbeddingColumn &
        " BLOB NOT NULL DEFAULT X''"
      ))

  const InsertVecRows = "INSERT INTO " & SqliteVecTable &
    " (rowid, user_id, embedding) SELECT rowid, user_id, " & SqliteVectorEmbeddingColumn &
    " FROM " & SqliteNodesTable &
    " WHERE length(" & SqliteVectorEmbeddingColumn & ") = " & $SqliteVectorBytes

  proc updateVecIndex(db: DbConn; vecReady: bool; nodeId: string; deleting = false) =
    if vecReady:
      try:
        db.exec(sql(
          "DELETE FROM " & SqliteVecTable & " WHERE rowid = " &
          "(SELECT rowid FROM " & SqliteNodesTable & " WHERE id = ?)"
        ), nodeId)
        if not deleting:
          db.exec(sql(InsertVecRows & " AND id = ?"), nodeId)
        return
      except DbError:
        discard
    # The base table remains authoritative, including for writers without vec0.
    # A connection with vec0 will rebuild the index after an unsynced write.
    db.exec(sql"DELETE FROM magma_schema_migrations WHERE name IN (?, ?)",
            CosineIndexMigration, CosineIndexFailed)

  proc backfillVectorEmbeddings(db: DbConn) =
    let rows = db.getAllRows(sql(
      "SELECT id, " & SqliteLegacyEmbeddingColumn &
      " FROM " & SqliteNodesTable &
      " WHERE " & SqliteLegacyEmbeddingColumn & " != '' AND length(" &
      SqliteVectorEmbeddingColumn & ") = 0"
    ))
    if rows.len == 0:
      return
    for row in rows:
      let blob = encodeVectorBlob(parseVectorLiteral(row[1]))
      if blob.len == 0:
        continue
      let blobData = blobBytes(blob)
      let stmt = db.prepare(
        "UPDATE " & SqliteNodesTable & " SET " & SqliteVectorEmbeddingColumn &
        " = ?, " & SqliteLegacyEmbeddingColumn & " = '' WHERE id = ?"
      )
      stmt.bindParam(1, blobData)
      stmt.bindParam(2, row[0])
      db.exec(stmt)
      stmt.finalize()

  proc migrateBlobSchema(db: DbConn) =
    db.createNodesTable()
    db.ensureVectorColumn()
    db.backfillVectorEmbeddings()
    db.exec(sql("""CREATE TABLE IF NOT EXISTS """ & SqliteEdgesTable & """ (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      from_id TEXT NOT NULL REFERENCES """ & SqliteNodesTable & """(id) ON DELETE CASCADE,
      to_id TEXT NOT NULL REFERENCES """ & SqliteNodesTable & """(id) ON DELETE CASCADE,
      edge_type TEXT NOT NULL,
      weight REAL NOT NULL DEFAULT 1.0,
      meta TEXT NOT NULL DEFAULT '{}',
      created_at INTEGER NOT NULL DEFAULT 0,
      UNIQUE (from_id, to_id, edge_type)
    )"""))
    db.exec(sql("""CREATE INDEX IF NOT EXISTS idx_sqlite_me_from_type
      ON """ & SqliteEdgesTable & """ (from_id, edge_type)"""))
    db.exec(sql("""CREATE INDEX IF NOT EXISTS idx_sqlite_me_to_type
      ON """ & SqliteEdgesTable & """ (to_id, edge_type)"""))
    db.exec(sql"INSERT INTO magma_schema_migrations (name) VALUES (?)", BlobSchemaMigration)

  proc rebuildVecIndex(db: DbConn): bool =
    db.exec(sql"SAVEPOINT magma_vec_rebuild")
    try:
      db.exec(sql("DROP TABLE IF EXISTS " & SqliteVecTable))
      db.exec(sql("CREATE VIRTUAL TABLE " & SqliteVecTable & " USING vec0(" &
        "user_id TEXT PARTITION KEY, embedding FLOAT[" & $SqliteVectorDimension &
        "] distance_metric=cosine)"))
      db.exec(sql(InsertVecRows))
      db.exec(sql"INSERT INTO magma_schema_migrations (name) VALUES (?)", CosineIndexMigration)
      db.exec(sql"RELEASE SAVEPOINT magma_vec_rebuild")
      true
    except DbError as e:
      db.exec(sql"ROLLBACK TO SAVEPOINT magma_vec_rebuild")
      db.exec(sql"RELEASE SAVEPOINT magma_vec_rebuild")
      db.exec(sql"INSERT OR IGNORE INTO magma_schema_migrations (name) VALUES (?)",
              CosineIndexFailed)
      stderr.writeLine("WARN magma.sqlite: vector index rebuild failed, " &
                       "searching without it: " & e.msg)
      false

  proc schemaMigrations(db: DbConn): tuple[blobs, vecIndex, vecFailed: bool] =
    if db.getValue(sql"""SELECT 1 FROM sqlite_master
        WHERE type = 'table' AND name = 'magma_schema_migrations'""") != "1":
      return
    for row in db.getAllRows(sql"SELECT name FROM magma_schema_migrations"):
      case row[0]
      of BlobSchemaMigration: result.blobs = true
      of CosineIndexMigration: result.vecIndex = true
      of CosineIndexFailed: result.vecFailed = true
      else: discard

  proc openStoreDb(a: SqliteMagmaStoreAdapter): tuple[db: DbConn, vecReady: bool] =
    let db = a.openDb()
    try:
      let vecAvailable = (hasEmbeddedSqliteVec() or a.vectorExtensionPath.len > 0) and
        db.hasLoadedVec()
      var migrations = db.schemaMigrations()
      let rebuildVec = vecAvailable and not migrations.vecIndex and
        not migrations.vecFailed
      if not migrations.blobs or rebuildVec:
        db.writeTransaction:
          db.exec(sql"CREATE TABLE IF NOT EXISTS magma_schema_migrations (name TEXT PRIMARY KEY)")
          migrations = db.schemaMigrations()
          if not migrations.blobs:
            db.migrateBlobSchema()
          if vecAvailable and not migrations.vecIndex and not migrations.vecFailed:
            migrations.vecIndex = db.rebuildVecIndex()
      (db, vecAvailable and migrations.vecIndex)
    except CatchableError:
      db.close()
      raise

  proc tryOpenStoreDb(a: SqliteMagmaStoreAdapter):
      Result[tuple[db: DbConn, vecReady: bool], string] =
    ## openStoreDb for the store operations: a locked or unreadable database
    ## (for example another writer holding the lock past busy_timeout during
    ## a migration) becomes an error value instead of leaving the adapter.
    try:
      ok(a.openStoreDb())
    except CatchableError as e:
      err("open store: " & e.msg)

  template openStoreOr(a: SqliteMagmaStoreAdapter; fallback: untyped) {.dirty.} =
    ## Opens the store as `db`/`vecReady`, or logs and returns `fallback`
    ## (which may read `opened.error`).
    let opened = a.tryOpenStoreDb()
    if opened.isErr:
      stderr.writeLine("WARN magma.sqlite: " & opened.error)
      return fallback
    let (db, vecReady) = opened.get()
    discard vecReady

  proc parseMeta(raw: string): JsonNode =
    if raw.len == 0:
      return newJObject()
    try:
      parseJson(raw)
    except CatchableError:
      newJObject()

  proc rowToNode(row: Row): MagmaNode =
    let vectorBlob =
      if row.len > 4: decodeVectorBlob(row[4])
      else: @[]
    let legacyVector =
      if row.len > 7 and row[7].len > 0: parseVectorLiteral(row[7])
      else: @[]
    MagmaNode(
      id: row[0],
      userId: row[1],
      nodeType: row[2],
      content: row[3],
      embedding: if vectorBlob.len > 0: vectorBlob else: legacyVector,
      timestamp: parseBiggestInt(row[5]),
      meta: parseMeta(row[6]),
    )

  func cosineSimilarity(a, b: seq[float32]): float32 =
    if a.len == 0 or b.len == 0:
      return 0.0'f32
    let n = min(a.len, b.len)
    var dot = 0.0
    var normA = 0.0
    var normB = 0.0
    for i in 0 ..< n:
      dot += a[i].float64 * b[i].float64
      normA += a[i].float64 * a[i].float64
      normB += b[i].float64 * b[i].float64
    if normA <= 0.0 or normB <= 0.0:
      return 0.0'f32
    (dot / (sqrt(normA) * sqrt(normB))).float32

  proc migrate*(a: SqliteMagmaStoreAdapter) =
    let opened = a.tryOpenStoreDb()
    if opened.isErr:
      stderr.writeLine("WARN magma.sqlite: " & opened.error)
      return
    opened.get().db.close()

  proc writeNode(db: DbConn; node: MagmaNode; upsert: bool) =
    let metaJson = if node.meta != nil: $node.meta else: "{}"
    let blob = encodeVectorBlob(node.embedding)
    let insert = (if upsert: "INSERT INTO " else: "INSERT OR IGNORE INTO ") &
      SqliteNodesTable & " (id, user_id, node_type, content, " &
      SqliteLegacyEmbeddingColumn & ", " & SqliteVectorEmbeddingColumn & ", ts, meta)"
    let onConflict =
      if upsert:
        " ON CONFLICT(id) DO UPDATE SET user_id=excluded.user_id, node_type=excluded.node_type," &
        " content=excluded.content, " & SqliteLegacyEmbeddingColumn & "=''," &
        " " & SqliteVectorEmbeddingColumn & "=excluded." & SqliteVectorEmbeddingColumn &
        ", ts=excluded.ts, meta=excluded.meta"
      else:
        ""
    if blob.len == 0:
      db.exec(sql(insert & " VALUES (?, ?, ?, ?, '', X'', ?, ?)" & onConflict),
        node.id, node.userId, node.nodeType, node.content, node.timestamp, metaJson)
    else:
      let stmt = db.prepare(insert & " VALUES (?, ?, ?, ?, '', ?, ?, ?)" & onConflict)
      try:
        stmt.bindParams(node.id, node.userId, node.nodeType, node.content,
          blobBytes(blob), node.timestamp, metaJson)
      except DbError:
        stmt.finalize()
        raise
      if not db.tryExec(stmt):
        # db_connector finalizes an unsuccessful prepared statement in tryExec.
        dbError(db)
      stmt.finalize()

  proc insertNode*(a: SqliteMagmaStoreAdapter; node: MagmaNode): bool =
    openStoreOr(a, false)
    defer: db.close()
    try:
      var inserted: bool
      db.writeTransaction:
        db.writeNode(node, upsert = false)
        inserted = db.getValue(sql"SELECT changes()") == "1"
        if inserted:
          db.updateVecIndex(vecReady, node.id)
      inserted
    except CatchableError:
      false

  proc upsertNode*(a: SqliteMagmaStoreAdapter;
                   node: MagmaNode): Result[void, string] =
    ## Inserts or replaces a node. A refused write comes back as an error:
    ## the caller must be able to tell a stored node from a lost one.
    try:
      openStoreOr(a, err(opened.error))
      defer: db.close()
      db.writeTransaction:
        db.writeNode(node, upsert = true)
        db.updateVecIndex(vecReady, node.id)
      ok()
    except CatchableError as e:
      err("upsert node: " & e.msg)

  proc getNode*(a: SqliteMagmaStoreAdapter; nodeId: string): Option[MagmaNode] =
    openStoreOr(a, none(MagmaNode))
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
        ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " &
        SqliteNodesTable & " WHERE id = ?"
      ), nodeId)
      if rows.len > 0: some(rowToNode(rows[0])) else: none(MagmaNode)
    except CatchableError:
      none(MagmaNode)

  proc listNodes*(a: SqliteMagmaStoreAdapter; userId: string; nodeType: string = ""): seq[MagmaNode] =
    openStoreOr(a, newSeq[MagmaNode]())
    defer: db.close()
    try:
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
            ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " &
            SqliteNodesTable & " WHERE user_id = ? AND node_type = ? ORDER BY ts ASC, rowid ASC"
          ), userId, nodeType)
        else:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
            ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " &
            SqliteNodesTable & " WHERE user_id = ? ORDER BY ts ASC, rowid ASC"
          ), userId)
      for row in rows:
        result.add(rowToNode(row))
    except CatchableError:
      discard

  proc listNodesLimited*(a: SqliteMagmaStoreAdapter; userId: string;
                         nodeType: string = ""; limit, maxContentBytes: int):
                         Result[seq[MagmaNode], string] =
    if limit <= 0 or maxContentBytes <= 0:
      return ok(newSeq[MagmaNode]())
    openStoreOr(a, err(opened.error))
    defer: db.close()
    try:
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, substr(content, 1, ?), ts, '{}' FROM " &
            SqliteNodesTable & " WHERE user_id = ? AND node_type = ? " &
            "ORDER BY ts DESC, rowid DESC LIMIT ?"
          ), maxContentBytes, userId, nodeType, limit)
        else:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, substr(content, 1, ?), ts, '{}' FROM " &
            SqliteNodesTable & " WHERE user_id = ? " &
            "ORDER BY ts DESC, rowid DESC LIMIT ?"
          ), maxContentBytes, userId, limit)
      var nodes: seq[MagmaNode]
      for row in rows:
        nodes.add(MagmaNode(
          id: row[0],
          userId: row[1],
          nodeType: row[2],
          content: row[3],
          timestamp: parseBiggestInt(row[4]),
          meta: newJObject(),
        ))
      ok(nodes)
    except CatchableError as e:
      err("listNodesLimited failed: " & e.msg)

  proc deleteNode*(a: SqliteMagmaStoreAdapter; nodeId: string): bool =
    openStoreOr(a, false)
    defer: db.close()
    try:
      var deleted: bool
      db.writeTransaction:
        db.updateVecIndex(vecReady, nodeId, deleting = true)
        db.exec(sql("DELETE FROM " & SqliteNodesTable & " WHERE id = ?"), nodeId)
        deleted = db.getValue(sql"SELECT changes()") == "1"
      deleted
    except CatchableError:
      false

  proc insertEdge*(a: SqliteMagmaStoreAdapter; edge: MagmaEdge): bool =
    openStoreOr(a, false)
    defer: db.close()
    try:
      db.exec(sql(
        "INSERT OR IGNORE INTO " & SqliteEdgesTable &
        " (from_id, to_id, edge_type, weight, meta, created_at) VALUES (?, ?, ?, ?, ?, ?)"
      ), edge.fromId, edge.toId, edge.edgeType, $edge.weight,
         if edge.meta != nil: $edge.meta else: "{}", $getTime().toUnix())
      let row = db.getRow(sql("SELECT changes()"))
      row.len > 0 and row[0] != "0"
    except CatchableError:
      false

  proc getEdges*(a: SqliteMagmaStoreAdapter; nodeId: string;
                 edgeType: string = ""; direction: string = "out"): seq[MagmaEdge] =
    openStoreOr(a, newSeq[MagmaEdge]())
    defer: db.close()
    try:
      var query = "SELECT from_id, to_id, edge_type, weight, meta FROM " & SqliteEdgesTable & " WHERE "
      var args: seq[string]
      if direction == "out":
        query.add("from_id = ?")
        args.add(nodeId)
      elif direction == "in":
        query.add("to_id = ?")
        args.add(nodeId)
      else:
        query.add("(from_id = ? OR to_id = ?)")
        args.add(nodeId)
        args.add(nodeId)
      if edgeType.len > 0:
        query.add(" AND edge_type = ?")
        args.add(edgeType)
      query.add(" ORDER BY id")
      for row in db.getAllRows(sql(query), args):
        result.add(MagmaEdge(
          fromId: row[0],
          toId: row[1],
          edgeType: row[2],
          weight: try: parseFloat(row[3]) except CatchableError: 1.0,
          meta: parseMeta(row[4]),
        ))
    except CatchableError:
      discard

  proc deleteEdges*(a: SqliteMagmaStoreAdapter; nodeId: string; edgeType: string = ""): int =
    openStoreOr(a, 0)
    defer: db.close()
    try:
      if edgeType.len > 0:
        db.exec(sql(
          "DELETE FROM " & SqliteEdgesTable & " WHERE (from_id = ? OR to_id = ?) AND edge_type = ?"
        ), nodeId, nodeId, edgeType)
      else:
        db.exec(sql(
          "DELETE FROM " & SqliteEdgesTable & " WHERE from_id = ? OR to_id = ?"
        ), nodeId, nodeId)
      let row = db.getRow(sql("SELECT changes()"))
      if row.len > 0: parseInt(row[0]) else: 0
    except CatchableError:
      0

  proc getLastNode*(a: SqliteMagmaStoreAdapter; userId: string; nodeType: string = ""): Option[MagmaNode] =
    ## Most recently inserted node for the user, optionally of one type.
    ## `ts` has one-second resolution and ids sort as text ("m9" > "m10"), so
    ## ties are broken by rowid, which follows insertion order.
    openStoreOr(a, none(MagmaNode))
    defer: db.close()
    try:
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
            ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " &
            SqliteNodesTable & " WHERE user_id = ? AND node_type = ? " &
            "ORDER BY ts DESC, rowid DESC LIMIT 1"
          ), userId, nodeType)
        else:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
            ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " &
            SqliteNodesTable & " WHERE user_id = ? " &
            "ORDER BY ts DESC, rowid DESC LIMIT 1"
          ), userId)
      if rows.len > 0: some(rowToNode(rows[0])) else: none(MagmaNode)
    except CatchableError:
      none(MagmaNode)

  proc linkTemporal*(a: SqliteMagmaStoreAdapter; fromId, toId: string) =
    discard a.insertEdge(MagmaEdge(fromId: fromId, toId: toId, edgeType: EdgeTemporal))

  const VecKnnMaxK = 4096
    ## Largest `k` the vector index accepts in one query.

  proc searchSimilar*(a: SqliteMagmaStoreAdapter; userId: string;
                      embedding: seq[float32];
                      topK: int = 10;
                      minScore: float32 = 0.0;
                      nodeType: string = ""): seq[MagmaHit] =
    ## Nearest nodes by cosine similarity. With `nodeType`, only nodes of that
    ## type count toward `topK`. The vector index knows nothing of types, so
    ## the neighbourhood is widened until enough nodes of the type are found
    ## or the index has no more to give; past its largest `k` the search
    ## falls back to comparing every node of the type.
    openStoreOr(a, newSeq[MagmaHit]())
    defer: db.close()
    if embedding.len == 0 or topK <= 0:
      return @[]
    if vecReady and embedding.len == SqliteVectorDimension and topK <= VecKnnMaxK:
      try:
        let queryVector = buildVectorJson(embedding)
        var k = topK
        var exhausted = false
        while true:
          let rows = db.getAllRows(sql(
            "SELECT n.id, n.user_id, n.node_type, n.content, n." & SqliteVectorEmbeddingColumn &
            ", n.ts, n.meta, n." & SqliteLegacyEmbeddingColumn &
            ", (1.0 - v.distance) AS score " &
            "FROM (" &
            "  SELECT rowid, distance FROM " & SqliteVecTable &
            " WHERE embedding MATCH ? AND k = ? AND user_id = ?" &
            ") AS v " &
            "JOIN " & SqliteNodesTable & " n ON n.rowid = v.rowid " &
            "WHERE (1.0 - v.distance) >= CAST(? AS REAL) " &
            "AND EXISTS (SELECT 1 FROM magma_schema_migrations WHERE name = ?) " &
            "ORDER BY v.distance LIMIT ?"
          ), queryVector, $k, userId, $minScore, CosineIndexMigration, $k)
          result.setLen(0)
          for row in rows:
            if nodeType.len > 0 and row[2] != nodeType:
              continue
            if result.len >= topK:
              break
            result.add(MagmaHit(
              node: rowToNode(row[0 .. 7]),
              score: clamp(try: parseFloat(row[8]) except CatchableError: 0.0, 0.0, 1.0).float32,
              path: @[row[0]],
            ))
          if result.len >= topK or rows.len < k:
            exhausted = true
            break
          if k >= VecKnnMaxK:
            break
          k = min(k * 4, VecKnnMaxK)
        # Non-indexable legacy vectors can still meet a zero or negative
        # threshold in the in-process cosine fallback.
        if exhausted and result.len > 0 and
           (minScore > 0 or (result.len == topK and result[^1].score > 0)):
          return result
      except CatchableError:
        discard
    result.setLen(0)
    type RankedHit = tuple[node: MagmaNode, score: float32]
    var ranked: seq[RankedHit]
    for node in a.listNodes(userId, nodeType):
      if node.embedding.len == 0:
        continue
      let score = cosineSimilarity(node.embedding, embedding)
      if score >= minScore:
        ranked.add((node, score))
    ranked.sort(proc(x, y: RankedHit): int = cmp(y.score, x.score))
    for hit in ranked:
      if result.len >= topK:
        break
      result.add(MagmaHit(node: hit.node, score: hit.score, path: @[hit.node.id]))

  proc queryByTimeRange*(a: SqliteMagmaStoreAdapter; userId: string;
                         tsStart, tsEnd: int64; limit: int = 50;
                         nodeType: string = ""): seq[MagmaNode] =
    ## Newest first. With `nodeType`, the filter is part of the query, so the
    ## limit counts only nodes of that type.
    openStoreOr(a, newSeq[MagmaNode]())
    defer: db.close()
    try:
      let columns =
        "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
        ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " & SqliteNodesTable
      let order = " ORDER BY ts DESC, rowid DESC LIMIT ?"
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            columns & " WHERE user_id = ? AND node_type = ? AND ts BETWEEN ? AND ?" & order
          ), userId, nodeType, $tsStart, $tsEnd, $limit)
        else:
          db.getAllRows(sql(
            columns & " WHERE user_id = ? AND ts BETWEEN ? AND ?" & order
          ), userId, $tsStart, $tsEnd, $limit)
      for row in rows:
        result.add(rowToNode(row))
    except CatchableError:
      discard

  proc traverseNeighbors*(a: SqliteMagmaStoreAdapter; nodeId: string;
                          edgeTypes: seq[string] = @[]; maxDepth: int = 2): seq[MagmaNode] =
    var visited = @[nodeId]
    var frontier = @[nodeId]
    var depth = 0
    while frontier.len > 0 and depth < maxDepth:
      var nextFrontier: seq[string]
      for current in frontier:
        for edge in a.getEdges(current, direction = "both"):
          if edgeTypes.len > 0 and edge.edgeType notin edgeTypes:
            continue
          let neighborId = if edge.fromId == current: edge.toId else: edge.fromId
          if neighborId in visited:
            continue
          visited.add(neighborId)
          nextFrontier.add(neighborId)
          let node = a.getNode(neighborId)
          if node.isSome:
            result.add(node.get())
      frontier = nextFrontier
      inc depth

  proc stats*(a: SqliteMagmaStoreAdapter; userId: string): MagmaStats =
    openStoreOr(a, MagmaStats())
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(nodeStatsSql(SqliteNodesTable, "length(" & SqliteVectorEmbeddingColumn & ") > 0 OR " & SqliteLegacyEmbeddingColumn & " != ''", perUser = true)), userId)
      if rows.len > 0:
        result = nodeStatsFromRow(rows[0])
      let edgeRows = db.getAllRows(sql(edgeCountSql(SqliteEdgesTable, SqliteNodesTable, perUser = true)), userId)
      if edgeRows.len > 0:
        result.totalEdges = parseCount(edgeRows[0][0])
    except CatchableError:
      discard

  proc stats*(a: SqliteMagmaStoreAdapter): MagmaStats =
    openStoreOr(a, MagmaStats())
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(nodeStatsSql(SqliteNodesTable, "length(" & SqliteVectorEmbeddingColumn & ") > 0 OR " & SqliteLegacyEmbeddingColumn & " != ''", perUser = false)))
      if rows.len > 0:
        result = nodeStatsFromRow(rows[0])
      let edgeRows = db.getAllRows(sql(edgeCountSql(SqliteEdgesTable, SqliteNodesTable, perUser = false)))
      if edgeRows.len > 0:
        result.totalEdges = parseCount(edgeRows[0][0])
    except CatchableError:
      discard

  proc toStorePort*(a: SqliteMagmaStoreAdapter): MultigraphStorePort =
    MultigraphStorePort(
      migrate: proc() {.gcsafe.} = a.migrate(),
      insertNode: proc(node: MagmaNode): bool {.gcsafe.} = a.insertNode(node),
      upsertNode: proc(node: MagmaNode): Result[void, string] {.gcsafe.} =
        a.upsertNode(node),
      getNode: proc(nodeId: string): Option[MagmaNode] {.gcsafe.} = a.getNode(nodeId),
      listNodes: proc(userId: string; nodeType: string = ""): seq[MagmaNode] {.gcsafe.} = a.listNodes(userId, nodeType),
      listNodesLimited: proc(userId: string; nodeType: string = "";
                             limit, maxContentBytes: int):
                             Result[seq[MagmaNode], string] {.gcsafe.} =
        a.listNodesLimited(userId, nodeType, limit, maxContentBytes),
      deleteNode: proc(nodeId: string): bool {.gcsafe.} = a.deleteNode(nodeId),
      insertEdge: proc(edge: MagmaEdge): bool {.gcsafe.} = a.insertEdge(edge),
      getEdges: proc(nodeId: string; edgeType: string = ""; direction: string = "out"): seq[MagmaEdge] {.gcsafe.} =
        a.getEdges(nodeId, edgeType = edgeType, direction = direction),
      deleteEdges: proc(nodeId: string; edgeType: string = ""): int {.gcsafe.} = a.deleteEdges(nodeId, edgeType),
      getLastNode: proc(userId: string; nodeType: string = ""): Option[MagmaNode] {.gcsafe.} = a.getLastNode(userId, nodeType),
      linkTemporal: proc(fromId, toId: string) {.gcsafe.} = a.linkTemporal(fromId, toId),
      searchSimilar: proc(userId: string; embedding: seq[float32]; topK: int = 10; minScore: float32 = 0.0; nodeType: string = ""): seq[MagmaHit] {.gcsafe.} =
        a.searchSimilar(userId, embedding, topK = topK, minScore = minScore,
                        nodeType = nodeType),
      queryByTimeRange: proc(userId: string; tsStart, tsEnd: int64; limit: int = 50; nodeType: string = ""): seq[MagmaNode] {.gcsafe.} =
        a.queryByTimeRange(userId, tsStart, tsEnd, limit = limit,
                           nodeType = nodeType),
      traverseNeighbors: proc(nodeId: string; edgeTypes: seq[string] = @[]; maxDepth: int = 2): seq[MagmaNode] {.gcsafe.} =
        a.traverseNeighbors(nodeId, edgeTypes = edgeTypes, maxDepth = maxDepth),
      statsForUser: proc(userId: string): MagmaStats {.gcsafe.} = a.stats(userId),
      statsGlobal: proc(): MagmaStats {.gcsafe.} = a.stats(),
    )

else:
  type
    SqliteMagmaStoreAdapter* = ref object

  func sqliteVecPlatformDir*(): string = ""
  func sqliteVecExtensionFileName*(): string = ""
  proc resolveVecExtensionPath*(explicitPath = ""; cwd = ""; appPath = ""): string = ""

  proc newSqliteMagmaStoreAdapter*(dbPath: string; vectorExtensionPath = ""): SqliteMagmaStoreAdapter =
    SqliteMagmaStoreAdapter()

  proc toStorePort*(a: SqliteMagmaStoreAdapter): MultigraphStorePort = MultigraphStorePort()
