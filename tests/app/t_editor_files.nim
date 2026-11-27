## Reading a file in the person's editor (E10.5): the daemon asks through the
## turn's stream and waits, with a deadline, for the editor's answer; only
## the person whose turn asked can answer.

import std/[json, strutils, unittest]
import chronos
import donkey/core/pipeops
import donkey/core/types
import donkey/domain/message
import donkey/app/editor_files

proc runTests*() =
  suite "editor file requests":
    test "the request goes to the turn's stream; the person's answer comes back":
      let r = newEditorFileRequests()
      let outbox = newAsyncQueue[OutboundMessage](4)
      let asked = r.ask(UserId("u-ana"), outbox, 7, "src/a.nim", line = 10, limit = 50,
                        timeoutMs = 5_000)
      let sent = outbox.getNoWait()
      check sent.bridgeToken == 7 and sent.userId == UserId("u-ana")
      let req = parseJson(sent.editorRequest)
      check req["method"] == %"fs/read_text_file"
      check req["params"] == %* {"path": "src/a.nim", "line": 10, "limit": 50}
      check r.answer(UserId("u-bob"), req["id"].getStr, "intruso", "").isErr   ## not his
      check r.answer(UserId("u-ana"), req["id"].getStr, "echo 1", "").isOk
      check (waitFor asked).get == "echo 1"
      check r.answer(UserId("u-ana"), req["id"].getStr, "again", "").isErr     ## once

    test "the editor's error comes back as an error":
      let r = newEditorFileRequests()
      let outbox = newAsyncQueue[OutboundMessage](4)
      let asked = r.ask(UserId("u"), outbox, 1, "/x", timeoutMs = 5_000)
      let id = parseJson(outbox.getNoWait().editorRequest)["id"].getStr
      check r.answer(UserId("u"), id, "", "no such file").isOk
      let got = waitFor asked
      check got.isErr and "no such file" in got.error

    test "no answer in time is an error, and a late answer is refused":
      let r = newEditorFileRequests()
      let outbox = newAsyncQueue[OutboundMessage](4)
      let got = waitFor r.ask(UserId("u"), outbox, 1, "/x", timeoutMs = 50)
      check got.isErr and "did not answer" in got.error
      let id = parseJson(outbox.getNoWait().editorRequest)["id"].getStr
      check r.answer(UserId("u"), id, "late", "").isErr

    test "an answer that lands as the deadline fires is still taken":
      let r = newEditorFileRequests()
      let outbox = newAsyncQueue[OutboundMessage](4)
      let asked = r.ask(UserId("u"), outbox, 1, "/x", timeoutMs = 1)
      let id = parseJson(outbox.getNoWait().editorRequest)["id"].getStr
      discard r.answer(UserId("u"), id, "just in time", "")
      check (waitFor asked).get == "just in time"

    test "a long file is cut, saying so":
      let r = newEditorFileRequests()
      let outbox = newAsyncQueue[OutboundMessage](4)
      let asked = r.ask(UserId("u"), outbox, 1, "/big", timeoutMs = 5_000)
      let id = parseJson(outbox.getNoWait().editorRequest)["id"].getStr
      check r.answer(UserId("u"), id, "x".repeat(MaxEditorFileBytes + 10), "").isOk
      let text = (waitFor asked).get
      check text.len < MaxEditorFileBytes + 200 and "cortado" in text

when isMainModule:
  runTests()
