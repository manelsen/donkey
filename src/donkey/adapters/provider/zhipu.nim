## ZhipuAdapter — ProviderPort for Zhipu AI (GLM series).
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

import std/[httpclient, json, strutils]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops

const
  ZhipuEndpoint* = "https://api.z.ai/api/coding/paas/v4/chat/completions"
  ZhipuDefaultModel* = "glm-4.7"

type
  ZhipuAdapter* = object
    apiKey*:   string
    model*:    string   ## defaults to ZhipuDefaultModel
    endpoint*: string   ## override for testing

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: ZhipuAdapter): ProviderCaps =
  ProviderCaps(
    name:             "zhipu/" & a.model,
    streaming:        false,
    toolCalling:      true,
    nativeTools:      @["web_search", "code_interpreter"],
    maxContextTokens: 128_000,
    requiresUserFirst: false,
  )

# ── JSON serialisation ────────────────────────────────────────────────────────

proc toJson(msg: ChatMessage): JsonNode =
  if msg.role == "tool":
    return %* {"role": "tool",
               "tool_call_id": msg.toolCallId,
               "content":      msg.text}
  if msg.toolCalls.len > 0:
    var calls = newJArray()
    for tc in msg.toolCalls:
      calls.add(%* {"id": tc.id, "type": "function",
                    "function": {"name": tc.name, "arguments": tc.inputJson}})
    return %* {"role": "assistant", "content": msg.text, "tool_calls": calls}
  %* {"role": msg.role, "content": msg.text}

proc buildBody*(a: ZhipuAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing of JSON serialisation without live HTTP.
  var messages: seq[JsonNode] = @[]
  if req.system.len > 0:
    messages.add(%* {"role": "system", "content": req.system})
  for m in req.messages:
    messages.add(m.toJson())
  result = %* {"model": a.model, "messages": messages}
  if req.maxTokens > 0:
    result["max_tokens"] = %req.maxTokens
  if req.tools.len > 0:
    var toolsArr = newJArray()
    for td in req.tools:
      let schema = try: parseJson(td.schemaJson) except: newJObject()
      toolsArr.add(%* {"type": "function",
                        "function": {"name":        td.name,
                                     "description": td.description,
                                     "parameters":  schema}})
    result["tools"]       = toolsArr
    result["tool_choice"] = %"auto"

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: ZhipuAdapter; req: CompletionRequest): Result[CompletionResponse, string] =
  try:
    let client = newHttpClient()
    defer: client.close()

    client.headers = newHttpHeaders({
      "Content-Type":  "application/json",
      "Authorization": "Bearer " & a.apiKey,
    })

    let body = $a.buildBody(req)
    let url  = if a.endpoint.len > 0: a.endpoint else: ZhipuEndpoint
    let resp = client.post(url, body = body)

    if resp.status[0] != '2':
      return err("Zhipu API error " & resp.status & ": " & resp.body)

    let parsed = parseJson(resp.body)
    let msg    = parsed["choices"][0]["message"]
    let usage  = parsed.getOrDefault("usage")
    var toolCalls: seq[ToolCallRequest] = @[]
    let tcs = msg.getOrDefault("tool_calls")
    if tcs != nil and tcs.kind == JArray:
      for tc in tcs:
        let fn = tc["function"]
        toolCalls.add ToolCallRequest(
          id:        tc["id"].getStr(""),
          name:      fn["name"].getStr(""),
          inputJson: fn["arguments"].getStr("{}"),
        )

    ok CompletionResponse(
      text:         msg.getOrDefault("content").getStr(""),
      inputTokens:  if usage != nil: usage["prompt_tokens"].getInt(0)    else: 0,
      outputTokens: if usage != nil: usage["completion_tokens"].getInt(0) else: 0,
      toolCalls:    toolCalls,
    )
  except CatchableError as e:
    err(e.msg)

# ── Constructor ───────────────────────────────────────────────────────────────

proc newZhipuAdapter*(apiKey: string;
                      model    = ZhipuDefaultModel;
                      endpoint = ""): ZhipuAdapter =
  ZhipuAdapter(apiKey: apiKey, model: model, endpoint: endpoint)
