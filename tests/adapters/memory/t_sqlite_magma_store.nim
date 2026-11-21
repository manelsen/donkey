## Tests for sqlite_magma_store — SQLite-backed MAGMA store.

when defined(withSqlite):
  import db_connector/db_sqlite
  import std/[os, sequtils, strutils, unittest, options]
  import donkey/adapters/memory/md_file
  import donkey/adapters/memory/sqlite_magma_store
  import donkey/core/pipeops
  import donkey/core/types
  import donkey/domain/memory/session_search_pure
  import donkey/ports/multigraph_store

  suite "SqliteMagmaStoreAdapter":
    let dbPath = getTempDir() / "donkey_sqlite_magma_store.db"

    setup:
      if fileExists(dbPath):
        removeFile(dbPath)

    teardown:
      if fileExists(dbPath):
        removeFile(dbPath)

    test "node and edge CRUD":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      check store.insertNode(MagmaNode(id: "n1", userId: "u1", nodeType: "memory", content: "alpha", timestamp: 1))
      check store.insertNode(MagmaNode(id: "n2", userId: "u1", nodeType: "memory", content: "beta", timestamp: 2))
      check store.insertEdge(MagmaEdge(fromId: "n1", toId: "n2", edgeType: EdgeTemporal))
      check store.getNode("n1").isSome()
      check store.listNodes("u1", "memory").len == 2
      check store.getEdges("n1", edgeType = EdgeTemporal).len == 1

    test "same-second inserts keep insertion order":
      ## ts has one-second resolution and ids sort as text ("m9" > "m10"), so
      ## ordering must fall back to insertion order, not to the id.
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      for i in 0 .. 11:
        check store.insertNode(MagmaNode(
          id: "u1_m" & $i, userId: "u1", nodeType: "memory",
          content: "node " & $i, timestamp: 100))
      let last = store.getLastNode("u1", "memory")
      check last.isSome()
      check last.get().id == "u1_m11"
      check store.listNodes("u1", "memory").mapIt(it.id) ==
        (0 .. 11).toSeq.mapIt("u1_m" & $it)
      let recent = store.queryByTimeRange("u1", 0, 200, limit = 3)
      check recent.mapIt(it.id) == @["u1_m11", "u1_m10", "u1_m9"]
      let limited = store.listNodesLimited("u1", "memory", 3, 64)
      check limited.isOk
      check limited.get().mapIt(it.id) == @["u1_m11", "u1_m10", "u1_m9"]

    test "getLastNode respects the node type filter":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      check store.insertNode(MagmaNode(
        id: "m0", userId: "u1", nodeType: "memory", content: "a", timestamp: 5))
      check store.insertNode(MagmaNode(
        id: "e0", userId: "u1", nodeType: "entity", content: "b", timestamp: 9))
      check store.getLastNode("u1", "memory").get().id == "m0"
      check store.getLastNode("u1").get().id == "e0"
      check store.getLastNode("nobody").isNone()

    test "listNodesLimited limits before materializing":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      for i in 1 .. 3:
        check store.insertNode(MagmaNode(
          id: "l" & $i, userId: "u1", nodeType: "memory",
          content: "node " & $i, timestamp: i))
      let limited = store.listNodesLimited("u1", "", 2, 4096).get()
      check limited.len == 2
      check limited[0].id == "l3"
      check limited[1].id == "l2"

    test "session search finds MAGMA-only memory":
      let base = getTempDir() / "donkey_session_search_magma"
      removeDir(base)
      createDir(base)
      defer: removeDir(base)
      let adapter = MdFileAdapter(
        paddocksDir: base,
        magmaSqlitePath: dbPath,
      )
      let uid = UserId("u1")
      let port = adapter.toRuntimePort()
      check port.appendMemory(uid, "magma-only deploy fact").isOk
      let hits = port.searchSessions(uid, "magma-only", 10, true).get()
      check hits.anyIt(it.kind == shkMemory and "magma-only" in it.snippet)

    test "searchSimilar ranks by in-process cosine similarity":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      check store.insertNode(MagmaNode(
        id: "s1", userId: "u1", nodeType: "memory",
        content: "apple", embedding: @[1.0'f32, 0.0'f32], timestamp: 1))
      check store.insertNode(MagmaNode(
        id: "s2", userId: "u1", nodeType: "memory",
        content: "banana", embedding: @[0.0'f32, 1.0'f32], timestamp: 2))
      let hits = store.searchSimilar("u1", @[1.0'f32, 0.0'f32], topK = 2)
      check hits.len == 2
      check hits[0].node.id == "s1"

    test "searchSimilar filters by node type before applying the limit":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      for i in 0 ..< 6:
        check store.insertNode(MagmaNode(
          id: "l" & $i, userId: "u1", nodeType: "lesson",
          content: "legacy", embedding: @[1.0'f32, 0.0'f32], timestamp: 10 + i))
      check store.insertNode(MagmaNode(
        id: "m1", userId: "u1", nodeType: "memory",
        content: "kept", embedding: @[0.6'f32, 0.8'f32], timestamp: 1))
      let hits = store.searchSimilar("u1", @[1.0'f32, 0.0'f32], topK = 1,
                                     nodeType = "memory")
      check hits.len == 1
      check hits[0].node.id == "m1"
      check store.searchSimilar("u1", @[1.0'f32, 0.0'f32], topK = 1)[0]
        .node.nodeType == "lesson"

    test "queryByTimeRange filters by node type before applying the limit":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      check store.insertNode(MagmaNode(
        id: "m1", userId: "u1", nodeType: "memory", content: "kept", timestamp: 1))
      for i in 0 ..< 6:
        check store.insertNode(MagmaNode(
          id: "l" & $i, userId: "u1", nodeType: "lesson",
          content: "legacy", timestamp: 10 + i))
      let recent = store.queryByTimeRange("u1", 0, 100, limit = 2,
                                          nodeType = "memory")
      check recent.mapIt(it.id) == @["m1"]
      check store.queryByTimeRange("u1", 0, 100, limit = 2).allIt(
        it.nodeType == "lesson")

    test "stores embeddings as blobs":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      check store.insertNode(MagmaNode(
        id: "b1", userId: "u1", nodeType: "memory",
        content: "blob", embedding: @[1.0'f32, 2.0'f32], timestamp: 1))
      let db = db_sqlite.open(dbPath, "", "", "")
      defer: db.close()
      check db.getValue(sql"SELECT typeof(embedding_vec) FROM magma_nodes WHERE id = 'b1'") == "blob"

    when defined(staticSqlite):
      test "upgrades the old vector index once and leaves subsequent reads read-only":
        let store = newSqliteMagmaStoreAdapter(dbPath)
        let db = store.openDb()
        defer: db.close()
        db.exec(sql"""CREATE TABLE magma_nodes (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          node_type TEXT NOT NULL,
          content TEXT NOT NULL,
          embedding TEXT NOT NULL DEFAULT '',
          embedding_vec BLOB NOT NULL DEFAULT X'',
          ts INTEGER NOT NULL DEFAULT 0,
          meta TEXT NOT NULL DEFAULT '{}'
        )""")
        db.exec(sql"""CREATE VIRTUAL TABLE magma_node_vec USING vec0(
          user_id TEXT PARTITION KEY, embedding FLOAT[4096]
        )""")
        db.exec(sql"""INSERT INTO magma_nodes (id, user_id, node_type, content, embedding_vec)
          VALUES ('old', 'u1', 'memory', 'old node', zeroblob(16384))""")
        db.exec(sql"""INSERT INTO magma_node_vec (rowid, user_id, embedding)
          SELECT rowid, user_id, embedding_vec FROM magma_nodes""")

        store.migrate()
        check db.getValue(sql"SELECT count(*) FROM magma_node_vec") == "1"
        check db.getValue(sql"""SELECT count(*) FROM magma_schema_migrations
          WHERE name = 'cosine-index-v1'""") == "1"
        check "distance_metric=cosine" in db.getValue(sql"""SELECT sql FROM sqlite_master
          WHERE name = 'magma_node_vec'""")
        let version = db.getValue(sql"PRAGMA data_version")
        let reopened = newSqliteMagmaStoreAdapter(dbPath)
        reopened.migrate()
        check reopened.listNodesLimited("u1", "memory", 1, 64).get().len == 1
        check db.getValue(sql"PRAGMA data_version") == version
        check db.getValue(sql"SELECT count(*) FROM magma_node_vec") == "1"

      test "a write outside the index is repaired on the next open":
        ## A writer without sqlite-vec stores the node and drops the marker;
        ## the next connection with sqlite-vec rebuilds the index.
        let store = newSqliteMagmaStoreAdapter(dbPath)
        store.migrate()
        let db = store.openDb()
        defer: db.close()
        db.exec(sql"""INSERT INTO magma_nodes (id, user_id, node_type, content, embedding_vec)
          VALUES ('unsynced', 'u1', 'memory', 'written without vec0', zeroblob(16384))""")
        db.exec(sql"DELETE FROM magma_schema_migrations WHERE name = 'cosine-index-v1'")
        check db.getValue(sql"SELECT count(*) FROM magma_node_vec") == "0"
        store.migrate()
        check db.getValue(sql"SELECT count(*) FROM magma_node_vec") == "1"
        check db.getValue(sql"""SELECT count(*) FROM magma_schema_migrations
          WHERE name = 'cosine-index-v1'""") == "1"

      test "a failed index rebuild is recorded and not retried on every read":
        ## A view in place of the index makes DROP TABLE fail, so the rebuild
        ## cannot succeed. Reads must not take the write lock again each time.
        let store = newSqliteMagmaStoreAdapter(dbPath)
        store.migrate()
        let db = store.openDb()
        defer: db.close()
        db.exec(sql"DROP TABLE magma_node_vec")
        db.exec(sql"CREATE VIEW magma_node_vec AS SELECT 1 AS embedding")
        db.exec(sql"DELETE FROM magma_schema_migrations WHERE name = 'cosine-index-v1'")
        store.migrate()
        check db.getValue(sql"""SELECT count(*) FROM magma_schema_migrations
          WHERE name = 'cosine-index-v1-failed'""") == "1"
        let version = db.getValue(sql"PRAGMA data_version")
        check store.listNodesLimited("u1", "memory", 1, 64).isOk
        check db.getValue(sql"PRAGMA data_version") == version

      test "a locked database during the index migration is an error, not an exception":
        let store = newSqliteMagmaStoreAdapter(dbPath)
        store.migrate()
        let db = store.openDb()
        defer: db.close()
        db.exec(sql"DELETE FROM magma_schema_migrations WHERE name = 'cosine-index-v1'")
        let holder = store.openDb()
        defer: holder.close()
        holder.exec(sql"BEGIN IMMEDIATE")
        defer: discard holder.tryExec(sql"ROLLBACK")
        check store.listNodesLimited("u1", "memory", 1, 64).isErr

      test "indexed writes preserve duplicate inserts, cosine ranking and deletes":
        let store = newSqliteMagmaStoreAdapter(dbPath)
        store.migrate()
        var query = newSeq[float32](4096)
        query[0] = 1
        var near = newSeq[float32](4096)
        near[0] = 1
        near[1] = 1
        var aligned = newSeq[float32](4096)
        aligned[0] = 12
        let first = MagmaNode(
          id: "aligned", userId: "u1", nodeType: "memory", embedding: aligned)
        let second = MagmaNode(
          id: "near", userId: "u1", nodeType: "memory", embedding: near)
        check store.insertNode(first)
        check store.insertNode(second)
        check not store.insertNode(MagmaNode(
          id: first.id, userId: first.userId, nodeType: first.nodeType, embedding: near))

        let db = store.openDb()
        defer: db.close()
        check db.getValue(sql"SELECT count(*) FROM magma_node_vec") == "2"
        check db.getValue(sql"""SELECT n.id FROM magma_node_vec v
          JOIN magma_nodes n ON n.rowid = v.rowid
          WHERE v.embedding MATCH n.embedding_vec AND k = 1 AND v.user_id = 'u1'
            AND n.id = 'aligned'""") == "aligned"
        check store.searchSimilar("u1", query, topK = 1, minScore = 0.9).mapIt(it.node.id) ==
          @["aligned"]
        check store.upsertNode(MagmaNode(
          id: first.id, userId: first.userId, nodeType: first.nodeType)).isOk
        check db.getValue(sql"SELECT count(*) FROM magma_node_vec") == "1"
        check store.deleteNode(second.id)
        check db.getValue(sql"SELECT count(*) FROM magma_node_vec") == "0"

    test "migrates legacy text embeddings into blob column":
      block:
        let db = db_sqlite.open(dbPath, "", "", "")
        defer: db.close()
        db.exec(sql"""CREATE TABLE magma_nodes (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          node_type TEXT NOT NULL DEFAULT 'memory',
          content TEXT NOT NULL,
          embedding TEXT NOT NULL DEFAULT '',
          ts INTEGER NOT NULL DEFAULT 0,
          meta TEXT NOT NULL DEFAULT '{}'
        )""")
        db.exec(sql"""CREATE TABLE magma_edges (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          from_id TEXT NOT NULL REFERENCES magma_nodes(id) ON DELETE CASCADE,
          to_id TEXT NOT NULL REFERENCES magma_nodes(id) ON DELETE CASCADE,
          edge_type TEXT NOT NULL,
          weight REAL NOT NULL DEFAULT 1.0,
          meta TEXT NOT NULL DEFAULT '{}',
          created_at INTEGER NOT NULL DEFAULT 0,
          UNIQUE (from_id, to_id, edge_type)
        )""")
        db.exec(sql"""INSERT INTO magma_nodes
          (id, user_id, node_type, content, embedding, ts, meta)
          VALUES ('legacy1', 'u1', 'memory', 'legacy', '[1.0,0.0]', 1, '{}')""")
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      let db = db_sqlite.open(dbPath, "", "", "")
      defer: db.close()
      check db.getValue(sql"SELECT typeof(embedding_vec) FROM magma_nodes WHERE id = 'legacy1'") == "blob"
      let hits = store.searchSimilar("u1", @[1.0'f32, 0.0'f32], topK = 1)
      check hits.len == 1
      check hits[0].node.id == "legacy1"

    test "resolveVecExtensionPath autodetects vendorized sqlite-vec":
      let root = getTempDir() / "donkey_sqlite_vec_vendor_test"
      let vendorDir = root / "vendor" / "sqlite-vec" / sqliteVecPlatformDir()
      createDir(vendorDir)
      let extPath = vendorDir / sqliteVecExtensionFileName()
      writeFile(extPath, "stub")
      defer:
        if dirExists(root):
          removeDir(root)
      check resolveVecExtensionPath("", cwd = root, appPath = root / "bin" / "donkey") == extPath
