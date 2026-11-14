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

    test "listNodesLimited limits before materializing":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      for i in 1 .. 3:
        check store.insertNode(MagmaNode(
          id: "l" & $i, userId: "u1", nodeType: "memory",
          content: "node " & $i, timestamp: i))
      let limited = store.listNodesLimited("u1", "", 2)
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
      port.appendMemory(uid, "magma-only deploy fact")
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

    test "stores embeddings as blobs":
      let store = newSqliteMagmaStoreAdapter(dbPath)
      store.migrate()
      check store.insertNode(MagmaNode(
        id: "b1", userId: "u1", nodeType: "memory",
        content: "blob", embedding: @[1.0'f32, 2.0'f32], timestamp: 1))
      let db = db_sqlite.open(dbPath, "", "", "")
      defer: db.close()
      check db.getValue(sql"SELECT typeof(embedding_vec) FROM magma_nodes WHERE id = 'b1'") == "blob"

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
