## OpenRouterAdapter — ProviderPort for OpenRouter.
##
## API endpoint: https://openrouter.ai/api/v1/chat/completions
## Auth: Bearer token
## Recommended headers: HTTP-Referer and X-Title (optional, not enforced).
##
## Format: OpenAI-compatible (system as first message with role=system,
## messages array with role/content pairs).

import std/[json, httpclient, streams, strutils]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../http/std_http

const
  OpenRouterEndpoint*    = "https://openrouter.ai/api/v1/chat/completions"
  OpenRouterDefaultModel = "openai/gpt-4o-mini"
  OpenRouterReferer*     = "https://github.com/donkey-ai/donkey"
  OpenRouterTitle*       = "Donkey"

type
  OpenRouterAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## override for testing
    referer*:  string   ## HTTP-Referer header value
    xTitle*:   string   ## X-Title header value
    http*:     StdHttpAdapter

# ── Concept conformance ───────────────────────────────────────────────────────

func caps*(a: OpenRouterAdapter): ProviderCaps =
  ProviderCaps(
    name:              "openrouter/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  0,
    requiresUserFirst: false,
  )

# ── JSON serialisation ────────────────────────────────────────────────────────

func toJson(msg: ChatMessage): JsonNode =
  if msg.toolCallId.len > 0:
    ## Tool result: role=tool, tool_call_id, content
    %* {"role": roleTool, "tool_call_id": msg.toolCallId, "content": msg.text}
  elif msg.imageUrl.len > 0:
    ## Vision turn: content is an array of text + image_url blocks.
    let content = %* [
      {"type": "text",      "text": msg.text},
      {"type": "image_url", "image_url": {"url": msg.imageUrl}}
    ]
    %* {"role": msg.role, "content": content}
  else:
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

func parseOpenRouterResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing of response parsing without live HTTP.
  let choice = j["choices"][0]
  let msg    = choice["message"]
  let usage  = j.getOrDefault("usage")

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

func httpHeaders(a: OpenRouterAdapter): seq[(string, string)] =
  @[("Content-Type",  "application/json"),
    ("Authorization", "Bearer " & a.apiKey),
    ("HTTP-Referer",  a.referer),
    ("X-Title",       a.xTitle)]

proc complete*(a: OpenRouterAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  let headers = a.httpHeaders()
  let url  = if a.endpoint.len > 0: a.endpoint else: OpenRouterEndpoint
  let resp = ? a.http.post(url, $a.buildBody(req), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("OpenRouter API error " & $resp.status & ": " & resp.body)
  try:
    let parsed = parseJson(resp.body)
    ok(parseOpenRouterResponse(parsed))
  except CatchableError as e:
    err(e.msg)

# ── SSE streaming ─────────────────────────────────────────────────────────────

proc stream*(a: OpenRouterAdapter; req: CompletionRequest;
             onToken: TokenCb): Result[CompletionResponse, string] =
  ## Sends a streaming request; calls onToken for each token as it arrives.
  ## Blocking — intended to run in a dedicated OS thread.
  let url = if a.endpoint.len > 0: a.endpoint else: OpenRouterEndpoint
  var body = a.buildBody(req)
  body["stream"] = %true
  try:
    let client = newHttpClient()
    defer: client.close()
    client.headers = newHttpHeaders(a.httpHeaders())
    let resp = client.request(url, httpMethod = HttpPost, body = $body)
    if resp.code.int < 200 or resp.code.int >= 300:
      return err("OpenRouter stream error " & $resp.code.int & ": " &
                 resp.body[0 .. min(200, resp.body.len - 1)])
    var fullText    = ""
    var inputTokens = 0
    var outTokens   = 0
    var line        = ""
    while resp.bodyStream.readLine(line):
      let l = line.strip()
      if not l.startsWith("data: "): continue
      let data = l[6 .. ^1].strip()
      if data == "[DONE]": break
      try:
        let j = parseJson(data)
        let choices = j.getOrDefault("choices")
        if choices != nil and choices.kind == JArray and choices.len > 0:
          let delta = choices[0].getOrDefault("delta")
          if delta != nil:
            let tok = delta.getOrDefault("content").getStr("")
            if tok.len > 0:
              fullText.add(tok)
              onToken(tok)
        let usage = j.getOrDefault("usage")
        if usage != nil:
          inputTokens = usage.getOrDefault("prompt_tokens").getInt(0)
          outTokens   = usage.getOrDefault("completion_tokens").getInt(0)
      except: discard
    ok(CompletionResponse(text: fullText,
                          inputTokens: inputTokens, outputTokens: outTokens))
  except CatchableError as e:
    err(e.msg)

proc makeStreamFn*(a: OpenRouterAdapter): StreamFn =
  ## Returns a StreamFn closure capturing this adapter.
  ## `snap` is an explicit value copy — safe to pass to OS threads.
  let snap = a
  proc fn(req: CompletionRequest; onToken: TokenCb): Result[CompletionResponse, string] =
    snap.stream(req, onToken)
  fn

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
    http:     newStdHttpAdapter(),
  )
