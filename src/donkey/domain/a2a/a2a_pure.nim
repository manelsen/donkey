## a2a_pure — the Agent2Agent protocol (v1.0, JSON-RPC binding), the
## server's pure core (E13.4).
##
## The card is published at `/.well-known/agent-card.json`; requests are
## JSON-RPC 2.0 (`SendMessage`, `GetTask`, `CancelTask`), authenticated by a
## bearer token a person gave the remote agent by pairing it. Reading is
## lenient (v1.0 parts are `{"text": …}`, v0.3 ones carried `"kind":"text"`);
## writing follows v1.0: `ROLE_AGENT`, `TASK_STATE_*`, `{"task": …}`.

import std/[json, strutils, uri]
import ../../core/pipeops

const
  A2aProtocolVersion* = "1.0"
  CardPath* = "/.well-known/agent-card.json"
  ErrParse* = -32700
  ErrInvalidRequest* = -32600
  ErrMethodNotFound* = -32601
  ErrInvalidParams* = -32602
  ErrInternal* = -32603
  ErrTaskNotFound* = -32001
  ErrTaskNotCancelable* = -32002

type
  CardInfo* = object
    name*, description*, url*, version*: string

  RpcError* = object
    code*: int
    message*: string

  RpcCall* = object
    id*: JsonNode        ## as sent (number, string or null)
    meth*: string
    params*: JsonNode

  IncomingMessage* = object
    text*, messageId*, contextId*, taskId*: string

  TaskState* = enum
    tsSubmitted = "TASK_STATE_SUBMITTED"
    tsWorking = "TASK_STATE_WORKING"
    tsCompleted = "TASK_STATE_COMPLETED"
    tsFailed = "TASK_STATE_FAILED"
    tsCanceled = "TASK_STATE_CANCELED"
    tsRejected = "TASK_STATE_REJECTED"

  A2aTask* = object
    id*, contextId*: string
    state*: TaskState
    reply*: string       ## the agent's answer, or why it failed
    timestamp*: string   ## ISO 8601, UTC

func isTerminal*(s: TaskState): bool =
  s in {tsCompleted, tsFailed, tsCanceled, tsRejected}

proc agentCard*(info: CardInfo): JsonNode =
  %*{
    "name": info.name,
    "description": info.description,
    "supportedInterfaces": [{"url": info.url, "protocolBinding": "JSONRPC",
                             "protocolVersion": A2aProtocolVersion}],
    "version": info.version,
    "capabilities": {"streaming": false, "pushNotifications": false, "extensions": []},
    "defaultInputModes": ["text/plain"],
    "defaultOutputModes": ["text/plain"],
    "skills": [{"id": "assistant", "name": "Assistant",
                "description": "Answers and carries out requests in writing, as the person who paired this agent.",
                "tags": ["assistant", "text"]}],
    "securitySchemes": {"bearer": {"httpAuthSecurityScheme": {"scheme": "Bearer"}}},
    "securityRequirements": [{"schemes": {"bearer": {"list": []}}}]
  }

proc parseRpc*(body: string): Result[RpcCall, RpcError] =
  let node =
    try: parseJson(body)
    except CatchableError: return err(RpcError(code: ErrParse, message: "Parse error"))
  if node.kind != JObject or node{"jsonrpc"}.getStr != "2.0" or
     node{"method"}.isNil or node{"method"}.kind != JString:
    return err(RpcError(code: ErrInvalidRequest, message: "Invalid Request"))
  ok(RpcCall(id: (if node.hasKey("id"): node["id"] else: newJNull()),
             meth: node["method"].getStr,
             params: (if node{"params"}.isNil: newJObject() else: node["params"])))

proc incomingMessage*(params: JsonNode): Result[IncomingMessage, string] =
  ## The text of `params.message`: its text parts, one per line.
  let msg = params{"message"}
  if msg.isNil or msg.kind != JObject:
    return err("params.message is required")
  var texts: seq[string]
  let parts = msg{"parts"}
  if not parts.isNil and parts.kind == JArray:
    for part in parts:
      if part.kind != JObject: continue
      let kind = part{"kind"}.getStr
      if part{"text"}.isNil or part["text"].kind != JString: continue
      if kind.len > 0 and kind != "text": continue
      texts.add part["text"].getStr
  if texts.len == 0:
    return err("the message has no text part")
  ok(IncomingMessage(text: texts.join("\n"), messageId: msg{"messageId"}.getStr,
                     contextId: msg{"contextId"}.getStr, taskId: msg{"taskId"}.getStr))

proc textMessage(role, text: string): JsonNode =
  %*{"role": role, "parts": [{"text": text}]}

proc taskJson*(t: A2aTask): JsonNode =
  var status = %*{"state": $t.state}
  if t.timestamp.len > 0: status["timestamp"] = %t.timestamp
  if t.reply.len > 0: status["message"] = textMessage("ROLE_AGENT", t.reply)
  result = %*{"id": t.id, "contextId": t.contextId, "status": status}
  if t.state == tsCompleted and t.reply.len > 0:
    result["artifacts"] = %*[{"artifactId": t.id & "-reply", "name": "reply",
                              "parts": [{"text": t.reply}]}]

proc rpcResult*(id, res: JsonNode): JsonNode =
  %*{"jsonrpc": "2.0", "id": id, "result": res}

proc rpcError*(id: JsonNode; e: RpcError): JsonNode =
  %*{"jsonrpc": "2.0", "id": id, "error": {"code": e.code, "message": e.message}}

func publicA2aUrl*(value: string): Result[string, string] =
  ## `A2A_PUBLIC_URL`: where other agents reach `/a2a`, as the card says.
  ## https, or http on loopback only (a token crosses it).
  var url = value.strip
  while url.endsWith("/"): url.setLen(url.len - 1)
  let parsed = parseUri(url)
  if parsed.username.len > 0 or parsed.password.len > 0:
    return err("A2A_PUBLIC_URL must not carry credentials (it is published in the card): " & value)
  ## The host compared whole: a prefix would let 127.0.0.1.evil.com pass.
  let loopback = parsed.hostname in ["127.0.0.1", "localhost", "::1"]
  if parsed.hostname.len == 0 or
     not (parsed.scheme == "https" or (parsed.scheme == "http" and loopback)):
    return err("A2A_PUBLIC_URL must be https (http only on loopback): " & value)
  if not url.endsWith("/a2a"):
    return err("A2A_PUBLIC_URL must end at /a2a, the JSON-RPC endpoint: " & value)
  ok(url)
