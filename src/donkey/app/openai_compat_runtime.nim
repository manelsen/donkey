## openai_compat_runtime.nim — the gateway's /v1/chat/completions reply.
##
## The endpoint is a provider proxy: it parses the OpenAI request, calls the
## instance completion function, and renders an OpenAI-shaped answer. It does
## not run the agent loop (tools, memory, sessions), which is why tools and
## streaming are rejected instead of half-supported.

import std/json
import ../core/pipeops
import ../domain/providers/openai_compat
import ../ports/provider

type
  OpenAiChatReply* = object
    status*: string  ## HTTP status line, e.g. "200 OK"
    body*:   string  ## JSON body

func errorReply(status, message, kind: string): OpenAiChatReply =
  OpenAiChatReply(
    status: status,
    body: $(%* {"error": {"message": message, "type": kind}}),
  )

proc chatReply*(body: string; completeFn: CompleteFn; model: string;
                nowSec: int64; id = ""): OpenAiChatReply =
  ## 503 without a completion function, 400 for a bad request, 502 when the
  ## provider fails, 200 with the OpenAI response otherwise.
  if completeFn == nil:
    return errorReply("503 Service Unavailable",
                      "no completion backend configured", "server_error")
  let parsed = parseOpenAiChatRequest(body)
  if parsed.isErr:
    return errorReply("400 Bad Request", parsed.error, "invalid_request_error")
  let response = completeFn(parsed.get())
  if response.isErr:
    return errorReply("502 Bad Gateway", response.error, "provider_error")
  let chosenId = if id.len > 0: id else: "chatcmpl-" & $nowSec
  let chosenModel = if model.len > 0: model else: "donkey/default"
  OpenAiChatReply(status: "200 OK",
                  body: buildOpenAiChatResponse(response.get(), chosenModel,
                                                chosenId, nowSec))
