## OpenAI-compatible wire helpers for the gateway's /v1 endpoints.
##
## Parsing is deliberately narrow: text and image_url parts, no tools, no
## streaming. A client that asks for an unsupported shape gets a clear error
## instead of a half-working request.

import std/[json, strutils]
import ../../core/pipeops
import ../message

proc parseOpenAiMessage*(node: JsonNode; msg: var ChatMessage): Result[void, string] =
  if node.kind != JObject:
    return err("each message must be an object")
  let role = node.getOrDefault("role").getStr("").strip
  if role notin [roleSystem, roleUser, roleAssistant]:
    return err("unsupported message role: " & (if role.len > 0: role else: "(empty)"))
  msg.role = role
  let content = node.getOrDefault("content")
  if content.isNil:
    return err("message has no content")
  if content.kind == JString:
    msg.text = content.getStr()
  elif content.kind == JArray:
    for part in content:
      if part.kind != JObject:
        continue
      case part.getOrDefault("type").getStr("")
      of "text":
        let text = part.getOrDefault("text").getStr("")
        if msg.text.len > 0 and text.len > 0:
          msg.text.add("\n")
        msg.text.add(text)
      of "image_url":
        let image = part.getOrDefault("image_url")
        if not image.isNil and image.kind == JObject:
          let url = image.getOrDefault("url").getStr("")
          if url.len > 0 and msg.imageUrl.len == 0:
            msg.imageUrl = url
      else:
        discard
  else:
    return err("message content must be a string or an array of parts")
  ok()

proc parseOpenAiChatRequest*(body: string): Result[CompletionRequest, string] =
  ## `{"model","messages":[...],"max_tokens"}` -> CompletionRequest.
  let root = try:
    parseJson(body)
  except CatchableError:
    return err("invalid JSON")
  if root.kind != JObject:
    return err("expected a JSON object")
  let streamNode = root.getOrDefault("stream")
  if not streamNode.isNil and streamNode.kind == JBool and streamNode.getBool():
    return err("streaming is not supported by this endpoint")
  let tools = root.getOrDefault("tools")
  if not tools.isNil and tools.kind == JArray and tools.len > 0:
    return err("tools are not supported by this endpoint")

  let messages = root.getOrDefault("messages")
  if messages.isNil or messages.kind != JArray or messages.len == 0:
    return err("messages must be a non-empty array")

  var req = CompletionRequest()
  var history: ConversationHistory = @[]
  for item in messages:
    var msg = ChatMessage()
    let parsed = parseOpenAiMessage(item, msg)
    if parsed.isErr:
      return err(parsed.error)
    if msg.role == roleSystem:
      if req.system.len > 0:
        req.system.add("\n")
      req.system.add(msg.text)
    else:
      history.add(msg)
  if history.len == 0:
    return err("messages must contain a user or assistant turn")
  req.messages = history

  let maxTokens = root.getOrDefault("max_tokens")
  if not maxTokens.isNil and maxTokens.kind == JInt:
    req.maxTokens = maxTokens.getInt()
  let reasoningNode = root.getOrDefault("reasoning")
  req.reasoning = not reasoningNode.isNil and reasoningNode.kind == JBool and
                  reasoningNode.getBool()
  ok(req)

proc buildOpenAiChatResponse*(resp: CompletionResponse; model, id: string;
                              created: int64): string =
  ## Non-streaming `chat.completion` response.
  let total = resp.inputTokens + resp.outputTokens
  $(%* {
    "id": id,
    "object": "chat.completion",
    "created": created,
    "model": model,
    "choices": [{
      "index": 0,
      "message": {"role": "assistant", "content": resp.text},
      "finish_reason": "stop",
    }],
    "usage": {
      "prompt_tokens": resp.inputTokens,
      "completion_tokens": resp.outputTokens,
      "total_tokens": total,
    },
  })

proc buildOpenAiModels*(model: string; created: int64): string =
  $(%* {
    "object": "list",
    "data": [{
      "id": model,
      "object": "model",
      "created": created,
      "owned_by": "donkey",
    }],
  })
