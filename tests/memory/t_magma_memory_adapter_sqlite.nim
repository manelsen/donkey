## Tests for MagmaMemoryAdapter over SQLite-backed multigraph store.

when defined(withSqlite):
  import std/[os, unittest, options, strutils]
  import donkey/core/types
  import donkey/adapters/memory/magma_memory_adapter
  import donkey/domain/memory/commitment_pure

  proc fakeEmbedFn(text: string): seq[float32] {.gcsafe.} =
    result = @[0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32]
    for i in 0 ..< min(text.len, result.len):
      result[i] = float32(ord(text[i])) / 255.0'f32

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
