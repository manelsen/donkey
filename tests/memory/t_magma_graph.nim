## Tests for adapters/memory/magma_graph — MAGMA relational graph.
##
## Requires PostgreSQL with pgvector running on localhost.
## Uses donkey_test database.

when defined(withPostgres):
  import std/[unittest, options, json]
  import db_connector/db_postgres
  import ../../src/donkey/adapters/memory/magma_graph

  const testDsn = "host=localhost port=5432 dbname=donkey_test"

  proc testEmbedding(activeIndex = 0): seq[float32] =
    for i in 0 ..< 4096:
      result.add(if i == activeIndex: 1.0'f32 else: 0.0'f32)

  proc setupTestDb() =
    let g = newMagmaGraph(testDsn)
    g.migrate()

  proc cleanTestDb() =
    let g = newMagmaGraph(testDsn)
    let db = g.openDb()
    defer: db.close()
    try:
      db.exec(sql"DELETE FROM magma_edges")
      db.exec(sql"DELETE FROM magma_nodes")
    except:
      discard

  suite "magma_graph - migration":

    test "migrate creates tables without error":
      let g = newMagmaGraph(testDsn)
      g.migrate()

  suite "magma_graph - node CRUD":

    setup:
      setupTestDb()
      cleanTestDb()

    test "insertNode succeeds":
      let g = newMagmaGraph(testDsn)
      let ok = g.insertNode(MagmaNode(
        id: "n1", userId: "u1", nodeType: "memory",
        content: "test content", timestamp: 1000,
        meta: %* {"key": "value"},
      ))
      check ok

    test "insertNode duplicate returns false":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "n_dup", userId: "u1", content: "first", timestamp: 1))
      let ok = g.insertNode(MagmaNode(id: "n_dup", userId: "u1", content: "second", timestamp: 2))
      check not ok

    test "getNode returns node":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "n2", userId: "u1", content: "hello", timestamp: 100))
      let node = g.getNode("n2")
      check node.isSome
      check node.get().content == "hello"
      check node.get().timestamp == 100

    test "getNode returns none for missing":
      let g = newMagmaGraph(testDsn)
      let node = g.getNode("nonexistent")
      check node.isNone

    test "deleteNode removes node":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "n3", userId: "u1", content: "bye", timestamp: 1))
      let ok = g.deleteNode("n3")
      check ok
      check g.getNode("n3").isNone

    test "deleteNode cascades to edges":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "c_from", userId: "u1", content: "a", timestamp: 1))
      discard g.insertNode(MagmaNode(id: "c_to", userId: "u1", content: "b", timestamp: 2))
      discard g.insertEdge(MagmaEdge(fromId: "c_from", toId: "c_to", edgeType: "TEMPORAL"))
      discard g.deleteNode("c_from")
      let edges = g.getEdges("c_to", direction = "in")
      check edges.len == 0

  suite "magma_graph - edge CRUD":

    setup:
      setupTestDb()
      cleanTestDb()
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "e1", userId: "u1", content: "a", timestamp: 1))
      discard g.insertNode(MagmaNode(id: "e2", userId: "u1", content: "b", timestamp: 2))
      discard g.insertNode(MagmaNode(id: "e3", userId: "u1", content: "c", timestamp: 3))

    test "insertEdge succeeds":
      let ok = g.insertEdge(MagmaEdge(fromId: "e1", toId: "e2", edgeType: EdgeTemporal))
      check ok

    test "insertEdge duplicate returns false":
      discard g.insertEdge(MagmaEdge(fromId: "e1", toId: "e2", edgeType: EdgeTemporal))
      let ok = g.insertEdge(MagmaEdge(fromId: "e1", toId: "e2", edgeType: EdgeTemporal))
      check not ok

    test "getEdges out returns outgoing edges":
      discard g.insertEdge(MagmaEdge(fromId: "e1", toId: "e2", edgeType: EdgeTemporal))
      discard g.insertEdge(MagmaEdge(fromId: "e1", toId: "e3", edgeType: EdgeCausal))
      let edges = g.getEdges("e1", direction = "out")
      check edges.len == 2

    test "getEdges in returns incoming edges":
      discard g.insertEdge(MagmaEdge(fromId: "e1", toId: "e2", edgeType: EdgeTemporal))
      let edges = g.getEdges("e2", direction = "in")
      check edges.len == 1
      check edges[0].fromId == "e1"

    test "getEdges filters by type":
      discard g.insertEdge(MagmaEdge(fromId: "e1", toId: "e2", edgeType: EdgeTemporal))
      discard g.insertEdge(MagmaEdge(fromId: "e1", toId: "e3", edgeType: EdgeCausal))
      let temporal = g.getEdges("e1", edgeType = EdgeTemporal)
      check temporal.len == 1
      let causal = g.getEdges("e1", edgeType = EdgeCausal)
      check causal.len == 1

    test "deleteEdges removes edges":
      discard g.insertEdge(MagmaEdge(fromId: "e1", toId: "e2", edgeType: EdgeTemporal))
      discard g.insertEdge(MagmaEdge(fromId: "e1", toId: "e3", edgeType: EdgeCausal))
      let deleted = g.deleteEdges("e1", EdgeTemporal)
      check deleted == 1
      check g.getEdges("e1").len == 1

  suite "magma_graph - temporal chain":

    setup:
      setupTestDb()
      cleanTestDb()

    test "getLastNode returns most recent":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "t1", userId: "u1", content: "old", timestamp: 100))
      discard g.insertNode(MagmaNode(id: "t2", userId: "u1", content: "new", timestamp: 200))
      let last = g.getLastNode("u1")
      check last.isSome
      check last.get().content == "new"

    test "getLastNode returns none for empty":
      let g = newMagmaGraph(testDsn)
      let last = g.getLastNode("empty_user")
      check last.isNone

    test "linkTemporal creates temporal edge":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "tl1", userId: "u1", content: "a", timestamp: 1))
      discard g.insertNode(MagmaNode(id: "tl2", userId: "u1", content: "b", timestamp: 2))
      g.linkTemporal("tl1", "tl2")
      let edges = g.getEdges("tl1", edgeType = EdgeTemporal)
      check edges.len == 1
      check edges[0].toId == "tl2"

  suite "magma_graph - semantic search":

    setup:
      setupTestDb()
      cleanTestDb()

    test "searchSimilar finds matching nodes":
      let g = newMagmaGraph(testDsn)
      var emb1: seq[float32]
      var emb2: seq[float32]
      var emb3: seq[float32]
      for i in 0 ..< 4096:
        emb1.add(if i == 0: 1.0 else: 0.0)
        emb2.add(if i == 1: 1.0 else: 0.0)
        emb3.add(if i == 0: 0.9 else: 0.1)
      discard g.insertNode(MagmaNode(id: "s1", userId: "u1", content: "apple", timestamp: 1, embedding: emb1))
      discard g.insertNode(MagmaNode(id: "s2", userId: "u1", content: "banana", timestamp: 2, embedding: emb2))
      discard g.insertNode(MagmaNode(id: "s3", userId: "u1", content: "apple pie", timestamp: 3, embedding: emb3))

      let hits = g.searchSimilar("u1", emb1, topK = 5)
      check hits.len > 0
      check hits[0].node.id == "s1"  # exact match should be first
      check hits[0].score > 0.99

  suite "magma_graph - traversal":

    setup:
      setupTestDb()
      cleanTestDb()

    test "traverseNeighbors finds connected nodes":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "tr1", userId: "u1", content: "a", timestamp: 1))
      discard g.insertNode(MagmaNode(id: "tr2", userId: "u1", content: "b", timestamp: 2))
      discard g.insertNode(MagmaNode(id: "tr3", userId: "u1", content: "c", timestamp: 3))
      discard g.insertEdge(MagmaEdge(fromId: "tr1", toId: "tr2", edgeType: EdgeTemporal))
      discard g.insertEdge(MagmaEdge(fromId: "tr2", toId: "tr3", edgeType: EdgeCausal))

      let neighbors = g.traverseNeighbors("tr1", maxDepth = 2)
      check neighbors.len == 2
      let ids = @[neighbors[0].id, neighbors[1].id]
      check "tr2" in ids
      check "tr3" in ids

    test "traverseNeighbors filters by edge type":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "tf1", userId: "u1", content: "a", timestamp: 1))
      discard g.insertNode(MagmaNode(id: "tf2", userId: "u1", content: "b", timestamp: 2))
      discard g.insertNode(MagmaNode(id: "tf3", userId: "u1", content: "c", timestamp: 3))
      discard g.insertEdge(MagmaEdge(fromId: "tf1", toId: "tf2", edgeType: EdgeTemporal))
      discard g.insertEdge(MagmaEdge(fromId: "tf1", toId: "tf3", edgeType: EdgeCausal))

      let temporal = g.traverseNeighbors("tf1", edgeTypes = @[EdgeTemporal])
      check temporal.len == 1
      check temporal[0].id == "tf2"

  suite "magma_graph - statistics":

    setup:
      setupTestDb()
      cleanTestDb()

    test "nodeCount returns count":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "st1", userId: "u1", content: "a", timestamp: 1))
      discard g.insertNode(MagmaNode(id: "st2", userId: "u1", content: "b", timestamp: 2))
      discard g.insertNode(MagmaNode(id: "st3", userId: "u2", content: "c", timestamp: 3))
      check g.nodeCount("u1") == 2
      check g.nodeCount("u2") == 1
      check g.nodeCount("u3") == 0

    test "edgeCount returns count":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "ec1", userId: "u1", content: "a", timestamp: 1))
      discard g.insertNode(MagmaNode(id: "ec2", userId: "u1", content: "b", timestamp: 2))
      discard g.insertEdge(MagmaEdge(fromId: "ec1", toId: "ec2", edgeType: EdgeTemporal))
      check g.edgeCount("u1") == 1

  suite "magma_graph - detailed stats":

    setup:
      setupTestDb()
      cleanTestDb()

    test "stats returns per-type counts and embeddings":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(
        id: "profile1", userId: "u1", nodeType: "user_profile",
        content: "profile", timestamp: 1, embedding: testEmbedding(0)
      ))
      discard g.insertNode(MagmaNode(
        id: "pref1", userId: "u1", nodeType: "preference",
        content: "prefs", timestamp: 2, embedding: testEmbedding(1)
      ))
      discard g.insertNode(MagmaNode(
        id: "mem1", userId: "u1", nodeType: "memory",
        content: "memory a", timestamp: 3, embedding: testEmbedding(2)
      ))
      discard g.insertNode(MagmaNode(
        id: "mem2", userId: "u1", nodeType: "memory",
        content: "memory b", timestamp: 4
      ))
      discard g.insertNode(MagmaNode(
        id: "ent1", userId: "u1", nodeType: "entity",
        content: "Alice", timestamp: 5
      ))
      discard g.insertNode(MagmaNode(
        id: "other1", userId: "u2", nodeType: "memory",
        content: "other user", timestamp: 6, embedding: testEmbedding(3)
      ))
      discard g.insertEdge(MagmaEdge(fromId: "mem1", toId: "ent1", edgeType: EdgeMentions))
      discard g.insertEdge(MagmaEdge(fromId: "mem2", toId: "mem1", edgeType: EdgeTemporal))

      let stats = g.stats("u1")
      check stats.totalNodes == 5
      check stats.memoryNodes == 2
      check stats.profileNodes == 1
      check stats.preferenceNodes == 1
      check stats.entityNodes == 1
      check stats.embeddingNodes == 3
      check stats.totalEdges == 2

  suite "magma_graph - time range":

    setup:
      setupTestDb()
      cleanTestDb()

    test "queryByTimeRange returns nodes in range":
      let g = newMagmaGraph(testDsn)
      discard g.insertNode(MagmaNode(id: "trng1", userId: "u1", content: "jan", timestamp: 100))
      discard g.insertNode(MagmaNode(id: "trng2", userId: "u1", content: "feb", timestamp: 200))
      discard g.insertNode(MagmaNode(id: "trng3", userId: "u1", content: "mar", timestamp: 300))
      let nodes = g.queryByTimeRange("u1", tsStart = 150, tsEnd = 250)
      check nodes.len == 1
      check nodes[0].content == "feb"

else:
  echo "magma_graph tests skipped: -d:withPostgres not set"
