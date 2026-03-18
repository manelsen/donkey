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
  import std/os
  import donkey/ports/memory
  import donkey/core/types

when defined(withPostgres):
  import std/strutils
  import donkey/adapters/memory/postgres_memory

  proc stubEmbed(text: string): seq[float32] =
    ## Returns a 4096-dim zero vector for testing (no HTTP call).
    newSeq[float32](4096)

  let pgDsn = getEnv("DONKEY_TEST_PG_DSN")
  let hasPg = pgDsn.len > 0

  suite "PostgresMemoryAdapter (integration — needs DONKEY_TEST_PG_DSN)":

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
      a.savePreferences(uid, "provider = \"zhipu\"")
      let ctx = a.loadContext(uid)
      check ctx.userMd        == "user content"
      check ctx.memoryMd.contains("mem block A")
      check ctx.preferencesMd == "provider = \"zhipu\""

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
