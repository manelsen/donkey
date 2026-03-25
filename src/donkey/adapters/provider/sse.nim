## sse — SSE accumulation template for OpenAI-compatible streaming providers.
##
## Covers the standard pattern shared by Anthropic, OpenAI, OpenRouter, DeepSeek:
##   - loop over SSE lines
##   - propagate parse errors
##   - break on chunk.done
##   - accumulate token text and call onToken
##   - track inputTokens / outputTokens
##
## Ollama uses a different done/error model and is NOT covered here.

import std/streams
import ../../core/pipeops

template sseAccumulate*(stream: Stream; parseLine, onToken: untyped) =
  ## Standard SSE accumulation loop.
  ## Injects into calling scope: accumulated (string), inputTokens (int), outputTokens (int).
  ## parseLine: proc(string): Result[T, string] where T has .done, .token,
  ##   .inputTokens and .outputTokens fields.
  ## onToken: callable proc(tok: string) invoked for each non-empty token.
  var accumulated  {.inject.} = ""
  var inputTokens  {.inject.} = 0
  var outputTokens {.inject.} = 0
  var line = ""
  while stream.readLine(line):
    let chunk = parseLine(line).valueOr:
      return err(error)
    if chunk.done: break
    if chunk.token.len > 0:
      accumulated.add(chunk.token)
      onToken(chunk.token)
    if chunk.inputTokens > 0: inputTokens = chunk.inputTokens
    if chunk.outputTokens > 0: outputTokens = chunk.outputTokens
