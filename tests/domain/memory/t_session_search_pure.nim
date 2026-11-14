## Tests for pure session search ranking.

import std/[options, strutils, unicode, unittest]
import donkey/domain/memory/session_search_pure

proc rec(sessionId, role, text: string; kind = shkSession;
         ts: int64 = 0): SessionSearchRecord =
  SessionSearchRecord(sessionId: sessionId, kind: kind, role: role,
                      text: text, timestampMs: ts)

suite "session_search_pure":

  test "query terms fold case and punctuation":
    check queryTerms("Deploy, PRODUCTION!") == @["deploy", "production"]
    check queryTerms("café") == @["café"]
    check queryTerms("").len == 0
    check queryTerms("a a a b") == @["a", "b"]

  test "scores records with all terms above partial matches":
    let query = "deploy production"
    let full = rec("s1", "user", "We deploy production on Fridays")
    let partial = rec("s2", "user", "deploy staging only")
    check scoreSessionRecord(full, query, 0) > scoreSessionRecord(partial, query, 0)
    check scoreSessionRecord(rec("s3", "user", "nothing here"), query, 0) == 0

  test "phrase and role bonuses are applied":
    let phrase = rec("s1", "user", "the deploy production checklist")
    let scattered = rec("s2", "user", "deploy then production")
    check scoreSessionRecord(phrase, "deploy production", 0) >
          scoreSessionRecord(scattered, "deploy production", 0)
    check scoreSessionRecord(rec("s1", "memory", "deploy"), "deploy", 0) >
          scoreSessionRecord(rec("s1", "assistant", "deploy"), "deploy", 0)

  test "recency breaks ties without dominating relevance":
    let old = rec("old", "user", "deploy", ts = 0)
    let recent = rec("recent", "user", "deploy", ts = 1_000_000)
    check scoreSessionRecord(recent, "deploy", 1_000_001) >
          scoreSessionRecord(old, "deploy", 1_000_001)

  test "snippet is bounded and UTF-8-safe":
    let long = repeat("a", 200) & " café deploy " & repeat("b", 200)
    let snippet = makeSnippet(long, "deploy", 80)
    check snippet.len <= 90
    check "deploy" in snippet
    check validateUtf8(snippet) == -1
    let emoji = "😀 " & repeat("x", 100) & " deploy"
    check validateUtf8(makeSnippet(emoji, "deploy", 40)) == -1

  test "rank filters, sorts and clamps":
    let records = @[
      rec("s1", "user", "deploy production"),
      rec("s2", "user", "deploy"),
      rec("s3", "user", "unrelated"),
    ]
    let hits = rankSessionRecords(records, "deploy", 0, 1)
    check hits.len == 1
    check hits[0].sessionId == "s1"
    check hits[0].score > 0

  test "zero limit uses the default and max limit is capped":
    check clampSessionSearchLimit(0) == SessionSearchDefaultLimit
    check clampSessionSearchLimit(-1) == SessionSearchDefaultLimit
    check clampSessionSearchLimit(999) == SessionSearchMaxLimit
    check clampSessionSearchLimit(7) == 7

  test "empty query returns no hits":
    check rankSessionRecords(@[rec("s1", "user", "deploy")], "", 0).len == 0
