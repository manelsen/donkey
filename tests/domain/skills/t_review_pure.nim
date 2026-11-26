## The background review, the pure half (E7.4): when a review is due, what
## the reviewing model reads of the conversation, and the instructions it
## gets. Cadence and instructions after hermes-agent (MIT),
## agent/background_review.py and agent/review_signals.py.

import std/[strutils, unittest]
import donkey/config/environment
import donkey/domain/message
import donkey/domain/skills/review_pure

proc runTests*() =
  suite "review — settings and cadence":

    test "on by default, every 10 turns or 15 tool calls, the session's route":
      let s = reviewSettings(environmentOf({"X": "1"}))
      check s.enabled and s.everyTurns == 10 and s.everyToolCalls == 15
      check s.provider == "" and s.model == ""

    test "the operator sets the cadence and the auxiliary route, or turns it off":
      let s = reviewSettings(environmentOf({"DONKEY_REVIEW_EVERY_TURNS": "4",
        "DONKEY_REVIEW_EVERY_TOOL_CALLS": "6", "DONKEY_REVIEW_PROVIDER": "openrouter",
        "DONKEY_REVIEW_MODEL": "cheap/model"}))
      check s.everyTurns == 4 and s.everyToolCalls == 6
      check s.provider == "openrouter" and s.model == "cheap/model"
      check not reviewSettings(environmentOf({"DONKEY_REVIEW": "off"})).enabled
      check reviewSettings(environmentOf({"DONKEY_REVIEW_EVERY_TURNS": "0"})).everyTurns == 10

    test "a review is due after enough turns or enough tool calls, then the counts restart":
      let s = ReviewSettings(enabled: true, everyTurns: 3, everyToolCalls: 5)
      var c = ReviewCounts()
      check not c.noteTurn(toolCalls = 1, s)
      check not c.noteTurn(toolCalls = 1, s)
      check c.noteTurn(toolCalls = 0, s)          ## third turn
      check c.turns == 0 and c.toolCalls == 0
      check c.noteTurn(toolCalls = 6, s)          ## a busy turn
      var off = ReviewCounts()
      check not off.noteTurn(9, ReviewSettings(enabled: false, everyTurns: 1, everyToolCalls: 1))

  suite "review — what the reviewer reads":

    test "the last messages, as a transcript; tool calls named, results cut":
      var h: seq[ChatMessage]
      h.add ChatMessage(role: "user", text: "deploy the API to staging")
      h.add ChatMessage(role: "assistant", text: "", toolCalls: @[ToolCallRequest(id: "1", name: "bash")])
      h.add ChatMessage(role: "tool", toolCallId: "1", text: "x".repeat(5_000))
      h.add ChatMessage(role: "assistant", text: "Done: it is up.")
      let t = reviewTranscript(h)
      check "USER: deploy the API to staging" in t
      check "ASSISTANT called bash" in t
      check "TOOL: " in t and t.len < 3_000
      check t.endsWith("ASSISTANT: Done: it is up.")

    test "a long conversation keeps its end, within the budget":
      var h: seq[ChatMessage]
      for i in 0 ..< 400:
        h.add ChatMessage(role: "user", text: "message " & $i & " " & "y".repeat(200))
      let t = reviewTranscript(h)
      check t.len <= ReviewTranscriptChars + 200
      check "message 399" in t and "message 0 " notin t

    test "the instructions: what deserves a skill, and what never goes in one":
      check "skill_manage" in ReviewInstructions
      check "secret" in ReviewInstructions.toLowerAscii
      check "nothing" in ReviewInstructions.toLowerAscii

when isMainModule:
  runTests()
