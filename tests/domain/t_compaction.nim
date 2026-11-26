## Compaction (E8.5): when the history passes a share of the model's context
## (40% for 1M-token models, 60% for smaller ones), the old part becomes a
## summary and the recent tail stays as it was. Decided on 26/11.

import std/[strutils, unittest]
import donkey/domain/message
import donkey/domain/compaction_pure

proc turns(n: int; size = 400): ConversationHistory =
  var h = newHistory()
  for i in 0 ..< n:
    h.addUser("pergunta " & $i & " " & "x".repeat(size))
    h.addAssistant("resposta " & $i & " " & "y".repeat(size))
  h

proc runTests*() =
  suite "compaction — when":
    test "40% of a 1M context, 60% of a smaller one, 60% of 128k when unknown":
      check compactionThreshold(1_000_000) == 400_000
      check compactionThreshold(200_000) == 120_000
      check compactionThreshold(0) == 76_800

    test "the estimate grows with the text, about four characters a token":
      check estimateTokens(turns(10, 400)) in 2000 .. 2600

    test "past the threshold after an idle pause, or well past it at once":
      check not shouldCompact(tokens = 50_000, window = 100_000, idleMs = 600_000)
      check shouldCompact(tokens = 61_000, window = 100_000, idleMs = 600_000)
      ## right after a turn the cache is warm: wait, unless far beyond
      check not shouldCompact(tokens = 61_000, window = 100_000, idleMs = 60_000)
      check shouldCompact(tokens = 76_000, window = 100_000, idleMs = 60_000)

  suite "compaction — how":
    test "the tail starts at a person's message and holds about a quarter of the threshold":
      let h = turns(40, 400)
      let (old, tail) = splitForCompaction(h, keepTokens = 1000)
      check old.len + tail.len == h.len
      check tail[0].role == "user" and tail[0].toolCallId.len == 0
      check estimateTokens(tail) <= 1300
      check old.len > 0

    test "a tool call and its result are never split":
      var h = turns(10, 400)
      h.addUser("pesquisa")
      h.addAssistantWithToolCalls("", @[ToolCallRequest(id: "c1", name: "web_search", inputJson: "{}")])
      h.addToolResult("c1", "web_search", "z".repeat(4000), trkOutput)
      h.addAssistant("pronto")
      let (_, tail) = splitForCompaction(h, keepTokens = 200)
      check tail[0].text == "pesquisa"   ## the whole last exchange, from the person's message

    test "too short to split: nothing old":
      let (old, tail) = splitForCompaction(turns(1), keepTokens = 10_000)
      check old.len == 0 and tail.len == 2

    test "the compacted history: the summary, then the tail as it was":
      let (old, tail) = splitForCompaction(turns(40, 400), keepTokens = 1000)
      let c = compactedHistory("Decidimos usar Nim.", tail)
      check c.len == tail.len + 1
      check c[0].role == "user" and c[0].seq == SyntheticMessageSeq
      check "Decidimos usar Nim." in c[0].text
      check c[1 .. ^1] == tail
      check old.len > 0

    test "the summary request carries the old part as a transcript":
      let (old, _) = splitForCompaction(turns(40, 400), keepTokens = 1000)
      let req = summaryRequest(old)
      check req.system.len > 0 and req.tools.len == 0
      check req.messages.len == 1 and "pergunta 0" in req.messages[0].text

when isMainModule:
  runTests()
