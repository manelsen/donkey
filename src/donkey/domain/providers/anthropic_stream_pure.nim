## anthropic_stream_pure.nim — Anthropic's Messages stream, read into the
## same response a non-streamed call gives.
##
## The adapter used to keep only text deltas, so a streamed turn lost its
## tool_use blocks and the tool loop could not stream through Anthropic.
## Here: text blocks (joined by a newline, as `parseAnthropicResponse` joins
## them), tool_use blocks with their input assembled from
## `input_json_delta`, usage from message_start and message_delta. Thinking
## is not shown as text, matching the non-streamed parser.
##
## A stream is trusted only when it is one: an `error` event, a body with no
## `data:` event and a stream cut before `message_stop` are errors.
##
## `proc`, not `func`: parseJson is not `noSideEffect` (ADR-007 allows it).

import ./cache_usage_pure
import std/[json, strutils, tables]
import ../../core/pipeops
import ../message

type
  AnthropicStream* = object
    text:         string
    inputTokens:  int
    outputTokens: int
    cache:        CacheUsage
    tools:        Table[int, ToolCallRequest]
    order:        seq[int]
    textBlocks:   int        ## text blocks seen, to join them
    sawEvent:     bool
    done*:        bool       ## message_stop arrived: stop reading
    diagnostic:   string

const DiagnosticBytes = 200

func initAnthropicStream*(): AnthropicStream =
  AnthropicStream(tools: initTable[int, ToolCallRequest]())

func intField(node: JsonNode; key: string): int =
  if node.isNil or node.kind != JObject: return 0
  let value = node.getOrDefault(key)
  if value.isNil or value.kind != JInt: 0 else: value.getInt

proc feed*(acc: var AnthropicStream; line: string): Result[string, string] =
  ## Reads one line; returns the text it adds ("" for none).
  let trimmed = line.strip()
  if trimmed.len == 0 or trimmed.startsWith("event:") or trimmed.startsWith(":"):
    return ok("")
  if not trimmed.startsWith("data:"):
    if acc.diagnostic.len < DiagnosticBytes:
      acc.diagnostic.add(trimmed)
      acc.diagnostic.add(' ')
    return ok("")
  let payload = trimmed["data:".len .. ^1].strip()
  if payload.len == 0:
    return ok("")
  let j =
    try: parseJson(payload)
    except CatchableError as e: return err("malformed stream event: " & e.msg)
  acc.sawEvent = true
  let index = j{"index"}.getInt(0)
  case j{"type"}.getStr("")
  of "message_start":
    let usage = j{"message"}{"usage"}
    acc.cache = anthropicUsage(usage)
    acc.inputTokens = acc.cache.inputTokens
    acc.outputTokens = intField(usage, "output_tokens")
  of "message_delta":
    let usage = j{"usage"}
    if anthropicUsage(usage).inputTokens > 0:   ## any of the three counts
      acc.cache = anthropicUsage(usage)
      acc.inputTokens = acc.cache.inputTokens
    if intField(usage, "output_tokens") > 0:
      acc.outputTokens = intField(usage, "output_tokens")
  of "content_block_start":
    let blk = j{"content_block"}
    case blk{"type"}.getStr("")
    of "text":
      inc acc.textBlocks
      if acc.textBlocks > 1 and acc.text.len > 0:
        acc.text.add "\n"
        return ok("\n")
    of "tool_use":
      acc.tools[index] = ToolCallRequest(id: blk{"id"}.getStr(""),
                                         name: blk{"name"}.getStr(""))
      acc.order.add index
    else:
      discard
  of "content_block_delta":
    let delta = j{"delta"}
    case delta{"type"}.getStr("")
    of "text_delta":
      let token = delta{"text"}.getStr("")
      acc.text.add token
      return ok(token)
    of "input_json_delta":
      if index in acc.tools:
        acc.tools[index].inputJson.add delta{"partial_json"}.getStr("")
    else:
      discard
  of "message_stop":
    acc.done = true
  of "error":
    let message = j{"error"}{"message"}.getStr("")
    return err("Anthropic stream error: " &
               (if message.len > 0: message else: payload))
  else:
    discard
  ok("")

func finish*(acc: AnthropicStream; label: string): Result[CompletionResponse, string] =
  ## The whole response once the stream ended.
  if not acc.sawEvent:
    let detail = acc.diagnostic.strip
    return err(label & " returned a non-SSE response: " &
               (if detail.len > 0: detail else: "empty body"))
  if not acc.done:
    return err(label & " stream ended without message_stop (truncated)")
  var toolCalls: seq[ToolCallRequest]
  for index in acc.order:
    var call = acc.tools[index]
    if call.name.len == 0:
      continue
    if call.inputJson.strip.len == 0:
      call.inputJson = "{}"
    toolCalls.add call
  ok CompletionResponse(text: acc.text, inputTokens: acc.inputTokens,
                        outputTokens: acc.outputTokens, toolCalls: toolCalls,
                        cacheReadTokens: acc.cache.cacheRead,
                        cacheWriteTokens: acc.cache.cacheWrite)
