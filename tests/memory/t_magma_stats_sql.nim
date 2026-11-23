import std/[strutils, unittest]
import donkey/adapters/memory/magma_stats_sql

proc runTests*() =
  suite "graph statistics SQL":
    test "the per-user query has one parameter, the global one none":
      check nodeStatsSql("n", "e IS NOT NULL", perUser = true).count('?') == 1
      check nodeStatsSql("n", "e IS NOT NULL", perUser = false).count('?') == 0
      check edgeCountSql("e", "n", perUser = true).count('?') == 1
      check "JOIN" notin edgeCountSql("e", "n", perUser = false)

    test "a row becomes the node counts; bad cells are zero":
      let s = nodeStatsFromRow(@["10", "4", "1", "2", "3", ""])
      check s.totalNodes == 10
      check s.memoryNodes == 4
      check s.entityNodes == 3
      check s.embeddingNodes == 0
      check nodeStatsFromRow(@["x"]).totalNodes == 0

when isMainModule:
  runTests()
