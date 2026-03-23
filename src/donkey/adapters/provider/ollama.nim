## OllamaAdapter — ProviderPort for local Ollama inference.
##
## API endpoint: http://localhost:11434/api/chat  (configurable via baseUrl)
## Auth: none by default; optional Bearer token for remote instances.
## Format: Ollama-native /api/chat  (≠ OpenAI /v1/chat/completions)
##
## Quirks absorbed here:
##   - tool_calls.arguments is a JSON object, not a string — marshalled here
##   - tool_calls have no id — synthetic ids are generated ("ollama-<n>")
##   - Token counts are prompt_eval_count / eval_count (not prompt_tokens / completion_tokens)
##   - stream: false must be explicit (Ollama defaults to true)
##
## Pure wire-format helpers live in domain/providers/ollama_pure.nim.

import std/[httpclient, json, streams, strutils]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../../domain/providers/ollama_pure as opure

const
  OllamaDefaultBaseUrl* = "http://localhost:11434"
  OllamaDefaultModel*   = "llama3"

type
  OllamaAdapter* = object
    baseUrl*: string   ## e.g. "http://localhost:11434"; override for testing
    model*:   string
    apiKey*:  string   ## optional Bearer token for remote Ollama instances

  OllamaSseChunk* = object
    token*:        string
    done*:         bool
    inputTokens*:  int
    outputTokens*: int

# ── Constructor ───────────────────────────────────────────────────────────────

proc newOllamaAdapter*(model   = OllamaDefaultModel;
                       baseUrl = OllamaDefaultBaseUrl;
                       apiKey  = ""): OllamaAdapter =
  OllamaAdapter(model: model, baseUrl: baseUrl, apiKey: apiKey)

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: OllamaAdapter): ProviderCaps =
  ProviderCaps(
    name:              "ollama/" & a.model,
    streaming:         true,
    toolCalling:       true,
    nativeTools:       @[],
    maxContextTokens:  0,
    requiresUserFirst: false,
  )

# ── JSON serialisation ────────────────────────────────────────────────────────
## Uses pure helpers from domain/providers/ollama_pure.nim

proc buildBody*(a: OllamaAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing of JSON serialisation without live HTTP.
  opure.buildOllamaRequest(a.model, req, stream = false)

proc buildStreamBody*(a: OllamaAdapter; req: CompletionRequest): JsonNode =
  opure.buildOllamaRequest(a.model, req, stream = true)

# ── Response parsing ──────────────────────────────────────────────────────────
## Uses pure helpers from domain/providers/ollama_pure.nim

proc parseOllamaResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing of response parsing without live HTTP.
  ## Delegates to ollama_pure.parseOllamaResponse.
  opure.parseOllamaResponse j

proc parseOllamaSseLine*(line: string): Result[OllamaSseChunk, string] =
  let trimmed = line.strip()
  if trimmed.len == 0:
    return ok(OllamaSseChunk())
  let j = try: parseJson(trimmed) except CatchableError as e: return err(e.msg)
  let done  = j.getOrDefault("done").getBool(false)
  let msg   = j.getOrDefault("message")
  let token = if msg != nil: msg.getOrDefault("content").getStr("") else: ""
  ok(OllamaSseChunk(
    token:        token,
    done:         done,
    inputTokens:  j.getOrDefault("prompt_eval_count").getInt(0),
    outputTokens: j.getOrDefault("eval_count").getInt(0),
  ))

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: OllamaAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()

    var headers = @[("Content-Type", "application/json")]
    if a.apiKey.len > 0:
      headers.add(("Authorization", "Bearer " & a.apiKey))
    client.headers = newHttpHeaders(headers)

    let body = $a.buildBody(req)
    let url  = (if a.baseUrl.len > 0: a.baseUrl else: OllamaDefaultBaseUrl) & "/api/chat"
    let resp = client.post(url, body = body)

    if resp.status[0] != '2':
      return err("Ollama API error " & resp.status & ": " & resp.body)

    let parsed = parseJson(resp.body)
    ok(parseOllamaResponse(parsed))
  except CatchableError as e:
    err(e.msg)

# ── Streaming ─────────────────────────────────────────────────────────────────

proc makeStreamFn*(a: OllamaAdapter): StreamFn =
  ## Returns a StreamFn closure that performs SSE streaming via Ollama.
  let adapter = a
  result = proc(req: CompletionRequest;
                onToken: proc(tok: string) {.gcsafe.}
               ): Result[CompletionResponse, string] {.gcsafe.} =
    try:
      let client = newHttpClient()
      defer: client.close()

      var headers = @[("Content-Type", "application/json")]
      if adapter.apiKey.len > 0:
        headers.add(("Authorization", "Bearer " & adapter.apiKey))
      client.headers = newHttpHeaders(headers)

      let body = $adapter.buildStreamBody(req)
      let url  = (if adapter.baseUrl.len > 0: adapter.baseUrl else: OllamaDefaultBaseUrl) & "/api/chat"
      let resp = client.request(url, httpMethod = HttpPost, body = body)

      if resp.status[0] != '2':
        return err("Ollama API error " & resp.status & ": " & resp.body)

      var accumulated  = ""
      var inputTokens  = 0
      var outputTokens = 0
      var line = ""
      while streams.readLine(resp.bodyStream, line):
        let chunk = parseOllamaSseLine(line).valueOr: continue
        if chunk.token.len > 0:
          accumulated.add(chunk.token)
          onToken(chunk.token)
        if chunk.done:
          inputTokens  = chunk.inputTokens
          outputTokens = chunk.outputTokens
          break
      ok(CompletionResponse(
        text:         accumulated,
        inputTokens:  inputTokens,
        outputTokens: outputTokens,
      ))
    except CatchableError as e:
      err(e.msg)
