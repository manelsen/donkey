## Tests for the MdFileAdapter session/MEMORY search.

import std/[json, os, sequtils, strutils, unittest]
import donkey/adapters/memory/md_file
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/memory/session_search_pure
import donkey/domain/message

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

    let hits = adapter.searchSessions(uid, "deploy production", 10, true).get()
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
    let hitsA = adapter.searchSessions(a, "deploy", 10, true).get()
    let hitsB = adapter.searchSessions(b, "deploy", 10, true).get()
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
    let withMemory = adapter.searchSessions(uid, "deploy", 10, true).get()
    let withoutMemory = adapter.searchSessions(uid, "deploy", 10, false).get()
    check withMemory.anyIt(it.kind == shkMemory)
    check not withoutMemory.anyIt(it.kind == shkMemory)

  test "an oversized single line is not searched":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    let dir = adapter.paddockDir(uid) / "sessions"
    createDir(dir)
    writeFile(dir / "small.jsonl",
      $(%*{"role": "user", "text": "deploy small"}) & "\n")
    writeFile(dir / "big.jsonl",
      $(%*{"role": "user",
           "text": repeat("x", SessionSearchMaxFileBytes + 10) & " deploy"}) & "\n")
    let hits = adapter.searchSessions(uid, "deploy", 10, true).get()
    check hits.len == 1
    check hits[0].sessionId == "small"

  test "empty and malformed inputs do not raise":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    check adapter.searchSessions(uid, "", 10, true).get().len == 0
    check adapter.searchSessions(uid, "deploy", 10, true).get().len == 0
    createDir(adapter.paddockDir(uid) / "sessions")
    writeFile(adapter.paddockDir(uid) / "sessions" / "bad.jsonl",
      "{not json}\n[]\n\"scalar\"\n")
    check adapter.searchSessions(uid, "deploy", 10, true).get().len == 0

suite "MdFileAdapter session transcript":

  proc transcriptLines(adapter: MdFileAdapter; uid: UserId;
                       sessionId: string): seq[JsonNode] =
    let path = adapter.paddockDir(uid) / "sessions" / (sessionId & ".jsonl")
    for raw in readFile(path).splitLines():
      if raw.strip.len > 0:
        result.add(parseJson(raw))

  proc history(first, last: int): ConversationHistory =
    for i in first .. last:
      if i mod 2 == 1: result.addUser("mensagem " & $i)
      else: result.addAssistant("resposta " & $i)

  test "saving a trimmed history keeps the earlier messages":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    for last in countup(2, 40, 2):
      adapter.saveSession(uid, "s1", history(max(1, last - 19), last))
    let lines = adapter.transcriptLines(uid, "s1")
    check lines.len == 40
    check lines[0]["text"].getStr == "mensagem 1"
    check lines[^1]["text"].getStr == "resposta 40"

  test "saving the same history twice does not duplicate it":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    adapter.saveSession(uid, "s1", history(1, 6))
    adapter.saveSession(uid, "s1", history(1, 6))
    check adapter.transcriptLines(uid, "s1").len == 6

  test "every stored message carries its own timestamp":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    adapter.saveSession(uid, "s1", history(1, 4))
    for line in adapter.transcriptLines(uid, "s1"):
      check line["ts"].getBiggestInt > 1_600_000_000_000

  test "a file in the previous snapshot format is extended, not rewritten":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    createDir(adapter.paddockDir(uid) / "sessions")
    writeFile(adapter.paddockDir(uid) / "sessions" / "s1.jsonl",
      $(%*{"role": "user", "text": "mensagem 1", "imageUrl": ""}) & "\n" &
      $(%*{"role": "assistant", "text": "resposta 2", "imageUrl": ""}) & "\n")
    adapter.saveSession(uid, "s1", history(1, 4))
    let lines = adapter.transcriptLines(uid, "s1")
    check lines.len == 4
    check not lines[0].hasKey("ts")
    check lines[3].hasKey("ts")

  test "search reaches the start of a long session":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    var first: ConversationHistory
    first.addUser("o codinome do projeto é zarabatana")
    first.addAssistant("anotado")
    adapter.saveSession(uid, "s1", first)
    for last in countup(4, 60, 2):
      adapter.saveSession(uid, "s1", history(max(3, last - 19), last))
    let hits = adapter.searchSessions(uid, "zarabatana", 5, false).get()
    check hits.len == 1
    check hits[0].sessionId == "s1"

  test "search uses the per-message timestamp when the line has one":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    createDir(adapter.paddockDir(uid) / "sessions")
    writeFile(adapter.paddockDir(uid) / "sessions" / "s1.jsonl",
      $(%*{"role": "user", "text": "zarabatana antiga", "ts": 1_700_000_000_000}) & "\n")
    let hits = adapter.searchSessions(uid, "zarabatana", 5, false).get()
    check hits.len == 1
    check hits[0].timestampMs == 1_700_000_000_000

  test "an oversized transcript is searched through its most recent part":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    createDir(adapter.paddockDir(uid) / "sessions")
    var content = $(%*{"role": "user", "text": "inicio distante alcachofra"}) & "\n"
    let filler = $(%*{"role": "assistant", "text": repeat("x", 1000)}) & "\n"
    while content.len <= SessionSearchMaxFileBytes + 4096:
      content.add(filler)
    content.add($(%*{"role": "user", "text": "recado recente zarabatana"}) & "\n")
    writeFile(adapter.paddockDir(uid) / "sessions" / "big.jsonl", content)
    check adapter.searchSessions(uid, "zarabatana", 5, false).get().len == 1
    check adapter.searchSessions(uid, "alcachofra", 5, false).get().len == 0

  proc numbered(first, last: int): ConversationHistory =
    result = history(first, last)
    for i, msg in result.mpairs:
      msg.seq = (first + i).int64

  test "numbered messages with identical text are all stored":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    var all: ConversationHistory
    for i in 1 .. 24:
      all.add(ChatMessage(role: (if i mod 2 == 1: roleUser else: roleAssistant),
                          text: (if i mod 2 == 1: "ok" else: "certo"),
                          seq: i.int64))
    for last in countup(2, 24, 2):
      adapter.saveSession(uid, "s1", all[max(0, last - 20) ..< last])
    let lines = adapter.transcriptLines(uid, "s1")
    check lines.len == 24
    check lines[^1]["seq"].getBiggestInt == 24

  test "rewind followed by two saves stores each new message once":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    adapter.saveSession(uid, "s1", numbered(1, 6))
    var branch = numbered(1, 4)
    branch.add(ChatMessage(role: roleUser, text: "X", seq: 7))
    adapter.saveSession(uid, "s1", branch)
    adapter.saveSession(uid, "s1", branch)
    branch.add(ChatMessage(role: roleAssistant, text: "Y", seq: 8))
    adapter.saveSession(uid, "s1", branch)
    let texts = adapter.transcriptLines(uid, "s1").mapIt(it["text"].getStr)
    check texts.len == 8
    check texts.count("X") == 1
    check texts.count("Y") == 1

  test "a compaction summary never reaches the transcript":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    adapter.saveSession(uid, "s1", numbered(1, 6))
    var compacted = @[ChatMessage(role: roleUser, text: "resumo",
                                  seq: SyntheticMessageSeq)]
    compacted.add(numbered(5, 8))
    adapter.saveSession(uid, "s1", compacted)
    let texts = adapter.transcriptLines(uid, "s1").mapIt(it["text"].getStr)
    check texts.len == 8
    check "resumo" notin texts

  test "a truncated last line does not swallow the next message":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    createDir(adapter.paddockDir(uid) / "sessions")
    let path = adapter.paddockDir(uid) / "sessions" / "s1.jsonl"
    writeFile(path,
      $(%*{"role": "user", "text": "mensagem 1", "seq": 1}) & "\n" &
      "{\"role\": \"assistant\", \"text\": \"cortad")
    adapter.saveSession(uid, "s1", numbered(1, 4))
    let raw = readFile(path).splitLines()
    check raw[1] == "{\"role\": \"assistant\", \"text\": \"cortad"
    check parseJson(raw[2])["text"].getStr == "resposta 2"
    check adapter.searchSessions(uid, "resposta", 10, false).get().len == 2

  test "search reaches the newest lines of a transcript above the record cap":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    createDir(adapter.paddockDir(uid) / "sessions")
    var content = ""
    for i in 1 .. SessionSearchMaxRecords + 50:
      content.add($(%*{"role": "user", "text": "n" & $i}) & "\n")
    content.add($(%*{"role": "user", "text": "recado final zarabatana"}) & "\n")
    check content.len < SessionSearchMaxFileBytes
    writeFile(adapter.paddockDir(uid) / "sessions" / "long.jsonl", content)
    check adapter.searchSessions(uid, "zarabatana", 5, false).get().len == 1

  test "a last line larger than the read window does not block new messages":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    createDir(adapter.paddockDir(uid) / "sessions")
    let path = adapter.paddockDir(uid) / "sessions" / "s1.jsonl"
    writeFile(path, $(%*{"role": "user", "seq": 1,
                         "text": repeat("x", SessionTranscriptAlignBytes + 1024)}) & "\n")
    var next: ConversationHistory
    next.add(ChatMessage(role: roleUser, text: "primeira", seq: 1))
    next.add(ChatMessage(role: roleAssistant, text: "depois da linha enorme", seq: 2))
    adapter.saveSession(uid, "s1", next)
    adapter.saveSession(uid, "s1", next)
    let lines = readFile(path).splitLines().filterIt(it.strip.len > 0)
    check lines.len == 2
    check parseJson(lines[1])["seq"].getBiggestInt == 2

  test "a rewind to a checkpoint older than the read window stays exact":
    resetBase()
    defer: removeDir(searchBase)
    let adapter = MdFileAdapter(paddocksDir: searchBase)
    let uid = UserId("user-a")
    createDir(adapter.paddockDir(uid) / "sessions")
    let path = adapter.paddockDir(uid) / "sessions" / "s1.jsonl"
    ## Numbers 1, 2 and 6 onwards are stored; 4 was rewound before any save.
    var content = $(%*{"role": "user", "text": "m1", "seq": 1}) & "\n" &
                  $(%*{"role": "assistant", "text": "m2", "seq": 2}) & "\n"
    var number = 6
    while content.len <= SessionTranscriptAlignBytes + 4096:
      content.add($(%*{"role": "user", "seq": number,
                       "text": "m" & $number & " " & repeat("y", 2000)}) & "\n")
      inc number
    writeFile(path, content)
    let before = readFile(path).splitLines().filterIt(it.strip.len > 0).len
    var restored: ConversationHistory
    restored.add(ChatMessage(role: roleUser, text: "m1", seq: 1))
    restored.add(ChatMessage(role: roleAssistant, text: "m2", seq: 2))
    restored.add(ChatMessage(role: roleUser, text: "m4 nunca gravada", seq: 4))
    adapter.saveSession(uid, "s1", restored)
    adapter.saveSession(uid, "s1", restored)
    let lines = readFile(path).splitLines().filterIt(it.strip.len > 0)
    check lines.len == before + 1
    check parseJson(lines[^1])["seq"].getBiggestInt == 4

