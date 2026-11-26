## OpenRouterAdapter — ProviderPort for OpenRouter.
##
## API endpoint: https://openrouter.ai/api/v1/chat/completions
## Auth: Bearer token
## REQUIRED headers: HTTP-Referer and X-Title (platform policy).
##
## Format: OpenAI-compatible (system as first message with role=system,
## messages array with role/content pairs).

import ../../domain/providers/cache_usage_pure
import std/[json, streams, strutils, tables]
import ../../domain/message
import ../../domain/providers/compat
import ../../domain/providers/openai_pure
import ../../ports/provider
import ../../core/pipeops
import ../../core/app_meta
import ../../core/json_helpers
import ../../ports/http
import ./provider_http
import ./sse

const
  OpenRouterEndpoint*    = "https://openrouter.ai/api/v1/chat/completions"
  OpenRouterDefaultModel* = "openai/gpt-6.1-sol"
  OpenRouterReferer*     = OpenRouterRefererUrl
  OpenRouterTitle*       = AppName

type
  OpenRouterAdapter* = object
    apiKey*:   string
    http*:     HttpRuntimePort  ## nil → production provider transport
    model*:    string
    endpoint*: string   ## override for testing
    referer*:  string   ## HTTP-Referer header value
    xTitle*:   string   ## X-Title header value

  OpenRouterToolDelta* = object
    index*:     int
    id*:        string
    name*:      string
    arguments*: string
    signature*: string  ## Gemini thought signature (extra_content)

  OpenRouterSseChunk* = object
    token*:        string
    reasoning*:    string
    toolCalls*:    seq[OpenRouterToolDelta]
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

# ── Compat profile ────────────────────────────────────────────────────────────

func openRouterCompatProfile*(endpoint = OpenRouterEndpoint;
                              referer = OpenRouterReferer;
                              xTitle = OpenRouterTitle): CompatProfile =
  ## The OpenRouter deviations from the OpenAI transport: the two headers the
  ## platform requires, the wire quirks and usage reporting while streaming.
  ## `include_reasoning` comes from the quirk, so there are no reasoningExtras.
  CompatProfile(
    id: "openrouter",
    endpoint: endpoint,
    extraHeaders: @[("HTTP-Referer", referer), ("X-Title", xTitle)],
    streamExtras: %* {"stream_options": {"include_usage": true}},
    supportsImages: true,
    quirks: OpenAiWireQuirks(
      toolResultName: false,
      toolCallsEmptyContent: true,
      emptyContentKey: true,
      imageEmptyTextPart: true,
      imageWithToolCalls: false,
      toolChoiceAuto: true,
      omitStreamKey: true,
      includeReasoningField: true,
    ),
  )

func profileFor*(a: OpenRouterAdapter): CompatProfile =
  ## The profile for this adapter instance: explicit overrides win, an empty
  ## endpoint falls back to the OpenRouter default. Pure: safe to call from
  ## any thread (a fresh profile and fresh JsonNodes per call).
  let endpoint = if a.endpoint.len > 0: a.endpoint else: OpenRouterEndpoint
  openRouterCompatProfile(endpoint = endpoint, referer = a.referer,
                          xTitle = a.xTitle)

# ── JSON serialisation ────────────────────────────────────────────────────────

proc markText(msg: JsonNode) =
  ## The text of `msg` as one part carrying a 5-minute cache marker.
  let content = msg{"content"}
  if content.isNil: return
  if content.kind == JString:
    if content.getStr.len == 0: return
    msg["content"] = %* [{"type": "text", "text": content.getStr,
                          "cache_control": {"type": "ephemeral"}}]
  elif content.kind == JArray and content.len > 0:
    content[content.len - 1]["cache_control"] = %* {"type": "ephemeral"}

proc withClaudeCacheMarkers(a: OpenRouterAdapter; body: JsonNode) =
  ## E8.2: OpenRouter passes Anthropic's cache markers through for Claude
  ## models; the others cache on their own. One closes the stable system
  ## prompt, the other moves with the last message.
  if not a.model.startsWith("anthropic/"): return
  let msgs = body{"messages"}
  if msgs.isNil or msgs.len == 0: return
  if msgs[0]{"role"}.getStr == "system": markText(msgs[0])
  if msgs.len > 1: markText(msgs[msgs.len - 1])

proc buildBody*(a: OpenRouterAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing of JSON serialisation without live HTTP.
  result = buildCompatRequestBody(a.profileFor(), a.model, req)
  a.withClaudeCacheMarkers(result)

proc buildStreamBody*(a: OpenRouterAdapter; req: CompletionRequest): JsonNode =
  result = buildCompatRequestBody(a.profileFor(), a.model, req, stream = true)
  a.withClaudeCacheMarkers(result)

# ── Response parsing ──────────────────────────────────────────────────────────

func parseOpenRouterResponse*(j: JsonNode): Result[CompletionResponse, string] =
  ## Exported for unit testing of response parsing without live HTTP.
  let choices = j{"choices"}
  if choices.isNil or choices.kind != JArray or choices.len == 0:
    let errorMsg = j{"error"}{"message"}.getStr("")
    if errorMsg.len > 0:
      return err("OpenRouter error: " & errorMsg)
    return err("Invalid OpenRouter response: missing 'choices'")

  let msg   = choices[0]{"message"}
  if msg.isNil:
    return err("Invalid OpenRouter response: missing 'message' in first choice")

  let usage = j.getOrDefault("usage")
  var toolCalls: seq[ToolCallRequest] = @[]
  let tcs = msg.getOrDefault("tool_calls")
  if tcs != nil and tcs.kind == JArray:
    for tc in tcs:
      let fn = tc{"function"}
      if fn.isNil: continue
      toolCalls.add ToolCallRequest(
        id:        tc{"id"}.getStr(""),
        name:      fn{"name"}.getStr(""),
        inputJson: fn{"arguments"}.getStr("{}"),
        signature: extraContentSignature(tc),
      )
  var reasoning = msg{"reasoning"}.getStr("")
  if reasoning.len == 0:
    reasoning = msg{"reasoning_content"}.getStr("")

  ok CompletionResponse(
    text:         msg{"content"}.getStr(""),
    reasoning:    reasoning,
    inputTokens:  usage.jInt("prompt_tokens"),
    cacheReadTokens:  openAiUsage(usage).cacheRead,
    cacheWriteTokens: openAiUsage(usage).cacheWrite,
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
  var reasoning = ""
  var toolCalls: seq[OpenRouterToolDelta] = @[]
  if choices != nil and choices.kind == JArray and choices.len > 0:
    let delta = choices[0].getOrDefault("delta")
    if delta != nil:
      token = delta.getOrDefault("content").getStr("")
      reasoning = delta.getOrDefault("reasoning").getStr("")
      if reasoning.len == 0:
        reasoning = delta.getOrDefault("reasoning_content").getStr("")
      let tcs = delta.getOrDefault("tool_calls")
      if tcs != nil and tcs.kind == JArray:
        for tc in tcs:
          let fn = tc.getOrDefault("function")
          toolCalls.add OpenRouterToolDelta(
            index:     tc.getOrDefault("index").getInt(0),
            id:        tc.getOrDefault("id").getStr(""),
            name:      if fn != nil: fn.getOrDefault("name").getStr("") else: "",
            arguments: if fn != nil: fn.getOrDefault("arguments").getStr("") else: "",
            signature: extraContentSignature(tc),
          )
  ok(OpenRouterSseChunk(
    token:        token,
    reasoning:    reasoning,
    toolCalls:    toolCalls,
    inputTokens:  usage.jInt("prompt_tokens"),
    outputTokens: usage.jInt("completion_tokens"),
  ))

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: OpenRouterAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  let profile = a.profileFor()
  providerGuard:
    var headers: seq[HttpHeader] = @[("Content-Type", "application/json"), ("Authorization", "Bearer " & a.apiKey)]
    for (name, value) in profile.extraHeaders:
      headers.add((name, value))
    let body = $a.buildBody(req)
    let resp = ? postProvider(a.http, "OpenRouter", profile.endpoint, body, headers)
    resp |> parseJson |> parseOpenRouterResponse

# ── Streaming ─────────────────────────────────────────────────────────────────

proc makeStreamFn*(a: OpenRouterAdapter): StreamFn =
  ## Returns a StreamFn closure that performs SSE streaming via OpenRouter.
  ## Tokens are delivered one at a time via the onToken callback.
  ## Falls back to a regular completion when SSE is unavailable.
  let adapter = a   ## capture by value
  result = proc(req: CompletionRequest;
                onToken: proc(tok: string) {.gcsafe.}
               ): Result[CompletionResponse, string] {.gcsafe.} =
    ## The profile is rebuilt inside the worker thread: a CompatProfile owns
    ## JsonNodes, so nothing GC-managed is captured/shared across threads.
    let profile = adapter.profileFor()
    providerGuard:
      var headers: seq[HttpHeader] = @[("Content-Type", "application/json"), ("Authorization", "Bearer " & adapter.apiKey)]
      for (name, value) in profile.extraHeaders:
        headers.add((name, value))
      let body = $adapter.buildStreamBody(req)
      let resp = ? postProviderStream(adapter.http, "OpenRouter", profile.endpoint, body, headers)

      consumeOpenAiStream(resp, "OpenRouter", onToken)

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
