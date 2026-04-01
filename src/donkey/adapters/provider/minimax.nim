## MiniMaxAdapter — ProviderPort for MiniMax AI.
##
## API endpoint: https://api.minimax.chat/v1/text/chatcompletion_pro
## Auth: Bearer token
## Default model: abab6.5s-chat
##
## Quirks absorbed here:
##   - Messages use `sender_type: "USER"|"BOT"` instead of role
##   - Messages have `text` field instead of `content`
##   - System prompt goes into `bot_setting` array (top-level field)
##   - Response: choices[0].messages[0].text
##   - No streaming in current API (streaming=false)
##   - No native tool calling (toolCalling=false)

import std/[httpclient, json]
import ../../domain/message
import ../../ports/provider
import ../../core/pipeops
import ../../core/json_helpers
import ../http/helpers

const
  MiniMaxEndpoint*     = "https://api.minimax.chat/v1/text/chatcompletion_pro"
  MiniMaxDefaultModel* = "abab6.5s-chat"

type
  MiniMaxAdapter* = object
    apiKey*:   string
    model*:    string
    endpoint*: string   ## override for testing

# ── Concept conformance ───────────────────────────────────────────────────────

proc caps*(a: MiniMaxAdapter): ProviderCaps =
  ProviderCaps(
    name:              "minimax/" & a.model,
    streaming:         false,
    toolCalling:       false,
    nativeTools:       @[],
    maxContextTokens:  245_760,
    requiresUserFirst: false,
  )

# ── Role mapping ──────────────────────────────────────────────────────────────

func miniMaxSenderType(role: string): string =
  ## Maps OpenAI-style roles to MiniMax sender_type.
  if role == roleAssistant: "BOT" else: "USER"

# ── JSON serialisation ────────────────────────────────────────────────────────

proc toJson(msg: ChatMessage): JsonNode =
  ## MiniMax message format: sender_type + text (not role + content).
  %* {"sender_type": miniMaxSenderType(msg.role), "text": msg.text}

proc buildBody*(a: MiniMaxAdapter; req: CompletionRequest): JsonNode =
  ## Exported for unit testing.
  var messages: seq[JsonNode] = @[]
  for m in req.messages:
    messages.add(m.toJson())

  result = %* {"model": a.model, "messages": messages}
  if req.reasoning:
    result["reasoning_split"] = %true

  if req.system.len > 0:
    result["bot_setting"] = %* [{"bot_name": "Donkey", "content": req.system}]

  if req.maxTokens > 0:
    result["tokens_to_generate"] = %req.maxTokens

# ── Response parsing ──────────────────────────────────────────────────────────

func parseMiniMaxResponse*(j: JsonNode): Result[CompletionResponse, string] =
  ## Exported for unit testing.
  ## Handles multiple MiniMax response formats:
  ##   - v1 (legacy): choices[0].messages[0].text
  ##   - v2 (new):    choices[0].message.content  (OpenAI-compatible)
  ##   - error:       base_resp.status_msg or resp.status_msg

  # Check for error responses first
  for errKey in ["base_resp", "resp"]:
    let errNode = j{errKey}
    if not errNode.isNil:
      let status = errNode{"status_code"}.getInt(0)
      let msg = errNode{"status_msg"}.getStr("")
      if status != 0 or msg.len > 0:
        return err("MiniMax error: " & msg & " (code " & $status & ")")

  # Check for top-level error field (some versions)
  let topErr = j{"error"}
  if not topErr.isNil:
    let errMsg = topErr{"message"}.getStr(topErr.getStr(""))
    if errMsg.len > 0:
      return err("MiniMax error: " & errMsg)

  let choices = j{"choices"}
  if choices.isNil or choices.kind != JArray or choices.len == 0:
    return err("Invalid MiniMax response: missing 'choices'")

  let choice = choices[0]

  # Format 1 (legacy): choices[0].messages[0].text
  let messages = choice{"messages"}
  if not messages.isNil and messages.kind == JArray and messages.len > 0:
    let msgNode = messages[0]
    let text    = msgNode{"text"}.getStr("")
    var reasoning = msgNode{"reasoning_content"}.getStr("")
    if reasoning.len == 0:
      let details = msgNode{"reasoning_details"}
      if details != nil and details.kind == JArray:
        for d in details:
          reasoning &= d{"text"}.getStr("")
    let usage = j.getOrDefault("usage")
    return ok CompletionResponse(
      text:         text,
      reasoning:    reasoning,
      inputTokens:  usage.jInt("prompt_tokens"),
      outputTokens: usage.jInt("completion_tokens"),
    )

  # Format 2 (OpenAI-compatible): choices[0].message.content
  let msg = choice{"message"}
  if not msg.isNil:
    let text = msg{"content"}.getStr("")
    let usage = j.getOrDefault("usage")
    return ok CompletionResponse(
      text:         text,
      reasoning:    "",
      inputTokens:  usage.jInt("prompt_tokens"),
      outputTokens: usage.jInt("completion_tokens"),
    )

  err("Invalid MiniMax response: unrecognized choice format")

# ── HTTP call ─────────────────────────────────────────────────────────────────

proc complete*(a: MiniMaxAdapter;
               req: CompletionRequest): Result[CompletionResponse, string] =
  withHttpClient:
    client.headers = newHttpHeaders({
      "Content-Type":  "application/json",
      "Authorization": "Bearer " & a.apiKey,
    })
    let body = $a.buildBody(req)
    let url  = if a.endpoint.len > 0: a.endpoint else: MiniMaxEndpoint
    let resp = client.post(url, body = body)
    checkApiStatus(resp, "MiniMax")
    resp.body |> parseJson |> parseMiniMaxResponse

# ── Constructor ───────────────────────────────────────────────────────────────

proc newMiniMaxAdapter*(apiKey:   string;
                        model    = MiniMaxDefaultModel;
                        endpoint = ""): MiniMaxAdapter =
  MiniMaxAdapter(apiKey: apiKey, model: model, endpoint: endpoint)
