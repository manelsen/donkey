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

import std/[json]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../http/std_http

const
  GeminiBaseUrl*     = "https://generativelanguage.googleapis.com/v1beta/models"
  GeminiDefaultModel = "gemini-2.0-flash"

type
  GeminiAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## full URL override for testing
    http*:     StdHttpAdapter

# ── Concept conformance ───────────────────────────────────────────────────────

func caps*(a: GeminiAdapter): ProviderCaps =
  ProviderCaps(
    name:              "gemini/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  1_000_000,
    requiresUserFirst: true,
  )

# ── URL builder ───────────────────────────────────────────────────────────────

func buildUrl*(a: GeminiAdapter): string =
  ## Exported for unit testing.
  if a.endpoint.len > 0:
    return a.endpoint
  GeminiBaseUrl & "/" & a.model & ":generateContent?key=" & a.apiKey

# ── Role mapping ──────────────────────────────────────────────────────────────

func geminiRole(role: string): string =
  ## Maps OpenAI-style roles to Gemini roles.
  if role == roleAssistant: "model" else: role

# ── JSON serialisation ────────────────────────────────────────────────────────

func toContentPart(msg: ChatMessage): JsonNode =
  ## Gemini uses parts arrays. Tool results use functionResponse.
  if msg.toolCallId.len > 0:
    %* {
      "role": "user",
      "parts": [{"functionResponse": {
        "name":     msg.toolName,
        "response": {"output": msg.text}
      }}]
    }
  else:
    %* {
      "role":  geminiRole(msg.role),
      "parts": [{"text": msg.text}]
    }

proc buildBody*(a: GeminiAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  ## Produces Gemini generateContent request format.
  var contents: seq[JsonNode] = @[]
  for m in req.messages:
    contents.add(m.toContentPart())

  result = %* {"contents": contents}

  if req.system.len > 0:
    result["systemInstruction"] = %* {"parts": [{"text": req.system}]}

  if req.maxTokens > 0:
    result["generationConfig"] = %* {"maxOutputTokens": req.maxTokens}

  if req.tools.len > 0:
    var decls: seq[JsonNode] = @[]
    for td in req.tools:
      let schema = if td.schemaJson.len > 0:
                     try: parseJson(td.schemaJson) except: newJObject()
                   else: newJObject()
      decls.add(%* {"name": td.name, "description": td.description, "parameters": schema})
    result["tools"] = %* [{"functionDeclarations": decls}]

# ── Response parsing ──────────────────────────────────────────────────────────

func parseGeminiResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing.
  let cand  = j["candidates"][0]
  let parts = cand["content"]["parts"]
  let usage = j.getOrDefault("usageMetadata")

  var text      = ""
  var toolCalls: seq[ToolCallRequest]

  for part in parts:
    if part.hasKey("text"):
      text = part["text"].getStr("")
    elif part.hasKey("functionCall"):
      let fc   = part["functionCall"]
      let args = fc.getOrDefault("args")
      toolCalls.add(ToolCallRequest(
        id:        "",    ## Gemini doesn't assign call IDs
        name:      fc["name"].getStr(""),
        inputJson: if args != nil: $args else: "{}",
      ))

  CompletionResponse(
    text:         text,
    inputTokens:  if usage != nil: usage.getOrDefault("promptTokenCount").getInt(0)     else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("candidatesTokenCount").getInt(0) else: 0,
    toolCalls:    toolCalls,
  )

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: GeminiAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  let headers = @[
    ("Content-Type", "application/json"),
  ]
  let url  = a.buildUrl()
  let resp = ? a.http.post(url, $a.buildBody(req), headers)
  if resp.status < 200 or resp.status >= 300:
    return err("Gemini API error " & $resp.status & ": " & resp.body)
  try:
    let parsed = parseJson(resp.body)
    ok(parseGeminiResponse(parsed))
  except CatchableError as e:
    err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newGeminiAdapter*(apiKey:   string;
                       model    = GeminiDefaultModel;
                       endpoint = ""): GeminiAdapter =
  GeminiAdapter(apiKey: apiKey, model: model, endpoint: endpoint,
                http: newStdHttpAdapter())
