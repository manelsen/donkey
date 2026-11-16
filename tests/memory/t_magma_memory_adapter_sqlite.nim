## Tests for MagmaMemoryAdapter over SQLite-backed multigraph store.

when defined(withSqlite):
  import std/[os, unittest, options, strutils, times]
  import donkey/core/types
  import donkey/adapters/memory/magma_memory_adapter
  import donkey/domain/memory/commitment_pure
  import donkey/domain/memory/provenance_pure
  import donkey/domain/memory/recall_pure
  import donkey/ports/memory
  import donkey/ports/multigraph_store

  proc fakeEmbedFn(text: string): seq[float32] {.gcsafe.} =
    result = @[0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32]
    for i in 0 ..< min(text.len, result.len):
      result[i] = float32(ord(text[i])) / 255.0'f32

  proc letterEmbedFn(text: string): seq[float32] {.gcsafe.} =
    ## One direction per initial letter, so texts that start with different
    ## letters are orthogonal and a query retrieves exactly its own entry.
    result = newSeq[float32](26)
    if text.len > 0 and text[0] in {'a' .. 'z'}:
      result[ord(text[0]) - ord('a')] = 1.0'f32
    else:
      result[25] = 1.0'f32

  suite "MagmaMemoryAdapter SQLite":
    let dbPath = getTempDir() / "donkey_magma_memory_sqlite.db"

    setup:
      if fileExists(dbPath):
        removeFile(dbPath)

    teardown:
      if fileExists(dbPath):
        removeFile(dbPath)

    test "loadContext and search work over sqlite store":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      a.saveUserMd(UserId("u1"), "# Ada")
      a.savePreferences(UserId("u1"), "language = \"nim\"")
      a.appendMemory(UserId("u1"), "apple priority memory")
      a.appendMemory(UserId("u1"), "banana memory")
      let ctx = a.loadContext(UserId("u1"))
      check ctx.userMd == "# Ada"
      check ctx.preferencesMd == "language = \"nim\""
      check ctx.memoryMd.contains("apple priority memory")
      let hits = a.search(UserId("u1"), "apple", 2)
      check hits.len > 0

    test "burst of appends is chained in insertion order":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      for i in 0 .. 11:
        a.appendMemory(UserId("u1"), "fato " & $i)
      for i in 1 .. 11:
        let incoming = a.graph.getEdges(
          "u1_m" & $i, edgeType = EdgeTemporal, direction = "in")
        check incoming.len == 1
        check incoming[0].fromId == "u1_m" & $(i - 1)

    test "loadContext keeps memories when other node types crowd the window":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      a.appendMemory(UserId("u1"), "memoria que precisa sobreviver")
      for i in 1 .. 250:
        check a.graph.insertNode(MagmaNode(
          id: "u1_filler_" & $i, userId: "u1", nodeType: "entity",
          content: "entidade " & $i, timestamp: getTime().toUnix() + 1))
      check a.loadContext(UserId("u1")).memoryMd.contains(
        "memoria que precisa sobreviver")

    test "appendMemory stores the origin in node meta":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      a.appendMemory(UserId("u1"), "- **User:** oi\n  **Response:** ola\n",
                     turnOrigin("s1"))
      a.appendMemory(UserId("u1"), "nota sem origem")
      let tagged = a.graph.getNode("u1_m0")
      check tagged.isSome
      check originFromMeta(tagged.get().meta) == turnOrigin("s1")
      let plain = a.graph.getNode("u1_m1")
      check plain.isSome
      check originFromMeta(plain.get().meta) == MemoryOrigin()

    test "search returns a dialogue hit with its session neighbours":
      let a = newSqliteMagmaMemoryAdapter(dbPath, letterEmbedFn)
      let uid = UserId("u1")
      a.appendMemory(uid, "aaaa turno A", turnOrigin("s1"))          # m0
      a.appendMemory(uid, "iiii chunk ingerido",
                     MemoryOrigin(source: msIngest, sessionId: "s1")) # m1
      a.appendMemory(uid, "xxxx turno de outra sessao", turnOrigin("s2")) # m2
      a.appendMemory(uid, "bbbb turno B", turnOrigin("s1"))          # m3
      a.appendMemory(uid, "cccc turno C", turnOrigin("s1"))          # m4
      let hits = a.search(uid, "bbbb", 5)
      check hits.len > 0
      check hits[0].id == "u1_m3"
      check hits[0].content == "bbbb turno B"
      check hits[0].origin == turnOrigin("s1")
      check hits[0].timestamp > 0
      check hits[0].before.len == 1
      check hits[0].before[0].id == "u1_m0"
      check hits[0].after.len == 1
      check hits[0].after[0].id == "u1_m4"

    test "non-dialogue and legacy hits come alone":
      let a = newSqliteMagmaMemoryAdapter(dbPath, letterEmbedFn)
      let uid = UserId("u1")
      a.appendMemory(uid, "aaaa turno A", turnOrigin("s1"))
      a.appendMemory(uid, "iiii chunk ingerido", MemoryOrigin(source: msIngest))
      a.appendMemory(uid, "llll no legado sem origem")
      a.appendMemory(uid, "bbbb turno B", turnOrigin("s1"))
      for query in ["iiii", "llll"]:
        let hits = a.search(uid, query, 5)
        check hits.len > 0
        check hits[0].content.startsWith(query)
        check hits[0].before.len == 0
        check hits[0].after.len == 0

    test "first turn of a session has no earlier neighbour":
      let a = newSqliteMagmaMemoryAdapter(dbPath, letterEmbedFn)
      let uid = UserId("u1")
      a.appendMemory(uid, "zzzz turno de sessao antiga", turnOrigin("s0"))
      a.appendMemory(uid, "aaaa turno A", turnOrigin("s1"))
      a.appendMemory(uid, "bbbb turno B", turnOrigin("s1"))
      let hits = a.search(uid, "aaaa", 5)
      check hits[0].id == "u1_m1"
      check hits[0].before.len == 0
      check hits[0].after.len == 1
      check hits[0].after[0].id == "u1_m2"

    test "only the best dialogue hits are expanded":
      let a = newSqliteMagmaMemoryAdapter(dbPath, letterEmbedFn)
      let uid = UserId("u1")
      for i in 0 .. 7:
        a.appendMemory(uid, "aaaa turno " & $i, turnOrigin("s1"))
      let hits = a.search(uid, "aaaa", 8)
      var expanded = 0
      for hit in hits:
        if hit.before.len + hit.after.len > 0:
          inc expanded
      check hits.len == 8
      check expanded == RecallWindowMaxHits

    test "commitments round-trip":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      let c = newCommitment(
        sourceText = "Ship phase 1",
        owner = coAgent,
        dueAt = some(123'i64),
      )
      a.saveCommitment(UserId("u1"), c)
      let commitments = a.loadCommitments(UserId("u1"))
      check commitments.len == 1
      check commitments[0].sourceText == "Ship phase 1"
