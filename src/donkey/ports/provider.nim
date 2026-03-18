## ProviderPort — concept for LLM completion providers.
##
## Adapters: ZhipuAdapter (F1), OpenRouterAdapter, AnthropicAdapter,
##           MiniMaxAdapter, GeminiAdapter (F3).
##
## Each adapter absorbs its own quirks (auth headers, tool format, turn ordering).

import ../domain/message
import ../core/pipeops

type
  ProviderCaps* = object
    ## Static description of what a provider supports.
    name*:               string
    streaming*:          bool
    toolCalling*:        bool   ## supports tool use / function calling
    nativeTools*:        seq[string]  ## provider-managed tools (e.g. "web_search")
    maxContextTokens*:   int    ## 0 = unknown/unlimited
    requiresUserFirst*:  bool   ## Gemini: function response must follow model turn

  CompleteFn* = proc(req: CompletionRequest): Result[CompletionResponse, string] {.gcsafe.}
  ## Closure that wraps any adapter's complete() for use in AgentRunner.

  TokenCb* = proc(tok: string) {.gcsafe, raises: [].}
  ## Callback invoked for each SSE token during streaming.

  StreamFn* = proc(req: CompletionRequest; onToken: TokenCb): Result[CompletionResponse, string] {.gcsafe.}
  ## Blocking SSE streaming variant. Calls onToken for each token, returns full response.
  ## Run in an OS thread inside the orchestrator so it doesn't block the event loop.

  ProviderPort* = concept p
    p.complete(CompletionRequest) is Result[CompletionResponse, string]
    ## Blocking completion. Returns Result to propagate errors.

    p.caps() is ProviderCaps
    ## Declare provider capabilities (pure metadata, no I/O).
