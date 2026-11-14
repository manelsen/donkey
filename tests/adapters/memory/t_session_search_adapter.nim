## Tests for the MdFileAdapter session/MEMORY search.

import std/[json, os, sequtils, strutils, unittest]
import donkey/adapters/memory/md_file
import donkey/core/types
import donkey/domain/memory/session_search_pure

let searchBase = getTempDir() / ("donkey_session_search_" & $getCurrentProcessId())

proc resetBase() =
  removeDir(searchBase)
  createDir(searchBase)

suite "MdFileAdapter session search":

  test "searches session transcripts and MEMORY.md for the owner":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    let paddock = adapter.paddockDir(uid)
    createDir(paddock / "sessions")
    writeFile(paddock / "sessions" / "s1.jsonl",
      $(%*{"role": "user", "text": "We deploy production on Fridays"}) & "\n" &
      $(%*{"role": "assistant", "text": "The deploy checklist is green"}) & "\n" &
      "{broken json\n")
    writeFile(paddock / "sessions" / "s2.jsonl",
      $(%*{"role": "user", "text": "lunch plans"}) & "\n")
    writeFile(paddock / "MEMORY.md",
      "# Memory\n\nThe production deploy uses blue-green.\n")

    let hits = adapter.searchSessions(uid, "deploy production", 10, true)
    check hits.len >= 2
    check hits.anyIt(it.kind == shkMemory)
    check hits.anyIt(it.kind == shkSession and it.sessionId == "s1")
    check hits.allIt("deploy" in it.snippet.toLowerAscii or
                     "production" in it.snippet.toLowerAscii)

  test "does not leak another user's history":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let a = UserId("user-a")
    let b = UserId("user-b")
    createDir(adapter.paddockDir(a) / "sessions")
    writeFile(adapter.paddockDir(a) / "sessions" / "s1.jsonl",
      $(%*{"role": "user", "text": "deploy production"}) & "\n")
    let hitsA = adapter.searchSessions(a, "deploy", 10, true)
    let hitsB = adapter.searchSessions(b, "deploy", 10, true)
    check hitsA.len == 1
    check hitsB.len == 0
    check not fileExists(adapter.paddockDir(b) / "sessions" / "s1.jsonl")

  test "include_memory=false excludes MEMORY.md":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    createDir(adapter.paddockDir(uid) / "sessions")
    writeFile(adapter.paddockDir(uid) / "sessions" / "s1.jsonl",
      $(%*{"role": "user", "text": "deploy"}) & "\n")
    writeFile(adapter.paddockDir(uid) / "MEMORY.md", "deploy memory\n")
    let withMemory = adapter.searchSessions(uid, "deploy", 10, true)
    let withoutMemory = adapter.searchSessions(uid, "deploy", 10, false)
    check withMemory.anyIt(it.kind == shkMemory)
    check not withoutMemory.anyIt(it.kind == shkMemory)

  test "empty and malformed inputs do not raise":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    check adapter.searchSessions(uid, "", 10, true).len == 0
    check adapter.searchSessions(uid, "deploy", 10, true).len == 0
    createDir(adapter.paddockDir(uid) / "sessions")
    writeFile(adapter.paddockDir(uid) / "sessions" / "bad.jsonl",
      "{not json}\n[]\n\"scalar\"\n")
    check adapter.searchSessions(uid, "deploy", 10, true).len == 0
