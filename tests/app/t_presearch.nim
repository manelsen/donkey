## The pre-search: when the gatekeeper says a message is about the past, the
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
import donkey/ports/gatekeeper

let base = getTempDir() / ("donkey_presearch_" & $getCurrentProcessId())
let quiet = newLogger("test.presearch", lvlError)

proc gate(route: MessageRoute): GatekeeperPort =
  GatekeeperPort(classify: proc(message: string): Result[RouteDecision, string] {.gcsafe, raises: [].} =
    ok(RouteDecision(route: route, confidence: 0.9)))

proc failing(): GatekeeperPort =
  GatekeeperPort(classify: proc(message: string): Result[RouteDecision, string] {.gcsafe, raises: [].} =
    err("HTTP 503"))

proc ctx(): NativeCtx =
  NativeCtx(uid: UserId("marta"), channel: ckTelegram, fs: newFsAdapter(),
            outbox: newAsyncQueue[OutboundMessage](), log: quiet, paddockDir: base)

proc turn(port: GatekeeperPort; message: string): ConversationHistory =
  var h = newHistory()
  h.addUser(message)
  waitFor preSearch(port, ctx(), newSessionState(), h, message, quiet)

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
      check h[1].toolCalls[0].id == PreSearchCallId
      check parseJson(h[1].toolCalls[0].inputJson)["query"].getStr == "qual é a senha do wifi?"
      check h[2].role == roleTool
      check h[2].toolCallId == PreSearchCallId
      check "girassol42" in h[2].text

    test "order and recent-period messages are pre-searched too":
      check turn(gate(mrOrder), "o que veio primeiro?").len == 3
      check turn(gate(mrRecent), "o que falamos ontem?").len == 3

    test "a message not about the past is left alone":
      check turn(gate(mrNow), "kkkkk").len == 1

    test "a gatekeeper that fails leaves the turn as it would be without one":
      check turn(failing(), "qual é a senha do wifi?").len == 1

    test "no gatekeeper, no pre-search":
      check turn(GatekeeperPort(), "qual é a senha do wifi?").len == 1

when isMainModule:
  runTests()
