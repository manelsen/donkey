import std/unittest
import donkey/core/channels/recent_ids

proc runTests*() =
  suite "recent ids (event deduplication)":
    test "the first sighting is new, the second a duplicate":
      var r = initRecentIds(ttlSec = 600, capacity = 10)
      check not r.seenBefore("a", 0)
      check r.seenBefore("a", 1)
      check not r.seenBefore("b", 1)

    test "an id older than the ttl is new again":
      var r = initRecentIds(ttlSec = 600, capacity = 10)
      check not r.seenBefore("a", 0)
      check r.seenBefore("a", 600)
      check not r.seenBefore("a", 601)

    test "at capacity the oldest id is forgotten first":
      var r = initRecentIds(ttlSec = 600, capacity = 2)
      check not r.seenBefore("a", 0)
      check not r.seenBefore("b", 1)
      check not r.seenBefore("c", 2)   ## forgets "a"
      check r.seenBefore("b", 3)
      check not r.seenBefore("a", 4)

    test "an empty id is never a duplicate":
      var r = initRecentIds(ttlSec = 600, capacity = 10)
      check not r.seenBefore("", 0)
      check not r.seenBefore("", 0)

when isMainModule:
  runTests()
