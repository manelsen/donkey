## ollama_pure.nim — pure Ollama wire-format helpers.
##
## Formats `CompletionRequest` into an Ollama /api/chat JSON request body,
## and parses an Ollama JSON response into a `CompletionResponse`.
##
## No I/O, no side effects. All functions are `func` unless they call `parseJson`.
##
## Topology (pipeops):
##   |>    — unary pure transform  (req |> buildOllamaRequest)
##   >>=   — Result chain          (body >>= parseOllamaResponse)
##
## Ollama API reference:
##   https://github.com/ollama/ollama/blob/main/docs/api.md

import std/json
import ../../core/pipeops
import ../../domain/message

# ── Internal pure helpers ─────────────────────────────────────────────────────

proc messageToOllama*(msg: ChatMessage): JsonNode =
  ## Serialises a ChatMessage to Ollama /api/chat message format.
  if msg.role == "tool":
    ## Ollama tool result: role=tool, content=result text.
    return %* {"role": "tool", "content": msg.text}
  if msg.toolCalls.len > 0:
    ## Assistant message with pending tool calls.
    ## Ollama tool_calls use JSON object arguments, not string.
    var calls = newJArray()
    for tc in msg.toolCalls:
      let args = try: parseJson(tc.inputJson) except: newJObject()
      calls.add(%* {"function": {"name": tc.name, "arguments": args}})
    return %* {"role": "assistant", "content": msg.text, "tool_calls": calls}
  if msg.imageUrl.len > 0:
    ## Ollama multimodal: images passed as base64 in images array.
    ## For URL-based images we embed the URL as content for now.
    return %* {"role": msg.role, "content": msg.text & "\n" & msg.imageUrl}
  %* {"role": msg.role, "content": msg.text}

# ── Public pure API ───────────────────────────────────────────────────────────

proc buildOllamaRequest*(model: string; req: CompletionRequest;
                         stream = false): JsonNode =
  ## Builds an Ollama /api/chat request body as JSON.
  ##
  ## Usage:  req |> buildOllamaRequest("llama3")
  var messages: seq[JsonNode] = @[]
  if req.system.len > 0:
    messages.add(%* {"role": "system", "content": req.system})
  for m in req.messages:
    messages.add m |> messageToOllama
  result = %* {"model": model, "messages": messages, "stream": stream}
  if req.maxTokens > 0:
    result["options"] = %* {"num_predict": req.maxTokens}
  if req.tools.len > 0:
    var toolsArr = newJArray()
    for td in req.tools:
      let schema = try: parseJson(td.schemaJson) except: newJObject()
      toolsArr.add(%* {"type": "function",
                        "function": {"name":        td.name,
                                     "description": td.description,
                                     "parameters":  schema}})
    result["tools"] = toolsArr

func parseOllamaResponse*(j: JsonNode): CompletionResponse =
  ## Parses an Ollama /api/chat response body into CompletionResponse.
  ##
  ## Usage:  responseJson >>= parseOllamaResponse
  let msg     = j.getOrDefault("message")
  let content = if msg != nil: msg.getOrDefault("content").getStr("") else: ""
  var toolCalls: seq[ToolCallRequest] = @[]
  if msg != nil:
    let tcs = msg.getOrDefault("tool_calls")
    if tcs != nil and tcs.kind == JArray:
      for i in 0 ..< tcs.len:
        let tc = tcs[i]
        let fn = tc.getOrDefault("function")
        if fn == nil: continue
        let argsNode = fn.getOrDefault("arguments")
        let inputJson =
          if argsNode == nil or argsNode.kind == JNull: "{}"
          elif argsNode.kind == JString: argsNode.getStr("{}")
          else: $argsNode
        toolCalls.add ToolCallRequest(
          id:        "ollama-" & $i,
          name:      fn.getOrDefault("name").getStr(""),
          inputJson: inputJson,
        )
  CompletionResponse(
    text:         content,
    inputTokens:  j.getOrDefault("prompt_eval_count").getInt(0),
    outputTokens: j.getOrDefault("eval_count").getInt(0),
    toolCalls:    toolCalls,
  )
