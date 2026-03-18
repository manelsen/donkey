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

  ## CompleteFn — a closure wrapping any adapter's complete() call.
  ## Allows passing providers as values without generics at call sites.
  CompleteFn* = proc(req: CompletionRequest): Result[CompletionResponse, string]
                     {.gcsafe.}

  ## StreamFn — like CompleteFn but streams tokens via a callback.
  ## nil means streaming is not available for this provider.
  StreamFn* = proc(req: CompletionRequest;
                   onToken: proc(tok: string) {.gcsafe.}
                  ): Result[CompletionResponse, string]
                     {.gcsafe.}

  ProviderPort* = concept p
    p.complete(CompletionRequest) is CompletionResponse
    ## Blocking completion. Returns full response or raises on error.

    p.caps() is ProviderCaps
    ## Declare provider capabilities (pure metadata, no I/O).
