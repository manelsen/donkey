## GeminiAdapter — ProviderPort for Google Gemini.
##
## API endpoint: https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}
## Auth: query parameter `key=` (NOT a header)
## Default model: gemini-2.0-flash
##
## Quirks absorbed here:
##   - Role mapping: "assistant" → "model"
##   - Content format: [{role, parts: [{text}|{functionCall}|{functionResponse}]}]
##   - System prompt: systemInstruction: {parts: [{text}]} (top-level field)
##   - QUIRK: history must alternate user/model turns (normalised in buildBody)
##   - requiresUserFirst = true: function response must follow model turn
##   - Response: candidates[0].content.parts[0].text
##   - Token usage: usageMetadata.promptTokenCount / candidatesTokenCount

import std/[httpclient, json, strutils, tables]
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

# ── Role mapping ──────────────────────────────────────────────────────────────

func geminiRole(role: string): string =
  ## Maps OpenAI-style roles to Gemini roles.
  if role == roleAssistant: "model"
  elif role == "tool": "user"
  else: role

proc textPart(text: string): JsonNode =
  %* {"text": text}

proc functionCallPart(tc: ToolCallRequest): JsonNode =
  let args = try: parseJson(tc.inputJson) except: newJObject()
  %* {"functionCall": {"name": tc.name, "args": args}}

proc functionResponsePart(msg: ChatMessage; functionName: string): JsonNode =
  let response = try: parseJson(msg.text) except: %* {"result": msg.text}
  %* {"functionResponse": {"name": functionName, "response": response, "id": msg.toolCallId}}

proc toGeminiContent(msg: ChatMessage): JsonNode =
  var parts = newJArray()
  if msg.text.len > 0:
    parts.add(textPart(msg.text))
  for tc in msg.toolCalls:
    parts.add(functionCallPart(tc))
  %* {"role": geminiRole(msg.role), "parts": parts}

proc appendContent(contents: var seq[JsonNode]; content: JsonNode) =
  ## Gemini wants alternating user/model turns; merge adjacent same-role parts.
  if contents.len > 0 and contents[^1]["role"].getStr("") == content["role"].getStr(""):
    for part in content["parts"]:
      contents[^1]["parts"].add(part)
  else:
    contents.add(content)

# ── JSON serialisation ────────────────────────────────────────────────────────

proc buildBody*(a: GeminiAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  ## Produces Gemini generateContent request format.
  var contents: seq[JsonNode] = @[]
  var toolNamesById: Table[string, string]
  for m in req.messages:
    if m.role == "tool":
      let functionName = toolNamesById.getOrDefault(m.toolCallId, "")
      appendContent(contents, %* {
        "role": "user",
        "parts": [functionResponsePart(m, functionName)],
      })
      continue

    for tc in m.toolCalls:
      toolNamesById[tc.id] = tc.name
    appendContent(contents, toGeminiContent(m))

  result = %* {"contents": contents}

  if req.system.len > 0:
    result["systemInstruction"] = %* {
      "parts": [{"text": req.system}]
    }

  if req.maxTokens > 0:
    result["generationConfig"] = %* {"maxOutputTokens": req.maxTokens}
  if req.tools.len > 0:
    var declarations = newJArray()
    for td in req.tools:
      let schema = try: parseJson(td.schemaJson) except: newJObject()
      declarations.add(%* {
        "name": td.name,
        "description": td.description,
        "parameters": schema,
      })
    result["tools"] = %* [{"functionDeclarations": declarations}]

# ── Response parsing ──────────────────────────────────────────────────────────

func parseGeminiResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing.
  let cand  = j["candidates"][0]
  let parts = cand["content"]["parts"]
  var textParts: seq[string] = @[]
  var toolCalls: seq[ToolCallRequest] = @[]
  for part in parts:
    if part.hasKey("text"):
      let text = part["text"].getStr("")
      if text.len > 0:
        textParts.add(text)
    elif part.hasKey("functionCall"):
      let fc = part["functionCall"]
      toolCalls.add(ToolCallRequest(
        id: fc.getOrDefault("id").getStr(""),
        name: fc.getOrDefault("name").getStr(""),
        inputJson: $fc.getOrDefault("args"),
      ))
  let usage = j.getOrDefault("usageMetadata")
  CompletionResponse(
    text:         textParts.join("\n"),
    inputTokens:  if usage != nil: usage.getOrDefault("promptTokenCount").getInt(0)     else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("candidatesTokenCount").getInt(0) else: 0,
    toolCalls:    toolCalls,
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
