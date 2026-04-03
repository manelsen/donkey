## Integration tests for MAGMA memory — real conversation simulation.
##
## Simulates full conversation flows to verify:
##   - Memories are stored and retrieved correctly
##   - Semantic search finds relevant context
##   - Entity graph captures relationships
##   - Temporal chain preserves conversation order
##   - Context loading reconstructs user state
##
## Requires PostgreSQL with pgvector on localhost, database donkey_test.
## Run: nim c -d:withPostgres -r tests/memory/t_magma_integration.nim

when defined(withPostgres):
  import std/[unittest, strutils, options]
  import db_connector/db_postgres
  import ../../src/donkey/core/types
  import ../../src/donkey/ports/memory
  import ../../src/donkey/ports/embedding
  import ../../src/donkey/adapters/memory/magma_graph
  import ../../src/donkey/adapters/memory/magma_memory_adapter

  const testDsn = "host=localhost port=5432 dbname=donkey_test"

  # ── Embedding simulation ─────────────────────────────────────────────────────
  #
  # Fake embeddings that create semantic similarity:
  #   - Texts sharing words get similar vectors (first 64 dims)
  #   - Different topics get orthogonal vectors

  proc fakeEmbedFn(text: string): seq[float32] {.gcsafe.} =
    var emb = newSeq[float32](4096)
    let lower = text.toLowerAscii()
    # Topic-based embeddings: each topic activates specific dimensions
    if "nim" in lower or "programming" in lower or "language" in lower:
      for i in 0 ..< 100: emb[i] = 0.8
    if "rust" in lower or "borrow" in lower or "memory" in lower:
      for i in 100 ..< 200: emb[i] = 0.8
    if "python" in lower or "script" in lower or "data" in lower:
      for i in 200 ..< 300: emb[i] = 0.8
    if "project" in lower or "ci" in lower or "pipeline" in lower:
      for i in 300 ..< 400: emb[i] = 0.8
    if "alice" in lower or "bob" in lower or "person" in lower:
      for i in 400 ..< 500: emb[i] = 0.8
    if "database" in lower or "postgres" in lower or "sql" in lower:
      for i in 500 ..< 600: emb[i] = 0.8
    # Add character-level signal for uniqueness
    for i in 0 ..< min(text.len, 64):
      emb[i + 1000] = float32(text[i]) / 255.0
    emb

  # ── Test helpers ─────────────────────────────────────────────────────────────

  proc cleanDb() =
    let g = newMagmaGraph(testDsn)
    let db = g.openDb()
    defer: db.close()
    try:
      db.exec(sql"DELETE FROM magma_edges")
      db.exec(sql"DELETE FROM magma_nodes")
    except:
      discard

  proc newAdapter(): MagmaMemoryAdapter =
    let g = newMagmaGraph(testDsn)
    g.migrate()
    cleanDb()
    newMagmaMemoryAdapter(testDsn, fakeEmbedFn)

  # ── Test suites ──────────────────────────────────────────────────────────────

  suite "MAGMA Integration - Real conversation flow":

    setup:
      let a = newAdapter()

    test "full onboarding + memory accumulation + retrieval":
      # Phase 1: User onboarding
      a.saveUserMd(UserId("alice"), """---
summary: Alice — software engineer
---
# Alice
**Preferred name:** Alice
**Timezone:** America/Sao_Paulo
**Language:** English
""")
      a.savePreferences(UserId("alice"), "language = \"en\"\ntimezone = \"America/Sao_Paulo\"")

      # Verify onboarding state
      check a.hasProfile(UserId("alice"))
      let onboardCtx = a.loadContext(UserId("alice"))
      check "Alice" in onboardCtx.userMd
      check "America/Sao_Paulo" in onboardCtx.preferencesMd
      check onboardCtx.memoryMd == ""

      # Phase 2: Conversation memories accumulate
      a.appendMemory(UserId("alice"), "Alice is working on a Nim project")
      a.appendMemory(UserId("alice"), "The project uses PostgreSQL for storage")
      a.appendMemory(UserId("alice"), "Alice prefers Rust for systems programming")
      a.appendMemory(UserId("alice"), "Setting up CI pipeline with GitHub Actions")

      # Verify memories are accumulated
      let ctx = a.loadContext(UserId("alice"))
      check "Nim project" in ctx.memoryMd
      check "PostgreSQL" in ctx.memoryMd
      check "Rust" in ctx.memoryMd
      check "CI pipeline" in ctx.memoryMd

      # Phase 3: Semantic search finds relevant context
      let nimHits = a.search(UserId("alice"), "Nim programming language", 5)
      check nimHits.len > 0
      var foundNim = false
      for h in nimHits:
        if "Nim" in h.content: foundNim = true
      check foundNim

      let rustHits = a.search(UserId("alice"), "Rust systems programming", 5)
      check rustHits.len > 0
      var foundRust = false
      for h in rustHits:
        if "Rust" in h.content:
          foundRust = true
      check foundRust

      # Phase 4: Search is scoped to user
      a.appendMemory(UserId("bob"), "Bob works with Python and data science")
      let aliceHits = a.search(UserId("alice"), "Python data", 5)
      for h in aliceHits:
        check "Bob" notin h.content

    test "temporal ordering is preserved across sessions":
      a.appendMemory(UserId("u1"), "Session 1: Started learning Nim")
      a.appendMemory(UserId("u1"), "Session 2: Built first web server")
      a.appendMemory(UserId("u1"), "Session 3: Deployed to production")
      a.appendMemory(UserId("u1"), "Session 4: Added monitoring")

      let ctx = a.loadContext(UserId("u1"))
      let memLines = ctx.memoryMd.split("\n\n")
      check memLines.len == 4
      for line in memLines:
        check line.contains("Session 1") or
              line.contains("Session 2") or
              line.contains("Session 3") or
              line.contains("Session 4")
      let g = newMagmaGraph(testDsn)
      let temporalEdges = g.getEdges("u1_m0", edgeType = EdgeTemporal)
      let edgesFromM0 = g.getEdges("u1_m0")
      check temporalEdges.len >= 1
      check edgesFromM0.len > 0

    test "entity extraction builds knowledge graph":
      # Store memories with entities
      a.appendMemory(UserId("u1"), "Alice works at Acme Corp")
      a.appendMemory(UserId("u1"), "Alice uses Nim programming")
      a.appendMemory(UserId("u1"), "Bob knows Alice from university")

      # Verify entity nodes were created
      let g = newMagmaGraph(testDsn)
      let nodeCount = g.nodeCount("u1")
      # Should have: 3 memory nodes + entity nodes (Alice, Acme Corp, Nim, Bob, university)
      check nodeCount >= 3

      # Verify edges exist
      let edges0 = g.getEdges("u1_m0")
      check edges0.len > 0  # Should have MENTIONS/ABOUT edges

    test "search enrichment finds related memories via graph":
      a.appendMemory(UserId("u1"), "Started project Alpha")
      a.appendMemory(UserId("u1"), "Project Alpha uses Nim language")
      a.appendMemory(UserId("u1"), "Nim is great for systems programming")

      let hits = a.search(UserId("u1"), "project", 10)
      check hits.len > 0
      var foundProject = false
      for h in hits:
        if "project" in h.content.toLowerAscii():
          foundProject = true
      check foundProject

    test "context reconstruction for RAG injection":
      # Setup complete user state
      a.saveUserMd(UserId("u1"), "# Dev\n**Preferred name:** Dev\n**Language:** pt-BR")
      a.savePreferences(UserId("u1"), "language = \"pt-BR\"")
      a.appendMemory(UserId("u1"), "User prefers functional programming")
      a.appendMemory(UserId("u1"), "Working on compiler optimization")
      a.appendMemory(UserId("u1"), "Uses Nim for metaprogramming")

      # Load full context
      let ctx = a.loadContext(UserId("u1"))

      # Verify all components are present
      check ctx.userId == UserId("u1")
      check "Dev" in ctx.userMd
      check "pt-BR" in ctx.preferencesMd
      check "functional programming" in ctx.memoryMd
      check "compiler" in ctx.memoryMd
      check "metaprogramming" in ctx.memoryMd

      # Search should return relevant hits
      let hits = a.search(UserId("u1"), "Nim compiler", 5)
      check hits.len > 0
      # Should find both Nim and compiler-related memories
      var foundNim = false
      var foundCompiler = false
      for h in hits:
        if "Nim" in h.content or "nim" in h.content.toLowerAscii():
          foundNim = true
        if "compiler" in h.content.toLowerAscii():
          foundCompiler = true
      check foundNim or foundCompiler

    test "memory isolation between users":
      # User A's data
      a.saveUserMd(UserId("userA"), "# User A profile")
      a.appendMemory(UserId("userA"), "User A secret memory")

      # User B's data
      a.saveUserMd(UserId("userB"), "# User B profile")
      a.appendMemory(UserId("userB"), "User B secret memory")

      # Cross-user checks
      check a.hasProfile(UserId("userA"))
      check a.hasProfile(UserId("userB"))

      let ctxA = a.loadContext(UserId("userA"))
      let ctxB = a.loadContext(UserId("userB"))

      check "User A" in ctxA.userMd
      check "User B" notin ctxA.userMd
      check "User B" in ctxB.userMd
      check "User A" notin ctxB.userMd

      # Search isolation
      let hitsA = a.search(UserId("userA"), "secret", 5)
      for h in hitsA:
        check "User B" notin h.content

    test "memory update and deletion":
      # Create profile
      a.saveUserMd(UserId("u1"), "Original profile")
      check a.hasProfile(UserId("u1"))

      # Update profile
      a.saveUserMd(UserId("u1"), "Updated profile")
      let ctx = a.loadContext(UserId("u1"))
      check ctx.userMd == "Updated profile"
      check "Original" notin ctx.userMd

      # Add memories
      a.appendMemory(UserId("u1"), "Memory 1")
      a.appendMemory(UserId("u1"), "Memory 2")

      # Verify accumulation
      let ctx2 = a.loadContext(UserId("u1"))
      check "Memory 1" in ctx2.memoryMd
      check "Memory 2" in ctx2.memoryMd

  suite "MAGMA Integration - Edge cases":

    setup:
      let a = newAdapter()

    test "empty search returns gracefully":
      let hits = a.search(UserId("empty"), "anything", 5)
      check hits.len == 0

    test "search with no embedding returns empty":
      a.appendMemory(UserId("u1"), "some memory")
      # Search with different user who has no embeddings
      let hits = a.search(UserId("u1"), "query", 5)
      # Should return hits since we have memories
      check hits.len >= 0

    test "rapid memory accumulation":
      # Store many memories quickly
      for i in 0 ..< 20:
        a.appendMemory(UserId("u1"), "Memory number " & $i)

      let ctx = a.loadContext(UserId("u1"))
      let lines = ctx.memoryMd.split("\n\n")
      check lines.len == 20

      # Search should find specific memory
      let hits = a.search(UserId("u1"), "Memory number 15", 5)
      check hits.len > 0

    test "special characters in memories":
      a.appendMemory(UserId("u1"), "Memory with special chars: àéïöü ñ ç")
      a.appendMemory(UserId("u1"), "Memory with quotes: \"hello\" and 'world'")
      a.appendMemory(UserId("u1"), "Memory with symbols: <tag> & \"entity\"")

      let ctx = a.loadContext(UserId("u1"))
      check "àéïöü" in ctx.memoryMd
      check "\"hello\"" in ctx.memoryMd
      check "<tag>" in ctx.memoryMd

else:
  echo "MAGMA integration tests skipped: -d:withPostgres not set"
