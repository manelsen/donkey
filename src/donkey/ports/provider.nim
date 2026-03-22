## ProviderPort — concept for LLM completion providers.
##
## Adapters: ZhipuAdapter (F1), OpenRouterAdapter, AnthropicAdapter,
##           MiniMaxAdapter, GeminiAdapter (F3).
##
## Each adapter absorbs its own quirks (auth headers, tool format, turn ordering).

import ../domain/message
import ../core/pipeops

type
  ProviderPrefs* = object
    providerName*: string
    modelName*:    string

  ProviderSpec* = object
    providerName*: string
    modelName*:    string
    apiKey*:       string

  ModelCatalogEntry* = object
    providerName*: string
    modelName*:    string
    label*:        string
    isFree*:       bool
    available*:    bool
    hasPricing*:   bool
    inputCostMicrosPer1k*: int
    outputCostMicrosPer1k*: int

  ModelCatalogSource* = enum
    mcsLive
    mcsCache
    mcsFallback

  ModelCatalogResult* = object
    entries*:      seq[ModelCatalogEntry]
    source*:       ModelCatalogSource
    fetchedAtUnix*: int64

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

  ProviderBundle* = object
    completeFn*: CompleteFn
    streamFn*:   StreamFn

  ProviderRuntimeBuilder* = proc(spec: ProviderSpec): ProviderBundle {.gcsafe.}
  ModelCatalogLoader* = proc(providerName: string): Result[ModelCatalogResult, string] {.gcsafe.}

  ProviderPort* = concept p
    p.complete(CompletionRequest) is CompletionResponse
    ## Blocking completion. Returns full response or raises on error.

    p.caps() is ProviderCaps
    ## Declare provider capabilities (pure metadata, no I/O).

func catalogSourceLabel*(source: ModelCatalogSource): string =
  case source
  of mcsLive: "live"
  of mcsCache: "cache"
  of mcsFallback: "fallback"

func relativeAgeText*(ageSec: int64): string =
  if ageSec <= 0: "agora"
  elif ageSec < 60: $ageSec & "s"
  elif ageSec < 3600: $(ageSec div 60) & "m"
  else: $(ageSec div 3600) & "h " & $((ageSec mod 3600) div 60) & "m"
