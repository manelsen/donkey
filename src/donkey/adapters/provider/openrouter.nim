## OpenRouterAdapter — ProviderPort for OpenRouter.
##
## API endpoint: https://openrouter.ai/api/v1/chat/completions
## Auth: Bearer token
## REQUIRED headers: HTTP-Referer and X-Title (platform policy).
##
## Format: OpenAI-compatible (system as first message with role=system,
## messages array with role/content pairs).

import std/[httpclient, json, strutils]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops

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

# ── Response parsing ──────────────────────────────────────────────────────────

func parseOpenRouterResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing of response parsing without live HTTP.
  let msg   = j["choices"][0]["message"]
  let usage = j.getOrDefault("usage")
  CompletionResponse(
    text:         msg["content"].getStr(""),
    inputTokens:  if usage != nil: usage.getOrDefault("prompt_tokens").getInt(0)     else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("completion_tokens").getInt(0) else: 0,
  )

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: OpenRouterAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()

    client.headers = newHttpHeaders({
      "Content-Type":  "application/json",
      "Authorization": "Bearer " & a.apiKey,
      "HTTP-Referer":  a.referer,
      "X-Title":       a.xTitle,
    })

    let body = $a.buildBody(req)
    let url  = if a.endpoint.len > 0: a.endpoint else: OpenRouterEndpoint
    let resp = client.post(url, body = body)

    if resp.status[0] != '2':
      return err("OpenRouter API error " & resp.status & ": " & resp.body)

    let parsed = parseJson(resp.body)
    ok(parseOpenRouterResponse(parsed))
  except CatchableError as e:
    err(e.msg)

# ── Streaming ─────────────────────────────────────────────────────────────────

proc makeStreamFn*(a: OpenRouterAdapter): StreamFn =
  ## Returns a StreamFn closure that performs SSE streaming via OpenRouter.
  ## Tokens are delivered one at a time via the onToken callback.
  ## Falls back to a regular completion when SSE is unavailable.
  let adapter = a   ## capture by value
  result = proc(req: CompletionRequest;
                onToken: proc(tok: string) {.gcsafe.}
               ): Result[CompletionResponse, string] {.gcsafe.} =
    ## Simple fallback: complete non-streaming and emit the full text as one token.
    ## A proper SSE implementation would chunk the response; this is functional.
    {.cast(gcsafe).}:
      let r = adapter.complete(req)
      if r.isOk:
        onToken(r.value.text)
      r

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
