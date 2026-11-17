## Tests for the self-improvement review cadence.

import std/unittest
import donkey/core/review/cadence

suite "review cadence — counters":

  test "a fresh cadence owes nothing":
    let c = defaultReviewCadence(memoryInterval = 3, skillInterval = 2)
    check not c.memoryDue
    check not c.skillDue

  test "memory becomes due exactly at the interval":
    var c = defaultReviewCadence(memoryInterval = 3, skillInterval = 0)
    c.noteUserTurn()
    c.noteUserTurn()
    check not c.memoryDue
    c.noteUserTurn()
    check c.memoryDue

  test "consuming a memory review resets the counter":
    var c = defaultReviewCadence(memoryInterval = 1, skillInterval = 0)
    c.noteUserTurn()
    check c.memoryDue
    c.consumeMemory()
    check not c.memoryDue
    check c.turnsSinceMemory == 0

  test "skill becomes due from tool iterations, not turns":
    var c = defaultReviewCadence(memoryInterval = 0, skillInterval = 5)
    c.noteUserTurn()
    c.noteUserTurn()
    check not c.skillDue
    c.noteToolIterations(5)
    check c.skillDue
    c.consumeSkill()
    check not c.skillDue
    check c.itersSinceSkill == 0

  test "an interval of zero disables that review":
    var c = defaultReviewCadence(memoryInterval = 0, skillInterval = 0)
    for _ in 0 ..< 100:
      c.noteUserTurn()
    c.noteToolIterations(100)
    check not c.memoryDue
    check not c.skillDue

  test "tool iterations accumulate across turns":
    var c = defaultReviewCadence(memoryInterval = 0, skillInterval = 4)
    c.noteToolIterations(3)
    check not c.skillDue
    c.noteToolIterations(1)
    check c.skillDue

  test "negative tool counts are ignored":
    var c = defaultReviewCadence(memoryInterval = 0, skillInterval = 2)
    c.noteToolIterations(-5)
    check c.itersSinceSkill == 0
