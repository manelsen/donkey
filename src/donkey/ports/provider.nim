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
    baseUrl*:      string   ## the descriptor's `baseUrlEnv` override, read
                            ## on the loop; empty means the descriptor's URL

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

func withApiKey*(spec: ProviderSpec; key: string): ProviderSpec =
  ## Same provider/model with another credential, for an in-flight retry.
  result = spec
  result.apiKey = key

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
                     {.gcsafe, raises: [].}
    ## Never raises: a failure is an `err`. Built from an adapter by
    ## `makeFn`, which is where an adapter's exception stops.

  ## StreamFn — like CompleteFn but streams tokens via a callback.
  ## nil means streaming is not available for this provider.
  StreamFn* = proc(req: CompletionRequest;
                   onToken: proc(tok: string) {.gcsafe.}
                  ): Result[CompletionResponse, string]
                     {.gcsafe.}

  StreamBuilder* = proc(credential: string): StreamFn {.gcsafe, nimcall.}

  StreamFactory* = object
    ## Builds a fresh StreamFn. Streaming runs on its own thread and calls
    ## `build` there, so the provider closure is built, used and freed on
    ## that thread alone: ORC counts references without atomics, and a
    ## closure shared with the event loop could be freed twice. `nimcall`
    ## forbids the builder from capturing loop state; what it needs (the API
    ## key) travels as plain data in `credential`, read on the loop from the
    ## environment snapshot. No builder means streaming is not available.
    build*:      StreamBuilder
    credential*: string

  ProviderBundle* = object
    completeFn*: CompleteFn
    streamFn*:   StreamFn

  ProviderRuntimeBuilder* = proc(spec: ProviderSpec): ProviderBundle
    {.gcsafe, nimcall.}
    ## `nimcall` is deliberate: the executor calls this builder on the event
    ## loop and moves the resulting bundle to a worker. Forbidding closures
    ## guarantees the builder cannot share an environment with the worker or
    ## with another in-flight call.
  ModelCatalogLoader* = proc(providerName: string): Result[ModelCatalogResult, string] {.gcsafe.}

  ProviderPort* = concept p
    p.complete(CompletionRequest) is Result[CompletionResponse, string]
    ## Blocking completion. Returns Result to propagate errors.

    p.caps() is ProviderCaps
    ## Declare provider capabilities (pure metadata, no I/O).

func available*(factory: StreamFactory): bool =
  ## Whether streaming can run with this factory.
  factory.build != nil

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
