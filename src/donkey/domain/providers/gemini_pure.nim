## gemini_pure.nim — pure Google Gemini wire-format helpers.
##
## Formats `CompletionRequest` into a Gemini generateContent JSON request body,
## and parses a Gemini JSON response into a `CompletionResponse`.
##
## No I/O, no side effects in the pure helpers.
##
## Topology (pipeops):
##   |>    — unary pure transform  (req.messages |> buildGeminiContents)
##   |>->  — last-arg pipe         (json |>-> parseGeminiResponse)
##
## Gemini API reference:
##   https://ai.google.dev/api/rest/v1beta/models/generateContent

import ./cache_usage_pure
import std/[json, tables, strutils]
import ../../core/pipeops
import ../../domain/message
import ./media_pure

# ── Role mapping ──────────────────────────────────────────────────────────────

func geminiRole*(role: string): string =
  ## Maps internal role names to Gemini roles.
  ## assistant → model, tool → user, others pass through unchanged.
  if role == roleAssistant: "model"
  elif role == "tool": "user"
  else: role

# ── JSON part builders ───────────────────────────────────────────────────────

proc textPart*(text: string): JsonNode =
  %* {"text": text}

const GeminiSkipThoughtSignature* = "skip_thought_signature_validator"
  ## The placeholder Google accepts in place of a real signature, for a call
  ## that has none (made by another provider before a fallback).

proc functionCallPart*(tc: ToolCallRequest): JsonNode =
  ## Converts a ToolCallRequest to a Gemini functionCall part.
  ## inputJson is used as-is (assumed pre-serialized or simple string).
  ## Gemini 3 answers 400 when a replayed call lacks its thoughtSignature, so
  ## every call carries its own or the placeholder (hermes
  ## agent/gemini_native_adapter.py).
  let args = try: parseJson(tc.inputJson) except CatchableError: newJObject()
  %* {"functionCall": {"name": tc.name, "args": args},
      "thoughtSignature": (if tc.signature.len > 0: tc.signature
                           else: GeminiSkipThoughtSignature)}

proc functionResponsePart*(msg: ChatMessage; functionName: string): JsonNode =
  ## Converts a tool-result message to a Gemini functionResponse part.
  let response = try: parseJson(msg.text) except CatchableError: %* {"result": msg.text}
  %* {"functionResponse": {"name": functionName, "response": response, "id": msg.toolCallId}}

# ── Content array builder ────────────────────────────────────────────────────

proc toGeminiContent*(msg: ChatMessage): JsonNode =
  ## Converts a ChatMessage to a Gemini content object with parts array.
  var parts = newJArray()
  if msg.text.len > 0:
    parts.add(textPart(msg.text))
  if msg.imageUrl.len > 0:
    ## Gemini can inline bytes, but it cannot fetch an arbitrary http URL.
    let image = parseDataUrl(msg.imageUrl)
    if image.isOk:
      parts.add(%* {"inlineData": {
        "mimeType": image.get().mimeType,
        "data": image.get().data,
      }})
  for tc in msg.toolCalls:
    parts.add(functionCallPart(tc))
  %* {"role": geminiRole(msg.role), "parts": parts}

proc appendContent*(contents: var seq[JsonNode]; content: JsonNode) =
  ## Gemini wants alternating user/model turns; merge adjacent same-role parts.
  if contents.len > 0 and contents[^1]["role"].getStr("") == content["role"].getStr(""):
    for part in content["parts"]:
      contents[^1]["parts"].add(part)
  else:
    contents.add(content)

proc buildGeminiContents*(messages: seq[ChatMessage]): tuple[contents: seq[JsonNode], toolNamesById: Table[string, string]] =
  ## Converts a message history to Gemini contents array format.
  ## Returns both the contents and a mapping of tool call IDs to names.
  var contents: seq[JsonNode] = @[]
  var toolNamesById: Table[string, string]
  for m in messages:
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
  result = (contents, toolNamesById)

proc buildToolsArray*(tools: seq[ToolDescription]): JsonNode =
  ## Serializes tool descriptions to Gemini tools format.
  var declarations = newJArray()
  for td in tools:
    let schema = try: parseJson(td.schemaJson) except CatchableError: newJObject()
    declarations.add(%* {
      "name": td.name,
      "description": td.description,
      "parameters": schema,
    })
  %* [{"functionDeclarations": declarations}]

# ── Public pure API ─────────────────────────────────────────────────────────

proc buildGeminiRequest*(req: CompletionRequest): JsonNode =
  ## Builds a complete Gemini generateContent request body.
  ## Exported for unit testing.
  let (contents, _) = req.messages.buildGeminiContents()
  result = %* {"contents": contents}
  if req.system.len > 0:
    result["systemInstruction"] = %* {
      "parts": [{"text": req.system}]
    }
  if req.maxTokens > 0:
    result["generationConfig"] = %* {"maxOutputTokens": req.maxTokens}

  if req.reasoning:
    if result.hasKey("generationConfig"):
      result["generationConfig"]["thinking_config"] = %* {"include_thoughts": true, "thinking_level": "HIGH"}
    else:
      result["generationConfig"] = %* {"thinking_config": {"include_thoughts": true, "thinking_level": "HIGH"}}

  if req.tools.len > 0:
    result["tools"] = req.tools.buildToolsArray()

func parseGeminiResponse*(j: JsonNode): Result[CompletionResponse, string] =
  ## Parses a Gemini generateContent response into a CompletionResponse.
  ## Exported for unit testing.
  let candidates = j{"candidates"}
  if candidates.isNil or candidates.kind != JArray or candidates.len == 0:
    let errorMsg = j{"error"}{"message"}.getStr("")
    if errorMsg.len > 0:
      return err("Gemini error: " & errorMsg)
    return err("Invalid Gemini response: missing 'candidates'")

  let cand  = candidates[0]
  let parts = cand{"content"}{"parts"}
  if parts.isNil or parts.kind != JArray:
    return err("Invalid Gemini response: missing 'parts' in first candidate")

  var textParts: seq[string] = @[]
  var reasoningParts: seq[string] = @[]
  var toolCalls: seq[ToolCallRequest] = @[]
  for part in parts:
    if part.hasKey("text"):
      let text = part["text"].getStr("")
      if text.len > 0:
        if part.getOrDefault("thought").getBool(false):
          reasoningParts.add(text)
        else:
          textParts.add(text)
    elif part.hasKey("thought"):
      # Some versions return thought as a string field
      let thought = part["thought"].getStr("")
      if thought.len > 0:
        reasoningParts.add(thought)
    elif part.hasKey("functionCall"):
      let fc = part["functionCall"]
      toolCalls.add(ToolCallRequest(
        id: fc.getOrDefault("id").getStr(""),
        name: fc.getOrDefault("name").getStr(""),
        inputJson: $fc.getOrDefault("args"),
        signature: part.getOrDefault("thoughtSignature").getStr(""),
      ))
  let usage = j.getOrDefault("usageMetadata")
  ok CompletionResponse(
    text:         textParts.join("\n"),
    reasoning:    reasoningParts.join("\n"),
    inputTokens:  if usage != nil: usage.getOrDefault("promptTokenCount").getInt(0)     else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("candidatesTokenCount").getInt(0) else: 0,
    cacheReadTokens: geminiUsage(usage).cacheRead,
    toolCalls:    toolCalls,
  )
