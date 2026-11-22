## Fixed-capacity text and tables hold no GC memory, so state shared between
## threads can live in them under a lock with no {.cast(gcsafe).}: the
## {.thread.} proc below reads and writes a global one directly.

import std/[locks, unittest]
import donkey/infra/fixed

var gLock: Lock
initLock(gLock)
var gCounts: FixedTable[4, 16, int]

proc bump(times: int) {.thread.} =
  for _ in 0 ..< times:
    withLock gLock:
      gCounts.inc("worker")

proc runTests*() =
  suite "fixed-capacity text and tables":
    test "text round-trips and truncates on a UTF-8 boundary":
      check $toFixed[8]("short") == "short"
      check $toFixed[4]("abcdef") == "abcd"
      check $toFixed[4]("aéé") == "aé"      ## 'a' + 2-byte 'é' fits; a third byte would split the next
      check $toFixed[3]("aéé") == "aé"
      check $toFixed[2]("aéé") == "a"

    test "a table counts per key and sends overflow to _other":
      var t: FixedTable[3, 8, int]
      t.inc("a")
      t.inc("a")
      t.inc("b", 5)
      t.inc("c")
      t.inc("d")         ## table full: lands in _other
      check t.get("a") == 2
      check t.get("b") == 5
      check t.get(OtherKey) == 2
      check t.get("missing") == 0
      var keys: seq[string]
      for k, v in t.pairs: keys.add k
      check keys == @["a", "b", OtherKey]

    test "values can be any plain object, updated in place":
      type Breaker = object
        fails: int
        open: bool
      var t: FixedTable[2, 8, Breaker]
      t.mgetOrPut("h").fails += 2
      t.mgetOrPut("h").open = true
      check t.get("h") == Breaker(fails: 2, open: true)
      t.clear()
      check t.len == 0

    test "a global table is shared by threads under a lock, with no cast":
      var threads: array[4, Thread[int]]
      for t in threads.mitems: createThread(t, bump, 500)
      for t in threads.mitems: joinThread(t)
      withLock gLock:
        check gCounts.get("worker") == 2000

when isMainModule:
  runTests()
