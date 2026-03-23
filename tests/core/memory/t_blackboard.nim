## t_blackboard.nim - tests for core/memory/blackboard.nim

import std/[unittest, strutils, options]
import donkey/core/pipeops
import donkey/core/memory/blackboard

suite "blackboard - Blackboard construction":

  test "newBlackboard creates empty blackboard":
    let bb = newBlackboard()
    check bb.entries.len == 0
    check bb.maxEntries == DefaultMaxBlackboardEntries

  test "newBlackboard with custom maxEntries":
    let bb = newBlackboard(maxEntries = 10)
    check bb.maxEntries == 10

  test "newBlackboard with unlimited entries":
    let bb = newBlackboard(maxEntries = 0)
    check bb.maxEntries == 0

  test "newEntry creates entry with all fields":
    let entry = newEntry("key1", "content1", PriorityHigh, 123456'i64)
    check entry.key == "key1"
    check entry.content == "content1"
    check entry.priority == PriorityHigh
    check entry.createdAt == 123456'i64

suite "blackboard - Priority ordering":

  test "priorityOrder critical is lowest":
    check priorityOrder(PriorityCritical) == 0

  test "priorityOrder high < medium < low":
    check priorityOrder(PriorityHigh) < priorityOrder(PriorityMedium)
    check priorityOrder(PriorityMedium) < priorityOrder(PriorityLow)

  test "compareEntries sorts by priority first":
    let e1 = newEntry("a", "x", PriorityLow, 0)
    let e2 = newEntry("b", "y", PriorityCritical, 0)
    check compareEntries(e1, e2) > 0  # e1 comes after e2 (lower priority)

  test "compareEntries sorts by key as tiebreaker":
    let e1 = newEntry("a", "x", PriorityHigh, 0)
    let e2 = newEntry("b", "y", PriorityHigh, 0)
    check compareEntries(e1, e2) < 0  # "a" comes before "b"

suite "blackboard - Query functions":

  test "entryKeys returns all keys":
    var bb = newBlackboard()
    discard bb.addEntry("key1", "c1", PriorityMedium)
    discard bb.addEntry("key2", "c2", PriorityMedium)
    let keys = bb.entryKeys()
    check keys.len == 2
    check "key1" in keys
    check "key2" in keys

  test "hasEntry returns true for existing key":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "do stuff", PriorityMedium)
    check bb.hasEntry("task1")

  test "hasEntry returns false for missing key":
    var bb = newBlackboard()
    check not bb.hasEntry("nonexistent")

  test "getEntry returns some for existing key":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "do stuff", PriorityMedium)
    let result = bb.getEntry("task1")
    check result.isSome
    check result.get().key == "task1"

  test "getEntry returns none for missing key":
    var bb = newBlackboard()
    let result = bb.getEntry("nonexistent")
    check result.isNone

  test "filterByPrefix returns matching entries":
    var bb = newBlackboard()
    discard bb.addEntry("task_1", "first", PriorityMedium)
    discard bb.addEntry("task_2", "second", PriorityMedium)
    discard bb.addEntry("note_x", "other", PriorityMedium)
    let filtered = bb.filterByPrefix("task_")
    check filtered.len == 2

  test "filterByPrefix returns empty when no matches":
    var bb = newBlackboard()
    discard bb.addEntry("note_x", "other", PriorityMedium)
    let filtered = bb.filterByPrefix("task_")
    check filtered.len == 0

  test "filterByPriority returns matching entries":
    var bb = newBlackboard()
    discard bb.addEntry("high1", "h", PriorityHigh)
    discard bb.addEntry("low1", "l", PriorityLow)
    discard bb.addEntry("high2", "h", PriorityHigh)
    let filtered = bb.filterByPriority(PriorityHigh)
    check filtered.len == 2

  test "filterByPriority returns empty when no matches":
    var bb = newBlackboard()
    discard bb.addEntry("low1", "l", PriorityLow)
    let filtered = bb.filterByPriority(PriorityCritical)
    check filtered.len == 0

  test "sortEntries sorts by priority then key":
    var bb = newBlackboard()
    discard bb.addEntry("b", "2", PriorityLow)
    discard bb.addEntry("a", "1", PriorityCritical)
    discard bb.addEntry("c", "3", PriorityHigh)
    let sorted = sortEntries(bb.entries)
    check sorted[0].key == "a"
    check sorted[1].key == "c"
    check sorted[2].key == "b"

suite "blackboard - Formatting":

  test "formatEntry critical shows [!]":
    let e = newEntry("key", "content", PriorityCritical, 0)
    check formatEntry(e) == "[!] key: content"

  test "formatEntry high shows [+]":
    let e = newEntry("key", "content", PriorityHigh, 0)
    check formatEntry(e) == "[+] key: content"

  test "formatEntry medium shows [-]":
    let e = newEntry("key", "content", PriorityMedium, 0)
    check formatEntry(e) == "[-] key: content"

  test "formatEntry low shows [.]":
    let e = newEntry("key", "content", PriorityLow, 0)
    check formatEntry(e) == "[.] key: content"

  test "render empty blackboard shows placeholder":
    let bb = newBlackboard()
    let output = bb.render()
    check "# BLACKBOARD" in output
    check "empty" in output

  test "render with entries shows formatted content":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "first task", PriorityCritical)
    discard bb.addEntry("task2", "second task", PriorityLow)
    let output = bb.render()
    check "# BLACKBOARD" in output
    check "[!] task1: first task" in output
    check "[.] task2: second task" in output

  test "render with custom title":
    var bb = newBlackboard()
    discard bb.addEntry("x", "y", PriorityMedium)
    let output = bb.render(title = "PLANNING")
    check "# PLANNING" in output

  test "renderForUser empty returns empty string":
    let bb = newBlackboard()
    check bb.renderForUser() == ""

  test "renderForUser returns only content":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "first", PriorityHigh)
    discard bb.addEntry("task2", "second", PriorityMedium)
    let output = bb.renderForUser()
    check output == "first\nsecond"

suite "blackboard - addEntry":

  test "addEntry succeeds with valid key and content":
    var bb = newBlackboard()
    let result = bb.addEntry("task1", "do work", PriorityHigh, 1000'i64)
    check result.isOk
    check bb.entries.len == 1
    check bb.entries[0].key == "task1"
    check bb.entries[0].content == "do work"
    check bb.entries[0].priority == PriorityHigh
    check bb.entries[0].createdAt == 1000'i64

  test "addEntry fails with empty key":
    var bb = newBlackboard()
    let result = bb.addEntry("", "content", PriorityMedium, 0'i64)
    check result.isErr
    check "empty" in result.error

  test "addEntry fails with duplicate key":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "first", PriorityMedium)
    let result = bb.addEntry("task1", "second", PriorityMedium)
    check result.isErr
    check "already has entry" in result.error

  test "addEntry fails when blackboard is full":
    var bb = newBlackboard(maxEntries = 2)
    discard bb.addEntry("task1", "first", PriorityMedium)
    discard bb.addEntry("task2", "second", PriorityMedium)
    let result = bb.addEntry("task3", "third", PriorityMedium)
    check result.isErr
    check "full" in result.error

  test "addEntry with unlimited maxEntries does not fail":
    var bb = newBlackboard(maxEntries = 0)
    for i in 0 ..< 100:
      let r = bb.addEntry("task" & $i, "content", PriorityMedium)
      check r.isOk

  test "addEntry with default priority uses PriorityMedium":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "content")
    check bb.entries[0].priority == PriorityMedium

  test "addEntry without createdAt uses nowMs":
    var bb = newBlackboard()
    let before = nowMs()
    discard bb.addEntry("task1", "content")
    let after = nowMs()
    check bb.entries[0].createdAt >= before
    check bb.entries[0].createdAt <= after

suite "blackboard - updateEntry":

  test "updateEntry succeeds for existing key":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "original", PriorityMedium, 1000'i64)
    let result = bb.updateEntry("task1", "updated", PriorityHigh)
    check result.isOk
    check bb.entries[0].content == "updated"
    check bb.entries[0].priority == PriorityHigh
    check bb.entries[0].createdAt == 1000'i64  # unchanged

  test "updateEntry fails for missing key":
    var bb = newBlackboard()
    let result = bb.updateEntry("nonexistent", "content", PriorityMedium)
    check result.isErr
    check "no entry with key" in result.error

  test "updateEntry preserves createdAt":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "original", PriorityMedium, 5000'i64)
    discard bb.updateEntry("task1", "updated", PriorityLow)
    check bb.entries[0].createdAt == 5000'i64

suite "blackboard - removeEntry":

  test "removeEntry succeeds for existing key":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "content", PriorityMedium)
    let result = bb.removeEntry("task1")
    check result.isOk
    check bb.entries.len == 0

  test "removeEntry fails for missing key":
    var bb = newBlackboard()
    let result = bb.removeEntry("nonexistent")
    check result.isErr
    check "no entry with key" in result.error

  test "removeEntry only removes specified entry":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "first", PriorityMedium)
    discard bb.addEntry("task2", "second", PriorityMedium)
    discard bb.removeEntry("task1")
    check bb.entries.len == 1
    check bb.entries[0].key == "task2"

suite "blackboard - clear":

  test "clear removes all entries":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "first", PriorityMedium)
    discard bb.addEntry("task2", "second", PriorityMedium)
    bb.clear()
    check bb.entries.len == 0

  test "clear on empty blackboard is safe":
    var bb = newBlackboard()
    bb.clear()
    check bb.entries.len == 0

suite "blackboard - addEntryChain":

  test "addEntryChain returns entry on success":
    var bb = newBlackboard()
    let result = bb.addEntryChain("task1", "do work", PriorityHigh)
    check result.isOk
    check result.get().key == "task1"
    check result.get().content == "do work"

  test "addEntryChain fails on duplicate key":
    var bb = newBlackboard()
    discard bb.addEntry("task1", "first", PriorityMedium)
    let result = bb.addEntryChain("task1", "second", PriorityMedium)
    check result.isErr

suite "blackboard - Result binding with >>=":

  test "addEntry returns Result that can be checked":
    var bb = newBlackboard()
    let finalResult = bb.addEntry("task1", "content", PriorityMedium)
    check finalResult.isOk
    check bb.hasEntry("task1")
