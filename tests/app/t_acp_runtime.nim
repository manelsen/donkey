## `donkey acp` (E10.1–E10.3): the editor's JSON-RPC in, the gateway's stream
## out, pairing the first time. Ports are fakes: no socket, no clock.

import std/[json, strutils, unittest]
import chronos
import donkey/core/pipeops
import donkey/app/acp_runtime

type Fake = ref object
  written: seq[string]
  token: string            ## the stored credential
  saved: seq[string]
  pollAnswers: seq[GatewayPoll]
  turnLines: seq[string]
  turnStatus: int
  turnError: string
  turnTexts: seq[string]
  turnTokens: seq[string]
  hangTurn: bool
  naps: int
  approved: seq[(string, string)]   ## (token, callback) sent back
  waitApproval: bool                ## the turn waits for the decision, as the daemon's does
  results: seq[(string, string, string, string)]   ## editor results: (token, id, content, error)
  decided: Future[void].Raising([CancelledError])

var gF {.threadvar.}: Fake

proc fakeWrite(line: string) {.gcsafe, raises: [].} = gF.written.add line
proc fakeLoad(): string {.gcsafe, raises: [].} = gF.token
proc fakeSave(token: string): Result[void, string] {.gcsafe, raises: [].} =
  gF.saved.add token
  gF.token = token
  ok()
proc fakePair(name: string): Future[Result[GatewayPairing, string]] {.async: (raises: []).} =
  return ok(GatewayPairing(code: "K7QP2M", secret: "sec"))
proc fakePoll(secret: string): Future[Result[GatewayPoll, string]] {.async: (raises: []).} =
  let answer = gF.pollAnswers[0]
  gF.pollAnswers.delete(0)
  return ok(answer)
proc fakeTurn(token, text: string; onLine: LineSink): Future[TurnReply] {.async: (raises: [CancelledError]).} =
  gF.turnTexts.add text
  gF.turnTokens.add token
  if gF.hangTurn:
    await sleepAsync(chronos.hours(1))
  for line in gF.turnLines: onLine(line)
  if gF.waitApproval:
    await gF.decided
  return TurnReply(status: gF.turnStatus, error: gF.turnError)
proc fakeNap(ms: int): Future[void] {.async: (raises: [CancelledError]).} =
  inc gF.naps
proc fakeApprove(token, callback: string): Future[Result[string, string]] {.async: (raises: []).} =
  gF.approved.add((token, callback))
  if gF.waitApproval and not gF.decided.finished: gF.decided.complete()
  return ok("✅ Aprovado.")

proc fakeEditorResult(token, id, content, error: string): Future[Result[void, string]] {.async: (raises: []).} =
  gF.results.add((token, id, content, error))
  if gF.waitApproval and not gF.decided.finished: gF.decided.complete()
  return ok()

proc fakePorts(f: Fake): AcpPorts =
  gF = f
  f.decided = Future[void].Raising([CancelledError]).init("fake.decided")
  AcpPorts(write: fakeWrite, loadToken: fakeLoad, saveToken: fakeSave,
           pair: fakePair, poll: fakePoll, turn: fakeTurn, nap: fakeNap,
           approve: fakeApprove, editorResult: fakeEditorResult)

proc sent(f: Fake): seq[JsonNode] =
  for w in f.written: result.add parseJson(w)

proc feed(rt: AcpRuntime; line: string) = waitFor rt.handleLine(line)

proc started(f: Fake; reads = false): AcpRuntime =
  result = newAcpRuntime(fakePorts(f), "0.3.0")
  if reads:
    result.feed("""{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true}}}}""")
  else:
    result.feed("""{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}""")
  result.feed("""{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"/proj","mcpServers":[]}}""")

const Prompt = """{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"$1","prompt":[{"type":"text","text":"oi"}]}}"""

proc runTests*() =
  suite "acp runtime":
    test "initialize and a new session":
      let f = Fake(token: "tok")
      discard started(f)
      check f.sent[0]["id"] == %1 and f.sent[0]["result"]["protocolVersion"] == %1
      check f.sent[1]["id"] == %2 and f.sent[1]["result"]["sessionId"].getStr.len > 0

    test "a prompt streams text and tools and answers why it stopped":
      let f = Fake(token: "tok", turnStatus: 200, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"role":"assistant"}}]}""",
        """data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"bash"}}]}}]}""",
        """data: {"choices":[{"index":0,"delta":{"content":"Pronto"}}]}""",
        """data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}""",
        "data: [DONE]"])
      let rt = started(f)
      let sid = f.sent[1]["result"]["sessionId"].getStr
      rt.feed(Prompt % sid)
      waitFor rt.idle()
      check f.turnTexts == @["oi"] and f.turnTokens == @["tok"]
      let s = f.sent
      check s[2]["params"]["update"]["sessionUpdate"] == %"tool_call"
      check s[3]["params"]["update"] == %* {"sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "completed"}
      check s[4]["params"]["update"]["content"]["text"] == %"Pronto"
      check s[^1] == %* {"jsonrpc": "2.0", "id": 3, "result": {"stopReason": "end_turn"}}

    test "the first prompt pairs: the code, waiting, the credential saved, then the turn":
      let f = Fake(turnStatus: 200, turnLines: @["""data: {"choices":[{"index":0,"delta":{"content":"oi, Ana"}}]}"""],
                   pollAnswers: @[GatewayPoll(state: gpPending), GatewayPoll(state: gpPaired, token: "new-tok")])
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()
      check "/editor K7QP2M" in f.written[2]
      check f.saved == @["new-tok"] and f.turnTokens == @["new-tok"]
      check f.naps >= 2
      check "oi, Ana" in f.written[^2]
      check f.sent[^1]["result"]["stopReason"] == %"end_turn"

    test "an expired code ends the prompt, saying so":
      let f = Fake(pollAnswers: @[GatewayPoll(state: gpUnknown)])
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()
      check f.turnTexts.len == 0 and f.saved.len == 0
      check "expirou" in f.written[^2]
      check f.sent[^1]["result"]["stopReason"] == %"end_turn"

    test "a revoked credential is forgotten and the editor is told to pair again":
      let f = Fake(token: "old", turnStatus: 401)
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()
      check f.saved == @[""]
      check "parear de novo" in f.written[^2]

    test "a refusal from the gateway is shown, not swallowed":
      let f = Fake(token: "tok", turnStatus: 429)
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()
      check "429" in f.written[^2] or "ocupad" in f.written[^2]

    test "a tool chunk without a name or id, or repeating the open tool, starts nothing":
      let f = Fake(token: "tok", turnStatus: 200, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"bash"}}]}}]}""",
        """data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"bash"}}]}}]}""",
        """data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"type":"function","function":{"name":""}}]}}]}"""])
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()
      var starts = 0
      for m in f.sent:
        if m{"params"}{"update"}{"sessionUpdate"}.getStr == "tool_call": inc starts
      check starts == 1

    test "a stream cut after it began is said as an interruption, not as unreachable":
      let f = Fake(token: "tok", turnStatus: 200, turnError: "line too long",
                   turnLines: @["""data: {"choices":[{"index":0,"delta":{"content":"Começo"}}]}"""])
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()
      check "interrompida" in f.written[^2] and "Não consegui falar" notin f.written[^2]

    test "an approval in the stream asks the editor; the choice goes back to the daemon (E10.4)":
      let f = Fake(token: "tok", turnStatus: 200, waitApproval: true, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"bash"}}]}}]}""",
        """data: {"choices":[{"index":0,"delta":{"donkey_approval":{"text":"Aprovar bash?","options":[{"label":"✅ Aprovar","callback":"approval:abc:allow"},{"label":"❌ Negar","callback":"approval:abc:deny"}]}}}]}"""])
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      var ask: JsonNode
      for m in f.sent:
        if m{"method"}.getStr == "session/request_permission": ask = m
      check not ask.isNil
      check ask["params"]["toolCall"]["toolCallId"] == %"c1"
      rt.feed($(%* {"jsonrpc": "2.0", "id": ask["id"],
                    "result": {"outcome": {"outcome": "selected", "optionId": "approval:abc:allow"}}}))
      waitFor rt.idle()
      check f.approved == @[("tok", "approval:abc:allow")]

    test "an approval the editor cancels is denied":
      let f = Fake(token: "tok", turnStatus: 200, waitApproval: true, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"donkey_approval":{"text":"Aprovar?","options":[{"label":"✅","callback":"approval:x:allow"},{"label":"❌","callback":"approval:x:deny"}]}}}]}"""])
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      var askId: JsonNode
      for m in f.sent:
        if m{"method"}.getStr == "session/request_permission": askId = m["id"]
      rt.feed($(%* {"jsonrpc": "2.0", "id": askId, "result": {"outcome": {"outcome": "cancelled"}}}))
      waitFor rt.idle()
      check f.approved == @[("tok", "approval:x:deny")]

    test "a permission the editor never answers ends with the prompt, sending nothing":
      let f = Fake(token: "tok", turnStatus: 200, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"donkey_approval":{"text":"Aprovar?","options":[{"label":"✅","callback":"approval:x:allow"},{"label":"❌","callback":"approval:x:deny"}]}}}]}"""])
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()          ## would hang if the question outlived the prompt
      check f.approved.len == 0
      check f.sent[^1]["result"]["stopReason"] == %"end_turn"

    test "a file request in the stream asks the editor; its content goes back (E10.5)":
      let f = Fake(token: "tok", turnStatus: 200, waitApproval: true, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"donkey_editor_request":{"id":"ef-1","method":"fs/read_text_file","params":{"path":"src/a.nim"}}}}]}"""])
      let rt = started(f, reads = true)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      var ask: JsonNode
      for m in f.sent:
        if m{"method"}.getStr == "fs/read_text_file": ask = m
      check not ask.isNil and ask["params"]["path"] == %"/proj/src/a.nim"
      rt.feed($(%* {"jsonrpc": "2.0", "id": ask["id"], "result": {"content": "echo 1"}}))
      waitFor rt.idle()
      check f.results == @[("tok", "ef-1", "echo 1", "")]

    test "an editor that does not read files: the daemon is told so, the editor is not asked":
      let f = Fake(token: "tok", turnStatus: 200, waitApproval: true, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"donkey_editor_request":{"id":"ef-1","method":"fs/read_text_file","params":{"path":"a"}}}}]}"""])
      let rt = started(f)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()
      for m in f.sent: check m{"method"}.getStr != "fs/read_text_file"
      check f.results.len == 1 and f.results[0][1] == "ef-1" and "does not" in f.results[0][3]

    test "a path outside the project is refused without asking the editor":
      let f = Fake(token: "tok", turnStatus: 200, waitApproval: true, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"donkey_editor_request":{"id":"ef-3","method":"fs/read_text_file","params":{"path":"../../etc/passwd"}}}}]}"""])
      let rt = started(f, reads = true)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      waitFor rt.idle()
      for m in f.sent: check m{"method"}.getStr != "fs/read_text_file"
      check f.results.len == 1 and "outside the project" in f.results[0][3]

    test "the editor's error goes back as the reason":
      let f = Fake(token: "tok", turnStatus: 200, waitApproval: true, turnLines: @[
        """data: {"choices":[{"index":0,"delta":{"donkey_editor_request":{"id":"ef-2","method":"fs/read_text_file","params":{"path":"/proj/missing.nim"}}}}]}"""])
      let rt = started(f, reads = true)
      rt.feed(Prompt % f.sent[1]["result"]["sessionId"].getStr)
      var askId: JsonNode
      for m in f.sent:
        if m{"method"}.getStr == "fs/read_text_file": askId = m["id"]
      rt.feed($(%* {"jsonrpc": "2.0", "id": askId, "error": {"code": -32002, "message": "Resource not found"}}))
      waitFor rt.idle()
      check f.results == @[("tok", "ef-2", "", "Resource not found")]

    test "session/cancel stops the turn and the prompt answers cancelled":
      let f = Fake(token: "tok", turnStatus: 200, hangTurn: true)
      let rt = started(f)
      let sid = f.sent[1]["result"]["sessionId"].getStr
      rt.feed(Prompt % sid)
      rt.feed("""{"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":"""" & sid & """"}}""")
      waitFor rt.idle()
      check f.sent[^1] == %* {"jsonrpc": "2.0", "id": 3, "result": {"stopReason": "cancelled"}}

    test "unknown methods, bad lines and unknown sessions get JSON-RPC errors":
      let f = Fake(token: "tok")
      let rt = started(f)
      rt.feed("""{"jsonrpc":"2.0","id":9,"method":"session/load","params":{}}""")
      check f.sent[^1]["error"]["code"] == %(-32601)
      rt.feed("garbage")
      check f.sent[^1]["error"]["code"] == %(-32700)
      rt.feed(Prompt % "nope")
      check f.sent[^1]["error"]["code"] == %(-32602)
      rt.feed("""{"jsonrpc":"2.0","method":"whatever/note","params":{}}""")   ## a notification: no answer
      check f.sent[^1]["error"]["code"] == %(-32602)

when isMainModule:
  runTests()
