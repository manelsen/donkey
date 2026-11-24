## `searchConversations` over a real paddock: every mode, the whole history
## (not just the newest sessions), time windows and the coverage it reports.

import std/[json, os, strutils, times, unittest]
import chronos
import donkey/adapters/filesystem/fs_adapter
import donkey/app/conversation_search
import donkey/core/pipeops

const
  DayMs = 86_400_000'i64
  Now = 1_700_000_040_000'i64

let base = getTempDir() / ("donkey_conv_search_" & $getCurrentProcessId())

proc writeSession(id: string; texts: openArray[string]; ageDays: int) =
  var content = ""
  let start = Now - int64(ageDays) * DayMs
  for i, t in texts:
    content.add($(%*{"role": (if i mod 2 == 0: "user" else: "assistant"),
                     "text": t, "ts": start + int64(i) * 60_000, "seq": i + 1}) & "\n")
  let path = base / "sessions" / (id & ".jsonl")
  writeFile(path, content)
  setLastModificationTime(path, fromUnix((start div 1000) + 3600))

proc search(req: ConversationSearchRequest): string =
  let r = waitFor searchConversations(newFsAdapter(), base, req, Now)
  if r.isErr: "ERR " & r.error else: r.get

proc runTests*() =
  suite "conversation search — over the whole history":
    setup:
      removeDir(base)
      createDir(base / "sessions")
    teardown:
      removeDir(base)

    test "an exact phrase is found in an old session past the newest fifty":
      writeSession("old", ["a senha do wifi é kappa-7731", "ok"], ageDays = 400)
      for i in 0 ..< 60:
        writeSession("recent" & $i, ["nada a ver " & $i, "certo"], ageDays = i)
      let text = search(ConversationSearchRequest(phrase: "KAPPA-7731"))
      check "1 matches for \"KAPPA-7731\" (all 61 sessions)" in text
      check "[session old ·" in text
      check ": user: a senha do wifi é kappa-7731" in text
      check "- assistant: ok" in text

    test "matches page newest first, and offset continues":
      for i in 0 ..< 15:
        writeSession("s" & $i, ["deploy do kappa " & $i], ageDays = i)
      let first = search(ConversationSearchRequest(phrase: "deploy do kappa", limit: 10))
      check "15 matches" in first
      check "showing 1-10" in first
      check "offset=10" in first
      check first.find("[session s0 ") < first.find("[session s1 ")
      let second = search(ConversationSearchRequest(phrase: "deploy do kappa", limit: 10, offset: 10))
      check "showing 11-15" in second
      check "offset=" notin second
      let oldest = search(ConversationSearchRequest(phrase: "deploy do kappa", oldestFirst: true, limit: 1))
      check "[session s14 " in oldest

    test "count says how many, per session, without the messages":
      writeSession("a", ["kappa", "kappa de novo", "kappa"], ageDays = 1)
      writeSession("b", ["kappa"], ageDays = 2)
      let text = search(ConversationSearchRequest(phrase: "kappa", countOnly: true))
      check "4 matches" in text
      check "- a: 3" in text
      check "- b: 1" in text
      check "kappa de novo" notin text

    test "ranked terms find the right conversation and say where to read":
      writeSession("bolo", ["receita de bolo de cenoura", "anotado"], ageDays = 3)
      writeSession("infra", ["o cluster kubernetes caiu no deploy", "vou ver"], ageDays = 200)
      let text = search(ConversationSearchRequest(query: "deploy no kubernetes"))
      check "[session infra" in text
      check "bolo" notin text

    test "reading around a hit shows the neighbouring messages":
      writeSession("s1", ["um", "dois", "três", "quatro", "cinco"], ageDays = 1)
      let text = search(ConversationSearchRequest(sessionId: "s1", around: 3, context: 1))
      check "#2 assistant: dois" in text
      check "> #3 user: três" in text
      check "#4 assistant: quatro" in text
      check "#1 " notin text
      check "Session s1 has no message #9" in search(
        ConversationSearchRequest(sessionId: "s1", around: 9))
      check search(ConversationSearchRequest(sessionId: "../etc")).startsWith("ERR")
      check search(ConversationSearchRequest(sessionId: "nope")).startsWith("ERR")

    test "since and until narrow by time":
      writeSession("old", ["kappa antigo"], ageDays = 30)
      writeSession("new", ["kappa novo"], ageDays = 1)
      let recent = search(ConversationSearchRequest(phrase: "kappa", since: "7d"))
      check "kappa novo" in recent and "kappa antigo" notin recent
      let older = search(ConversationSearchRequest(phrase: "kappa", until: "7d"))
      check "kappa antigo" in older and "kappa novo" notin older
      check search(ConversationSearchRequest(phrase: "kappa", since: "ontem")).startsWith("ERR")

    test "a user with no sessions yet gets no matches, not an error":
      removeDir(base / "sessions")
      check "0 matches" in search(ConversationSearchRequest(phrase: "kappa"))

    test "a paddock that is not there is an error":
      removeDir(base)
      check search(ConversationSearchRequest(phrase: "kappa")).startsWith("ERR")

when isMainModule:
  runTests()
