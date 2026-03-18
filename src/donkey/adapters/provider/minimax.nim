## MiniMaxAdapter — ProviderPort for MiniMax AI (M2 model).
##
## API endpoint: https://api.minimax.io/v1/chat/completions
## Auth: Bearer token
## Default model: MiniMax-M2
##
## Format: OpenAI-compatible (role/content pairs, system as first message).
##
## Quirks absorbed here:
##   - None beyond standard OpenAI format — M2 is fully compatible

import std/[json]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../http/std_http

const
  MiniMaxEndpoint*     = "https://api.minimax.io/v1/chat/completions"
  MiniMaxDefaultModel* = "MiniMax-M2"

type
  MiniMaxAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## override for testing
    http*:     StdHttpAdapter

# ── Concept conformance ───────────────────────────────────────────────────────

func caps*(a: MiniMaxAdapter): ProviderCaps =
  ProviderCaps(
    name:              "minimax/" & a.model,
    streaming:         false,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  1_000_000,
    requiresUserFirst: false,
  )

# ── JSON serialisation ────────────────────────────────────────────────────────

func toJson(msg: ChatMessage): JsonNode =
  if msg.toolCallId.len > 0:
    ## Tool result: role=tool, tool_call_id, content (OpenAI-compatible)
    %* {"role": roleTool, "tool_call_id": msg.toolCallId, "content": msg.text}
  else:
    %* {"role": msg.role, "content": msg.text}

proc buildBody*(a: MiniMaxAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  var messages: seq[JsonNode] = @[]
  if req.system.len > 0:
    messages.add(%* {"role": "system", "content": req.system})
  for m in req.messages:
    messages.add(m.toJson())

  result = %* {"model": a.model, "messages": messages}

  if req.maxTokens > 0:
    result["max_tokens"] = %req.maxTokens

  if req.tools.len > 0:
    var tools: seq[JsonNode] = @[]
    for td in req.tools:
      let schema = if td.schemaJson.len > 0:
                     try: parseJson(td.schemaJson) except: newJObject()
                   else: newJObject()
      tools.add(%* {
        "type": "function",
        "function": {"name": td.name, "description": td.description, "parameters": schema}
      })
    result["tools"] = %tools

# ── Response parsing ──────────────────────────────────────────────────────────

func parseMiniMaxResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing.
  let msg   = j["choices"][0]["message"]
  let usage = j.getOrDefault("usage")

  var toolCalls: seq[ToolCallRequest]
  let rawCalls = msg.getOrDefault("tool_calls")
  if rawCalls != nil and rawCalls.kind == JArray:
    for tc in rawCalls:
      let fn = tc["function"]
      toolCalls.add(ToolCallRequest(
        id:        tc["id"].getStr(""),
        name:      fn["name"].getStr(""),
        inputJson: fn["arguments"].getStr(""),
      ))

  CompletionResponse(
    text:         msg.getOrDefault("content").getStr(""),
    inputTokens:  if usage != nil: usage.getOrDefault("prompt_tokens").getInt(0)     else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("completion_tokens").getInt(0) else: 0,
    toolCalls:    toolCalls,
  )

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: MiniMaxAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  let headers = @[
    ("Content-Type",  "application/json"),
    ("Authorization", "Bearer " & a.apiKey),
  ]
  let url  = if a.endpoint.len > 0: a.endpoint else: MiniMaxEndpoint
  let resp = ? a.http.post(url, $a.buildBody(req), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("MiniMax API error " & $resp.status & ": " & resp.body)
  try:
    let parsed = parseJson(resp.body)
    ok(parseMiniMaxResponse(parsed))
  except CatchableError as e:
    err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newMiniMaxAdapter*(apiKey:   string;
                        model    = MiniMaxDefaultModel;
                        endpoint = ""): MiniMaxAdapter =
  MiniMaxAdapter(apiKey: apiKey, model: model, endpoint: endpoint,
                 http: newStdHttpAdapter())
