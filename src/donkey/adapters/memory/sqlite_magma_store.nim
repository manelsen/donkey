## sqlite_magma_store — SQLite-backed MAGMA store.
##
## Embeddings are stored as BLOBs so the store can use sqlite-vec when the
## extension is available. The graph layout remains relational for now.

import ../../core/pipeops
import ../../ports/multigraph_store

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

  func configuredVecEnvPath(): string =
    let vecPath = getEnv("DONKEY_SQLITE_VEC_PATH")
    if vecPath.len > 0:
      return vecPath
    getEnv("DONKEY_SQLITE_VECTOR_PATH")

  proc resolveVecExtensionPath*(explicitPath = "";
                                cwd = getCurrentDir();
                                appPath = getAppFilename()): string =
    let configured =
      if explicitPath.len > 0: explicitPath
      else: configuredVecEnvPath()
    if configured.len > 0 and fileExists(configured):
      return configured
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
                                   vectorExtensionPath = configuredVecEnvPath()): SqliteMagmaStoreAdapter =
    SqliteMagmaStoreAdapter(
      dbPath: dbPath,
      vectorExtensionPath: resolveVecExtensionPath(vectorExtensionPath),
    )

  proc openDb(a: SqliteMagmaStoreAdapter): DbConn =
    ensureEmbeddedSqliteVecRegistered()
    result = db_sqlite.open(a.dbPath, "", "", "")
    result.exec(sql"PRAGMA foreign_keys = ON")
    if not hasEmbeddedSqliteVec() and a.vectorExtensionPath.len > 0:
      try:
        result.enableLoadExtension()
        result.loadExtension(a.vectorExtensionPath)
      except CatchableError:
        discard

  func hasVectorExtension(a: SqliteMagmaStoreAdapter): bool =
    hasEmbeddedSqliteVec() or a.vectorExtensionPath.len > 0

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

  proc tryInitVec(a: SqliteMagmaStoreAdapter; db: DbConn): bool =
    if not a.hasVectorExtension or not db.hasLoadedVec():
      return false
    try:
      db.exec(sql("""CREATE VIRTUAL TABLE IF NOT EXISTS """ & SqliteVecTable &
        """ USING vec0(
          user_id TEXT PARTITION KEY,
          embedding FLOAT[""" & $SqliteVectorDimension & """]
        )"""))
      true
    except CatchableError:
      false

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

  proc syncVecRow(db: DbConn; nodeRowid, userId, blob: string) =
    if not db.hasLoadedVec():
      return
    try:
      db.exec(sql("DELETE FROM " & SqliteVecTable & " WHERE rowid = ?"), nodeRowid)
    except CatchableError:
      discard
    if blob.len == 0:
      return
    try:
      let stmt = db.prepare(
        "INSERT INTO " & SqliteVecTable & " (rowid, user_id, embedding) VALUES (?, ?, ?)"
      )
      let blobData = blobBytes(blob)
      stmt.bindParam(1, nodeRowid)
      stmt.bindParam(2, userId)
      stmt.bindParam(3, blobData)
      db.exec(stmt)
      stmt.finalize()
    except CatchableError:
      discard

  proc backfillVecIndex(db: DbConn) =
    if not db.hasLoadedVec():
      return
    let rows = db.getAllRows(sql(
      "SELECT rowid, user_id, " & SqliteVectorEmbeddingColumn &
      " FROM " & SqliteNodesTable &
      " WHERE length(" & SqliteVectorEmbeddingColumn & ") > 0"
    ))
    for row in rows:
      db.syncVecRow(row[0], row[1], row[2])

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
      let blobData = blobBytes(blob)
      let stmt = db.prepare(
        "UPDATE " & SqliteNodesTable & " SET " & SqliteVectorEmbeddingColumn &
        " = ?, " & SqliteLegacyEmbeddingColumn & " = '' WHERE id = ?"
      )
      stmt.bindParam(1, blobData)
      stmt.bindParam(2, row[0])
      db.exec(stmt)
      stmt.finalize()

  proc ensureSchema(a: SqliteMagmaStoreAdapter) =
    let db = a.openDb()
    defer: db.close()
    db.createNodesTable()
    db.ensureVectorColumn()
    db.backfillVectorEmbeddings()
    discard a.tryInitVec(db)
    db.backfillVecIndex()
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
    a.ensureSchema()

  proc insertNode*(a: SqliteMagmaStoreAdapter; node: MagmaNode): bool =
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    try:
      var inserted = false
      let metaJson = if node.meta != nil: $node.meta else: "{}"
      let blob = encodeVectorBlob(node.embedding)
      if blob.len > 0:
        block:
          let stmt = db.prepare(
            "INSERT OR IGNORE INTO " & SqliteNodesTable &
            " (id, user_id, node_type, content, " & SqliteLegacyEmbeddingColumn &
            ", " & SqliteVectorEmbeddingColumn &
            ", ts, meta) VALUES (?, ?, ?, ?, '', ?, ?, ?)"
          )
          defer: stmt.finalize()
          let blobData = blobBytes(blob)
          stmt.bindParam(1, node.id)
          stmt.bindParam(2, node.userId)
          stmt.bindParam(3, node.nodeType)
          stmt.bindParam(4, node.content)
          stmt.bindParam(5, blobData)
          stmt.bindParam(6, $node.timestamp)
          stmt.bindParam(7, metaJson)
          db.exec(stmt)
        let row = db.getRow(sql("SELECT changes()"))
        inserted = row.len > 0 and row[0] != "0"
        let rowid = db.getValue(sql("SELECT rowid FROM " & SqliteNodesTable & " WHERE id = ?"), node.id)
        db.syncVecRow(rowid, node.userId, blob)
      else:
        db.exec(sql(
          "INSERT OR IGNORE INTO " & SqliteNodesTable &
          " (id, user_id, node_type, content, ts, meta) VALUES (?, ?, ?, ?, ?, ?)"
        ), node.id, node.userId, node.nodeType, node.content,
           $node.timestamp, metaJson)
        let row = db.getRow(sql("SELECT changes()"))
        inserted = row.len > 0 and row[0] != "0"
      inserted
    except CatchableError:
      false

  proc upsertNode*(a: SqliteMagmaStoreAdapter; node: MagmaNode) =
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    try:
      let metaJson = if node.meta != nil: $node.meta else: "{}"
      let blob = encodeVectorBlob(node.embedding)
      if blob.len > 0:
        block:
          let stmt = db.prepare(
            "INSERT INTO " & SqliteNodesTable &
            " (id, user_id, node_type, content, " & SqliteLegacyEmbeddingColumn &
            ", " & SqliteVectorEmbeddingColumn & ", ts, meta) VALUES (?, ?, ?, ?, '', ?, ?, ?) " &
            "ON CONFLICT(id) DO UPDATE SET user_id=excluded.user_id, node_type=excluded.node_type, " &
            "content=excluded.content, " & SqliteLegacyEmbeddingColumn & "=excluded." &
            SqliteLegacyEmbeddingColumn & ", " & SqliteVectorEmbeddingColumn &
            "=excluded." & SqliteVectorEmbeddingColumn & ", ts=excluded.ts, meta=excluded.meta"
          )
          defer: stmt.finalize()
          let blobData = blobBytes(blob)
          stmt.bindParam(1, node.id)
          stmt.bindParam(2, node.userId)
          stmt.bindParam(3, node.nodeType)
          stmt.bindParam(4, node.content)
          stmt.bindParam(5, blobData)
          stmt.bindParam(6, $node.timestamp)
          stmt.bindParam(7, metaJson)
          db.exec(stmt)
        let rowid = db.getValue(sql("SELECT rowid FROM " & SqliteNodesTable & " WHERE id = ?"), node.id)
        db.syncVecRow(rowid, node.userId, blob)
      else:
        db.exec(sql(
          "INSERT INTO " & SqliteNodesTable &
          " (id, user_id, node_type, content, ts, meta) VALUES (?, ?, ?, ?, ?, ?) " &
          "ON CONFLICT(id) DO UPDATE SET user_id=excluded.user_id, node_type=excluded.node_type, " &
          "content=excluded.content, " & SqliteLegacyEmbeddingColumn & "='', " &
          SqliteVectorEmbeddingColumn & "=X'', ts=excluded.ts, meta=excluded.meta"
        ), node.id, node.userId, node.nodeType, node.content,
           $node.timestamp, metaJson)
        let rowid = db.getValue(sql("SELECT rowid FROM " & SqliteNodesTable & " WHERE id = ?"), node.id)
        db.syncVecRow(rowid, node.userId, "")
    except CatchableError:
      discard

  proc getNode*(a: SqliteMagmaStoreAdapter; nodeId: string): Option[MagmaNode] =
    a.ensureSchema()
    let db = a.openDb()
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
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    try:
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
            ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " &
            SqliteNodesTable & " WHERE user_id = ? AND node_type = ? ORDER BY ts ASC, id ASC"
          ), userId, nodeType)
        else:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
            ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " &
            SqliteNodesTable & " WHERE user_id = ? ORDER BY ts ASC, id ASC"
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
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    try:
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, substr(content, 1, ?), ts, '{}' FROM " &
            SqliteNodesTable & " WHERE user_id = ? AND node_type = ? " &
            "ORDER BY ts DESC, id DESC LIMIT ?"
          ), maxContentBytes, userId, nodeType, limit)
        else:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, substr(content, 1, ?), ts, '{}' FROM " &
            SqliteNodesTable & " WHERE user_id = ? " &
            "ORDER BY ts DESC, id DESC LIMIT ?"
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
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    try:
      let nodeRowid = db.getValue(sql("SELECT rowid FROM " & SqliteNodesTable & " WHERE id = ?"), nodeId)
      if nodeRowid.len > 0 and db.hasLoadedVec():
        try:
          db.exec(sql("DELETE FROM " & SqliteVecTable & " WHERE node_rowid = ?"), nodeRowid)
        except CatchableError:
          discard
      db.exec(sql("DELETE FROM " & SqliteNodesTable & " WHERE id = ?"), nodeId)
      let row = db.getRow(sql("SELECT changes()"))
      row.len > 0 and row[0] != "0"
    except CatchableError:
      false

  proc insertEdge*(a: SqliteMagmaStoreAdapter; edge: MagmaEdge): bool =
    a.ensureSchema()
    let db = a.openDb()
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
    a.ensureSchema()
    let db = a.openDb()
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
          weight: try: parseFloat(row[3]) except: 1.0,
          meta: parseMeta(row[4]),
        ))
    except CatchableError:
      discard

  proc deleteEdges*(a: SqliteMagmaStoreAdapter; nodeId: string; edgeType: string = ""): int =
    a.ensureSchema()
    let db = a.openDb()
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
    let nodes = a.listNodes(userId, nodeType)
    if nodes.len > 0: some(nodes[^1]) else: none(MagmaNode)

  proc linkTemporal*(a: SqliteMagmaStoreAdapter; fromId, toId: string) =
    discard a.insertEdge(MagmaEdge(fromId: fromId, toId: toId, edgeType: EdgeTemporal))

  proc searchSimilar*(a: SqliteMagmaStoreAdapter; userId: string;
                      embedding: seq[float32];
                      topK: int = 10;
                      minScore: float32 = 0.0): seq[MagmaHit] =
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    if embedding.len == 0:
      return @[]
    if a.tryInitVec(db):
      try:
        let rows = db.getAllRows(sql(
          "SELECT n.id, n.user_id, n.node_type, n.content, n." & SqliteVectorEmbeddingColumn &
          ", n.ts, n.meta, n." & SqliteLegacyEmbeddingColumn &
          ", (1.0 - v.distance) AS score " &
          "FROM (" &
          "  SELECT rowid, distance FROM " & SqliteVecTable &
          " WHERE embedding MATCH ? AND k = ? AND user_id = ?" &
          ") AS v " &
          "JOIN " & SqliteNodesTable & " n ON n.rowid = v.rowid " &
          "WHERE (1.0 - v.distance) >= ? " &
          "ORDER BY v.distance LIMIT ?"
        ), buildVectorJson(embedding), $topK, userId, $minScore, $topK)
        for row in rows:
          result.add(MagmaHit(
            node: rowToNode(row[0 .. 7]),
            score: clamp(try: parseFloat(row[8]) except: 0.0, 0.0, 1.0).float32,
            path: @[row[0]],
          ))
        if result.len > 0:
          return result
      except CatchableError:
        discard
    type RankedHit = tuple[node: MagmaNode, score: float32]
    var ranked: seq[RankedHit]
    for node in a.listNodes(userId):
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
                         tsStart, tsEnd: int64; limit: int = 50): seq[MagmaNode] =
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    try:
      for row in db.getAllRows(sql(
        "SELECT id, user_id, node_type, content, " & SqliteVectorEmbeddingColumn &
        ", ts, meta, " & SqliteLegacyEmbeddingColumn & " FROM " &
        SqliteNodesTable & " WHERE user_id = ? AND ts BETWEEN ? AND ? ORDER BY ts DESC LIMIT ?"
      ), userId, $tsStart, $tsEnd, $limit):
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

  func parseCount(raw: string): int =
    if raw.len == 0: 0 else: parseInt(raw)

  proc stats*(a: SqliteMagmaStoreAdapter; userId: string): MagmaStats =
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT COUNT(*), " &
        "COALESCE(SUM(CASE WHEN node_type = 'memory' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'user_profile' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'preference' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'entity' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN length(" & SqliteVectorEmbeddingColumn &
        ") > 0 OR " & SqliteLegacyEmbeddingColumn & " != '' THEN 1 ELSE 0 END), 0) " &
        "FROM " & SqliteNodesTable & " WHERE user_id = ?"
      ), userId)
      if rows.len > 0:
        result.totalNodes = parseCount(rows[0][0])
        result.memoryNodes = parseCount(rows[0][1])
        result.profileNodes = parseCount(rows[0][2])
        result.preferenceNodes = parseCount(rows[0][3])
        result.entityNodes = parseCount(rows[0][4])
        result.embeddingNodes = parseCount(rows[0][5])
      let edgeRows = db.getAllRows(sql(
        "SELECT COUNT(*) FROM " & SqliteEdgesTable &
        " e JOIN " & SqliteNodesTable & " n ON e.from_id = n.id WHERE n.user_id = ?"
      ), userId)
      if edgeRows.len > 0:
        result.totalEdges = parseCount(edgeRows[0][0])
    except CatchableError:
      discard

  proc stats*(a: SqliteMagmaStoreAdapter): MagmaStats =
    a.ensureSchema()
    let db = a.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT COUNT(*), " &
        "COALESCE(SUM(CASE WHEN node_type = 'memory' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'user_profile' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'preference' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'entity' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN length(" & SqliteVectorEmbeddingColumn &
        ") > 0 OR " & SqliteLegacyEmbeddingColumn & " != '' THEN 1 ELSE 0 END), 0) " &
        "FROM " & SqliteNodesTable
      ))
      if rows.len > 0:
        result.totalNodes = parseCount(rows[0][0])
        result.memoryNodes = parseCount(rows[0][1])
        result.profileNodes = parseCount(rows[0][2])
        result.preferenceNodes = parseCount(rows[0][3])
        result.entityNodes = parseCount(rows[0][4])
        result.embeddingNodes = parseCount(rows[0][5])
      let edgeRows = db.getAllRows(sql("SELECT COUNT(*) FROM " & SqliteEdgesTable))
      if edgeRows.len > 0:
        result.totalEdges = parseCount(edgeRows[0][0])
    except CatchableError:
      discard

  proc toStorePort*(a: SqliteMagmaStoreAdapter): MultigraphStorePort =
    MultigraphStorePort(
      migrate: proc() {.gcsafe.} = a.migrate(),
      insertNode: proc(node: MagmaNode): bool {.gcsafe.} = a.insertNode(node),
      upsertNode: proc(node: MagmaNode) {.gcsafe.} = a.upsertNode(node),
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
      searchSimilar: proc(userId: string; embedding: seq[float32]; topK: int = 10; minScore: float32 = 0.0): seq[MagmaHit] {.gcsafe.} =
        a.searchSimilar(userId, embedding, topK = topK, minScore = minScore),
      queryByTimeRange: proc(userId: string; tsStart, tsEnd: int64; limit: int = 50): seq[MagmaNode] {.gcsafe.} =
        a.queryByTimeRange(userId, tsStart, tsEnd, limit = limit),
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
