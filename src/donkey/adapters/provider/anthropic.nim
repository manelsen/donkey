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

import std/[httpclient, json, strutils]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops

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

proc toJson(msg: ChatMessage): JsonNode =
  ## Anthropic uses "user" and "assistant"; content is a plain string.
  %* {"role": msg.role, "content": msg.text}

proc buildBody*(a: AnthropicAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  ## system is top-level; messages array contains only user/assistant turns.
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

# ── Response parsing ──────────────────────────────────────────────────────────

func parseAnthropicResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing.
  let content = j["content"]
  var text = ""
  for blk in content:
    if blk.getOrDefault("type").getStr("") == "text":
      text = blk.getOrDefault("text").getStr("")
      break
  let usage = j.getOrDefault("usage")
  CompletionResponse(
    text:         text,
    inputTokens:  if usage != nil: usage.getOrDefault("input_tokens").getInt(0)  else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("output_tokens").getInt(0) else: 0,
  )

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: AnthropicAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()

    client.headers = newHttpHeaders({
      "Content-Type":    "application/json",
      "x-api-key":       a.apiKey,
      "anthropic-version": AnthropicVersion,
    })

    let body = $a.buildBody(req)
    let url  = if a.endpoint.len > 0: a.endpoint else: AnthropicEndpoint
    let resp = client.post(url, body = body)

    if resp.status[0] != '2':
      return err("Anthropic API error " & resp.status & ": " & resp.body)

    let parsed = parseJson(resp.body)
    ok(parseAnthropicResponse(parsed))
  except CatchableError as e:
    err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newAnthropicAdapter*(apiKey:   string;
                          model    = AnthropicDefaultModel;
                          endpoint = ""): AnthropicAdapter =
  AnthropicAdapter(apiKey: apiKey, model: model, endpoint: endpoint)
