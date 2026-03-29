## GeminiAdapter — ProviderPort for Google Gemini.
##
## API endpoint: https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}
## Auth: query parameter `key=` (NOT a header)
## Default model: gemini-2.5-flash
##
## Quirks absorbed here:
##   - Role mapping: "assistant" → "model"
##   - Content format: [{role, parts: [{text}|{functionCall}|{functionResponse}]}]
##   - System prompt: systemInstruction: {parts: [{text}]} (top-level field)
##   - QUIRK: history must alternate user/model turns (normalised in buildBody)
##   - requiresUserFirst = true: function response must follow model turn
##   - Response: candidates[0].content.parts[0].text
##   - Token usage: usageMetadata.promptTokenCount / candidatesTokenCount

import std/[httpclient, json]
import ../../domain/message
import ../../domain/providers/gemini_pure as gp
import ../../ports/provider
import ../../core/pipeops
import ../http/helpers

# Re-export from pure module for backwards compatibility
export gp.geminiRole, gp.textPart, gp.functionCallPart, gp.functionResponsePart,
       gp.toGeminiContent, gp.appendContent, gp.buildGeminiContents,
       gp.buildGeminiRequest, gp.parseGeminiResponse

const
  GeminiBaseUrl*     = "https://generativelanguage.googleapis.com/v1beta/models"
  GeminiDefaultModel = "gemini-2.5-flash"

type
  GeminiAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## full URL override for testing

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: GeminiAdapter): ProviderCaps =
  ProviderCaps(
    name:              "gemini/" & a.model,
    streaming:         false,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  1_000_000,
    requiresUserFirst: true,
  )

# ── URL builder ───────────────────────────────────────────────────────────────

proc buildUrl*(a: GeminiAdapter): string =
  ## Exported for unit testing.
  if a.endpoint.len > 0:
    return a.endpoint
  GeminiBaseUrl & "/" & a.model & ":generateContent?key=" & a.apiKey

# ── JSON serialisation (delegated to pure) ────────────────────────────────────

proc buildBody*(a: GeminiAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  ## Produces Gemini generateContent request format by delegating to pure helpers.
  req.buildGeminiRequest()

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: GeminiAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  withHttpClient:
    client.headers = newHttpHeaders({"Content-Type": "application/json"})
    let body = $a.buildBody(req)
    let url  = a.buildUrl()
    let resp = client.post(url, body = body)
    checkApiStatus(resp, "Gemini")
    resp.body |> parseJson |> parseGeminiResponse |> ok

# ── Constructor ───────────────────────────────────────────────────────────────

proc newGeminiAdapter*(apiKey:   string;
                       model    = GeminiDefaultModel;
                       endpoint = ""): GeminiAdapter =
  GeminiAdapter(apiKey: apiKey, model: model, endpoint: endpoint)
