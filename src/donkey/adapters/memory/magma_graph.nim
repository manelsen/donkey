## magma_graph — Multi-graph agentic memory using PostgreSQL + pgvector.
##
## Implements MAGMA (arXiv:2601.03236) with relational tables:
##   magma_nodes  — memory items with embeddings (pgvector)
##   magma_edges  — typed edges: TEMPORAL, CAUSAL, MENTIONS, ABOUT
##
## Four orthogonal graphs:
##   Temporal: ordered chain (n_prev → n_curr) by timestamp
##   Causal:   LLM-inferred cause→effect edges
##   Semantic: pgvector cosine similarity (implicit graph)
##   Entity:   event ↔ entity edges (MENTIONS, ABOUT)
##
## Compile with -d:withPostgres to activate.
## Without the flag the module exports only stub types.

import ../../core/pipeops
import ../../ports/multigraph_store
export multigraph_store

when defined(withPostgres):
  import db_connector/db_postgres
  import std/[hashes, json, locks, options, strutils]

  const
    MagmaNodesTable = "magma_nodes"
    MagmaEdgesTable = "magma_edges"
    EmbeddingDim = 4096
    MagmaSchemaCacheSlots = 16

  # ── Types ───────────────────────────────────────────────────────────────────

  type
    MagmaSchemaKey = object
      hashA: Hash
      hashB: Hash
      length: int

    MagmaGraph* = ref object
      dsn: string

  var gMagmaSchemaLock {.global.}: Lock
  var gMagmaSchemaReady {.global.}: array[MagmaSchemaCacheSlots, MagmaSchemaKey]
  var gMagmaSchemaReadyCount {.global.}: int

  initLock(gMagmaSchemaLock)

  func schemaKey(dsn: string): MagmaSchemaKey =
    MagmaSchemaKey(
      hashA: hash(dsn),
      hashB: hash("magma:" & dsn),
      length: dsn.len,
    )

  proc hasCachedSchema(dsn: string): bool =
    let key = schemaKey(dsn)
    for idx in 0 ..< gMagmaSchemaReadyCount:
      if gMagmaSchemaReady[idx] == key:
        return true
    false

  proc cacheSchemaReady(dsn: string) =
    let key = schemaKey(dsn)
    if hasCachedSchema(dsn):
      return
    if gMagmaSchemaReadyCount >= MagmaSchemaCacheSlots:
      return
    gMagmaSchemaReady[gMagmaSchemaReadyCount] = key
    inc gMagmaSchemaReadyCount

  # ── Schema ──────────────────────────────────────────────────────────────────

  proc schemaSql(): string =
    """
    CREATE EXTENSION IF NOT EXISTS vector;

    CREATE TABLE IF NOT EXISTS """ & MagmaNodesTable & """ (
      id          TEXT PRIMARY KEY,
      user_id     TEXT        NOT NULL,
      node_type   TEXT        NOT NULL DEFAULT 'memory',
      content     TEXT        NOT NULL,
      embedding   vector(""" & $EmbeddingDim & """),
      ts          BIGINT      NOT NULL DEFAULT 0,
      meta        JSONB       NOT NULL DEFAULT '{}'
    );

    CREATE INDEX IF NOT EXISTS idx_mn_user_type
      ON """ & MagmaNodesTable & """ (user_id, node_type);

    CREATE INDEX IF NOT EXISTS idx_mn_user_ts
      ON """ & MagmaNodesTable & """ (user_id, ts);

    CREATE TABLE IF NOT EXISTS """ & MagmaEdgesTable & """ (
      id          BIGSERIAL PRIMARY KEY,
      from_id     TEXT        NOT NULL REFERENCES """ & MagmaNodesTable & """(id) ON DELETE CASCADE,
      to_id       TEXT        NOT NULL REFERENCES """ & MagmaNodesTable & """(id) ON DELETE CASCADE,
      edge_type   TEXT        NOT NULL,
      weight      DOUBLE PRECISION NOT NULL DEFAULT 1.0,
      meta        JSONB       NOT NULL DEFAULT '{}',
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (from_id, to_id, edge_type)
    );

    CREATE INDEX IF NOT EXISTS idx_me_from_type
      ON """ & MagmaEdgesTable & """ (from_id, edge_type);

    CREATE INDEX IF NOT EXISTS idx_me_to_type
      ON """ & MagmaEdgesTable & """ (to_id, edge_type);
    """

  # ── Constructor ─────────────────────────────────────────────────────────────

  proc newMagmaGraph*(dsn: string): MagmaGraph =
    MagmaGraph(dsn: dsn)

  proc openDb*(g: MagmaGraph): DbConn =
    open("", "", "", g.dsn)

  # ── Migration ───────────────────────────────────────────────────────────────

  proc migrate*(g: MagmaGraph) =
    acquire(gMagmaSchemaLock)
    defer: release(gMagmaSchemaLock)
    if hasCachedSchema(g.dsn):
      return
    let db = g.openDb()
    defer: db.close()
    try:
      db.exec(sql"SET client_min_messages TO WARNING")
    except CatchableError:
      discard
    for stmt in schemaSql().split(';'):
      let s = stmt.strip()
      if s.len > 0:
        db.exec(sql(s))
    cacheSchemaReady(g.dsn)

  # ── Node CRUD ───────────────────────────────────────────────────────────────

  proc insertNode*(g: MagmaGraph; node: MagmaNode): bool =
    ## Inserts a node. Returns false if ID already exists.
    let db = g.openDb()
    defer: db.close()
    try:
      let metaStr = if node.meta != nil: $node.meta else: "{}"
      var rows: seq[Row]
      if node.embedding.len > 0:
        let emb = "[" & node.embedding.join(",") & "]"
        rows = db.getAllRows(sql(
          "INSERT INTO " & MagmaNodesTable & " (id, user_id, node_type, content, embedding, ts, meta) " &
          "VALUES (?, ?, ?, ?, ?::vector, ?, ?::jsonb) ON CONFLICT (id) DO NOTHING RETURNING id"
        ), node.id, node.userId, node.nodeType, node.content, emb, $node.timestamp, metaStr)
      else:
        rows = db.getAllRows(sql(
          "INSERT INTO " & MagmaNodesTable & " (id, user_id, node_type, content, ts, meta) " &
          "VALUES (?, ?, ?, ?, ?, ?::jsonb) ON CONFLICT (id) DO NOTHING RETURNING id"
        ), node.id, node.userId, node.nodeType, node.content, $node.timestamp, metaStr)
      rows.len > 0
    except CatchableError:
      false

  proc upsertNode*(g: MagmaGraph; node: MagmaNode) =
    let db = g.openDb()
    defer: db.close()
    try:
      let metaStr = if node.meta != nil: $node.meta else: "{}"
      if node.embedding.len > 0:
        let emb = "[" & node.embedding.join(",") & "]"
        db.exec(sql(
          "INSERT INTO " & MagmaNodesTable & " (id, user_id, node_type, content, embedding, ts, meta) " &
          "VALUES (?, ?, ?, ?, ?::vector, ?, ?::jsonb) " &
          "ON CONFLICT (id) DO UPDATE SET " &
          "user_id = excluded.user_id, node_type = excluded.node_type, content = excluded.content, " &
          "embedding = excluded.embedding, ts = excluded.ts, meta = excluded.meta"
        ), node.id, node.userId, node.nodeType, node.content, emb, $node.timestamp, metaStr)
      else:
        db.exec(sql(
          "INSERT INTO " & MagmaNodesTable & " (id, user_id, node_type, content, ts, meta) " &
          "VALUES (?, ?, ?, ?, ?, ?::jsonb) " &
          "ON CONFLICT (id) DO UPDATE SET " &
          "user_id = excluded.user_id, node_type = excluded.node_type, content = excluded.content, " &
          "embedding = NULL, ts = excluded.ts, meta = excluded.meta"
        ), node.id, node.userId, node.nodeType, node.content, $node.timestamp, metaStr)
    except CatchableError:
      discard

  proc getNode*(g: MagmaGraph; nodeId: string): Option[MagmaNode] =
    let db = g.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT id, user_id, node_type, content, ts, meta FROM " & MagmaNodesTable &
        " WHERE id = ?"
      ), nodeId)
      if rows.len > 0:
        some(MagmaNode(
          id: rows[0][0],
          userId: rows[0][1],
          nodeType: rows[0][2],
          content: rows[0][3],
          timestamp: parseBiggestInt(rows[0][4]),
          meta: if rows[0][5].len > 0: parseJson(rows[0][5]) else: newJObject(),
        ))
      else:
        none(MagmaNode)
    except CatchableError:
      none(MagmaNode)

  proc listNodes*(g: MagmaGraph; userId: string; nodeType: string = ""): seq[MagmaNode] =
    let db = g.openDb()
    defer: db.close()
    try:
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, ts, meta FROM " & MagmaNodesTable &
            " WHERE user_id = ? AND node_type = ? ORDER BY ts ASC, id ASC"
          ), userId, nodeType)
        else:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, ts, meta FROM " & MagmaNodesTable &
            " WHERE user_id = ? ORDER BY ts ASC, id ASC"
          ), userId)
      for row in rows:
        result.add(MagmaNode(
          id: row[0],
          userId: row[1],
          nodeType: row[2],
          content: row[3],
          timestamp: parseBiggestInt(row[4]),
          meta: if row[5].len > 0: parseJson(row[5]) else: newJObject(),
        ))
    except CatchableError:
      discard

  proc listNodesLimited*(g: MagmaGraph; userId: string;
                         nodeType: string = ""; limit, maxContentBytes: int):
                         Result[seq[MagmaNode], string] =
    if limit <= 0 or maxContentBytes <= 0:
      return ok(newSeq[MagmaNode]())
    let db = g.openDb()
    defer: db.close()
    try:
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, substr(content, 1, ?), ts, '{}' FROM " &
            MagmaNodesTable & " WHERE user_id = ? AND node_type = ? " &
            "ORDER BY ts DESC, id DESC LIMIT ?"
          ), maxContentBytes, userId, nodeType, limit)
        else:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, substr(content, 1, ?), ts, '{}' FROM " &
            MagmaNodesTable & " WHERE user_id = ? " &
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

  proc deleteNode*(g: MagmaGraph; nodeId: string): bool =
    let db = g.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "DELETE FROM " & MagmaNodesTable & " WHERE id = ? RETURNING id"
      ), nodeId)
      rows.len > 0
    except CatchableError:
      false

  # ── Edge CRUD ───────────────────────────────────────────────────────────────

  proc insertEdge*(g: MagmaGraph; edge: MagmaEdge): bool =
    let db = g.openDb()
    defer: db.close()
    try:
      let metaStr = if edge.meta != nil: $edge.meta else: "{}"
      let rows = db.getAllRows(sql(
        "INSERT INTO " & MagmaEdgesTable & " (from_id, to_id, edge_type, weight, meta) " &
        "VALUES (?, ?, ?, ?, ?::jsonb) ON CONFLICT (from_id, to_id, edge_type) DO NOTHING " &
        "RETURNING id"
      ), edge.fromId, edge.toId, edge.edgeType, $edge.weight, metaStr)
      rows.len > 0
    except CatchableError:
      false

  proc getEdges*(g: MagmaGraph; nodeId: string;
                 edgeType: string = "";
                 direction: string = "out"): seq[MagmaEdge] =
    ## Get edges from/to a node. direction: "out" (from), "in" (to), "both".
    let db = g.openDb()
    defer: db.close()
    try:
      var query = "SELECT from_id, to_id, edge_type, weight, meta FROM " & MagmaEdgesTable & " WHERE "
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

      let rows = db.getAllRows(sql(query), args)
      for row in rows:
        result.add(MagmaEdge(
          fromId: row[0],
          toId: row[1],
          edgeType: row[2],
          weight: try: parseFloat(row[3]) except: 1.0,
          meta: if row[4].len > 0: parseJson(row[4]) else: newJObject(),
        ))
    except CatchableError:
      discard

  proc deleteEdges*(g: MagmaGraph; nodeId: string; edgeType: string = ""): int =
    let db = g.openDb()
    defer: db.close()
    try:
      var rows: seq[Row]
      if edgeType.len > 0:
        rows = db.getAllRows(sql(
          "DELETE FROM " & MagmaEdgesTable & " WHERE (from_id = ? OR to_id = ?) AND edge_type = ? RETURNING id"
        ), nodeId, nodeId, edgeType)
      else:
        rows = db.getAllRows(sql(
          "DELETE FROM " & MagmaEdgesTable & " WHERE from_id = ? OR to_id = ? RETURNING id"
        ), nodeId, nodeId)
      rows.len
    except CatchableError:
      0

  # ── Temporal graph ──────────────────────────────────────────────────────────

  proc getLastNode*(g: MagmaGraph; userId: string;
                    nodeType: string = ""): Option[MagmaNode] =
    ## Get the most recent node for a user (optionally filtered by node type).
    let db = g.openDb()
    defer: db.close()
    try:
      let rows =
        if nodeType.len > 0:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, ts, meta FROM " & MagmaNodesTable &
            " WHERE user_id = ? AND node_type = ? ORDER BY ts DESC LIMIT 1"
          ), userId, nodeType)
        else:
          db.getAllRows(sql(
            "SELECT id, user_id, node_type, content, ts, meta FROM " & MagmaNodesTable &
            " WHERE user_id = ? ORDER BY ts DESC LIMIT 1"
          ), userId)
      if rows.len > 0:
        some(MagmaNode(
          id: rows[0][0], userId: rows[0][1], nodeType: rows[0][2],
          content: rows[0][3],
          timestamp: parseBiggestInt(rows[0][4]),
          meta: if rows[0][5].len > 0: parseJson(rows[0][5]) else: newJObject(),
        ))
      else:
        none(MagmaNode)
    except CatchableError:
      none(MagmaNode)

  proc linkTemporal*(g: MagmaGraph; fromId, toId: string) =
    ## Add a TEMPORAL edge (chronological chain).
    discard g.insertEdge(MagmaEdge(fromId: fromId, toId: toId, edgeType: EdgeTemporal))

  # ── Semantic search (pgvector) ─────────────────────────────────────────────

  proc searchSimilar*(g: MagmaGraph; userId: string;
                      embedding: seq[float32];
                      topK: int = 10;
                      minScore: float32 = 0.0): seq[MagmaHit] =
    ## Vector similarity search using pgvector cosine distance.
    let db = g.openDb()
    defer: db.close()
    try:
      let emb = "[" & embedding.join(",") & "]"
      let rows = db.getAllRows(sql(
        "SELECT id, user_id, node_type, content, ts, meta, " &
        "1 - (embedding <=> ?::vector) AS score " &
        "FROM " & MagmaNodesTable &
        " WHERE user_id = ? AND embedding IS NOT NULL " &
        "ORDER BY embedding <=> ?::vector LIMIT ?"
      ), emb, userId, emb, $topK)
      for row in rows:
        let score = try: parseFloat(row[6]).float32 except: 0.0
        if score >= minScore:
          result.add(MagmaHit(
            node: MagmaNode(
              id: row[0], userId: row[1], nodeType: row[2],
              content: row[3],
              timestamp: parseBiggestInt(row[4]),
              meta: if row[5].len > 0: parseJson(row[5]) else: newJObject(),
            ),
            score: score,
            path: @[row[0]],
          ))
    except CatchableError:
      discard

  # ── Temporal query ──────────────────────────────────────────────────────────

  proc queryByTimeRange*(g: MagmaGraph; userId: string;
                         tsStart, tsEnd: int64;
                         limit: int = 50): seq[MagmaNode] =
    let db = g.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT id, user_id, node_type, content, ts, meta FROM " & MagmaNodesTable &
        " WHERE user_id = ? AND ts BETWEEN ? AND ? ORDER BY ts DESC LIMIT ?"
      ), userId, $tsStart, $tsEnd, $limit)
      for row in rows:
        result.add(MagmaNode(
          id: row[0], userId: row[1], nodeType: row[2],
          content: row[3],
          timestamp: parseBiggestInt(row[4]),
          meta: if row[5].len > 0: parseJson(row[5]) else: newJObject(),
        ))
    except CatchableError:
      discard

  # ── Graph traversal (relational) ───────────────────────────────────────────

  proc traverseNeighbors*(g: MagmaGraph; nodeId: string;
                          edgeTypes: seq[string] = @[];
                          maxDepth: int = 2): seq[MagmaNode] =
    ## BFS traversal from a node through specified edge types.
    var visited: seq[string] = @[nodeId]
    var frontier: seq[string] = @[nodeId]
    var depth = 0

    while frontier.len > 0 and depth < maxDepth:
      var nextFrontier: seq[string] = @[]
      for current in frontier:
        let edges = g.getEdges(current, direction = "both")
        for edge in edges:
          let neighbor = if edge.fromId == current: edge.toId else: edge.fromId
          if neighbor in visited: continue
          if edgeTypes.len > 0 and edge.edgeType notin edgeTypes: continue
          visited.add(neighbor)
          nextFrontier.add(neighbor)
          let node = g.getNode(neighbor)
          if node.isSome:
            result.add(node.get())
      frontier = nextFrontier
      inc depth

  # ── Statistics ──────────────────────────────────────────────────────────────

  func parseCount(raw: string): int =
    if raw.len == 0:
      0
    else:
      try:
        parseInt(raw)
      except ValueError:
        0

  proc nodeCount*(g: MagmaGraph; userId: string): int =
    let db = g.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT count(*) FROM " & MagmaNodesTable & " WHERE user_id = ?"
      ), userId)
      if rows.len > 0: parseInt(rows[0][0]) else: 0
    except CatchableError:
      0

  proc edgeCount*(g: MagmaGraph; userId: string): int =
    let db = g.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT count(*) FROM " & MagmaEdgesTable &
        " e JOIN " & MagmaNodesTable & " n ON e.from_id = n.id WHERE n.user_id = ?"
      ), userId)
      if rows.len > 0: parseInt(rows[0][0]) else: 0
    except CatchableError:
      0

  proc stats*(g: MagmaGraph; userId: string): MagmaStats =
    let db = g.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT " &
        "COUNT(*), " &
        "COALESCE(SUM(CASE WHEN node_type = 'memory' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'user_profile' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'preference' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'entity' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN embedding IS NOT NULL THEN 1 ELSE 0 END), 0) " &
        "FROM " & MagmaNodesTable & " WHERE user_id = ?"
      ), userId)
      if rows.len > 0:
        result.totalNodes = parseCount(rows[0][0])
        result.memoryNodes = parseCount(rows[0][1])
        result.profileNodes = parseCount(rows[0][2])
        result.preferenceNodes = parseCount(rows[0][3])
        result.entityNodes = parseCount(rows[0][4])
        result.embeddingNodes = parseCount(rows[0][5])
      result.totalEdges = g.edgeCount(userId)
    except CatchableError:
      discard

  proc stats*(g: MagmaGraph): MagmaStats =
    let db = g.openDb()
    defer: db.close()
    try:
      let rows = db.getAllRows(sql(
        "SELECT " &
        "COUNT(*), " &
        "COALESCE(SUM(CASE WHEN node_type = 'memory' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'user_profile' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'preference' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN node_type = 'entity' THEN 1 ELSE 0 END), 0), " &
        "COALESCE(SUM(CASE WHEN embedding IS NOT NULL THEN 1 ELSE 0 END), 0) " &
        "FROM " & MagmaNodesTable
      ))
      if rows.len > 0:
        result.totalNodes = parseCount(rows[0][0])
        result.memoryNodes = parseCount(rows[0][1])
        result.profileNodes = parseCount(rows[0][2])
        result.preferenceNodes = parseCount(rows[0][3])
        result.entityNodes = parseCount(rows[0][4])
        result.embeddingNodes = parseCount(rows[0][5])
      let edgeRows = db.getAllRows(sql(
        "SELECT count(*) FROM " & MagmaEdgesTable
      ))
      if edgeRows.len > 0:
        result.totalEdges = parseCount(edgeRows[0][0])
    except CatchableError:
      discard

  proc toStorePort*(g: MagmaGraph): MultigraphStorePort =
    MultigraphStorePort(
      migrate: proc() {.gcsafe.} = g.migrate(),
      insertNode: proc(node: MagmaNode): bool {.gcsafe.} = g.insertNode(node),
      upsertNode: proc(node: MagmaNode) {.gcsafe.} = g.upsertNode(node),
      getNode: proc(nodeId: string): Option[MagmaNode] {.gcsafe.} = g.getNode(nodeId),
      listNodes: proc(userId: string; nodeType: string = ""): seq[MagmaNode] {.gcsafe.} =
        g.listNodes(userId, nodeType),
      listNodesLimited: proc(userId: string; nodeType: string = "";
                             limit, maxContentBytes: int):
                             Result[seq[MagmaNode], string] {.gcsafe.} =
        g.listNodesLimited(userId, nodeType, limit, maxContentBytes),
      deleteNode: proc(nodeId: string): bool {.gcsafe.} = g.deleteNode(nodeId),
      insertEdge: proc(edge: MagmaEdge): bool {.gcsafe.} = g.insertEdge(edge),
      getEdges: proc(nodeId: string; edgeType: string = ""; direction: string = "out"): seq[MagmaEdge] {.gcsafe.} =
        g.getEdges(nodeId, edgeType = edgeType, direction = direction),
      deleteEdges: proc(nodeId: string; edgeType: string = ""): int {.gcsafe.} = g.deleteEdges(nodeId, edgeType),
      getLastNode: proc(userId: string; nodeType: string = ""): Option[MagmaNode] {.gcsafe.} =
        g.getLastNode(userId, nodeType),
      linkTemporal: proc(fromId, toId: string) {.gcsafe.} = g.linkTemporal(fromId, toId),
      searchSimilar: proc(userId: string; embedding: seq[float32]; topK: int = 10; minScore: float32 = 0.0): seq[MagmaHit] {.gcsafe.} =
        g.searchSimilar(userId, embedding, topK = topK, minScore = minScore),
      queryByTimeRange: proc(userId: string; tsStart, tsEnd: int64; limit: int = 50): seq[MagmaNode] {.gcsafe.} =
        g.queryByTimeRange(userId, tsStart, tsEnd, limit = limit),
      traverseNeighbors: proc(nodeId: string; edgeTypes: seq[string] = @[]; maxDepth: int = 2): seq[MagmaNode] {.gcsafe.} =
        g.traverseNeighbors(nodeId, edgeTypes = edgeTypes, maxDepth = maxDepth),
      statsForUser: proc(userId: string): MagmaStats {.gcsafe.} = g.stats(userId),
      statsGlobal: proc(): MagmaStats {.gcsafe.} = g.stats(),
    )

else:
  ## Stub types when -d:withPostgres is not set.
  type
    MagmaGraph* = ref object

  proc toStorePort*(g: MagmaGraph): MultigraphStorePort = MultigraphStorePort()
