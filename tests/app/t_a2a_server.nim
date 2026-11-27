## E13.4: the A2A server's methods, with a fake turn.

import std/[json, unittest]
import chronos
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/a2a/a2a_pure
import donkey/app/a2a_server

var gSeq = 0
proc nextId(): string {.gcsafe, raises: [].} =
  inc gSeq
  "id" & $gSeq

proc echoTurn(person: UserId; text: string): Future[Result[string, string]] {.async.} =
  if text == "falhe": return err("o provider caiu")
  return ok($person & " leu: " & text)

proc call(srv: A2aServer; person: UserId; body: string): JsonNode =
  waitFor srv.handleRpc(person, body)

proc send(text: string; contextId = ""): string =
  var msg = %*{"messageId": "m", "role": "ROLE_USER", "parts": [{"text": text}]}
  if contextId.len > 0: msg["contextId"] = %contextId
  $(%*{"jsonrpc": "2.0", "id": 1, "method": "SendMessage", "params": {"message": msg}})

proc runTests*() =
  suite "a2a server (E13.4)":
    setup:
      gSeq = 0
      let srv = newA2aServer(echoTurn, nextId, proc(): string = "2026-11-27T22:00:00Z")

    test "SendMessage runs a turn as the paired person and answers a completed task":
      let r = srv.call(UserId("ana"), send("oi", contextId = "c9"))
      let task = r["result"]["task"]
      check task["status"]["state"].getStr == "TASK_STATE_COMPLETED"
      check task["artifacts"][0]["parts"][0]["text"].getStr == "ana leu: oi"
      check task["contextId"].getStr == "c9"

    test "a turn that fails is a failed task, not a JSON-RPC error":
      let task = srv.call(UserId("ana"), send("falhe"))["result"]["task"]
      check task["status"]["state"].getStr == "TASK_STATE_FAILED"
      check task["status"]["message"]["parts"][0]["text"].getStr == "o provider caiu"

    test "GetTask finds the person's task, and only theirs":
      let id = srv.call(UserId("ana"), send("oi"))["result"]["task"]["id"].getStr
      let get = $(%*{"jsonrpc": "2.0", "id": 2, "method": "GetTask", "params": {"id": id}})
      check srv.call(UserId("ana"), get)["result"]["id"].getStr == id
      check srv.call(UserId("bia"), get)["error"]["code"].getInt == ErrTaskNotFound

    test "CancelTask on a finished task: not cancelable; unknown: not found":
      let id = srv.call(UserId("ana"), send("oi"))["result"]["task"]["id"].getStr
      let cancel = proc(tid: string): string =
        $(%*{"jsonrpc": "2.0", "id": 3, "method": "CancelTask", "params": {"id": tid}})
      check srv.call(UserId("ana"), cancel(id))["error"]["code"].getInt == ErrTaskNotCancelable
      check srv.call(UserId("ana"), cancel("nada"))["error"]["code"].getInt == ErrTaskNotFound

    test "bad requests: parse, unknown method, missing text":
      check srv.call(UserId("ana"), "{x")["error"]["code"].getInt == ErrParse
      let other = $(%*{"jsonrpc": "2.0", "id": 4, "method": "SendStreamingMessage", "params": {}})
      check srv.call(UserId("ana"), other)["error"]["code"].getInt == ErrMethodNotFound
      ## v0.3's names answer in v0.3's shape, which this server does not speak
      let old = $(%*{"jsonrpc": "2.0", "id": 6, "method": "message/send", "params": {}})
      check srv.call(UserId("ana"), old)["error"]["code"].getInt == ErrMethodNotFound
      let empty = $(%*{"jsonrpc": "2.0", "id": 5, "method": "SendMessage",
                       "params": {"message": {"parts": []}}})
      check srv.call(UserId("ana"), empty)["error"]["code"].getInt == ErrInvalidParams

    test "the store keeps the newest tasks only":
      for i in 0 ..< MaxA2aTasks + 5: discard srv.call(UserId("ana"), send("oi"))
      check srv.taskCount == MaxA2aTasks

  suite "a2a server — the turn's reply (E13.4)":
    test "200: the completion's text; otherwise the error's message":
      let okBody = """{"choices":[{"message":{"role":"assistant","content":"feito"}}]}"""
      check replyText(200, okBody).get == "feito"
      let late = """{"error":{"message":"agent turn timed out","type":"timeout"}}"""
      check replyText(504, late).error == "agent turn timed out"
      check replyText(502, "not json").isErr
      check replyText(200, """{"choices":[]}""").isErr

when isMainModule:
  runTests()
