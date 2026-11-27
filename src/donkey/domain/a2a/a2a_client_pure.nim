## a2a_client_pure — A2A's client side, pure (E13.4).
##
## The agents Donkey may delegate to are listed by the operator in
## `[[a2a.agents]]` (name, the JSON-RPC URL, the variable holding the token
## the remote agent gave by pairing); nothing else can be called. Requests
## are v1.0 (`SendMessage`, `GetTask`) and, when the remote answers "method
## not found", v0.3 (`message/send`, `tasks/get`); answers are read in either
## shape.

import std/[json, strutils, uri]
import ../../core/pipeops

type
  A2aAgent* = object
    name*, url*, tokenEnv*, description*: string
    host*: string        ## the only host a call to it may reach

  RemoteOutcome* = object
    done*: bool          ## nothing more will come (a terminal state, a message,
                         ## or a question back: input or auth required)
    failed*: bool
    text*: string        ## the answer, the question, or why it failed
    taskId*: string      ## to ask again while it is not done

func validName(name: string): bool =
  if name.len == 0 or name.len > 40: return false
  for c in name:
    if c notin {'a'..'z', '0'..'9', '-', '_'}: return false
  true

proc parseA2aAgents*(section: JsonNode): Result[seq[A2aAgent], string] =
  ## `[a2a]` as JSON; `agents` is the list.
  var agents: seq[A2aAgent]
  let list = section{"agents"}
  if list.isNil: return ok(agents)
  if list.kind != JArray: return err("[[a2a.agents]] must be a list")
  for entry in list:
    let name = entry{"name"}.getStr.strip
    if not validName(name):
      return err("[[a2a.agents]]: name \"" & name & "\" must be lowercase letters, digits, - or _")
    for a in agents:
      if a.name == name: return err("[[a2a.agents]]: " & name & " appears twice")
    var url = entry{"url"}.getStr.strip
    while url.endsWith("/"): url.setLen(url.len - 1)
    let parsed = parseUri(url)
    let loopback = parsed.hostname in ["127.0.0.1", "localhost", "::1"]
    if not (parsed.scheme == "https" or (parsed.scheme == "http" and loopback)) or
       parsed.hostname.len == 0:
      return err("[[a2a.agents]] " & name & ": url must be https (http only on loopback)")
    let tokenEnv = entry{"token_env"}.getStr.strip
    if tokenEnv.len == 0:
      return err("[[a2a.agents]] " & name & ": token_env names the variable with its token")
    agents.add A2aAgent(name: name, url: url, tokenEnv: tokenEnv, host: parsed.hostname,
                        description: entry{"description"}.getStr.strip)
  ok(agents)

proc sendRequest*(text, messageId: string; legacy: bool): string =
  if legacy:
    $(%*{"jsonrpc": "2.0", "id": 1, "method": "message/send",
         "params": {"message": {"kind": "message", "messageId": messageId, "role": "user",
                                "parts": [{"kind": "text", "text": text}]}}})
  else:
    $(%*{"jsonrpc": "2.0", "id": 1, "method": "SendMessage",
         "params": {"message": {"messageId": messageId, "role": "ROLE_USER",
                                "parts": [{"text": text}]}}})

proc getTaskRequest*(taskId: string; legacy: bool): string =
  $(%*{"jsonrpc": "2.0", "id": 2, "method": (if legacy: "tasks/get" else: "GetTask"),
       "params": {"id": taskId}})

proc partsText(parts: JsonNode): string =
  var texts: seq[string]
  if not parts.isNil and parts.kind == JArray:
    for p in parts:
      if p.kind == JObject and not p{"text"}.isNil and p["text"].kind == JString and
         p{"kind"}.getStr in ["", "text"]:
        texts.add p["text"].getStr
  texts.join("\n")

proc isMethodNotFound*(body: string): bool =
  try: parseJson(body){"error"}{"code"}.getInt == -32601
  except CatchableError: false

proc parseOutcome*(body: string): Result[RemoteOutcome, string] =
  let node =
    try: parseJson(body)
    except CatchableError: return err("the agent's answer is not JSON")
  if node.kind != JObject: return err("the agent's answer is not a JSON-RPC response")
  if not node{"error"}.isNil:
    return err("the agent refused: " & node["error"]{"message"}.getStr("error") &
               " (" & $node["error"]{"code"}.getInt & ")")
  var res = node{"result"}
  if res.isNil or res.kind != JObject: return err("the agent's answer has no result")
  ## v1.0 wraps it ({"task"} / {"message"}); v0.3 says its kind.
  if not res{"message"}.isNil and res{"status"}.isNil:
    return ok(RemoteOutcome(done: true, text: partsText(res["message"]{"parts"})))
  if res{"kind"}.getStr == "message":
    return ok(RemoteOutcome(done: true, text: partsText(res{"parts"})))
  if not res{"task"}.isNil: res = res["task"]
  let state = res{"status"}{"state"}.getStr.toUpperAscii
    .replace("TASK_STATE_", "").replace("-", "_")
  var texts: seq[string]
  let artifacts = res{"artifacts"}
  if not artifacts.isNil and artifacts.kind == JArray:
    for a in artifacts:
      let t = partsText(a{"parts"})
      if t.len > 0: texts.add t
  let statusText = partsText(res{"status"}{"message"}{"parts"})
  if texts.len == 0 and statusText.len > 0: texts.add statusText
  let text = texts.join("\n")
  let taskId = res{"id"}.getStr
  case state
  of "COMPLETED":
    ok(RemoteOutcome(done: true, text: text, taskId: taskId))
  of "FAILED", "CANCELED", "REJECTED":
    ok(RemoteOutcome(done: true, failed: true, taskId: taskId,
                     text: "the task ended " & state.toLowerAscii &
                           (if text.len > 0: ": " & text else: "")))
  of "INPUT_REQUIRED", "AUTH_REQUIRED":
    ok(RemoteOutcome(done: true, taskId: taskId,
                     text: "the agent needs more " &
                           (if state == "AUTH_REQUIRED": "authorization" else: "input") &
                           (if text.len > 0: ": " & text else: "")))
  of "SUBMITTED", "WORKING":
    ok(RemoteOutcome(done: false, text: text, taskId: taskId))
  else:
    err("the agent's task is in an unknown state: " & state)

# ── The delegate_to_agent tool ────────────────────────────────────────────────

const DelegateToolName* = "delegate_to_agent"

proc delegateToolSchema*(agents: openArray[A2aAgent]): string =
  var names = newJArray()
  for a in agents: names.add %a.name
  $(%*{"type": "object",
       "properties": {
         "agent": {"type": "string", "enum": names,
                   "description": "Which agent to ask (only these are allowed)."},
         "task": {"type": "string",
                  "description": "What to ask it, complete and self-contained: it sees nothing else of this conversation."}},
       "required": ["agent", "task"]})

func delegateToolDescription*(agents: openArray[A2aAgent]): string =
  var lines: seq[string]
  for a in agents:
    lines.add "- " & a.name & (if a.description.len > 0: ": " & a.description else: "")
  "Delegates a task to another AI agent over A2A and returns its answer. " &
    "The person approves each call, seeing the whole task. Agents available:\n" &
    lines.join("\n")

func delegateSummary*(agent: A2aAgent; task: string): string =
  "Enviar ao agente " & agent.name & " (" & agent.url & "):\n\n" & task
