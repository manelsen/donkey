## ZhipuAdapter — ProviderPort for Zhipu AI (GLM series).
##
## API endpoint: https://api.z.ai/api/coding/paas/v4/chat/completions
## Auth: Bearer token via Authorization header
## Model: glm-4-flash (default) or configurable
##
## GLM quirks absorbed here:
##   - Native tools declared in caps(): web_search, code_interpreter
##   - Tool format differs from OpenAI: uses "type":"function" wrapper same as OAI
##     but native tools are passed as {"type":"web_search"} etc.
##   - No streaming in F1 (streaming added in F4)

import std/[json, strutils]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../http/std_http

const
  ZhipuEndpoint* = "https://api.z.ai/api/coding/paas/v4/chat/completions"
  ZhipuDefaultModel* = "glm-4.7"

type
  ZhipuAdapter* = object
    apiKey*:   string
    model*:    string   ## defaults to ZhipuDefaultModel
    endpoint*: string   ## override for testing
    http*:     StdHttpAdapter

# ── Concept conformance ───────────────────────────────────────────────────────

func caps*(a: ZhipuAdapter): ProviderCaps =
  ProviderCaps(
    name:             "zhipu/" & a.model,
    streaming:        false,
    toolCalling:      true,
    nativeTools:      @["web_search", "code_interpreter"],
    maxContextTokens: 128_000,
    requiresUserFirst: false,
  )

# ── JSON serialisation ────────────────────────────────────────────────────────

func toJson(msg: ChatMessage): JsonNode =
  %* {"role": msg.role, "content": msg.text}

func buildBody*(a: ZhipuAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing of JSON serialisation without live HTTP.
  var messages: seq[JsonNode] = @[]
  if req.system.len > 0:
    messages.add(%* {"role": "system", "content": req.system})
  for m in req.messages:
    messages.add(m.toJson())
  result = %* {"model": a.model, "messages": messages}
  if req.maxTokens > 0:
    result["max_tokens"] = %req.maxTokens

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: ZhipuAdapter; req: CompletionRequest): Result[CompletionResponse, string] =
  let headers = @[
    ("Content-Type",  "application/json"),
    ("Authorization", "Bearer " & a.apiKey),
  ]
  let url  = if a.endpoint.len > 0: a.endpoint else: ZhipuEndpoint
  let resp = ? a.http.post(url, $a.buildBody(req), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Zhipu API error " & $resp.status & ": " & resp.body)
  try:
    let parsed = parseJson(resp.body)
    let msg    = parsed["choices"][0]["message"]
    let usage  = parsed.getOrDefault("usage")
    ok CompletionResponse(
      text:         msg["content"].getStr(""),
      inputTokens:  if usage != nil: usage["prompt_tokens"].getInt(0)    else: 0,
      outputTokens: if usage != nil: usage["completion_tokens"].getInt(0) else: 0,
    )
  except CatchableError as e:
    err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newZhipuAdapter*(apiKey: string;
                      model    = ZhipuDefaultModel;
                      endpoint = ""): ZhipuAdapter =
  ZhipuAdapter(apiKey: apiKey, model: model, endpoint: endpoint,
               http: newStdHttpAdapter())
