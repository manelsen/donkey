## AnthropicAdapter — ProviderPort for Anthropic (Claude series).
##
## API endpoint: https://api.anthropic.com/v1/messages
## Compatible base URLs can override the host while keeping the /v1/messages
## contract, e.g. https://api.z.ai/api/anthropic
## Auth: x-api-key header (NOT Bearer)
## Required header: anthropic-version: 2023-06-01
## Default model: claude-opus-4-6
##
## Quirks absorbed here:
##   - `system` is a top-level field, not a message in the array
##   - Messages: [{role: "user"|"assistant", content: "...|[blocks]"}]
##   - Tool use uses tool_use/tool_result content blocks
##   - Tool results are sent back as role=user content blocks of type tool_result
##   - Response parsing must extract both text blocks and tool_use blocks
##   - max_tokens is REQUIRED by the API (no default)

import std/[httpclient, json, streams, strutils]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../../core/json_helpers
import ../http/helpers
import ./sse

const
  AnthropicEndpoint*     = "https://api.anthropic.com/v1/messages"
  AnthropicDefaultBaseUrl* = "https://api.anthropic.com"
  AnthropicDefaultModel* = "claude-opus-4-6"
  AnthropicVersion*      = "2023-06-01"
  AnthropicDefaultMaxTok = 4096

type
  AnthropicAdapter* = object
    apiKey*:   string
    model*:    string
    baseUrl*:  string   ## base URL override for compatible APIs
    endpoint*: string   ## override for testing

  AnthropicSseChunk* = object
    token*:        string
    done*:         bool
    inputTokens*:  int
    outputTokens*: int

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: AnthropicAdapter): ProviderCaps =
  ProviderCaps(
    name:              "anthropic/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  200_000,
    requiresUserFirst: false,
  )

# ── JSON serialisation ────────────────────────────────────────────────────────

proc textBlock(text: string): JsonNode =
  %* {"type": "text", "text": text}

proc toolUseBlock(tc: ToolCallRequest): JsonNode =
  let input = try: parseJson(tc.inputJson) except: newJObject()
  %* {
    "type": "tool_use",
    "id": tc.id,
    "name": tc.name,
    "input": input,
  }

proc toolResultBlock(msg: ChatMessage): JsonNode =
  %* {
    "type": "tool_result",
    "tool_use_id": msg.toolCallId,
    "content": msg.text,
  }

proc toJson(msg: ChatMessage): JsonNode =
  ## Anthropic tool results are represented as a user turn with tool_result blocks.
  if msg.role == "tool":
    return %* {
      "role": "user",
      "content": [toolResultBlock(msg)],
    }

  if msg.toolCalls.len > 0:
    var content = newJArray()
    if msg.text.len > 0:
      content.add(textBlock(msg.text))
    for tc in msg.toolCalls:
      content.add(toolUseBlock(tc))
    return %* {"role": msg.role, "content": content}

  %* {"role": msg.role, "content": msg.text}

proc buildBody*(a: AnthropicAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  ## system is top-level; messages array contains only user/assistant turns.
  var messages: seq[JsonNode] = @[]
  for m in req.messages:
    messages.add(m.toJson())

  let maxTok = if req.maxTokens > 0: req.maxTokens else: AnthropicDefaultMaxTok

  result = %* {
    "model": a.model,
    "max_tokens": maxTok,
    "messages": messages,
  }

  if req.reasoning:
    result["thinking"] = %* {"type": "enabled", "budget_tokens": 1024}
    if maxTok <= 1024:
      result["max_tokens"] = %2048

  if req.system.len > 0:
    result["system"] = %req.system
  if req.tools.len > 0:
    var toolsArr = newJArray()
    for td in req.tools:
      let schema = try: parseJson(td.schemaJson) except: newJObject()
      toolsArr.add(%* {
        "name": td.name,
        "description": td.description,
        "input_schema": schema,
      })
    result["tools"] = toolsArr

proc buildStreamBody*(a: AnthropicAdapter; req: CompletionRequest): JsonNode =
  result = a.buildBody(req)
  result["stream"] = %true

func messagesUrl*(a: AnthropicAdapter): string =
  if a.endpoint.len > 0:
    return a.endpoint
  let baseUrl =
    if a.baseUrl.len > 0: a.baseUrl.strip(chars = {'/'})
    else: AnthropicDefaultBaseUrl
  baseUrl & "/v1/messages"

# ── Response parsing ──────────────────────────────────────────────────────────

func parseAnthropicResponse*(j: JsonNode): Result[CompletionResponse, string] =
  ## Exported for unit testing.
  let content = j{"content"}
  if content.isNil or content.kind != JArray:
    let errorMsg = j{"error"}{"message"}.getStr("")
    if errorMsg.len > 0:
      return err("Anthropic error: " & errorMsg)
    return err("Invalid Anthropic response: missing 'content' array")

  var textParts: seq[string] = @[]
  var toolCalls: seq[ToolCallRequest] = @[]
  for blk in content:
    case blk.getOrDefault("type").getStr("")
    of "text":
      let text = blk.getOrDefault("text").getStr("")
      if text.len > 0:
        textParts.add(text)
    of "tool_use":
      let input = blk{"input"}
      let inputNode = if not input.isNil: input else: newJObject()
      toolCalls.add(ToolCallRequest(
        id: blk.getOrDefault("id").getStr(""),
        name: blk.getOrDefault("name").getStr(""),
        inputJson: $inputNode,
      ))
    else:
      discard
  let usage = j.getOrDefault("usage")
  ok CompletionResponse(
    text:         textParts.join("\n"),
    inputTokens:  usage.jInt("input_tokens"),
    outputTokens: usage.jInt("output_tokens"),
    toolCalls:    toolCalls,
  )

proc parseAnthropicSseLine*(line: string): Result[AnthropicSseChunk, string] =
  let trimmed = line.strip()
  if trimmed.len == 0 or not trimmed.startsWith("data:"):
    return ok(AnthropicSseChunk())
  let payload = trimmed["data:".len .. ^1].strip()
  if payload.len == 0:
    return ok(AnthropicSseChunk())
  let j = try: parseJson(payload) except CatchableError as e: return err(e.msg)
  let kind = j.getOrDefault("type").getStr("")
  case kind
  of "content_block_delta":
    let delta = j.getOrDefault("delta")
    ok(AnthropicSseChunk(token: if delta != nil: delta.getOrDefault("text").getStr("") else: ""))
  of "message_stop":
    ok(AnthropicSseChunk(done: true))
  of "message_start":
    let usage = j.getOrDefault("message").getOrDefault("usage")
    ok(AnthropicSseChunk(
      inputTokens:  usage.jInt("input_tokens"),
      outputTokens: usage.jInt("output_tokens"),
    ))
  of "message_delta":
    let usage = j.getOrDefault("usage")
    ok(AnthropicSseChunk(
      inputTokens:  usage.jInt("input_tokens"),
      outputTokens: usage.jInt("output_tokens"),
    ))
  else:
    ok(AnthropicSseChunk())

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: AnthropicAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  withHttpClient:
    client.headers = newHttpHeaders({
      "Content-Type":      "application/json",
      "x-api-key":         a.apiKey,
      "anthropic-version": AnthropicVersion,
    })
    let body = $a.buildBody(req)
    let url  = a.messagesUrl()
    let resp = client.post(url, body = body)
    checkApiStatus(resp, "Anthropic")
    resp.body |> parseJson |> parseAnthropicResponse

proc makeStreamFn*(a: AnthropicAdapter): StreamFn =
  let adapter = a
  result = proc(req: CompletionRequest;
                onToken: proc(tok: string) {.gcsafe.}
               ): Result[CompletionResponse, string] {.gcsafe.} =
    withHttpClient:
      client.headers = newHttpHeaders({
        "Content-Type":      "application/json",
        "x-api-key":         adapter.apiKey,
        "anthropic-version": AnthropicVersion,
      })
      let body = $adapter.buildStreamBody(req)
      let url  = adapter.messagesUrl()
      let resp = client.request(url, httpMethod = HttpPost, body = body)
      checkApiStatus(resp, "Anthropic")
      sseAccumulate(resp.bodyStream, parseAnthropicSseLine, onToken)
      ok(CompletionResponse(
        text:         accumulated,
        inputTokens:  inputTokens,
        outputTokens: outputTokens,
      ))

# ── Constructor ───────────────────────────────────────────────────────────────

proc newAnthropicAdapter*(apiKey:   string;
                          model    = AnthropicDefaultModel;
                          endpoint = "";
                          baseUrl  = ""): AnthropicAdapter =
  AnthropicAdapter(apiKey: apiKey, model: model, baseUrl: baseUrl, endpoint: endpoint)
