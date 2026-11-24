## The pre-search: when the backtrail says a message is about the past, the
## turn starts with the result of `session_search` already in the history.

import std/[json, os, strutils, unittest]
import chronos
import chronos/asyncsync
import donkey/adapters/filesystem/fs_adapter
import donkey/app/native_tools
import donkey/app/presearch
import donkey/app/session_state
import donkey/core/log
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/ports/backtrail

let base = getTempDir() / ("donkey_presearch_" & $getCurrentProcessId())
let quiet = newLogger("test.presearch", lvlError)

proc gate(route: MessageRoute): BacktrailPort =
  BacktrailPort(classify: proc(message: string): Result[RouteDecision, string] {.gcsafe, raises: [].} =
    ok(RouteDecision(route: route, confidence: 0.9)))

proc failing(): BacktrailPort =
  BacktrailPort(classify: proc(message: string): Result[RouteDecision, string] {.gcsafe, raises: [].} =
    err("HTTP 503"))

proc ctx(): NativeCtx =
  NativeCtx(uid: UserId("marta"), channel: ckTelegram, fs: newFsAdapter(),
            outbox: newAsyncQueue[OutboundMessage](), log: quiet, paddockDir: base)

proc turn(port: BacktrailPort; message: string; callId = "presearch-m1"): ConversationHistory =
  var h = newHistory()
  h.addUser(message)
  waitFor preSearch(port, ctx(), newSessionState(), h, message, callId, quiet)

proc runTests*() =
  suite "pre-search":
    setup:
      removeDir(base)
      createDir(base / "sessions")
      writeFile(base / "sessions" / "s1.jsonl",
        $(%*{"role": "user", "text": "trocaram o roteador, a senha do wifi novo é girassol42",
             "ts": 1_700_000_000_000'i64, "seq": 1}) & "\n")
    teardown:
      removeDir(base)

    test "a message about the past starts with the search already made":
      let h = turn(gate(mrFact), "qual é a senha do wifi?")
      check h.len == 3
      check h[0].role == roleUser
      check h[1].role == roleAssistant
      check h[1].toolCalls.len == 1
      check h[1].toolCalls[0].name == "session_search"
      check h[1].toolCalls[0].id == "presearch-m1"
      check parseJson(h[1].toolCalls[0].inputJson)["query"].getStr == "qual é a senha do wifi?"
      check h[2].role == roleTool
      check h[2].toolCallId == "presearch-m1"
      check "girassol42" in h[2].text

    test "each turn's pre-search has its own call id":
      ## Providers reject a conversation where two tool calls share an id.
      var h = turn(gate(mrFact), "qual é a senha do wifi?", preSearchCallId("m1"))
      h.addAssistant("girassol42")
      h.addUser("e o protocolo?")
      h = waitFor preSearch(gate(mrFact), ctx(), newSessionState(), h, "e o protocolo?",
                            preSearchCallId("m2"), quiet)
      var ids: seq[string]
      for m in h:
        for c in m.toolCalls: ids.add(c.id)
      check ids == @["presearch-m1", "presearch-m2"]

    test "order and recent-period messages are pre-searched too":
      check turn(gate(mrOrder), "o que veio primeiro?").len == 3
      check turn(gate(mrRecent), "o que falamos ontem?").len == 3

    test "a message not about the past is left alone":
      check turn(gate(mrNow), "kkkkk").len == 1

    test "a backtrail that fails leaves the turn as it would be without one":
      check turn(failing(), "qual é a senha do wifi?").len == 1

    test "no backtrail, no pre-search":
      check turn(BacktrailPort(), "qual é a senha do wifi?").len == 1

when isMainModule:
  runTests()
