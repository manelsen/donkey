## ZhipuAdapter — ProviderPort for Z.AI Coding (GLM series).
##
## API endpoint: https://api.z.ai/api/coding/paas/v4/chat/completions
## Auth: Bearer token via Authorization header
## Model: glm-4-flash (default) or configurable
##
## GLM quirks absorbed here:
##   - Native tools declared in caps(): web_search, code_interpreter
##   - Tool format differs from OpenAI: uses "type":"function" wrapper same as OAI
##     but native tools are passed as {"type":"web_search"} etc.
##   - No streaming in F1 (streaming added in F4)

import ../../domain/providers/cache_usage_pure
import std/[json]
import ../../domain/message
import ../../domain/providers/compat
import ../../domain/providers/openai_pure
import ../../ports/provider
import ../../core/pipeops
import ../../core/json_helpers
import ../../ports/http
import ./provider_http

const
  ZhipuEndpoint* = "https://api.z.ai/api/coding/paas/v4/chat/completions"
  ZaiGeneralEndpoint* = "https://api.z.ai/api/paas/v4/chat/completions"
  ZhipuDefaultModel* = "glm-4.7"

type
  ZhipuAdapter* = object
    apiKey*:   string
    http*:     HttpRuntimePort  ## nil → production provider transport
    model*:    string   ## defaults to ZhipuDefaultModel
    endpoint*: string   ## override for testing

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: ZhipuAdapter): ProviderCaps =
  ProviderCaps(
    name:             "zai-coding/" & a.model,
    streaming:        false,
    toolCalling:      true,
    nativeTools:      @["web_search", "code_interpreter"],
    maxContextTokens: 128_000,
    requiresUserFirst: false,
  )

# ── Compat profile ────────────────────────────────────────────────────────────

func zhipuCompatProfile*(endpoint = ZhipuEndpoint): CompatProfile =
  ## Z.AI / GLM expresses only its wire deviations: `thinking` when reasoning
  ## is requested, native tools, no `name` on tool results, `content: ""` on an
  ## assistant tool call, and no image envelope once the turn has tool calls.
  ## An empty endpoint means the default Z.AI coding endpoint, matching the
  ## adapter's `newZhipuAdapter` default.
  let resolved = if endpoint.len > 0: endpoint else: ZhipuEndpoint
  CompatProfile(
    id:             "zai-coding",
    endpoint:       resolved,
    supportsImages: true,
    quirks: OpenAiWireQuirks(
      toolResultName:        false,
      toolCallsEmptyContent: true,
      emptyContentKey: true,
      imageEmptyTextPart:    false,
      imageWithToolCalls:    false,
      toolChoiceAuto:        true,
      omitStreamKey:         true,
      includeReasoningField: false,
    ),
    reasoningExtras: %* {"thinking": {"type": "enabled"}},
  )

# ── JSON serialisation ────────────────────────────────────────────────────────

proc buildBody*(a: ZhipuAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing of JSON serialisation without live HTTP.
  buildCompatRequestBody(zhipuCompatProfile(a.endpoint), a.model, req)

func parseZhipuResponse*(parsed: JsonNode): Result[CompletionResponse, string] =
  let choices = parsed{"choices"}
  if choices.isNil or choices.kind != JArray or choices.len == 0:
    let errorMsg = parsed{"error"}{"message"}.getStr("")
    if errorMsg.len > 0:
      return err("Zhipu error: " & errorMsg)
    return err("Invalid Zhipu response: missing 'choices'")

  let msg   = choices[0]{"message"}
  if msg.isNil:
    return err("Invalid Zhipu response: missing 'message' in first choice")

  var reasoning = msg{"reasoning_content"}.getStr("")
  if reasoning.len == 0:
    reasoning = msg{"reasoning"}.getStr("")
  if reasoning.len == 0:
    reasoning = msg{"thought"}.getStr("")

  let usage = parsed.getOrDefault("usage")
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
      )

  ok CompletionResponse(
    text:         msg{"content"}.getStr(""),
    reasoning:    msg{"reasoning_content"}.getStr(""),
    inputTokens:  usage.jInt("prompt_tokens"),
    cacheReadTokens:  openAiUsage(usage).cacheRead,
    outputTokens: usage.jInt("completion_tokens"),
    toolCalls:    toolCalls,
  )

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: ZhipuAdapter; req: CompletionRequest): Result[CompletionResponse, string] =
  providerGuard:
    var headers: seq[HttpHeader] = @[("Content-Type", "application/json"), ("Authorization", "Bearer " & a.apiKey)]
    let body = $a.buildBody(req)
    let url  = if a.endpoint.len > 0: a.endpoint else: ZhipuEndpoint
    let resp = ? postProvider(a.http, "Zhipu", url, body, headers)
    resp |> parseJson |> parseZhipuResponse

# ── Constructor ───────────────────────────────────────────────────────────────

proc newZhipuAdapter*(apiKey: string;
                      model    = ZhipuDefaultModel;
                      endpoint = ""): ZhipuAdapter =
  ZhipuAdapter(apiKey: apiKey, model: model, endpoint: endpoint)

proc newZaiAdapter*(apiKey: string;
                    model    = ZhipuDefaultModel;
                    endpoint = ""): ZhipuAdapter =
  ZhipuAdapter(
    apiKey: apiKey,
    model: model,
    endpoint: if endpoint.len > 0: endpoint else: ZaiGeneralEndpoint,
  )

proc newZaiCodingAdapter*(apiKey: string;
                          model    = ZhipuDefaultModel): ZhipuAdapter =
  ZhipuAdapter(
    apiKey: apiKey,
    model: model,
    endpoint: ZhipuEndpoint,
  )
