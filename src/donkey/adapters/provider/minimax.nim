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

  if req.system.len > 0:
    result["bot_setting"] = %* [{"bot_name": "Donkey", "content": req.system}]

  if req.maxTokens > 0:
    result["tokens_to_generate"] = %req.maxTokens

# ── Response parsing ──────────────────────────────────────────────────────────

func parseMiniMaxResponse*(j: JsonNode): CompletionResponse =
  ## Exported for unit testing.
  let text  = j["choices"][0]["messages"][0]["text"].getStr("")
  let usage = j.getOrDefault("usage")
  CompletionResponse(
    text:         text,
    inputTokens:  usage.jInt("prompt_tokens"),
    outputTokens: usage.jInt("completion_tokens"),
  )

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
    resp.body |> parseJson |> parseMiniMaxResponse |> ok

# ── Constructor ───────────────────────────────────────────────────────────────

proc newMiniMaxAdapter*(apiKey:   string;
                        model    = MiniMaxDefaultModel;
                        endpoint = ""): MiniMaxAdapter =
  MiniMaxAdapter(apiKey: apiKey, model: model, endpoint: endpoint)
