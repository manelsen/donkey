## AnthropicAdapter — ProviderPort for Anthropic (Claude series).
##
## API endpoint: https://api.anthropic.com/v1/messages
## Auth: x-api-key header (NOT Bearer)
## Required header: anthropic-version: 2023-06-01
## Default model: claude-opus-4-6
##
## Quirks absorbed here:
##   - `system` is a top-level field, not a message in the array
##   - Messages: [{role: "user"|"assistant", content: "text"}]
##   - Tool use uses tool_use/tool_result content blocks (F3+ scope)
##   - Response: content[0].text
##   - max_tokens is REQUIRED by the API (no default)

import std/[json]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../http/std_http

const
  AnthropicEndpoint*     = "https://api.anthropic.com/v1/messages"
  AnthropicDefaultModel* = "claude-opus-4-6"
  AnthropicVersion*      = "2023-06-01"
  AnthropicDefaultMaxTok = 4096

type
  AnthropicAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## override for testing
    http*:     StdHttpAdapter

# ── Concept conformance ───────────────────────────────────────────────────────

func caps*(a: AnthropicAdapter): ProviderCaps =
  ProviderCaps(
    name:              "anthropic/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  200_000,
    requiresUserFirst: false,
  )

# ── JSON serialisation ────────────────────────────────────────────────────────

func toJson(msg: ChatMessage): JsonNode =
  ## Anthropic uses "user" and "assistant".
  ## Tool results: user role with tool_result content block.
  if msg.toolCallId.len > 0:
    %* {
      "role": "user",
      "content": [{"type": "tool_result", "tool_use_id": msg.toolCallId, "content": msg.text}]
    }
  else:
    %* {"role": msg.role, "content": msg.text}

proc buildBody*(a: AnthropicAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  ## system is top-level; messages array contains only user/assistant/tool turns.
  var messages: seq[JsonNode] = @[]
  for m in req.messages:
    messages.add(m.toJson())

  let maxTok = if req.maxTokens > 0: req.maxTokens else: AnthropicDefaultMaxTok

  result = %* {
    "model":      a.model,
    "max_tokens": maxTok,
    "messages":   messages
  }

  if req.system.len > 0:
    result["system"] = %req.system

  if req.tools.len > 0:
    var tools: seq[JsonNode] = @[]
    for td in req.tools:
      let schema = if td.schemaJson.len > 0:
                     try: parseJson(td.schemaJson) except: newJObject()
                   else: newJObject()
      tools.add(%* {"name": td.name, "description": td.description, "input_schema": schema})
    result["tools"] = %tools

# ── Response parsing ──────────────────────────────────────────────────────────

func parseAnthropicResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing.
  let content = j["content"]
  var text      = ""
  var toolCalls: seq[ToolCallRequest]

  for blk in content:
    let blkType = blk.getOrDefault("type").getStr("")
    case blkType
    of "text":
      text = blk.getOrDefault("text").getStr("")
    of "tool_use":
      let inputNode = blk.getOrDefault("input")
      toolCalls.add(ToolCallRequest(
        id:        blk["id"].getStr(""),
        name:      blk["name"].getStr(""),
        inputJson: if inputNode != nil: $inputNode else: "{}",
      ))
    else: discard

  let usage = j.getOrDefault("usage")
  CompletionResponse(
    text:         text,
    inputTokens:  if usage != nil: usage.getOrDefault("input_tokens").getInt(0)  else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("output_tokens").getInt(0) else: 0,
    toolCalls:    toolCalls,
  )

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: AnthropicAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  let headers = @[
    ("Content-Type",      "application/json"),
    ("x-api-key",         a.apiKey),
    ("anthropic-version", AnthropicVersion),
  ]
  let url  = if a.endpoint.len > 0: a.endpoint else: AnthropicEndpoint
  let resp = ? a.http.post(url, $a.buildBody(req), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Anthropic API error " & $resp.status & ": " & resp.body)
  try:
    let parsed = parseJson(resp.body)
    ok(parseAnthropicResponse(parsed))
  except CatchableError as e:
    err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newAnthropicAdapter*(apiKey:   string;
                          model    = AnthropicDefaultModel;
                          endpoint = ""): AnthropicAdapter =
  AnthropicAdapter(apiKey: apiKey, model: model, endpoint: endpoint,
                   http: newStdHttpAdapter())
