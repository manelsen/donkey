## Tests for MagmaMemoryAdapter over SQLite-backed multigraph store.

when defined(withSqlite):
  import std/[os, unittest, options, sequtils, strutils, times]
  import donkey/core/pipeops
  import donkey/core/types
  import donkey/adapters/memory/magma_memory_adapter
  import donkey/domain/memory/commitment_pure
  import donkey/domain/memory/episode_pure
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

    test "lesson nodes left by older versions are never recalled":
      let a = newSqliteMagmaMemoryAdapter(dbPath, letterEmbedFn)
      let uid = UserId("u1")
      a.appendMemory(uid, "aaaa episodio", turnOrigin("s1"))
      check a.graph.insertNode(MagmaNode(
        id: "u1_lesson_old", userId: "u1", nodeType: "lesson",
        content: "aaaa regra destilada", embedding: letterEmbedFn("aaaa"),
        timestamp: getTime().toUnix()))
      let hits = a.search(uid, "aaaa", 5)
      check hits.len == 1
      check hits[0].kind == "memory"

    test "appendMemory writes no entity nodes and no causal edges":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      let uid = UserId("u1")
      a.appendMemory(uid, "Alice is a developer. The cache node crashed.")
      a.appendMemory(uid, "Because of that, latency spiked for every request.")
      check a.graph.listNodes("u1", "entity").len == 0
      check a.graph.getEdges("u1_m0", edgeType = EdgeCausal).len == 0
      check a.graph.getEdges("u1_m0", edgeType = EdgeMentions).len == 0
      check a.graph.getEdges("u1_m0", edgeType = EdgeAbout).len == 0
      check a.graph.getEdges("u1_m0", edgeType = EdgeTemporal).len == 1

    test "a literal term finds a memory the embedding ranks last":
      let a = newSqliteMagmaMemoryAdapter(dbPath, letterEmbedFn)
      let uid = UserId("u1")
      ## The query embedding points at the routine notes (same initial);
      ## only the words point at the memory that answers it.
      for i in 1 .. 30:
        a.appendMemory(uid, "abacaxi rotina numero " & $i)
      a.appendMemory(uid, "zzzz o codinome do projeto e zarabatana")
      ## Best-by-words and best-by-meaning weigh the same, so the memory
      ## shares the top with the nearest note; embeddings alone leave it out.
      let hits = a.search(uid, "aaaa codinome zarabatana", 3)
      check hits.len == 3
      check hits.anyIt(it.content.contains("zarabatana"))

    test "an old memory that answers the question beats recent ones that do not":
      ## Recall ranks by relevance, not age (MAGMA applies no time decay to
      ## relevance; time is a filter for "when" questions). With a 30-day
      ## half-life a four-month-old fact lost to last week's small talk.
      let a = newSqliteMagmaMemoryAdapter(dbPath, letterEmbedFn)
      let uid = UserId("u1")
      let fourMonthsAgo = getTime().toUnix() - 120 * 86_400
      check a.graph.insertNode(MagmaNode(
        id: a.memId(uid), userId: $uid, nodeType: NtMemory,
        content: "wifi novo: a senha e girassol42",
        embedding: letterEmbedFn("w"), timestamp: fourMonthsAgo))
      for i in 1 .. 10:
        a.appendMemory(uid, "wow, que dia comprido " & $i)
      let hits = a.search(uid, "wifi senha", 3)
      check hits.len >= 1
      check hits[0].content.contains("girassol42")

    test "search works when no embedding is available":
      proc noEmbedFn(text: string): seq[float32] {.gcsafe.} = @[]
      let a = newSqliteMagmaMemoryAdapter(dbPath, noEmbedFn)
      let uid = UserId("u1")
      a.appendMemory(uid, "o codinome do projeto e zarabatana")
      for i in 1 .. 10:
        a.appendMemory(uid, "anotacao de rotina numero " & $i)
      let hits = a.search(uid, "zarabatana", 3)
      check hits.len > 0
      check hits[0].content.contains("zarabatana")

    test "a hit found only by its words keeps origin and neighbours":
      proc noEmbedFn(text: string): seq[float32] {.gcsafe.} = @[]
      let a = newSqliteMagmaMemoryAdapter(dbPath, noEmbedFn)
      let uid = UserId("u1")
      a.appendMemory(uid, "o prazo e quinta", turnOrigin("s1"))
      a.appendMemory(uid, "correcao zarabatana: o prazo e sexta", turnOrigin("s1"))
      let hits = a.search(uid, "zarabatana", 3)
      check hits[0].id == "u1_m1"
      check hits[0].origin == turnOrigin("s1")
      check hits[0].before.len == 1
      check hits[0].before[0].id == "u1_m0"

    test "appendMemory reports success and failure as a Result":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      check a.appendMemory(UserId("u1"), "fato").isOk
      var rejecting = a.graph
      rejecting.insertNode = proc(node: MagmaNode): bool {.gcsafe.} = false
      let failing = newMagmaMemoryAdapter(rejecting, fakeEmbedFn)
      let res = failing.appendMemory(UserId("u1"), "outro fato")
      check res.isErr
      check res.error.len > 0

    test "profile, preferences and episodes report a write the store refused":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      check a.saveUserMd(UserId("u1"), "# Ada").isOk
      check a.savePreferences(UserId("u1"), "language = \"pt-BR\"").isOk
      var rejecting = a.graph
      rejecting.upsertNode = proc(node: MagmaNode): Result[void, string] {.gcsafe.} =
        err("disk full")
      let failing = newMagmaMemoryAdapter(rejecting, fakeEmbedFn)
      check failing.saveUserMd(UserId("u1"), "# Outra").isErr
      check failing.savePreferences(UserId("u1"), "language = \"en\"").isErr
      let episode = newEpisodeJournal("Titulo", "Resumo", 1_700_000_000,
                                      1_700_000_100, @[])
      check failing.saveEpisode(UserId("u1"), episode).isErr
      check a.loadUserMd(UserId("u1")) == "# Ada"

    test "the store reports an upsert it could not make":
      ## The database file gives way to a directory after the adapter is
      ## built, so the next write cannot open it.
      let lostPath = dbPath & ".lost"
      let lost = newSqliteMagmaMemoryAdapter(lostPath, fakeEmbedFn)
      check lost.saveUserMd(UserId("u1"), "# Ada").isOk
      removeFile(lostPath)
      createDir(lostPath)
      check lost.saveUserMd(UserId("u1"), "# Outra").isErr
      removeDir(lostPath)

    test "clearMemory and resetBootstrap report what was not deleted":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      ## Nothing to delete is a success: the operations are idempotent.
      check a.clearMemory(UserId("nobody")).isOk
      check a.resetBootstrap(UserId("nobody")).isOk
      a.saveUserMd(UserId("u1"), "# Ada")
      a.appendMemory(UserId("u1"), "fato")
      var stuck = a.graph
      stuck.deleteNode = proc(nodeId: string): bool {.gcsafe.} = false
      let failing = newMagmaMemoryAdapter(stuck, fakeEmbedFn)
      check failing.clearMemory(UserId("u1")).isErr
      check failing.resetBootstrap(UserId("u1")).isErr
      check a.clearMemory(UserId("u1")).isOk
      check a.resetBootstrap(UserId("u1")).isOk
      check not a.hasContext(UserId("u1")).get()

    test "the profile and preferences reads tell failure from absence":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      check a.readUserMd(UserId("u1")).get() == ""
      a.saveUserMd(UserId("u1"), "# Ada")
      a.savePreferences(UserId("u1"), "language = \"pt-BR\"")
      check a.readUserMd(UserId("u1")).get() == "# Ada"
      check a.readPreferences(UserId("u1")).get() == "language = \"pt-BR\""
      var broken = a.graph
      broken.listNodesLimited = proc(userId: string; nodeType: string = "";
                                     limit, maxContentBytes: int):
                                     Result[seq[MagmaNode], string] {.gcsafe.} =
        err("database is locked")
      let failing = newMagmaMemoryAdapter(broken, fakeEmbedFn)
      check failing.readUserMd(UserId("u1")).isErr
      check failing.readPreferences(UserId("u1")).isErr
      check failing.readContext(UserId("u1")).isErr

    test "legacy nodes do not take the place of memories in the search":
      ## Lessons and entities written before they were dropped are still in
      ## the table. They must not fill the semantic or the recent window.
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      a.appendMemory(UserId("u1"), "passeio no parque")
      for i in 0 ..< 40:
        check a.graph.insertNode(MagmaNode(
          id: "legacy" & $i, userId: "u1", nodeType: "lesson",
          content: "licao antiga " & $i,
          embedding: fakeEmbedFn("o que"), timestamp: getTime().toUnix()))
      let hits = a.search(UserId("u1"), "o que aconteceu ontem", 1)
      check hits.len == 1
      check hits[0].content == "passeio no parque"

    test "a refused commitment update is not reported as done":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      let c = newCommitment(sourceText = "ligar para a Ada", owner = coAgent)
      check a.saveCommitment(UserId("u1"), c).isOk
      var rejecting = a.graph
      rejecting.upsertNode = proc(node: MagmaNode): Result[void, string] {.gcsafe.} =
        err("disk full")
      let failing = newMagmaMemoryAdapter(rejecting, fakeEmbedFn)
      check not failing.updateCommitmentStatus(UserId("u1"), c.id, csDone)
      check a.updateCommitmentStatus(UserId("u1"), c.id, csDone)

    test "reading the context reports a graph that cannot be read":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      a.saveUserMd(UserId("u1"), "# Ada")
      check a.readContext(UserId("u1")).get().userMd == "# Ada"
      check a.hasContext(UserId("u1")).get()
      check not a.hasContext(UserId("nobody")).get()
      var broken = a.graph
      broken.listNodesLimited = proc(userId: string; nodeType: string = "";
                                     limit, maxContentBytes: int):
                                     Result[seq[MagmaNode], string] {.gcsafe.} =
        err("database is locked")
      let failing = newMagmaMemoryAdapter(broken, fakeEmbedFn)
      check failing.readContext(UserId("u1")).isErr
      check failing.hasContext(UserId("u1")).isErr

    test "hasContext sees a user that only has a profile or only preferences":
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      a.saveUserMd(UserId("p1"), "# Ada")
      a.savePreferences(UserId("p2"), "language = \"pt-BR\"")
      check a.hasContext(UserId("p1")).get()
      check a.hasContext(UserId("p2")).get()

    test "hasContext reports a failed profile read instead of an empty graph":
      ## Memories read fine and there are none; the profile read fails. That
      ## is not an empty graph.
      let a = newSqliteMagmaMemoryAdapter(dbPath, fakeEmbedFn)
      a.saveUserMd(UserId("u1"), "# Ada")
      var flaky = a.graph
      let realList = a.graph.listNodesLimited
      flaky.listNodesLimited = proc(userId: string; nodeType: string = "";
                                    limit, maxContentBytes: int):
                                    Result[seq[MagmaNode], string] {.gcsafe.} =
        {.cast(gcsafe).}:
          if nodeType == "memory":
            return realList(userId, nodeType, limit, maxContentBytes)
        err("database is locked")
      check newMagmaMemoryAdapter(flaky, fakeEmbedFn).hasContext(UserId("u1")).isErr

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
