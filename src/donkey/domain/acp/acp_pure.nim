## acp_pure — the Agent Client Protocol (ACP v1) on the agent's side (E10.1,
## E10.3): JSON-RPC 2.0, one message per line on the editor's stdin and
## stdout (agentclientprotocol.com/protocol). Parsing what the editor sends,
## building what Donkey answers, and reading the gateway's stream (the OpenAI
## chunks of /v1/acp/chat/completions) into events.

import std/[json, strutils]
import ../../core/pipeops

const
  AcpProtocolVersion* = 1
  RpcParseError* = -32700
  RpcInvalidRequest* = -32600
  RpcMethodNotFound* = -32601
  RpcInvalidParams* = -32602
  RpcInternalError* = -32603

type
  AcpMessageKind* = enum
    amRequest, amNotification, amResponse

  AcpMessage* = object
    kind*: AcpMessageKind
    id*: JsonNode            ## requests and responses
    methodName*: string      ## requests and notifications
    params*: JsonNode
    result*: JsonNode        ## responses
    error*: JsonNode

  AcpPrompt* = object
    sessionId*, text*: string

  StreamEventKind* = enum
    sekNone, sekText, sekTool, sekFinish, sekDone, sekError, sekApproval, sekEditorRequest

  StreamEvent* = object
    kind*: StreamEventKind
    text*: string
    toolId*, toolName*: string
    finishReason*: string
    options*: seq[(string, string)]   ## an approval's buttons: (label, callback)
    requestId*, requestMethod*: string  ## a request for the editor (E10.5)
    requestParams*: JsonNode

proc parseAcpLine*(line: string): Result[AcpMessage, string] =
  try:
    let j = parseJson(line)
    if j.kind != JObject: return err("not a JSON-RPC object")
    let hasId = j.hasKey("id")
    if j.hasKey("method"):
      let params = if j.hasKey("params"): j["params"] else: newJObject()
      if hasId:
        return ok(AcpMessage(kind: amRequest, id: j["id"], methodName: j["method"].getStr,
                             params: params))
      return ok(AcpMessage(kind: amNotification, methodName: j["method"].getStr, params: params))
    if hasId and (j.hasKey("result") or j.hasKey("error")):
      return ok(AcpMessage(kind: amResponse, id: j["id"], result: j{"result"}, error: j{"error"}))
    err("neither a request, a notification nor a response")
  except CatchableError as e:
    err("invalid JSON: " & e.msg)

proc rpcResult*(id, value: JsonNode): string =
  $(%* {"jsonrpc": "2.0", "id": id, "result": value})

proc rpcError*(id: JsonNode; code: int; message: string): string =
  $(%* {"jsonrpc": "2.0", "id": (if id.isNil: newJNull() else: id),
        "error": {"code": code, "message": message}})

proc rpcRequest*(id: JsonNode; methodName: string; params: JsonNode): string =
  $(%* {"jsonrpc": "2.0", "id": id, "method": methodName, "params": params})

proc notification(methodName: string; params: JsonNode): string =
  $(%* {"jsonrpc": "2.0", "method": methodName, "params": params})

proc initializeResult*(params: JsonNode; version: string): JsonNode =
  ## Only v1 exists for Donkey: any other request gets v1 back, and the
  ## editor decides. Files embedded in a prompt are read; images and audio
  ## are not offered.
  discard params
  %* {"protocolVersion": AcpProtocolVersion,
      "agentCapabilities": {"loadSession": false,
        "promptCapabilities": {"image": false, "audio": false, "embeddedContext": true}},
      "agentInfo": {"name": "donkey", "title": "Donkey", "version": version},
      "authMethods": newJArray()}

proc parsePrompt*(params: JsonNode): Result[AcpPrompt, string] =
  ## The turn's text: text blocks as they are, an embedded file wrapped in
  ## `<file uri=…>`, a link named; anything else named as unread, never
  ## dropped silently.
  if params.isNil or params.kind != JObject: return err("params must be an object")
  let sessionId = params{"sessionId"}.getStr
  if sessionId.len == 0: return err("missing sessionId")
  let blocks = params{"prompt"}
  if blocks.isNil or blocks.kind != JArray or blocks.len == 0:
    return err("prompt must be a non-empty array")
  var parts: seq[string]
  for b in blocks:
    case b{"type"}.getStr
    of "text":
      parts.add b{"text"}.getStr
    of "resource":
      let r = b{"resource"}
      if r{"text"}.getStr.len > 0 or r.hasKey("text"):
        parts.add "<file uri=\"" & r{"uri"}.getStr & "\">\n" & r{"text"}.getStr & "\n</file>"
      else:
        parts.add "[arquivo binário não lido: " & r{"uri"}.getStr & "]"
    of "resource_link":
      parts.add "[arquivo: " & b{"name"}.getStr & " (" & b{"uri"}.getStr & ")]"
    of "image":
      parts.add "[imagem não lida]"
    of "audio":
      parts.add "[áudio não lido]"
    else:
      parts.add "[conteúdo não lido: " & b{"type"}.getStr & "]"
  ok(AcpPrompt(sessionId: sessionId, text: parts.join("\n\n")))

proc update(sessionId: string; body: JsonNode): string =
  notification("session/update", %* {"sessionId": sessionId, "update": body})

proc messageChunk*(sessionId, text: string): string =
  update(sessionId, %* {"sessionUpdate": "agent_message_chunk",
                        "content": {"type": "text", "text": text}})

func toolKind*(name: string): string =
  ## ACP's tool kinds, for the editor's icon.
  case name
  of "bash", "execute_code", "run_code": "execute"
  of "edit_file", "fs_write", "text_replace", "write_file": "edit"
  of "rm": "delete"
  of "mv": "move"
  of "web_search", "search_conversations", "memory_search", "grep": "search"
  of "fetch", "http_fetch", "browser": "fetch"
  of "fs_read", "text_read", "read_file", "inspect_image", "git_inspect": "read"
  else: "other"

proc toolCallStarted*(sessionId, id, name: string): string =
  update(sessionId, %* {"sessionUpdate": "tool_call", "toolCallId": id, "title": name,
                        "kind": toolKind(name), "status": "in_progress"})

proc toolCallFinished*(sessionId, id: string; ok: bool): string =
  update(sessionId, %* {"sessionUpdate": "tool_call_update", "toolCallId": id,
                        "status": (if ok: "completed" else: "failed")})

proc promptResult*(id: JsonNode; stopReason: string): string =
  rpcResult(id, %* {"stopReason": stopReason})

func stopReasonFor*(finishReason: string): string =
  case finishReason
  of "length": "max_tokens"
  else: "end_turn"

proc parseStreamLine*(line: string): StreamEvent =
  ## One line of the gateway's SSE stream.
  if not line.startsWith("data:"): return StreamEvent(kind: sekNone)
  let payload = line["data:".len .. ^1].strip
  if payload == "[DONE]": return StreamEvent(kind: sekDone)
  try:
    let j = parseJson(payload)
    if j.hasKey("error"):
      return StreamEvent(kind: sekError, text: j["error"]{"message"}.getStr("error"))
    let choice = j{"choices"}{0}
    if choice.isNil: return StreamEvent(kind: sekNone)
    let delta = choice{"delta"}
    let editorRequest = delta{"donkey_editor_request"}
    if not editorRequest.isNil:
      return StreamEvent(kind: sekEditorRequest, requestId: editorRequest{"id"}.getStr,
                         requestMethod: editorRequest{"method"}.getStr,
                         requestParams: (let p = editorRequest{"params"};
                                         if p.isNil: newJObject() else: p))
    let approval = delta{"donkey_approval"}
    if not approval.isNil:
      var options: seq[(string, string)]
      for o in approval{"options"}.getElems:
        options.add((o{"label"}.getStr, o{"callback"}.getStr))
      return StreamEvent(kind: sekApproval, text: approval{"text"}.getStr, options: options)
    let calls = delta{"tool_calls"}
    if not calls.isNil and calls.len > 0:
      let call = calls[0]
      return StreamEvent(kind: sekTool, toolId: call{"id"}.getStr,
                         toolName: call{"function"}{"name"}.getStr)
    let content = delta{"content"}.getStr
    if content.len > 0: return StreamEvent(kind: sekText, text: content)
    let finish = choice{"finish_reason"}.getStr
    if finish.len > 0: return StreamEvent(kind: sekFinish, finishReason: finish)
    StreamEvent(kind: sekNone)
  except CatchableError:
    StreamEvent(kind: sekNone)

func permissionKind(callback: string): string =
  if callback.endsWith(":always"): "allow_always"
  elif callback.endsWith(":allow"): "allow_once"
  else: "reject_once"

proc permissionRequest*(id: JsonNode; sessionId, toolCallId, title: string;
                        options: seq[(string, string)]): string =
  ## E10.4: Donkey asks the editor (agent → client request); each of the
  ## approval's buttons is an option, its callback the option's id.
  var opts = newJArray()
  for (label, callback) in options:
    opts.add(%* {"optionId": callback, "name": label, "kind": permissionKind(callback)})
  rpcRequest(id, "session/request_permission", %* {"sessionId": sessionId,
    "toolCall": {"toolCallId": toolCallId, "title": title}, "options": opts})

func denial(options: seq[(string, string)]): string =
  for (_, callback) in options:
    if permissionKind(callback) == "reject_once": return callback
  ""

proc chosenCallback*(answer: JsonNode; options: seq[(string, string)]): string =
  ## The option the person chose. Cancelled, malformed or an option we did
  ## not offer is a denial: never an approval by accident.
  if answer.isNil or answer.kind != JObject: return denial(options)
  let outcome = answer{"outcome"}
  if outcome.isNil or outcome{"outcome"}.getStr != "selected": return denial(options)
  let chosen = outcome{"optionId"}.getStr
  for (_, callback) in options:
    if callback == chosen: return chosen
  denial(options)

proc editorReadsFiles*(initializeParams: JsonNode): bool =
  ## E10.5: the editor said, in `initialize`, that Donkey may ask it to read
  ## a text file.
  if initializeParams.isNil: return false
  initializeParams{"clientCapabilities"}{"fs"}{"readTextFile"}.getBool(false)

proc fsReadRequest*(id: JsonNode; sessionId, cwd: string; params: JsonNode): string =
  ## `fs/read_text_file` (agent → client). ACP wants an absolute path: a
  ## relative one is resolved from the session's folder.
  var path = params{"path"}.getStr
  if not path.startsWith("/") and cwd.len > 0:
    path = cwd.strip(leading = false, chars = {'/'}) & "/" & path
  var p = %* {"sessionId": sessionId, "path": path}
  if params{"line"}.getInt > 0: p["line"] = %params{"line"}.getInt
  if params{"limit"}.getInt > 0: p["limit"] = %params{"limit"}.getInt
  rpcRequest(id, "fs/read_text_file", p)
