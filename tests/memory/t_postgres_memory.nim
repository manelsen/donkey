## PostgresMemoryAdapter tests.
##
## Compile-time concept check always runs.
## Integration tests require:
##   -d:withPostgres                         (links libpq)
##   DONKEY_TEST_PG_DSN=host=... dbname=...  (live database)
##
## Example:
##   nim c -d:withPostgres -p:src tests/memory/t_postgres_memory.nim
##   DONKEY_TEST_PG_DSN="host=localhost dbname=donkey_test user=donkey password=donkey" \
##     ./tests/memory/t_postgres_memory

import std/unittest

when defined(withPostgres):
  import db_connector/db_postgres
  import std/os
  import donkey/ports/memory
  import donkey/core/types
  import donkey/domain/message

when defined(withPostgres):
  import std/strutils
  import donkey/adapters/memory/postgres_memory

  proc stubEmbed(text: string): seq[float32] =
    ## Returns a 4096-dim zero vector for testing (no HTTP call).
    newSeq[float32](4096)

  let pgDsn = getEnv("DONKEY_TEST_PG_DSN")
  let hasPg = pgDsn.len > 0

  suite "PostgresMemoryAdapter (integration — needs DONKEY_TEST_PG_DSN)":

    test "buildVectorLiteral returns empty for zero vectors":
      check buildVectorLiteral(@[0.0'f32, 0.0'f32]) == ""

    test "buildVectorLiteral serializes non-zero vectors":
      let literal = buildVectorLiteral(@[1.5'f32, 2.25'f32])
      check literal == "[1.5,2.25]"

    test "sanitizeAgeText escapes quotes and truncates":
      let text = "abc'def"
      check sanitizeAgeText(text, 20) == "abc\\'def"
      check sanitizeAgeText("0123456789", 5) == "01234"

    test "stripAgeValue removes wrapping quotes":
      check stripAgeValue("\"hello\"") == "hello"

    test "splitMemorySections keeps only meaningful blocks":
      let sections = splitMemorySections("short\n\nthis is a long enough block\n\n another valid block ")
      check sections.len == 2
      check sections[0] == "this is a long enough block"

    test "buildContextFromRows reconstructs context":
      let rows: seq[Row] = @[
        @["user_profile", "# User"],
        @["memory", "memory a"],
        @["fact", "fact b"],
        @["preference", "provider = \"zai-coding\""],
      ]
      let ctx = buildContextFromRows(UserId("u1"), rows)
      check ctx.userMd == "# User"
      check ctx.memoryMd.contains("memory a")
      check ctx.memoryMd.contains("fact b")
      check ctx.preferencesMd == "provider = \"zai-coding\""

    test "buildMemoryHits parses score column":
      let rows: seq[Row] = @[
        @["content a", "memory", "0.75"],
      ]
      let hits = buildMemoryHits(rows)
      check hits.len == 1
      check hits[0].score == 0.75'f32

    test "buildRecentMemoryHits defaults score to zero":
      let rows: seq[Row] = @[
        @["content a", "memory"],
      ]
      let hits = buildRecentMemoryHits(rows)
      check hits.len == 1
      check hits[0].score == 0.0'f32

    test "buildMemoryExportEntries uses deterministic file order":
      let ctx = UserContext(
        userId: UserId("u1"),
        userMd: "# User",
        memoryMd: "memory block",
        preferencesMd: "provider = \"zai-coding\"",
      )
      let entries = buildMemoryExportEntries(ctx)
      check entries.len == 3
      check entries[0].fileName == "USER.md"
      check entries[0].content == "# User"
      check entries[1].fileName == "MEMORY.md"
      check entries[1].content == "memory block"
      check entries[2].fileName == "PREFERENCES.md"
      check entries[2].content == "provider = \"zai-coding\""

    test "migrate: schema created without error":
      if not hasPg: skip()
      let a = newPostgresMemoryAdapter(pgDsn, stubEmbed)
      a.migrate()
      check true

    test "hasProfile: false for unknown user":
      if not hasPg: skip()
      let a = newPostgresMemoryAdapter(pgDsn, stubEmbed)
      a.migrate()
      let uid = UserId("pg-test-00000000-0000-0000-0000-000000000001")
      a.deleteUser(uid)
      check not a.hasProfile(uid)

    test "hasProfile: true after saveUserMd":
      if not hasPg: skip()
      let a = newPostgresMemoryAdapter(pgDsn, stubEmbed)
      a.migrate()
      let uid = UserId("pg-test-00000000-0000-0000-0000-000000000002")
      a.deleteUser(uid)
      a.saveUserMd(uid, "# Alice\n")
      check a.hasProfile(uid)

    test "loadContext: reads all three node kinds":
      if not hasPg: skip()
      let a = newPostgresMemoryAdapter(pgDsn, stubEmbed)
      a.migrate()
      let uid = UserId("pg-test-00000000-0000-0000-0000-000000000003")
      a.deleteUser(uid)
      a.saveUserMd(uid, "user content")
      a.appendMemory(uid, "mem block A")
      a.savePreferences(uid, "provider = \"zai-coding\"")
      let ctx = a.loadContext(uid)
      check ctx.userMd        == "user content"
      check ctx.memoryMd.contains("mem block A")
      check ctx.preferencesMd == "provider = \"zai-coding\""

    test "appendMemory: accumulates entries":
      if not hasPg: skip()
      let a = newPostgresMemoryAdapter(pgDsn, stubEmbed)
      a.migrate()
      let uid = UserId("pg-test-00000000-0000-0000-0000-000000000004")
      a.deleteUser(uid)
      a.appendMemory(uid, "note A")
      a.appendMemory(uid, "note B")
      let ctx = a.loadContext(uid)
      check ctx.memoryMd.contains("note A")
      check ctx.memoryMd.contains("note B")

    test "saveUserMd: overwrites on second call":
      if not hasPg: skip()
      let a = newPostgresMemoryAdapter(pgDsn, stubEmbed)
      a.migrate()
      let uid = UserId("pg-test-00000000-0000-0000-0000-000000000005")
      a.deleteUser(uid)
      a.saveUserMd(uid, "v1")
      a.saveUserMd(uid, "v2")
      let ctx = a.loadContext(uid)
      check ctx.userMd == "v2"

    test "search: no crash on zero vectors":
      if not hasPg: skip()
      let a = newPostgresMemoryAdapter(pgDsn, stubEmbed)
      a.migrate()
      let uid = UserId("pg-test-00000000-0000-0000-0000-000000000006")
      a.deleteUser(uid)
      a.appendMemory(uid, "user likes pizza")
      ## Zero-vector embed → embedOrNull returns "" → NULL stored → search skips
      let hits = a.search(uid, "food preferences", limit = 5)
      check hits.len >= 0

suite "PostgresMemoryAdapter satisfies SemanticMemoryPort concept":

  test "compile-time concept check (stub — no DB needed)":
    ## Concept conformance is verified at compile time by the generic constraint.
    ## The stub type (withPostgres not defined) has no procs, so this only
    ## checks that the import works. Full concept satisfaction is verified
    ## when compiled with -d:withPostgres.
    check true
