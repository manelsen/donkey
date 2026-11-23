## Conversation search, the pure part: transcripts, folding, exact phrases
## with context (GrepMem-style), BM25 ranking by session, time bounds and the
## rendered output the model reads.

import std/[json, options, strutils, unittest]
import results
import donkey/domain/memory/conversation_search_pure

const
  HourMs = 3_600_000'i64
  DayMs = 24 * HourMs
  Now = 1_700_000_040_000'i64   ## 2023-11-14T22:14:00Z

proc line(role, text: string; ts: int64; seq = 0'i64): string =
  var j = %*{"role": role, "text": text, "ts": ts}
  if seq > 0: j["seq"] = %seq
  $j & "\n"

proc msgs(sessionId: string; texts: openArray[(string, string)];
          start = Now - DayMs): seq[ConvMessage] =
  var content = ""
  for i, (role, text) in texts:
    content.add(line(role, text, start + int64(i) * 60_000, int64(i + 1)))
  parseTranscriptMessages(sessionId, content, 0)

proc runTests*() =
  suite "conversation search — transcripts and folding":

    test "a transcript line becomes a message with its number and time":
      let m = parseTranscriptMessages("s1",
        line("user", "olá", 1000, 7) & "garbage\n" & line("assistant", "", 2000) &
        line("assistant", "oi", 3000), fallbackTsMs = 5)
      check m.len == 2
      check m[0].seq == 7 and m[0].tsMs == 1000 and m[0].role == "user"
      check m[1].seq == 4      ## no number: the line's position
      check m[1].sessionId == "s1"

    test "a line without a time takes the fallback":
      let m = parseTranscriptMessages("s1", $(%*{"role": "user", "text": "x"}), 99)
      check m[0].tsMs == 99

    test "folding ignores case and Latin accents":
      check foldText("Não É Ação") == "nao e acao"
      check foldText("ÇÃO über") == "cao uber"

  suite "conversation search — exact phrases":

    test "every message holding the phrase is a match, with its neighbours":
      let session = msgs("s1", [("user", "o servidor é o kappa-7"),
                                ("assistant", "anotado"),
                                ("user", "lembra o Kappa-7?"),
                                ("assistant", "sim")])
      let found = phraseMatches(session, "kappa-7", context = 1)
      check found.len == 2
      check found[0].msg.seq == 1
      check found[0].before.len == 0 and found[0].after.len == 1
      check found[1].msg.seq == 3
      check found[1].before[0].text == "anotado"

    test "accents and case do not matter for the phrase":
      let session = msgs("s1", [("user", "A REUNIÃO é às 15h")])
      check phraseMatches(session, "reuniao e as 15h", 0).len == 1

    test "earlier search results in the transcript are not matched again":
      let session = msgs("s1", [("tool", "[tool_result name=\"session_search\" status=\"output\"]\nkappa-7"),
                                ("user", "kappa-7")])
      let found = phraseMatches(session, "kappa-7", 0)
      check found.len == 1
      check found[0].msg.role == "user"

    test "a time window keeps only the messages inside it":
      let session = msgs("s1", [("user", "kappa"), ("user", "kappa")], start = Now - 10 * DayMs)
      let w = TimeWindow(sinceMs: Now - 10 * DayMs + 30_000, untilMs: 0)
      check phraseMatches(session, "kappa", 0, w).len == 1

    test "a long message is clipped around the match":
      let text = repeat("a", 2000) & " kappa-7 " & repeat("b", 2000)
      let clipped = clipAround(text, "kappa-7", 300)
      check "kappa-7" in clipped
      check clipped.len <= 300 + 8
      check clipped.startsWith("…") and clipped.endsWith("…")

    test "clipping keeps the original accents":
      check "Reunião" in clipAround("x Reunião às 15h y", "reuniao", 300)

  suite "conversation search — ranked by session (BM25)":

    test "the session that best matches the terms ranks first, once":
      var r = initRanker(@["deploy", "kubernetes"])
      r.add(msgs("s1", [("user", "deploy no kubernetes amanhã"),
                        ("user", "o deploy do kubernetes falhou de novo")]))
      r.add(msgs("s2", [("user", "deploy manual")]))
      r.add(msgs("s3", [("user", "receita de bolo"), ("user", "outra receita")]))
      let hits = r.topSessions(10)
      check hits.len == 2
      check hits[0].sessionId == "s1"
      check hits[0].matchedMessages == 2
      check hits[1].sessionId == "s2"

    test "a rare term weighs more than a common one":
      var r = initRanker(@["deploy", "kappa"])
      for i in 0 ..< 20:
        r.add(msgs("common" & $i, [("user", "deploy")]))
      r.add(msgs("rare", [("user", "kappa")]))
      check r.topSessions(1)[0].sessionId == "rare"

    test "a term matches words that start with it":
      var r = initRanker(@["deploy"])
      r.add(msgs("s1", [("user", "os deployments de ontem")]))
      check r.topSessions(5).len == 1

    test "the snippet is the best message, clipped around a term":
      var r = initRanker(@["kappa"])
      r.add(msgs("s1", [("user", "nada"), ("assistant", "o kappa é o servidor")]))
      let hit = r.topSessions(1)[0]
      check hit.seq == 2
      check "kappa" in hit.snippet

    test "terms come from the query without short words":
      check rankTerms("o deploy de Kubernetes") == @["deploy", "kubernetes"]
      check rankTerms("de o") == @["de", "o"]

  suite "conversation search — time bounds":

    test "relative and absolute bounds":
      check parseTimeBound("7d", Now, isUntil = false).get == Now - 7 * DayMs
      check parseTimeBound("24h", Now, false).get == Now - DayMs
      check parseTimeBound("2w", Now, false).get == Now - 14 * DayMs
      check parseTimeBound("2023-11-01", Now, false).get == 1_698_796_800_000'i64
      check parseTimeBound("2023-11-01", Now, isUntil = true).get ==
        1_698_796_800_000'i64 + DayMs - 1
      check parseTimeBound("", Now, false).get == 0
      check parseTimeBound("yesterday", Now, false).isErr

  suite "conversation search — what the model reads":

    test "phrase results carry a header, mark the match and say what is next":
      let session = msgs("s1", [("user", "antes"), ("user", "o kappa-7"), ("assistant", "depois")])
      let found = phraseMatches(session, "kappa-7", 1)
      let text = renderPhraseResults(found, total = 3, offset = 0, phrase = "kappa-7",
                                     coverage = "all 4 sessions")
      check "3 matches for \"kappa-7\" (all 4 sessions); showing 1-1" in text
      check "[session s1 · 2023-11-13 22:15 UTC · #2]" in text
      check ": user: o kappa-7" in text
      check "- user: antes" in text
      check "- assistant: depois" in text
      check "offset=1" in text

    test "the output stops on a whole match under the cap":
      var found: seq[PhraseMatch]
      for i in 0 ..< 50:
        found.add(PhraseMatch(msg: ConvMessage(sessionId: "s", seq: int64(i + 1), role: "user",
                                               text: "kappa " & repeat("x", 280), tsMs: Now)))
      let text = renderPhraseResults(found, total = 50, offset = 0, phrase = "kappa",
                                     coverage = "all 1 sessions", maxChars = 2000)
      check text.len <= 2300
      check "offset=" in text

    test "ranked results list sessions with where to read":
      var r = initRanker(@["kappa"])
      r.add(msgs("s1", [("user", "o kappa")]))
      let text = renderRankedHits(r.topSessions(5), "kappa", coverage = "all 1 sessions")
      check "s1" in text
      check "#1" in text
      check "session_id" in text   ## how to read around it

    test "reading around a message numbers every line and clips long ones":
      let session = msgs("s1", [("user", "um"), ("assistant", repeat("z", 5000)),
                                ("user", "três"), ("user", "quatro")])
      let text = renderReadWindow(session, "s1", around = 2, radius = 1)
      check "#1 user: um" in text
      check "#3 user: três" in text
      check "#4" notin text
      check "[…truncated]" in text
      check renderReadWindow(session, "s1", around = 99, radius = 1).contains("no message #99")

  suite "conversation search — straight from the file":

    test "the file path finds the same matches as the parsed one":
      var content = ""
      for i, t in ["antes", "o \"kappa\"\nlinha dois", "depois", "nada"]:
        content.add(line((if i mod 2 == 0: "user" else: "assistant"), t, Now + int64(i), int64(i + 1)))
      let fromFile = phraseMatchesIn("s1", content, 0, "kappa", 1)
      let parsed = phraseMatches(parseTranscriptMessages("s1", content, 0), "kappa", 1)
      check fromFile.len == 1 and parsed.len == 1
      check fromFile[0].msg == parsed[0].msg
      check fromFile[0].msg.text == "o \"kappa\"\nlinha dois"
      check fromFile[0].before[0].text == "antes"
      check fromFile[0].after[0].text == "depois"

    test "a line with a \\u escape is still searched":
      let content = "{\"role\":\"user\",\"text\":\"reuni\\u00e3o kappa\",\"ts\":5}\n"
      let found = phraseMatchesIn("s1", content, 0, "reunião", 0)
      check found.len == 1
      check found[0].msg.text == "reunião kappa"

    test "a line without a number keeps its position":
      let content = $(%*{"role": "user", "text": "x"}) & "\n" &
                    $(%*{"role": "user", "text": "kappa"}) & "\n"
      check phraseMatchesIn("s1", content, 7, "kappa", 0)[0].msg.seq == 2
      check phraseMatchesIn("s1", content, 7, "kappa", 0)[0].msg.tsMs == 7

    test "ranking from the file agrees with ranking the messages":
      var a = initRanker(@["deploy"])
      var b = initRanker(@["deploy"])
      let content = line("user", "o deploy caiu", Now, 1) & line("user", "nada", Now, 2)
      a.addTranscript("s1", content, 0)
      b.add(parseTranscriptMessages("s1", content, 0))
      check a.topSessions(1)[0].seq == b.topSessions(1)[0].seq
      check "deploy" in a.topSessions(1)[0].snippet

when isMainModule:
  runTests()
