## Pure parser for the agent-facing `POST /v1/chat/completions` request.
##
## The endpoint runs the same turn as a channel, so the client only chooses
## the user and the current text. History, tools and generation knobs belong
## to the agent/session: unsupported shapes are refused with a structured 400
## instead of being silently half-honoured.

import std/[json, strutils]
import results
import ../../core/types
import ../message
import ./identity_pure

type
  AgentChatError* = object
    ## A ready-to-send 400 response: status line value, OpenAI error fields and
    ## the serialised body (so adapters never re-format an error).
    status*:    int
    errorType*: string
    code*:      string
    param*:     string
    message*:   string
    body*:      string

  AgentChatRequest* = object
    userId*: UserId  ## sanitised identity (`api:<name>`)
    text*:   string  ## only the last user message; the session owns history
    stream*: bool
    model*:  string

func agentChatError(status: int; code, message: string;
                    param = ""): AgentChatError =
  var errorObj = %* {
    "message": message,
    "type": "invalid_request_error",
    "code": code,
  }
  if param.len > 0:
    errorObj["param"] = %param
  AgentChatError(
    status:    status,
    errorType: "invalid_request_error",
    code:      code,
    param:     param,
    message:   message,
    body:      $(%* {"error": errorObj}),
  )

func invalidRequest(message: string; param = ""): AgentChatError =
  agentChatError(400, "invalid_request", message, param)

func unsupportedParameter(param, message: string): AgentChatError =
  agentChatError(400, "unsupported_parameter", message, param)

func present(node: JsonNode): bool =
  not node.isNil and node.kind != JNull

proc extractContent(node: JsonNode; text: var string): Result[void, AgentChatError] =
  ## Text-only extraction: extra parts (images) are ignored, not rejected.
  if node.isNil:
    return err(invalidRequest("message has no content", "messages"))
  case node.kind
  of JString:
    text = node.getStr()
  of JArray:
    for part in node:
      if part.kind != JObject:
        continue
      if part.getOrDefault("type").getStr("") == "text":
        let value = part.getOrDefault("text").getStr("")
        if text.len > 0 and value.len > 0:
          text.add("\n")
        text.add(value)
  else:
    return err(invalidRequest(
      "message content must be a string or an array of parts", "messages"))
  ok()

proc parseAgentChatRequest*(body: string): Result[AgentChatRequest, AgentChatError] =
  ## Parses and validates the body. `user` is required and must satisfy
  ## `apiUserId`; the last message must be a user message. `temperature`,
  ## `top_p` and `max_tokens` are deliberately ignored.
  let root = try:
    parseJson(body)
  except CatchableError:
    return err(invalidRequest("invalid JSON"))
  if root.kind != JObject:
    return err(invalidRequest("expected a JSON object"))

  var stream = false
  let streamNode = root.getOrDefault("stream")
  if present(streamNode):
    if streamNode.kind != JBool:
      return err(unsupportedParameter("stream", "stream must be a boolean"))
    stream = streamNode.getBool()

  let tools = root.getOrDefault("tools")
  if present(tools):
    if tools.kind != JArray:
      return err(unsupportedParameter("tools", "tools must be an array"))
    if tools.len > 0:
      return err(unsupportedParameter(
        "tools", "client tools are not supported by this endpoint"))

  for param in ["tool_choice", "response_format"]:
    if present(root.getOrDefault(param)):
      return err(unsupportedParameter(
        param, param & " is not supported by this endpoint"))

  let nNode = root.getOrDefault("n")
  if present(nNode):
    let tooMany =
      case nNode.kind
      of JInt: nNode.getInt() != 1
      of JFloat: nNode.getFloat() != 1.0
      of JString: true  # a string is never a valid `n`
      else: true        # bool/array/object/null is never a valid `n`
    if tooMany:
      return err(unsupportedParameter("n", "only one choice is supported"))

  let userNode = root.getOrDefault("user")
  if userNode.isNil or userNode.kind != JString or userNode.getStr().len == 0:
    return err(agentChatError(
      400, "missing_required_parameter", "user is required", "user"))
  let userId = apiUserId(userNode.getStr())
  if userId.isErr:
    return err(invalidRequest("invalid user: " & userId.error, "user"))

  let messages = root.getOrDefault("messages")
  if messages.isNil or messages.kind != JArray or messages.len == 0:
    return err(invalidRequest(
      "messages must be a non-empty array", "messages"))

  var lastRole = ""
  for item in messages:
    if item.kind != JObject:
      return err(invalidRequest("each message must be an object", "messages"))
    let roleNode = item.getOrDefault("role")
    let role = if roleNode.isNil: "" else: roleNode.getStr("")
    case role
    of roleUser, roleAssistant:
      discard
    of roleSystem, "developer":
      return err(unsupportedParameter(
        "messages", "system/developer messages are not supported"))
    else:
      return err(invalidRequest(
        "unsupported message role: " &
          (if role.len > 0: role else: "(empty)"), "messages"))
    lastRole = role

  if lastRole != roleUser:
    return err(invalidRequest("the last message must be from the user",
                              "messages"))

  var text = ""
  let parsed = extractContent(
    messages[messages.len - 1].getOrDefault("content"), text)
  if parsed.isErr:
    return err(parsed.error)
  if text.strip.len == 0:
    return err(invalidRequest("message content must not be empty", "messages"))

  let modelNode = root.getOrDefault("model")
  let model =
    if not modelNode.isNil and modelNode.kind == JString: modelNode.getStr()
    else: ""

  ok(AgentChatRequest(
    userId: userId.get(),
    text:   text,
    stream: stream,
    model:  model,
  ))
