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
##
## The wire format itself lives in the shared compat transport; this adapter
## only builds the MiniMax profile (endpoint + `reasoning_split`).

import std/[json]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../../ports/http
import ./provider_http
import ../../domain/providers/compat
import ../../domain/providers/openai_pure

const
  MiniMaxEndpoint*     = "https://api.minimax.io/v1/chat/completions"
  MiniMaxDefaultModel* = "MiniMax-M2.7"

type
  MiniMaxAdapter* = object
    apiKey*:   string
    http*:     HttpRuntimePort  ## nil → production provider transport
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

# ── Compat profile ────────────────────────────────────────────────────────────

func miniMaxCompatProfile*(endpoint = MiniMaxEndpoint): CompatProfile =
  ## MiniMax speaks plain OpenAI chat/completions. `reasoning_split: true` is
  ## unconditional: it keeps thinking out of `content` and in the reasoning
  ## details, as the previous local builder did.
  CompatProfile(
    id: "minimax",
    endpoint: endpoint,
    payloadExtras: %* {"reasoning_split": true},
    supportsImages: true,
    quirks: OpenAiWireQuirks(
      toolResultName: false,
      toolCallsEmptyContent: true,
      emptyContentKey: true,
      imageEmptyTextPart: false,
      imageWithToolCalls: false,
      toolChoiceAuto: false,
      omitStreamKey: true,
      includeReasoningField: false,
    ),
  )

# ── Request serialisation (shared OpenAI-compatible transport) ────────────────

proc buildBody*(a: MiniMaxAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  let endpoint = if a.endpoint.len > 0: a.endpoint else: MiniMaxEndpoint
  buildCompatRequestBody(miniMaxCompatProfile(endpoint), a.model, req)

# ── Response parsing (reuse OpenAI parser) ────────────────────────────────────

proc parseMiniMaxResponse*(j: JsonNode): Result[CompletionResponse, string] =
  ## Exported for unit testing.
  ## MiniMax uses OpenAI-compatible format, so we reuse the OpenAI parser.
  try:
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
  except CatchableError as e:
    err("Invalid MiniMax response: " & e.msg)

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: MiniMaxAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  providerGuard:
    var headers: seq[HttpHeader] = @[("Content-Type", "application/json"), ("Authorization", "Bearer " & a.apiKey)]
    let body = $a.buildBody(req)
    let url  = if a.endpoint.len > 0: a.endpoint else: MiniMaxEndpoint
    let resp = ? postProvider(a.http, "MiniMax", url, body, headers)
    resp |> parseJson |> parseMiniMaxResponse

# ── Constructor ───────────────────────────────────────────────────────────────

proc newMiniMaxAdapter*(apiKey:   string;
                        model    = MiniMaxDefaultModel;
                        endpoint = ""): MiniMaxAdapter =
  MiniMaxAdapter(apiKey: apiKey, model: model, endpoint: endpoint)
