## OpenRouterAdapter — ProviderPort for OpenRouter.
##
## API endpoint: https://openrouter.ai/api/v1/chat/completions
## Auth: Bearer token
## REQUIRED headers: HTTP-Referer and X-Title (platform policy).
##
## Format: OpenAI-compatible (system as first message with role=system,
## messages array with role/content pairs).

import std/[httpclient, json, streams, strutils]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../../core/app_meta
import ../../core/json_helpers
import ../http/helpers
import ./sse

const
  OpenRouterEndpoint*    = "https://openrouter.ai/api/v1/chat/completions"
  OpenRouterDefaultModel = "openai/gpt-4o-mini"
  OpenRouterReferer*     = OpenRouterRefererUrl
  OpenRouterTitle*       = AppName

type
  OpenRouterAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## override for testing
    referer*:  string   ## HTTP-Referer header value
    xTitle*:   string   ## X-Title header value

  OpenRouterSseChunk* = object
    token*:        string
    done*:         bool
    inputTokens*:  int
    outputTokens*: int

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: OpenRouterAdapter): ProviderCaps =
  ProviderCaps(
    name:              "openrouter/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  0,
    requiresUserFirst: false,
  )

# ── JSON serialisation ────────────────────────────────────────────────────────

proc toJson(msg: ChatMessage): JsonNode =
  ## Serialises a ChatMessage to OpenAI-compatible JSON.
  if msg.role == "tool":
    ## Tool result message — must carry tool_call_id.
    return %* {"role": "tool",
               "tool_call_id": msg.toolCallId,
               "content":      msg.text}
  if msg.toolCalls.len > 0:
    ## Assistant message with pending tool calls.
    var calls = newJArray()
    for tc in msg.toolCalls:
      calls.add(%* {"id": tc.id, "type": "function",
                    "function": {"name": tc.name, "arguments": tc.inputJson}})
    return %* {"role": "assistant", "content": msg.text, "tool_calls": calls}
  if msg.imageUrl.len > 0:
    let content = %* [
      {"type": "text",      "text": msg.text},
      {"type": "image_url", "image_url": {"url": msg.imageUrl}},
    ]
    return %* {"role": msg.role, "content": content}
  %* {"role": msg.role, "content": msg.text}

proc buildBody*(a: OpenRouterAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing of JSON serialisation without live HTTP.
  var messages: seq[JsonNode] = @[]
  if req.system.len > 0:
    messages.add(%* {"role": "system", "content": req.system})
  for m in req.messages:
    messages.add(m.toJson())
  result = %* {"model": a.model, "messages": messages}
  if req.maxTokens > 0:
    result["max_tokens"] = %req.maxTokens
  if req.tools.len > 0:
    var toolsArr = newJArray()
    for td in req.tools:
      let schema = try: parseJson(td.schemaJson) except: newJObject()
      toolsArr.add(%* {"type": "function",
                        "function": {"name":        td.name,
                                     "description": td.description,
                                     "parameters":  schema}})
    result["tools"]       = toolsArr
    result["tool_choice"] = %"auto"

proc buildStreamBody*(a: OpenRouterAdapter; req: CompletionRequest): JsonNode =
  result = a.buildBody(req)
  result["stream"] = %true
  result["stream_options"] = %* {"include_usage": true}

# ── Response parsing ──────────────────────────────────────────────────────────

func parseOpenRouterResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing of response parsing without live HTTP.
  let msg   = j["choices"][0]["message"]
  let usage = j.getOrDefault("usage")
  var toolCalls: seq[ToolCallRequest] = @[]
  let tcs = msg.getOrDefault("tool_calls")
  if tcs != nil and tcs.kind == JArray:
    for tc in tcs:
      let fn = tc["function"]
      toolCalls.add ToolCallRequest(
        id:        tc["id"].getStr(""),
        name:      fn["name"].getStr(""),
        inputJson: fn["arguments"].getStr("{}"),
      )
  CompletionResponse(
    text:         msg.getOrDefault("content").getStr(""),
    inputTokens:  usage.jInt("prompt_tokens"),
    outputTokens: usage.jInt("completion_tokens"),
    toolCalls:    toolCalls,
  )

proc parseOpenRouterSseLine*(line: string): Result[OpenRouterSseChunk, string] =
  let trimmed = line.strip()
  if trimmed.len == 0 or not trimmed.startsWith("data:"):
    return ok(OpenRouterSseChunk())
  let payload = trimmed["data:".len .. ^1].strip()
  if payload == "[DONE]":
    return ok(OpenRouterSseChunk(done: true))
  let j = try: parseJson(payload) except CatchableError as e: return err(e.msg)
  let usage = j.getOrDefault("usage")
  let choices = j.getOrDefault("choices")
  var token = ""
  if choices != nil and choices.kind == JArray and choices.len > 0:
    let delta = choices[0].getOrDefault("delta")
    if delta != nil:
      token = delta.getOrDefault("content").getStr("")
  ok(OpenRouterSseChunk(
    token:        token,
    inputTokens:  usage.jInt("prompt_tokens"),
    outputTokens: usage.jInt("completion_tokens"),
  ))

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: OpenRouterAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  withHttpClient:
    client.headers = newHttpHeaders({
      "Content-Type":  "application/json",
      "Authorization": "Bearer " & a.apiKey,
      "HTTP-Referer":  a.referer,
      "X-Title":       a.xTitle,
    })
    let body = $a.buildBody(req)
    let url  = if a.endpoint.len > 0: a.endpoint else: OpenRouterEndpoint
    let resp = client.post(url, body = body)
    checkApiStatus(resp, "OpenRouter")
    resp.body |> parseJson |> parseOpenRouterResponse |> ok

# ── Streaming ─────────────────────────────────────────────────────────────────

proc makeStreamFn*(a: OpenRouterAdapter): StreamFn =
  ## Returns a StreamFn closure that performs SSE streaming via OpenRouter.
  ## Tokens are delivered one at a time via the onToken callback.
  ## Falls back to a regular completion when SSE is unavailable.
  let adapter = a   ## capture by value
  result = proc(req: CompletionRequest;
                onToken: proc(tok: string) {.gcsafe.}
               ): Result[CompletionResponse, string] {.gcsafe.} =
    withHttpClient:
      client.headers = newHttpHeaders({
        "Content-Type":  "application/json",
        "Authorization": "Bearer " & adapter.apiKey,
        "HTTP-Referer":  adapter.referer,
        "X-Title":       adapter.xTitle,
      })
      let body = $adapter.buildStreamBody(req)
      let url  = if adapter.endpoint.len > 0: adapter.endpoint else: OpenRouterEndpoint
      let resp = client.request(url, httpMethod = HttpPost, body = body)
      checkApiStatus(resp, "OpenRouter")
      sseAccumulate(resp.bodyStream, parseOpenRouterSseLine, onToken)
      ok(CompletionResponse(
        text:         accumulated,
        inputTokens:  inputTokens,
        outputTokens: outputTokens,
      ))

# ── Constructor ───────────────────────────────────────────────────────────────

proc newOpenRouterAdapter*(apiKey:   string;
                           model    = OpenRouterDefaultModel;
                           endpoint = "";
                           referer  = OpenRouterReferer;
                           xTitle   = OpenRouterTitle): OpenRouterAdapter =
  OpenRouterAdapter(
    apiKey:   apiKey,
    model:    model,
    endpoint: endpoint,
    referer:  referer,
    xTitle:   xTitle,
  )
