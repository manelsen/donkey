## OpenAIAdapter — ProviderPort for OpenAI API (api.openai.com).
##
## API endpoint: https://api.openai.com/v1/chat/completions
## Auth: Bearer token via Authorization header.
## Format: OpenAI-compatible (system as first message with role=system,
## messages array with role/content pairs).
##
## Streaming: SSE via "stream": true request flag.

import std/[json, streams, strutils]
import ../../domain/message
import ../../domain/providers/openai_pure
import ../../domain/providers/compat
import ../../ports/provider
import ../../core/pipeops
import ../../core/json_helpers
import ../../ports/http
import ./provider_http

const
  OpenAIEndpoint*    = "https://api.openai.com/v1/chat/completions"
  OpenAIDefaultModel* = "gpt-6.1-sol"

type
  OpenAIAdapter* = object
    apiKey*:   string
    http*:     HttpRuntimePort  ## nil → production provider transport
    model*:    string
    endpoint*: string   ## override for testing
    providerName*: string ## e.g. "OpenAI" or "Groq"

  OpenAISseChunk* = object
    token*:        string
    reasoning*:    string
    done*:         bool
    inputTokens*:  int
    outputTokens*: int

# ── Concept conformance ───────────────────────────────────────────────────────

func displayName*(a: OpenAIAdapter): string =
  if a.providerName.len > 0: a.providerName else: "OpenAI"

proc caps*(a: OpenAIAdapter): ProviderCaps =
  ProviderCaps(
    name:              a.displayName.toLowerAscii & "/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens: 0,
    requiresUserFirst: false,
  )

# ── Response parsing ──────────────────────────────────────────────────────────

proc parseOpenAISseLine*(line: string): Result[OpenAISseChunk, string] =
  let trimmed = line.strip()
  if trimmed.len == 0 or not trimmed.startsWith("data:"):
    return ok(OpenAISseChunk())
  let payload = trimmed["data:".len .. ^1].strip()
  if payload == "[DONE]":
    return ok(OpenAISseChunk(done: true))
  let j = try: parseJson(payload) except CatchableError as e: return err(e.msg)
  let usage = j.getOrDefault("usage")
  let choices = j.getOrDefault("choices")
  var token = ""
  if choices != nil and choices.kind == JArray and choices.len > 0:
    let delta = choices[0].getOrDefault("delta")
    if delta != nil:
      token = delta.getOrDefault("content").getStr("")
  ok(OpenAISseChunk(
    token:        token,
    inputTokens:  usage.jInt("prompt_tokens"),
    outputTokens: usage.jInt("completion_tokens"),
  ))

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: OpenAIAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  providerGuard:
    var headers: seq[HttpHeader] = @[("Content-Type", "application/json"), ("Authorization", "Bearer " & a.apiKey)]
    let body = buildCompatRequestBody(defaultOpenAiProfile(endpoint = OpenAIEndpoint), a.model, req)
    let url  = if a.endpoint.len > 0: a.endpoint else: OpenAIEndpoint
    let resp = ? postProvider(a.http, a.displayName, url, $body, headers)
    resp |> parseJson |> parseResponseFrom

# ── Streaming ─────────────────────────────────────────────────────────────────

proc makeStreamFn*(a: OpenAIAdapter): StreamFn =
  let adapter = a
  result = proc(req: CompletionRequest;
                onToken: proc(tok: string) {.gcsafe.}
               ): Result[CompletionResponse, string] {.gcsafe.} =
    providerGuard:
      var headers: seq[HttpHeader] = @[("Content-Type", "application/json"), ("Authorization", "Bearer " & adapter.apiKey)]
      let body = buildCompatRequestBody(defaultOpenAiProfile(endpoint = OpenAIEndpoint), adapter.model, req, stream = true)
      let url  = if adapter.endpoint.len > 0: adapter.endpoint else: OpenAIEndpoint
      let resp = ? postProviderStream(adapter.http, adapter.displayName, url, $body, headers)
      
      var accumulated = ""
      var reasoning = ""
      var inputTokens = 0
      var outputTokens = 0
      
      for line in resp.lines:
        let res = parseOpenAISseLine(line)
        if res.isErr: continue
        let chunk = res.value
        if chunk.done: break
        if chunk.token.len > 0:
          accumulated &= chunk.token
          onToken(chunk.token)
        if chunk.reasoning.len > 0:
          reasoning &= chunk.reasoning
        if chunk.inputTokens > 0: inputTokens = chunk.inputTokens
        if chunk.outputTokens > 0: outputTokens = chunk.outputTokens

      ok(CompletionResponse(
        text:         accumulated,
        reasoning:    reasoning,
        inputTokens:  inputTokens,
        outputTokens: outputTokens,
      ))

# ── Constructor ───────────────────────────────────────────────────────────────

proc newOpenAIAdapter*(apiKey:   string;
                       model    = OpenAIDefaultModel;
                       endpoint = "";
                       providerName = "OpenAI"): OpenAIAdapter =
  OpenAIAdapter(
    apiKey:   apiKey,
    model:    model,
    endpoint: endpoint,
    providerName: if providerName.len > 0: providerName else: "OpenAI",
  )