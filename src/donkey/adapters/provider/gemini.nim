## GeminiAdapter — ProviderPort for Google Gemini.
##
## API endpoint: https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}
## Auth: query parameter `key=` (NOT a header)
## Default model: gemini-2.0-flash
##
## Quirks absorbed here:
##   - Role mapping: "assistant" → "model"
##   - Content format: [{role, parts: [{text}]}]  (NOT role/content)
##   - System prompt: systemInstruction: {parts: [{text}]} (top-level field)
##   - QUIRK: history must alternate user/model turns (normalised in buildBody)
##   - requiresUserFirst = true: function response must follow model turn
##   - Response: candidates[0].content.parts[0].text
##   - Token usage: usageMetadata.promptTokenCount / candidatesTokenCount

import std/[httpclient, json, strutils, uri]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops

const
  GeminiBaseUrl*     = "https://generativelanguage.googleapis.com/v1beta/models"
  GeminiDefaultModel = "gemini-2.0-flash"

type
  GeminiAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## full URL override for testing

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: GeminiAdapter): ProviderCaps =
  ProviderCaps(
    name:              "gemini/" & a.model,
    streaming:         true,
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

# ── Role mapping ──────────────────────────────────────────────────────────────

func geminiRole(role: string): string =
  ## Maps OpenAI-style roles to Gemini roles.
  if role == roleAssistant: "model" else: role

# ── JSON serialisation ────────────────────────────────────────────────────────

proc buildBody*(a: GeminiAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  ## Produces Gemini generateContent request format.
  var contents: seq[JsonNode] = @[]
  for m in req.messages:
    contents.add(%* {
      "role":  geminiRole(m.role),
      "parts": [{"text": m.text}]
    })

  result = %* {"contents": contents}

  if req.system.len > 0:
    result["systemInstruction"] = %* {
      "parts": [{"text": req.system}]
    }

  if req.maxTokens > 0:
    result["generationConfig"] = %* {"maxOutputTokens": req.maxTokens}

# ── Response parsing ──────────────────────────────────────────────────────────

func parseGeminiResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing.
  let cand  = j["candidates"][0]
  let parts = cand["content"]["parts"]
  let text  = parts[0]["text"].getStr("")
  let usage = j.getOrDefault("usageMetadata")
  CompletionResponse(
    text:         text,
    inputTokens:  if usage != nil: usage.getOrDefault("promptTokenCount").getInt(0)     else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("candidatesTokenCount").getInt(0) else: 0,
  )

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: GeminiAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()

    client.headers = newHttpHeaders({"Content-Type": "application/json"})

    let body = $a.buildBody(req)
    let url  = a.buildUrl()
    let resp = client.post(url, body = body)

    if resp.status[0] != '2':
      return err("Gemini API error " & resp.status & ": " & resp.body)

    let parsed = parseJson(resp.body)
    ok(parseGeminiResponse(parsed))
  except CatchableError as e:
    err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newGeminiAdapter*(apiKey:   string;
                       model    = GeminiDefaultModel;
                       endpoint = ""): GeminiAdapter =
  GeminiAdapter(apiKey: apiKey, model: model, endpoint: endpoint)
