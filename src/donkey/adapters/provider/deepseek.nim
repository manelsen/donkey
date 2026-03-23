## DeepSeekAdapter — ProviderPort for DeepSeek API (api.deepseek.com).
##
## API endpoint: https://api.deepseek.com/v1/chat/completions
## Auth: Bearer token via Authorization header.
## Format: OpenAI-compatible request format.
##
## DeepSeek-specific quirk:
##   - Response includes a `reasoning` field containing chain-of-thought
##     that is NOT exposed to the user (CompletionResponse has no field for it).
##   - Streaming via SSE is supported.

import std/[httpclient, json, streams, strutils]
import ../../domain/message
import ../../domain/providers/openai_pure
import ../../ports/provider
import ../../core/pipeops

const
  DeepSeekEndpoint*    = "https://api.deepseek.com/v1/chat/completions"
  DeepSeekDefaultModel* = "deepseek-chat"

type
  DeepSeekAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## override for testing

  DeepSeekSseChunk* = object
    token*:        string
    done*:         bool
    inputTokens*:  int
    outputTokens*: int

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: DeepSeekAdapter): ProviderCaps =
  ProviderCaps(
    name:              "deepseek/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  64_000,
    requiresUserFirst: false,
  )

# ── Response parsing ──────────────────────────────────────────────────────────

proc parseDeepSeekSseLine*(line: string): Result[DeepSeekSseChunk, string] =
  let trimmed = line.strip()
  if trimmed.len == 0 or not trimmed.startsWith("data:"):
    return ok(DeepSeekSseChunk())
  let payload = trimmed["data:".len .. ^1].strip()
  if payload == "[DONE]":
    return ok(DeepSeekSseChunk(done: true))
  let j = try: parseJson(payload) except CatchableError as e: return err(e.msg)
  let usage = j.getOrDefault("usage")
  let choices = j.getOrDefault("choices")
  var token = ""
  if choices != nil and choices.kind == JArray and choices.len > 0:
    let delta = choices[0].getOrDefault("delta")
    if delta != nil:
      token = delta.getOrDefault("content").getStr("")
  ok(DeepSeekSseChunk(
    token: token,
    inputTokens: if usage != nil: usage.getOrDefault("prompt_tokens").getInt(0) else: 0,
    outputTokens: if usage != nil: usage.getOrDefault("completion_tokens").getInt(0) else: 0,
  ))

proc parseDeepSeekResponse*(body: JsonNode): Result[CompletionResponse, string] =
  ## Parses a DeepSeek /chat/completions response body into CompletionResponse.
  ##
  ## DeepSeek quirk: the `reasoning` field is extracted but discarded —
  ## CompletionResponse has no field for chain-of-thought.
  try:
    let choices = body{"choices"}
    if choices.kind != JArray or choices.len == 0:
      return err("No choices in DeepSeek response")
    let choice = choices[0]
    let msg = choice{"message"}

    let content = msg.getOrDefault("content").getStr("")
    let reasoning = msg.getOrDefault("reasoning").getStr("")
    if reasoning.len > 0:
      discard  ## DeepSeek chain-of-thought; not exposed to user

    var toolCalls: seq[ToolCallRequest] = @[]
    if not msg{"tool_calls"}.isNil:
      for tcNode in msg{"tool_calls"}:
        let args = tcNode{"function"}{"arguments"}.getStr("{}")
        toolCalls.add ToolCallRequest(
          id:        tcNode{"id"}.getStr(""),
          name:      tcNode{"function"}{"name"}.getStr(""),
          inputJson: args,
        )

    let usage = body{"usage"}
    let promptTokens = usage{"prompt_tokens"}.getInt(0)
    let completionTokens = usage{"completion_tokens"}.getInt(0)

    ok CompletionResponse(
      text:         content,
      inputTokens:  promptTokens,
      outputTokens: completionTokens,
      toolCalls:    toolCalls,
    )
  except JsonKindError, KeyError, ValueError:
    err "Failed to parse DeepSeek response: " & getCurrentExceptionMsg()

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: DeepSeekAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()

    client.headers = newHttpHeaders({
      "Content-Type":  "application/json",
      "Authorization": "Bearer " & a.apiKey,
    })

    let body = buildRequestBody(a.model, req)
    let url  = if a.endpoint.len > 0: a.endpoint else: DeepSeekEndpoint
    let resp = client.post(url, body = $body)

    if resp.status[0] != '2':
      return err("DeepSeek API error " & resp.status & ": " & resp.body)

    let parsed = parseJson(resp.body)
    let response = parseDeepSeekResponse(parsed).valueOr:
      return err(error)
    ok(response)
  except CatchableError as e:
    err(e.msg)

# ── Streaming ─────────────────────────────────────────────────────────────────

proc makeStreamFn*(a: DeepSeekAdapter): StreamFn =
  let adapter = a
  result = proc(req: CompletionRequest;
                onToken: proc(tok: string) {.gcsafe.}
               ): Result[CompletionResponse, string] {.gcsafe.} =
    try:
      let client = newHttpClient()
      defer: client.close()

      client.headers = newHttpHeaders({
        "Content-Type":  "application/json",
        "Authorization": "Bearer " & adapter.apiKey,
      })

      let body = buildRequestBody(adapter.model, req, stream = true)
      let url  = if adapter.endpoint.len > 0: adapter.endpoint else: DeepSeekEndpoint
      let resp = client.request(url, httpMethod = HttpPost, body = $body)

      if resp.status[0] != '2':
        return err("DeepSeek API error " & resp.status & ": " & resp.body)

      var accumulated = ""
      var inputTokens = 0
      var outputTokens = 0
      var line = ""
      while resp.bodyStream.readLine(line):
        let chunk = parseDeepSeekSseLine(line).valueOr:
          return err(error)
        if chunk.done:
          break
        if chunk.token.len > 0:
          accumulated.add(chunk.token)
          onToken(chunk.token)
        if chunk.inputTokens > 0:
          inputTokens = chunk.inputTokens
        if chunk.outputTokens > 0:
          outputTokens = chunk.outputTokens

      ok(CompletionResponse(
        text: accumulated,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
      ))
    except CatchableError as e:
      err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newDeepSeekAdapter*(apiKey:   string;
                         model    = DeepSeekDefaultModel;
                         endpoint = ""): DeepSeekAdapter =
  DeepSeekAdapter(
    apiKey:   apiKey,
    model:    model,
    endpoint: endpoint,
  )