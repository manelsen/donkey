## Pure OpenAI-shaped response builders for the agent-facing endpoint.
##
## These functions only serialise already-decided values: the runtime owns
## turn control, this module owns the wire contract (`chat.completion`,
## `chat.completion.chunk`, the `[DONE]` terminator and error redaction).

import std/json
import ../message
import ./redact_pure

func usageJson(inputTokens, outputTokens: int): JsonNode =
  %* {
    "prompt_tokens": inputTokens,
    "completion_tokens": outputTokens,
    "total_tokens": inputTokens + outputTokens,
  }

func buildAgentChatResponse*(text, model, id: string; created: int64;
                             inputTokens, outputTokens: int;
                             finishReason = "stop"): string =
  ## Non-streaming `chat.completion` for a finished agent turn.
  var message = newJObject()
  message["role"] = %"assistant"
  message["content"] = %text

  var choice = newJObject()
  choice["index"] = %0
  choice["message"] = message
  choice["finish_reason"] = %finishReason

  var root = newJObject()
  root["id"] = %id
  root["object"] = %"chat.completion"
  root["created"] = %created
  root["model"] = %model
  root["choices"] = %* [choice]
  root["usage"] = usageJson(inputTokens, outputTokens)
  $root

func buildAgentChunk*(id, model: string; created: int64;
                      role = ""; content = "";
                      toolCall = ToolCallNotice();
                      finishReason = "";
                      inputTokens = 0; outputTokens = 0): string =
  ## One SSE chunk. `delta.role` must only appear in the first chunk and
  ## `finish_reason` only in the last; callers pass those explicitly.
  ## Tool activity travels as `delta.tool_calls`, never as `content`.
  var delta = newJObject()
  if role.len > 0:
    delta["role"] = %role
  if content.len > 0:
    delta["content"] = %content
  if toolCall.phase.len > 0 or toolCall.name.len > 0:
    var functionObj = newJObject()
    functionObj["name"] = %toolCall.name
    var call = newJObject()
    call["index"] = %0
    call["type"] = %"function"
    if toolCall.id.len > 0:
      call["id"] = %toolCall.id
    call["function"] = functionObj
    var calls = newJArray()
    calls.add(call)
    delta["tool_calls"] = calls

  var choice = newJObject()
  choice["index"] = %0
  choice["delta"] = delta
  if finishReason.len > 0:
    choice["finish_reason"] = %finishReason

  var root = newJObject()
  root["id"] = %id
  root["object"] = %"chat.completion.chunk"
  root["created"] = %created
  root["model"] = %model
  root["choices"] = %* [choice]
  if finishReason.len > 0:
    root["usage"] = usageJson(inputTokens, outputTokens)
  $root

func buildApprovalChunk*(id, model: string; created: int64; text: string;
                         keyboard: seq[seq[(string, string)]]): string =
  ## An approval request in the stream (E10.4): a Donkey extension of the
  ## delta, `donkey_approval`, with the request's text and its buttons. An
  ## editor (`donkey acp`) asks the person; an OpenAI client ignores it.
  var options = newJArray()
  for row in keyboard:
    for (label, callback) in row:
      options.add(%* {"label": label, "callback": callback})
  var choice = newJObject()
  choice["index"] = %0
  choice["delta"] = %* {"donkey_approval": {"text": text, "options": options}}
  var root = newJObject()
  root["id"] = %id
  root["object"] = %"chat.completion.chunk"
  root["created"] = %created
  root["model"] = %model
  root["choices"] = %* [choice]
  $root

proc buildEditorRequestChunk*(id, model: string; created: int64; request: string): string =
  ## A request for the editor (E10.5), `donkey_editor_request`: the method and
  ## its params, for `donkey acp` to pass on (`fs/read_text_file`).
  var body = newJNull()
  try: body = parseJson(request)
  except CatchableError: body = %* {"error": "unreadable request"}
  var choice = newJObject()
  choice["index"] = %0
  choice["delta"] = %* {"donkey_editor_request": body}
  var root = newJObject()
  root["id"] = %id
  root["object"] = %"chat.completion.chunk"
  root["created"] = %created
  root["model"] = %model
  root["choices"] = %* [choice]
  $root

func buildAgentError*(message: string; errorType = "server_error";
                      code = ""): string =
  ## Redacted, OpenAI-shaped error body. The caller owns the HTTP status.
  var errorObj = newJObject()
  errorObj["message"] = %redactForClient(message)
  errorObj["type"] = %errorType
  if code.len > 0:
    errorObj["code"] = %code

  var root = newJObject()
  root["error"] = errorObj
  $root

func sseData*(payload: string): string =
  ## Frames one already-serialised chunk as a single SSE data event.
  "data: " & payload & "\n\n"

func sseDone*(): string =
  ## The OpenAI stream terminator, including its blank line.
  "data: [DONE]\n\n"

func deltaText*(text: string; kind: ReplyKind): string =
  ## The content a message may contribute to the SSE `content` delta.
  ## Only terminal answers are content; tool notices, debug and channel
  ## chatter are never sent as assistant content. Turn errors are diagnostics,
  ## so they are redacted before leaving the process.
  case kind
  of rkFinalAnswer: text
  of rkTurnError: redactForClient(text)
  of rkChannel, rkToolNotice, rkDebug: ""

func deltaText*(msg: OutboundMessage): string =
  deltaText(msg.text, msg.replyKind)
