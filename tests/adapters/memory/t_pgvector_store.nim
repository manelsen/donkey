## Tests for PgvectorStoreAdapter — contract tests following t_contract.nim pattern.
##
## Compile with -d:withPostgres to activate integration tests.
## Unit tests for pure functions (buildVectorLiteral, parseVectorLiteral) run always.
## Requires PostgreSQL with pgvector extension installed for integration tests.
## Environment: POSTGRES_DSN must be set for integration tests.

import std/[os, strutils, unittest]
import donkey/core/types
import donkey/core/pipeops
import donkey/adapters/memory/pgvector_store

# ── Pure function unit tests (always available) ────────────────────────────────

suite "PgvectorStoreAdapter pure functions":
  test "buildVectorLiteral: creates valid pgvector string":
    let vec = @[0.1'f32, 0.2'f32, 0.3'f32]
    let literal = buildVectorLiteral(vec)
    check literal == "[0.1,0.2,0.3]"

  test "buildVectorLiteral: returns empty for zero vector":
    let vec = @[0.0'f32, 0.0'f32, 0.0'f32]
    let literal = buildVectorLiteral(vec)
    check literal == ""

  test "buildVectorLiteral: returns empty for empty vector":
    let vec: seq[float32] = @[]
    let literal = buildVectorLiteral(vec)
    check literal == ""

  test "parseVectorLiteral: parses valid literal":
    let vec = parseVectorLiteral("[0.1,0.2,0.3]")
    check vec.len == 3
    check abs(vec[0] - 0.1) < 0.001
    check abs(vec[1] - 0.2) < 0.001
    check abs(vec[2] - 0.3) < 0.001

  test "parseVectorLiteral: handles empty literal":
    let vec = parseVectorLiteral("")
    check vec.len == 0

  test "parseVectorLiteral: handles literal with spaces":
    let vec = parseVectorLiteral("[0.1, 0.2, 0.3]")
    check vec.len == 3

  test "DefaultTableName is set correctly":
    check DefaultTableName == "donkey_memories"

# ── Integration tests (require PostgreSQL) ───────────────────────────────────

when defined(withPostgres):
  import donkey/core/memory/embedder
  import donkey/domain/message
  import donkey/adapters/memory/pgvector_store

  # ── Mock embed function for testing ─────────────────────────────────────────

  func mockEmbedFn*(text: string): seq[float32] =
    # Returns a simple mock embedding based on text length
    let dimensions = 4096
    var vec = newSeq[float32](dimensions)
    # Simple hash-based fill for consistent results
    var h = text.len * 17 + 13
    for i in 0 ..< min(text.len, 100):
      h = h * 31 + ord(text[i])
    for i in 0 ..< dimensions:
      vec[i] = ((h + i * 7) mod 1000).float32 / 1000.0
    vec

  const
    TestTableName = "donkey_test_pgvector_" & $getTime().toUnix()
    TestUserId = UserId("test-user-uuid-pgvector")
    TestDsn = "postgres:postgres@localhost/postgres"

  # ── Constructor tests ───────────────────────────────────────────────────────

  suite "PgvectorStoreAdapter constructor":
    test "newPgvectorStoreAdapter: creates adapter with defaults":
      let adapter = newPgvectorStoreAdapter("dsn", mockEmbedFn)
      check adapter.dsn == "dsn"
      check adapter.tableName == DefaultTableName

    test "newPgvectorStoreAdapter: creates adapter with custom table":
      let adapter = newPgvectorStoreAdapter("dsn", mockEmbedFn, "custom_table")
      check adapter.dsn == "dsn"
      check adapter.tableName == "custom_table"

  # ── Contract tests ───────────────────────────────────────────────────────────

  proc runContractTests(adapter: PgvectorStoreAdapter) =
    let uid = TestUserId

    suite "PgvectorStoreAdapter contract [" & adapter.tableName & "]":

      test "hasProfile: false when user absent":
        let r = adapter.hasProfile(uid)
        check r.isOk
        check not r.get

      test "hasProfile: true after saveUserMd":
        let r = adapter.saveUserMd(uid, "# Alice\n")
        check r.isOk
        let hr = adapter.hasProfile(uid)
        check hr.isOk
        check hr.get

      test "loadContext: returns empty strings when user absent":
        let r = adapter.loadContext(uid)
        check r.isOk
        let ctx = r.get
        check ctx.userId == uid
        check ctx.userMd == ""
        check ctx.memoryMd == ""
        check ctx.preferencesMd == ""

      test "loadContext: reads all three fields":
        discard adapter.saveUserMd(uid, "user content")
        discard adapter.appendMemory(uid, "memory content")
        discard adapter.savePreferences(uid, "prefs content")
        let r = adapter.loadContext(uid)
        check r.isOk
        let ctx = r.get
        check ctx.userMd == "user content"
        check ctx.memoryMd == "memory content"
        check ctx.preferencesMd == "prefs content"

      test "saveUserMd: stores content for later retrieval":
        discard adapter.saveUserMd(uid, "# Bob\n")
        let r = adapter.loadContext(uid)
        check r.isOk
        check r.get.userMd == "# Bob\n"

      test "saveUserMd: overwrites on second call":
        discard adapter.saveUserMd(uid, "v1")
        discard adapter.saveUserMd(uid, "v2")
        let r = adapter.loadContext(uid)
        check r.isOk
        check r.get.userMd == "v2"

      test "appendMemory: stores memory entry":
        let r = adapter.appendMemory(uid, "first note")
        check r.isOk
        let mr = adapter.loadContext(uid)
        check mr.isOk
        check mr.get.memoryMd.contains("first note")

      test "savePreferences: round-trips content":
        discard adapter.savePreferences(uid, "provider: zai-coding\n")
        let r = adapter.loadContext(uid)
        check r.isOk
        check r.get.preferencesMd == "provider: zai-coding\n"

      test "clearMemory: removes memory entries":
        discard adapter.appendMemory(uid, "some memory")
        let r = adapter.clearMemory(uid)
        check r.isOk
        let mr = adapter.loadContext(uid)
        check mr.isOk
        check mr.get.memoryMd == ""

      test "deleteUser: removes all user data":
        discard adapter.saveUserMd(uid, "user content")
        discard adapter.appendMemory(uid, "memory content")
        let r = adapter.deleteUser(uid)
        check r.isOk
        let hr = adapter.hasProfile(uid)
        check hr.isOk
        check not hr.get

  # ── Vector storage tests ──────────────────────────────────────────────────────

  proc runVectorTests(adapter: PgvectorStoreAdapter) =
    let uid = TestUserId

    suite "PgvectorStoreAdapter vector storage [" & adapter.tableName & "]":

      test "storeChunk: stores chunk with vector":
        let chunk = newEmbeddedChunk("test chunk content", "hash123", 0, 0, mockEmbedFn("test chunk content"))
        let r = adapter.storeChunk(uid, chunk)
        check r.isOk
        let count = adapter.countMemories(uid)
        check count.isOk
        check count.get == 1

      test "storeChunks: stores multiple chunks":
        let chunks = @[
          newEmbeddedChunk("chunk 1", "hash1", 0, 0, mockEmbedFn("chunk 1")),
          newEmbeddedChunk("chunk 2", "hash1", 1, 10, mockEmbedFn("chunk 2")),
          newEmbeddedChunk("chunk 3", "hash1", 2, 20, mockEmbedFn("chunk 3")),
        ]
        let r = adapter.storeChunks(uid, chunks)
        check r.isOk
        let count = adapter.countMemories(uid)
        check count.isOk
        check count.get == 3

      test "search: returns hits by vector similarity":
        discard adapter.clearMemory(uid)
        let chunks = @[
          newEmbeddedChunk("apple fruit", "hash-apple", 0, 0, mockEmbedFn("apple fruit")),
          newEmbeddedChunk("orange fruit", "hash-orange", 1, 0, mockEmbedFn("orange fruit")),
          newEmbeddedChunk("car auto", "hash-car", 2, 0, mockEmbedFn("car auto")),
        ]
        discard adapter.storeChunks(uid, chunks)
        let hits = adapter.search(uid, "fruit", 10)
        check hits.isOk
        let results = hits.get
        check results.len == 2
        # Apple and orange should be more similar to "fruit" than car
        for hit in results:
          check hit.content.contains("fruit")

      test "search: respects limit":
        discard adapter.clearMemory(uid)
        let chunks = @[
          newEmbeddedChunk("chunk A", "hash-a", 0, 0, mockEmbedFn("chunk A")),
          newEmbeddedChunk("chunk B", "hash-b", 1, 0, mockEmbedFn("chunk B")),
          newEmbeddedChunk("chunk C", "hash-c", 2, 0, mockEmbedFn("chunk C")),
        ]
        discard adapter.storeChunks(uid, chunks)
        let hits = adapter.search(uid, "chunk", 2)
        check hits.isOk
        check hits.get.len == 2

      test "searchByHash: returns chunks by hash":
        let testHash = "test-hash-search"
        let chunks = @[
          newEmbeddedChunk("content 1", testHash, 0, 0, mockEmbedFn("content 1")),
          newEmbeddedChunk("content 2", testHash, 1, 0, mockEmbedFn("content 2")),
        ]
        discard adapter.storeChunks(uid, chunks)
        let hits = adapter.searchByHash(uid, testHash)
        check hits.isOk
        let results = hits.get
        check results.len == 2

      test "getChunksByHash: returns chunks sorted by index":
        let testHash = "test-hash-chunks"
        let chunks = @[
          newEmbeddedChunk("third", testHash, 2, 20, mockEmbedFn("third")),
          newEmbeddedChunk("first", testHash, 0, 0, mockEmbedFn("first")),
          newEmbeddedChunk("second", testHash, 1, 10, mockEmbedFn("second")),
        ]
        discard adapter.storeChunks(uid, chunks)
        let results = adapter.getChunksByHash(uid, testHash)
        check results.isOk
        let chunksSeq = results.get
        check chunksSeq.len == 3
        # Should be sorted by chunk_index
        check chunksSeq[0][0] == "first"
        check chunksSeq[1][0] == "second"
        check chunksSeq[2][0] == "third"

      test "reconstructFromChunks: rebuilds original text":
        let testHash = "test-reconstruct"
        let chunks = @[
          newEmbeddedChunk("This is the", testHash, 0, 0, mockEmbedFn("This is the")),
          newEmbeddedChunk("original text", testHash, 1, 12, mockEmbedFn("original text")),
          newEmbeddedChunk("that was chunked.", testHash, 2, 26, mockEmbedFn("that was chunked.")),
        ]
        discard adapter.storeChunks(uid, chunks)
        let reconstructed = adapter.reconstructFromChunks(uid, testHash)
        check reconstructed.isOk
        check reconstructed.get.contains("This is the")
        check reconstructed.get.contains("original text")
        check reconstructed.get.contains("that was chunked.")

      test "getMemoryKinds: returns distinct kinds":
        discard adapter.clearMemory(uid)
        discard adapter.saveUserMd(uid, "user")
        discard adapter.appendMemory(uid, "memory")
        discard adapter.savePreferences(uid, "prefs")
        let chunk = newEmbeddedChunk("chunk", "hash-kinds", 0, 0, mockEmbedFn("chunk"))
        discard adapter.storeChunk(uid, chunk)
        let kinds = adapter.getMemoryKinds(uid)
        check kinds.isOk
        let kindsSeq = kinds.get
        check kindsSeq.contains("user_profile")
        check kindsSeq.contains("memory")
        check kindsSeq.contains("preference")
        check kindsSeq.contains("chunk")

  # ── Integration test runner ─────────────────────────────────────────────────

  when defined(INTEGRATION):
    # Requires PostgreSQL with pgvector extension
    let dsn = getEnv("POSTGRES_DSN", TestDsn)
    let adapter = newPgvectorStoreAdapter(dsn, mockEmbedFn, TestTableName)

    # Initialize schema
    let initResult = adapter.initStore
    if initResult.isErr:
      echo "WARNING: Could not initialize store: ", initResult.error
      echo "Skipping integration tests"
    else:
      runContractTests(adapter)
      runVectorTests(adapter)

      # Cleanup
      discard adapter.deleteUser(TestUserId)
