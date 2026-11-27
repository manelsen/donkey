## The Agent Client Protocol (ACP, v1) on the agent's side, pure (E10.1, E10.3):
## JSON-RPC 2.0, one message per line, over the editor's stdin and stdout.

import std/[json, strutils, unittest]
import donkey/core/pipeops
import donkey/domain/acp/acp_pure

proc runTests*() =
  suite "acp — messages":
    test "a line is a request, a notification or a response":
      let req = parseAcpLine("""{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}""").get
      check req.kind == amRequest and req.methodName == "initialize" and req.id == %1
      let note = parseAcpLine("""{"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":"s"}}""").get
      check note.kind == amNotification and note.params["sessionId"].getStr == "s"
      let resp = parseAcpLine("""{"jsonrpc":"2.0","id":"p1","result":{"outcome":{"outcome":"cancelled"}}}""").get
      check resp.kind == amResponse and resp.id == %"p1"
      check parseAcpLine("not json").isErr
      check parseAcpLine("""{"jsonrpc":"2.0"}""").isErr

    test "answers and errors are one line each":
      let ok1 = rpcResult(%7, %* {"sessionId": "s"})
      check '\n' notin ok1 and parseJson(ok1) == %* {"jsonrpc": "2.0", "id": 7, "result": {"sessionId": "s"}}
      check parseJson(rpcError(%7, -32601, "Method not found"))["error"] ==
        %* {"code": -32601, "message": "Method not found"}
      check parseJson(rpcError(newJNull(), -32700, "Parse error"))["id"].kind == JNull

  suite "acp — initialize and sessions":
    test "initialize: version 1, text and embedded files, no auth methods":
      let r = initializeResult(%* {"protocolVersion": 1}, "0.3.0")
      check r["protocolVersion"] == %1
      check r["agentCapabilities"]["loadSession"] == %false
      check r["agentCapabilities"]["promptCapabilities"] ==
        %* {"image": false, "audio": false, "embeddedContext": true}
      check r["agentInfo"]["name"] == %"donkey" and r["agentInfo"]["version"] == %"0.3.0"
      check r["authMethods"] == newJArray()
      check initializeResult(%* {"protocolVersion": 9}, "x")["protocolVersion"] == %1

    test "a prompt becomes the turn's text: text, embedded files and links":
      let params = %* {"sessionId": "s1", "prompt": [
        {"type": "text", "text": "revise isto"},
        {"type": "resource", "resource": {"uri": "file:///p/a.nim", "text": "echo 1", "mimeType": "text/x-nim"}},
        {"type": "resource_link", "uri": "file:///p/b.nim", "name": "b.nim"},
        {"type": "image", "data": "AAA", "mimeType": "image/png"}]}
      let p = parsePrompt(params).get
      check p.sessionId == "s1"
      check p.text.startsWith("revise isto")
      check "<file uri=\"file:///p/a.nim\">\necho 1\n</file>" in p.text
      check "[arquivo: b.nim (file:///p/b.nim)]" in p.text
      check "[imagem não lida]" in p.text   ## not advertised; named, never dropped silently
      check parsePrompt(%* {"sessionId": "s1", "prompt": []}).isErr
      check parsePrompt(%* {"prompt": [{"type": "text", "text": "x"}]}).isErr

  suite "acp — updates to the editor":
    test "a piece of the answer":
      check parseJson(messageChunk("s1", "Olá")) == %* {"jsonrpc": "2.0", "method": "session/update",
        "params": {"sessionId": "s1", "update": {"sessionUpdate": "agent_message_chunk",
          "content": {"type": "text", "text": "Olá"}}}}

    test "a tool starts and finishes":
      let started = parseJson(toolCallStarted("s1", "c1", "fs_read"))["params"]["update"]
      check started == %* {"sessionUpdate": "tool_call", "toolCallId": "c1", "title": "fs_read",
                           "kind": "read", "status": "in_progress"}
      check toolKind("bash") == "execute" and toolKind("edit_file") == "edit" and
            toolKind("web_search") == "search" and toolKind("fetch") == "fetch" and
            toolKind("rm") == "delete" and toolKind("mv") == "move" and toolKind("x") == "other"
      check parseJson(toolCallFinished("s1", "c1", ok = true))["params"]["update"] ==
        %* {"sessionUpdate": "tool_call_update", "toolCallId": "c1", "status": "completed"}
      check parseJson(toolCallFinished("s1", "c1", ok = false))["params"]["update"]["status"] == %"failed"

    test "the prompt's answer: why the turn stopped":
      check parseJson(promptResult(%3, "end_turn"))["result"] == %* {"stopReason": "end_turn"}

  suite "acp — the gateway's stream":
    test "an SSE data line becomes text, a tool, the end, or an error":
      check parseStreamLine("""data: {"choices":[{"index":0,"delta":{"content":"Oi"}}]}""") ==
        StreamEvent(kind: sekText, text: "Oi")
      check parseStreamLine("""data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","type":"function","function":{"name":"bash"}}]}}]}""") ==
        StreamEvent(kind: sekTool, toolId: "c1", toolName: "bash")
      check parseStreamLine("""data: {"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}""") ==
        StreamEvent(kind: sekFinish, finishReason: "length")
      check parseStreamLine("data: [DONE]").kind == sekDone
      check parseStreamLine("""data: {"error":{"message":"provider down","type":"provider_error"}}""") ==
        StreamEvent(kind: sekError, text: "provider down")
      check parseStreamLine(": ping").kind == sekNone
      check parseStreamLine("").kind == sekNone
      check parseStreamLine("""data: {"choices":[{"index":0,"delta":{"role":"assistant"}}]}""").kind == sekNone

    test "the stop reason from the finish reason":
      check stopReasonFor("stop") == "end_turn"
      check stopReasonFor("length") == "max_tokens"
      check stopReasonFor("") == "end_turn"

proc runPermissionTests*() =
  suite "acp — approvals in the editor (E10.4)":
    test "the stream's donkey_approval becomes an approval event":
      let e = parseStreamLine("""data: {"choices":[{"index":0,"delta":{"donkey_approval":{"text":"Aprovar bash?","options":[{"label":"✅ Aprovar","callback":"approval:abc:allow"},{"label":"❌ Negar","callback":"approval:abc:deny"}]}}}]}""")
      check e.kind == sekApproval and e.text == "Aprovar bash?"
      check e.options == @[("✅ Aprovar", "approval:abc:allow"), ("❌ Negar", "approval:abc:deny")]

    test "session/request_permission: the tool, and one option per button with its kind":
      let req = parseJson(permissionRequest(%"perm-1", "s1", "c1", "Aprovar bash?",
        @[("✅ Aprovar", "approval:abc:allow"), ("♾️ Sempre", "approval:abc:always"),
          ("❌ Negar", "approval:abc:deny")]))
      check req["method"] == %"session/request_permission" and req["id"] == %"perm-1"
      check req["params"]["sessionId"] == %"s1"
      check req["params"]["toolCall"] == %* {"toolCallId": "c1", "title": "Aprovar bash?"}
      check req["params"]["options"] == %* [
        {"optionId": "approval:abc:allow", "name": "✅ Aprovar", "kind": "allow_once"},
        {"optionId": "approval:abc:always", "name": "♾️ Sempre", "kind": "allow_always"},
        {"optionId": "approval:abc:deny", "name": "❌ Negar", "kind": "reject_once"}]

    test "the editor's answer: the chosen option; cancelled or anything else is a denial":
      let options = @[("✅", "approval:abc:allow"), ("❌", "approval:abc:deny")]
      check chosenCallback(%* {"outcome": {"outcome": "selected", "optionId": "approval:abc:allow"}}, options) ==
        "approval:abc:allow"
      check chosenCallback(%* {"outcome": {"outcome": "cancelled"}}, options) == "approval:abc:deny"
      check chosenCallback(%* {"outcome": {"outcome": "selected", "optionId": "approval:zzz:allow"}}, options) ==
        "approval:abc:deny"   ## not one we offered
      check chosenCallback(newJNull(), options) == "approval:abc:deny"

proc runEditorFileTests*() =
  suite "acp — reading a file in the editor (E10.5)":
    test "the stream's donkey_editor_request becomes an event with its id and params":
      let e = parseStreamLine("""data: {"choices":[{"index":0,"delta":{"donkey_editor_request":{"id":"ef-1","method":"fs/read_text_file","params":{"path":"src/a.nim","line":3,"limit":20}}}}]}""")
      check e.kind == sekEditorRequest and e.requestId == "ef-1"
      check e.requestMethod == "fs/read_text_file"
      check e.requestParams == %* {"path": "src/a.nim", "line": 3, "limit": 20}

    test "fs/read_text_file: an absolute path, resolved from the session's folder":
      let req = parseJson(fsReadRequest(%"fs-1", "s1", "/home/ana/proj", %* {"path": "src/a.nim", "line": 3, "limit": 20}))
      check req["method"] == %"fs/read_text_file"
      check req["params"] == %* {"sessionId": "s1", "path": "/home/ana/proj/src/a.nim", "line": 3, "limit": 20}
      let abs = parseJson(fsReadRequest(%"fs-2", "s1", "/home/ana/proj", %* {"path": "/etc/hosts"}))
      check abs["params"] == %* {"sessionId": "s1", "path": "/etc/hosts"}

    test "the editor offers reading only when it says so":
      check editorReadsFiles(%* {"protocolVersion": 1, "clientCapabilities": {"fs": {"readTextFile": true}}})
      check not editorReadsFiles(%* {"protocolVersion": 1, "clientCapabilities": {"fs": {"writeTextFile": true}}})
      check not editorReadsFiles(%* {"protocolVersion": 1})

when isMainModule:
  runTests()
  runPermissionTests()
  runEditorFileTests()
