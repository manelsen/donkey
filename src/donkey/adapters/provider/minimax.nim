## MiniMaxAdapter — ProviderPort for MiniMax AI.
##
## API endpoint: https://api.minimax.io/v1/chat/completions (OpenAI-compatible)
## Auth: Bearer token
## Default model: MiniMax-M2.7
##
## Quirks absorbed here:
##   - OpenAI-compatible format (choices[0].message.content)
##   - reasoning_split=true separates thinking into reasoning_details
##   - temperature range is (0.0, 1.0] (not 0.0-2.0 like OpenAI)
##   - Streaming supported via standard SSE
##   - Tool calling supported (M2.1+)

import std/[httpclient, json]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../http/helpers
import ../../domain/providers/openai_pure

const
  MiniMaxEndpoint*     = "https://api.minimax.io/v1/chat/completions"
  MiniMaxDefaultModel* = "MiniMax-M2.7"

type
  MiniMaxAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## override for testing

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: MiniMaxAdapter): ProviderCaps =
  ProviderCaps(
    name:              "minimax/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  204_800,
    requiresUserFirst: false,
  )

# ── JSON serialisation (OpenAI-compatible) ────────────────────────────────────

proc buildBody*(a: MiniMaxAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  ## OpenAI-compatible format with reasoning_split for thinking separation.
  var messages: seq[JsonNode] = @[]
  if req.system.len > 0:
    messages.add(%* {"role": "system", "content": req.system})
  for m in req.messages:
    messages.add(%* {"role": m.role, "content": m.text})

  result = %* {
    "model": a.model,
    "messages": messages,
    "reasoning_split": true,
  }

  if req.maxTokens > 0:
    result["max_tokens"] = %req.maxTokens

  if req.tools.len > 0:
    var tools: seq[JsonNode] = @[]
    for t in req.tools:
      tools.add(%* {
        "type": "function",
        "function": {
          "name": t.name,
          "description": t.description,
          "parameters": parseJson(t.schemaJson),
        }
      })
    result["tools"] = %tools

# ── Response parsing (reuse OpenAI parser) ────────────────────────────────────

proc parseMiniMaxResponse*(j: JsonNode): Result[CompletionResponse, string] =
  ## Exported for unit testing.
  ## MiniMax uses OpenAI-compatible format, so we reuse the OpenAI parser.

  # Check for error responses
  let errNode = j{"error"}
  if not errNode.isNil:
    let errMsg = errNode{"message"}.getStr("")
    let errCode = errNode{"code"}.getStr("")
    if errMsg.len > 0:
      return err("MiniMax error: " & errMsg & " (code " & errCode & ")")

  # Check for missing choices before delegating
  let choices = j{"choices"}
  if choices.isNil or choices.kind != JArray or choices.len == 0:
    return err("Invalid MiniMax response: missing 'choices'")

  # Use OpenAI parser for the standard format
  openai_pure.parseResponseFrom(j)

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: MiniMaxAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  withHttpClient:
    client.headers = newHttpHeaders({
      "Content-Type":  "application/json",
      "Authorization": "Bearer " & a.apiKey,
    })
    let body = $a.buildBody(req)
    let url  = if a.endpoint.len > 0: a.endpoint else: MiniMaxEndpoint
    let resp = client.post(url, body = body)
    checkApiStatus(resp, "MiniMax")
    resp.body |> parseJson |> parseMiniMaxResponse

# ── Constructor ───────────────────────────────────────────────────────────────

proc newMiniMaxAdapter*(apiKey:   string;
                        model    = MiniMaxDefaultModel;
                        endpoint = ""): MiniMaxAdapter =
  MiniMaxAdapter(apiKey: apiKey, model: model, endpoint: endpoint)
