## openai_stream_pure.nim — the OpenAI SSE dialect, read once.
##
## OpenRouter, OpenAI, DeepSeek and the compat family (Alibaba, Fireworks,
## NVIDIA, Mistral, …) all stream the same `data: {...}` lines. Each adapter
## used to read them itself, and only OpenRouter assembled tool calls: the
## others dropped them, so the tool loop could not stream through them. This
## accumulator reads a line at a time and returns the text to show; `finish`
## gives the whole response, tool calls included.
##
## A stream is trusted only when it is one: a body with no `data:` event (an
## HTML error page) and a stream cut before `[DONE]` are errors, never a
## short answer passed off as complete.
##
## `proc`, not `func`: parseJson is not `noSideEffect` (ADR-007 allows it).

import std/[json, strutils, tables]
import ../../core/pipeops
import ../message
import ./openai_pure

type
  OpenAiStream* = object
    text:         string
    reasoning:    string
    inputTokens:  int
    outputTokens: int
    tools:        Table[int, ToolCallRequest]
    order:        seq[int]   ## tool-call indexes in the order they first came
    sawEvent:     bool
    done*:        bool       ## `[DONE]` arrived: stop reading
    diagnostic:   string     ## the start of a non-SSE body, for the error

const DiagnosticBytes = 200

func initOpenAiStream*(): OpenAiStream =
  OpenAiStream(tools: initTable[int, ToolCallRequest]())

func intField(node: JsonNode; key: string): int =
  if node.isNil or node.kind != JObject: return 0
  let value = node.getOrDefault(key)
  if value.isNil or value.kind != JInt: 0 else: value.getInt

proc addToolDelta(acc: var OpenAiStream; delta: JsonNode) =
  let fn = delta{"function"}
  ## The dialect numbers each call (`index`). Some compat backends omit it:
  ## then a delta with a new `id` starts a call and one without continues
  ## the last, instead of every delta merging into call 0.
  let index =
    if delta.hasKey("index"):
      delta["index"].getInt(0)
    elif acc.order.len > 0 and (delta{"id"}.getStr("").len == 0 or
         delta{"id"}.getStr("") == acc.tools[acc.order[^1]].id):
      acc.order[^1]
    else:
      (if acc.order.len > 0: max(acc.order) + 1 else: 0)
  let name = if fn.isNil: "" else: fn{"name"}.getStr("")
  let arguments = if fn.isNil: "" else: fn{"arguments"}.getStr("")
  let id = delta{"id"}.getStr("")
  let signature = extraContentSignature(delta)
  if index notin acc.tools:
    acc.tools[index] = ToolCallRequest(id: id, name: name, inputJson: arguments,
                                       signature: signature)
    acc.order.add index
  else:
    var current = acc.tools[index]
    if id.len > 0: current.id = id
    if name.len > 0: current.name = name
    if signature.len > 0: current.signature = signature
    current.inputJson.add arguments
    acc.tools[index] = current

proc feed*(acc: var OpenAiStream; line: string): Result[string, string] =
  ## Reads one line; returns the text it adds ("" for none).
  let trimmed = line.strip()
  if trimmed.len == 0 or trimmed == "data:" or trimmed.startsWith(":"):
    return ok("")                       ## blank line, heartbeat, SSE comment
  if not trimmed.startsWith("data:"):
    if acc.diagnostic.len < DiagnosticBytes:
      acc.diagnostic.add(trimmed)
      acc.diagnostic.add(' ')
    return ok("")
  let payload = trimmed["data:".len .. ^1].strip()
  acc.sawEvent = true
  if payload == "[DONE]":
    acc.done = true
    return ok("")
  let j =
    try: parseJson(payload)
    except CatchableError as e: return err("malformed stream event: " & e.msg)
  let usage = j{"usage"}
  if intField(usage, "prompt_tokens") > 0:
    acc.inputTokens = intField(usage, "prompt_tokens")
  if intField(usage, "completion_tokens") > 0:
    acc.outputTokens = intField(usage, "completion_tokens")
  let choices = j{"choices"}
  if choices.isNil or choices.kind != JArray or choices.len == 0:
    return ok("")
  let delta = choices[0]{"delta"}
  if delta.isNil or delta.kind != JObject:
    return ok("")
  var reasoning = delta{"reasoning"}.getStr("")
  if reasoning.len == 0:
    reasoning = delta{"reasoning_content"}.getStr("")
  acc.reasoning.add reasoning
  let calls = delta{"tool_calls"}
  if not calls.isNil and calls.kind == JArray:
    for call in calls:
      acc.addToolDelta(call)
  let token = delta{"content"}.getStr("")
  acc.text.add token
  ok(token)

func finish*(acc: OpenAiStream; label: string): Result[CompletionResponse, string] =
  ## The whole response once the stream ended.
  if not acc.sawEvent:
    let detail = acc.diagnostic.strip
    return err(label & " returned a non-SSE response: " &
               (if detail.len > 0: detail else: "empty body"))
  if not acc.done:
    ## EOF without `[DONE]` is a cut connection: the text is partial.
    return err(label & " stream ended without [DONE] (truncated)")
  var toolCalls: seq[ToolCallRequest]
  for index in acc.order:
    var call = acc.tools[index]
    if call.name.len == 0:
      continue
    if call.inputJson.strip.len == 0:
      call.inputJson = "{}"
    toolCalls.add call
  ok CompletionResponse(text: acc.text, reasoning: acc.reasoning,
                        inputTokens: acc.inputTokens,
                        outputTokens: acc.outputTokens, toolCalls: toolCalls)
