## Per-turn traces: one JSON line per agent turn, with what happened (tools,
## tokens, provider, outcome) and never what was said.

import std/[json, strutils, unittest]
import donkey/domain/message
import donkey/domain/turn_trace_pure

proc turnMessages(): seq[ChatMessage] =
  var h = newHistory()
  h.addUser("qual é a senha do wifi?")
  h.addAssistantWithToolCalls("", @[
    ToolCallRequest(id: "c1", name: "session_search", inputJson: """{"phrase":"senha"}"""),
    ToolCallRequest(id: "c2", name: "calc", inputJson: "{}")])
  h.addToolResult("c1", "session_search", "girassol42", trkOutput)
  h.addToolResult("c2", "calc", "Error: bad expression", trkUsageError)
  h.addAssistant("A senha é girassol42.")
  h

proc runTests*() =
  suite "turn traces":

    test "the turn's tool calls, with each outcome":
      let tools = toolCallsOfTurn(turnMessages())
      check tools.len == 2
      check tools[0].name == "session_search" and tools[0].outcome == "output"
      check tools[1].name == "calc" and tools[1].outcome == "usage_error"

    test "a line carries what happened and none of what was said":
      let t = TurnTrace(startedMs: 1_800_000_000_000, durationMs: 1234,
        userId: "u-1", channel: "telegram", kind: "user", sessionId: "s1",
        provider: "openrouter", streamed: true, tools: toolCallsOfTurn(turnMessages()),
        inputTokens: 100, outputTokens: 20, outcome: "ok")
      let line = traceLine(t)
      check '\n' notin line
      let j = parseJson(line)
      check j["user"].getStr == "u-1"
      check j["duration_ms"].getInt == 1234
      check j["tools"].len == 2
      check j["tools"][1]["outcome"].getStr == "usage_error"
      check j["tokens"]["input"].getInt == 100
      check "senha" notin line and "girassol42" notin line

    test "one file per UTC day":
      check traceFileName(0) == "1970-01-01.jsonl"
      check traceFileName(1_800_000_000_000) == "2027-01-15.jsonl"
      check traceFileName(951_782_400_000) == "2000-02-29.jsonl"   ## leap day

    test "files older than the retention are the ones to remove":
      let now = 1_800_000_000_000'i64   ## 2027-01-15
      let names = @["2027-01-15.jsonl", "2027-01-02.jsonl", "2027-01-01.jsonl",
                    "2026-12-01.jsonl", "notes.txt"]
      check expiredTraceFiles(names, now, days = 14) == @["2027-01-01.jsonl", "2026-12-01.jsonl"]

    test "export keeps the lines since a time, for one user or all":
      let a = traceLine(TurnTrace(startedMs: 1_000, userId: "u-1", outcome: "ok"))
      let b = traceLine(TurnTrace(startedMs: 5_000, userId: "u-2", outcome: "ok"))
      check traceMatches(a, sinceMs = 0, user = "")
      check not traceMatches(a, sinceMs = 2_000, user = "")
      check traceMatches(b, sinceMs = 2_000, user = "u-2")
      check not traceMatches(b, sinceMs = 0, user = "u-1")
      check not traceMatches("not json", sinceMs = 0, user = "")

when isMainModule:
  runTests()
