import ../../config/environment
import std/[algorithm, json, math, options, os, strutils, tables, times]
import ../../domain/providers/descriptors
import ../../ports/provider
import ../../ports/http
import ../http/std_http
import ../../core/pipeops
import ../../core/providers/provider_defaults
import ../../core/providers/smart_routing
import openrouter
import anthropic

const
  ## Endpoints that are NOT derivable from the descriptor chat URL, so they stay
  ## explicit: `/models` is a sibling resource with a provider-specific path
  ## (Gemini's collection is `/v1beta/models`, z.ai's is `.../models`, Ollama
  ## lists `/api/tags`). Model lists below are hand-curated because models.dev
  ## does not carry every aggregator/free variant; only env names and the Ollama
  ## base URL come from the descriptor table.
  OpenRouterModelsEndpoint = "https://openrouter.ai/api/v1/models"
  GroqModelsEndpoint = "https://api.groq.com/openai/v1/models"
  AnthropicModelsEndpoint = "https://api.anthropic.com/v1/models"
  GeminiModelsEndpoint = "https://generativelanguage.googleapis.com/v1beta/models"
  ModelsDevEndpoint = "https://models.dev/api.json"

type
  CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.}

func catalogEnvValue(env: Environment; id: string): string =
  ## First non-empty credential/base-URL env for the provider, in descriptor
  ## order. Aliases resolve through the same table as the runtime builder.
  for envName in descriptorOr(id).envNames:
    let value = env.get(envName)
    if value.len > 0:
      return value
  ""

func sortCatalog(entries: seq[ModelCatalogEntry]): seq[ModelCatalogEntry] =
  result = entries
  result.sort(proc(a, b: ModelCatalogEntry): int =
    if a.isFree != b.isFree:
      return if a.isFree: -1 else: 1
    cmp(a.label.toLowerAscii(), b.label.toLowerAscii())
  )

func catalogResult(entries: seq[ModelCatalogEntry];
                   source: ModelCatalogSource;
                   fetchedAtUnix: int64): ModelCatalogResult =
  ModelCatalogResult(entries: entries, source: source, fetchedAtUnix: fetchedAtUnix)

func staticCatalog(providerName: string): seq[ModelCatalogEntry] =
  case providerName
  of "openrouter":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "openai/gpt-6.1-sol", label: "openai/gpt-6.1-sol", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "openai/gpt-6-astra", label: "openai/gpt-6-astra", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "openai/gpt-6.1-terra", label: "openai/gpt-6.1-terra", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "openai/gpt-6-luna", label: "openai/gpt-6-luna", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "anthropic/claude-opus-5-5", label: "anthropic/claude-opus-5-5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "anthropic/claude-sonnet-5-5", label: "anthropic/claude-sonnet-5-5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "deepseek/deepseek-4.1-flash", label: "deepseek/deepseek-4.1-flash", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "deepseek/deepseek-v4-pro", label: "deepseek/deepseek-v4-pro", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "google/gemini-3.8-flash", label: "google/gemini-3.8-flash", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "google/gemini-4-argon", label: "google/gemini-4-argon", isFree: false, available: true),
    ]
  of "openai":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "gpt-6.1-sol", label: "gpt-6.1-sol", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gpt-6-astra", label: "gpt-6-astra", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gpt-6.1-terra", label: "gpt-6.1-terra", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gpt-6-luna", label: "gpt-6-luna", isFree: false, available: true),
    ]
  of "deepseek":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "deepseek-4.1-flash", label: "deepseek-4.1-flash", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "deepseek-v4-pro", label: "deepseek-v4-pro", isFree: false, available: true),
    ]
  of "groq":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "llama-3.3-70b-versatile", label: "llama-3.3-70b-versatile", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "llama-3.1-8b-instant", label: "llama-3.1-8b-instant", isFree: true, available: true, hasPricing: true),
    ]
  of "opencode-go", "opencode":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "deepseek-4.1-flash", label: "deepseek-4.1-flash", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "deepseek-v4-pro", label: "deepseek-v4-pro", isFree: false, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "claude-sonnet-5-5", label: "claude-sonnet-5-5", isFree: false, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gpt-6.1-sol", label: "gpt-6.1-sol", isFree: false, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "kimi-k3.1-pro", label: "kimi-k3.1-pro", isFree: false, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-5.3", label: "glm-5.3", isFree: true, available: true, hasPricing: true),
    ]
  of "zen", "opencode-zen":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "deepseek-4.1-flash", label: "deepseek-4.1-flash", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "deepseek-v4-pro", label: "deepseek-v4-pro", isFree: false, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gpt-6.1-sol", label: "gpt-6.1-sol", isFree: false, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "claude-sonnet-5-5", label: "claude-sonnet-5-5", isFree: false, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "claude-opus-5-5", label: "claude-opus-5-5", isFree: false, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-5.1", label: "glm-5.1", isFree: false, available: true, hasPricing: true),
    ]
  of "anthropic":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "claude-sonnet-5-5", label: "claude-sonnet-5-5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "claude-opus-5-5", label: "claude-opus-5-5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "claude-fable-5-2", label: "claude-fable-5-2", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "claude-haiku-5-5", label: "claude-haiku-5-5", isFree: false, available: true),
    ]
  of "gemini":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "gemini-3.8-flash", label: "gemini-3.8-flash", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gemini-4-argon", label: "gemini-4-argon", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gemini-3.1-pro", label: "gemini-3.1-pro", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gemini-3.5-flash-lite", label: "gemini-3.5-flash-lite", isFree: true, available: true),
    ]
  of "minimax":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "MiniMax-M2", label: "MiniMax-M2", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "MiniMax-M2.5", label: "MiniMax-M2.5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "MiniMax-M2.7", label: "MiniMax-M2.7", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "MiniMax-M2.7-highspeed", label: "MiniMax-M2.7-highspeed", isFree: false, available: true),
    ]
  of "zai", "zai-coding":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "glm-5.1", label: "glm-5.1", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-5", label: "glm-5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-4.7", label: "glm-4.7", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-4.6", label: "glm-4.6", isFree: false, available: true),
    ]
  of "zai-anthropic":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "glm-4.7", label: "glm-4.7", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-4.6", label: "glm-4.6", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-4.5", label: "glm-4.5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-4.5-air", label: "glm-4.5-air", isFree: false, available: true),
    ]
  of "nvidia", "nvidia-nim", "nim", "build-nvidia":
    @[
      ModelCatalogEntry(providerName: providerName,
                        modelName: DefaultModelNvidia,
                        label: "nvidia/nemotron-3.5-super-vl-120b-a12b",
                        isFree: false, available: true, hasPricing: false),
    ]
  of "mistral", "mistralai", "mistral-ai":
    @[
      ModelCatalogEntry(providerName: providerName,
                        modelName: DefaultModelMistral,
                        label: DefaultModelMistral,
                        isFree: false, available: true, hasPricing: false),
    ]
  of "fireworks", "fireworks-ai", "fw":
    @[
      ModelCatalogEntry(providerName: providerName,
                        modelName: DefaultModelFireworks,
                        label: DefaultModelFireworks,
                        isFree: false, available: true, hasPricing: false),
    ]
  of "alibaba", "dashscope", "alibaba-cloud", "aliyun":
    @[
      ModelCatalogEntry(providerName: providerName,
                        modelName: DefaultModelAlibaba,
                        label: "qwen3.8-max",
                        isFree: false, available: true, hasPricing: false),
    ]
  of "ollama":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "llama3.3", label: "llama3.3", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "llama4:scout", label: "llama4:scout", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "qwen2.5-coder", label: "qwen2.5-coder", isFree: true, available: true, hasPricing: true),
    ]
  else:
    @[]

func fallbackCatalog(providerName: string): ModelCatalogResult =
  catalogResult(staticCatalog(providerName), mcsFallback, 0)

func defaultCatalogHttp(): HttpRuntimePort =
  newStdHttpAdapter().toRuntimePort()

proc httpGetCatalog(http: HttpRuntimePort; url: string;
                    headers: seq[(string, string)]): Result[string, string] =
  ## Fetches catalog JSON through the injected HTTP port.
  var httpHeaders: seq[HttpHeader] = @[]
  for (name, value) in headers:
    httpHeaders.add((name: name, value: value))
  let response = http.get(url, httpHeaders)
  if response.isErr:
    return err(response.error)
  if response.get().status < 200 or response.get().status >= 300:
    return err("HTTP " & $response.get().status)
  ok(response.get().body)

proc parseCatalogJson(body: string; parser: CatalogParser): Result[ModelCatalogResult, string] =
  ## Parses JSON body and wraps entries in ModelCatalogResult.
  let root = try:
    parseJson(body)
  except CatchableError as e:
    return err("invalid catalog JSON: " & e.msg)
  let parsed = parser(root)
  if parsed.isErr:
    return err(parsed.error)
  
  if parsed.value.len > 0:
    ok(catalogResult(parsed.value.sortCatalog(), mcsLive, getTime().toUnix()))
  else:
    err("no models found")

proc fetchHttpCatalog(http: HttpRuntimePort; url: string;
                      headers: seq[(string, string)];
                      parser: CatalogParser): Result[ModelCatalogResult, string] =
  ## Fetches model catalog from HTTP REST API.
  ## Composes: httpGetCatalog |> parseCatalogJson
  let body = httpGetCatalog(http, url, headers)
  if body.isErr:
    return err(body.error)
  
  parseCatalogJson(body.get(), parser)

proc fetchWithApiKey(http: HttpRuntimePort; url: string; apiKey: string;
                     parser: CatalogParser;
                     headers: seq[(string, string)] = @[]): Result[ModelCatalogResult, string] =
  ## Helper para APIs que usam API Key no header Authorization.
  if apiKey.len == 0:
    return err("API key required")
  
  var allHeaders = @[("Authorization", "Bearer " & apiKey)]
  for h in headers:
    allHeaders.add(h)
  
  fetchHttpCatalog(http, url, allHeaders, parser)

proc fetchWithQueryParam(http: HttpRuntimePort; url: string;
                         queryParam: string; queryValue: string;
                         parser: CatalogParser): Result[ModelCatalogResult, string] =
  ## Helper para APIs que usam chave como query param.
  let fullUrl = url & (if "?" in url: "&" else: "?") & queryParam & "=" & queryValue
  fetchHttpCatalog(http, fullUrl, @[], parser)

proc loadModelsDevCatalog(http: HttpRuntimePort): Result[ModelCatalogResult, string] =
  ## Carrega catálogo do models.dev (catálogo aberto mantido pela comunidade).
  ## Formato: { "provider-id": { "name": "...", "models": { "model-id": { ... } } } }
  let response = http.get(ModelsDevEndpoint, @[(name: "Accept", value: "application/json")])
  if response.isErr:
    return err(response.error)
  if response.get().status < 200 or response.get().status >= 300:
    return err("models.dev returned status " & $response.get().status)
  try:
    let root = parseJson(response.get().body)
    if root.kind != JObject:
      return err("models.dev response is not an object")

    # Provider key → internal name. Only canonical keys to avoid duplicates.
    const providerMap = {
      "minimax": "minimax",
      "zhipu-coding": "zai-coding",
      "openrouter": "openrouter",
      "openai": "openai",
      "groq": "groq",
      "anthropic": "anthropic",
      "google": "gemini",
      "deepseek": "deepseek",
      "qwen": "alibaba",
    }.toTable()

    var entries: seq[ModelCatalogEntry] = @[]
    var seen: seq[string] = @[]  # for dedup

    for providerKey, providerNode in root:
      let internalProvider = providerMap.getOrDefault(providerKey.toLowerAscii())
      if internalProvider.len == 0:
        continue

      let modelsNode = providerNode.getOrDefault("models")
      if modelsNode.isNil or modelsNode.kind != JObject:
        continue

      for modelId, modelData in modelsNode:
        # Dedup: skip if already added for this provider
        let key = internalProvider & "/" & modelId
        if key in seen:
          continue
        seen.add(key)

        # isFree only when pricing is explicitly zero (not when null/missing)
        let pricingNode = modelData.getOrDefault("pricing")
        var isFree = false
        var hasPricing = false
        if not pricingNode.isNil and pricingNode.kind == JObject:
          hasPricing = true
          let inputCost = pricingNode.getOrDefault("input").getFloat(-1.0)
          let outputCost = pricingNode.getOrDefault("output").getFloat(-1.0)
          isFree = inputCost == 0.0 and outputCost == 0.0

        entries.add(ModelCatalogEntry(
          providerName: internalProvider,
          modelName: modelId,
          label: modelData.getOrDefault("name").getStr(modelId),
          isFree: isFree,
          available: true,
          hasPricing: hasPricing,
        ))

    if entries.len > 0:
      return ok(catalogResult(entries.sortCatalog(), mcsLive, getTime().toUnix()))
    else:
      return err("models.dev returned no entries for supported providers")
  except CatchableError as e:
    err(e.msg)

func parseCostMicrosPer1k(costStr: string): int =
  ## Parses a per-token USD cost string (e.g. "0.0000001") to micros per 1k tokens.
  if costStr.len == 0: return 0
  try:
    (costStr.parseFloat() * 1_000_000_000).round.int
  except CatchableError:
    0

proc parseOpenRouterCatalog*(body: string): Result[seq[ModelCatalogEntry], string] =
  try:
    let parsed = parseJson(body)
    let data = parsed.getOrDefault("data")
    if data == nil or data.kind != JArray:
      return err("openrouter models missing data")
    var entries: seq[ModelCatalogEntry] = @[]
    for item in data:
      let modelId = item.getOrDefault("id").getStr("")
      if modelId.len == 0:
        continue
      let pricing = item.getOrDefault("pricing")
      let promptCost = if pricing != nil: pricing.getOrDefault("prompt").getStr("") else: ""
      let completionCost = if pricing != nil: pricing.getOrDefault("completion").getStr("") else: ""
      let isFree = modelId.endsWith(":free") or
        ((promptCost == "0" or promptCost == "0.0") and (completionCost == "0" or completionCost == "0.0"))
      let inputCostMicrosPer1k = parseCostMicrosPer1k(promptCost)
      let outputCostMicrosPer1k = parseCostMicrosPer1k(completionCost)
      entries.add(ModelCatalogEntry(
        providerName: "openrouter",
        modelName: modelId,
        label: item.getOrDefault("name").getStr(modelId),
        isFree: isFree,
        available: true,
        hasPricing: promptCost.len > 0 or completionCost.len > 0,
        inputCostMicrosPer1k: inputCostMicrosPer1k,
        outputCostMicrosPer1k: outputCostMicrosPer1k,
      ))
    ok(entries.sortCatalog())
  except CatchableError as e:
    err(e.msg)

func modelLooksFree(modelId, label: string): bool =
  let lowerId = modelId.toLowerAscii()
  let lowerLabel = label.toLowerAscii()
  lowerId.endsWith(":free") or lowerId.endsWith("-free") or
    lowerLabel.endsWith(":free") or lowerLabel.endsWith("-free") or
    lowerId.contains(".free") or lowerLabel.contains(".free")

func normalizedListModelId(rawId: string): string =
  if rawId.startsWith("models/"):
    rawId["models/".len .. ^1]
  else:
    rawId

func extractModelArray(parsed: JsonNode): JsonNode =
  let data = parsed.getOrDefault("data")
  if data != nil:
    if data.kind == JArray:
      return data
    if data.kind == JObject:
      let dataModels = data.getOrDefault("models")
      if dataModels != nil and dataModels.kind == JArray:
        return dataModels
      let dataList = data.getOrDefault("list")
      if dataList != nil and dataList.kind == JArray:
        return dataList
      let dataItems = data.getOrDefault("items")
      if dataItems != nil and dataItems.kind == JArray:
        return dataItems
  for key in ["models", "list", "items"]:
    let candidate = parsed.getOrDefault(key)
    if candidate != nil and candidate.kind == JArray:
      return candidate
  nil

proc parseSimpleListCatalog*(providerName, body: string): Result[seq[ModelCatalogEntry], string] =
  try:
    let parsed = parseJson(body)
    let data = extractModelArray(parsed)
    if data == nil or data.kind != JArray:
      return err(providerName & " models missing data")
    var entries: seq[ModelCatalogEntry] = @[]
    for item in data:
      if item.kind != JObject:
        continue
      var modelId = item.getOrDefault("id").getStr("")
      if modelId.len == 0:
        modelId = item.getOrDefault("model").getStr("")
      if modelId.len == 0:
        modelId = item.getOrDefault("name").getStr("")
      modelId = normalizedListModelId(modelId)
      if modelId.len == 0:
        continue
      let rawLabel =
        block:
          let displayName = item.getOrDefault("display_name").getStr("")
          if displayName.len > 0: displayName
          else:
            let camelDisplay = item.getOrDefault("displayName").getStr("")
            if camelDisplay.len > 0: camelDisplay
            else:
              let itemName = item.getOrDefault("name").getStr("")
              if itemName.len > 0 and itemName != modelId:
                normalizedListModelId(itemName)
              else:
                modelId
      let label = if rawLabel.len > 0: rawLabel else: modelId
      entries.add(ModelCatalogEntry(
        providerName: providerName,
        modelName: modelId,
        label: label,
        isFree: modelLooksFree(modelId, label),
        available: true,
      ))
    ok(entries.sortCatalog())
  except CatchableError as e:
    err(e.msg)

proc loadRouteCostHints*(
    providerNames: seq[string]): seq[RouteCostHint] {.gcsafe.} =
  for providerName in providerNames:
    let catalog =
      block:
        fallbackCatalog(providerName)
    for entry in catalog.entries:
      if entry.hasPricing or entry.isFree:
        result.add(RouteCostHint(
          route: entry.providerName & "/" & entry.modelName,
          hasPricing: entry.hasPricing or entry.isFree,
          inputCostMicrosPer1k: entry.inputCostMicrosPer1k,
          outputCostMicrosPer1k: entry.outputCostMicrosPer1k,
        ))

proc parseAnthropicCatalog(body: string): Result[seq[ModelCatalogEntry], string] =
  try:
    let parsed = parseJson(body)
    let data = parsed.getOrDefault("data")
    if data == nil or data.kind != JArray:
      return err("anthropic models missing data")
    var entries: seq[ModelCatalogEntry] = @[]
    for item in data:
      let modelId = item.getOrDefault("id").getStr("")
      if modelId.len == 0:
        continue
      entries.add(ModelCatalogEntry(
        providerName: "anthropic",
        modelName: modelId,
        label: item.getOrDefault("display_name").getStr(modelId),
        isFree: false,
        available: true,
      ))
    ok(entries.sortCatalog())
  except CatchableError as e:
    err(e.msg)

proc parseGeminiCatalog(body: string): Result[seq[ModelCatalogEntry], string] =
  try:
    let parsed = parseJson(body)
    let models = parsed.getOrDefault("models")
    if models == nil or models.kind != JArray:
      return err("gemini models missing models")
    var entries: seq[ModelCatalogEntry] = @[]
    for item in models:
      let methods = item.getOrDefault("supportedGenerationMethods")
      var supportsGenerate = false
      if methods != nil and methods.kind == JArray:
        for supportedMethod in methods:
          if supportedMethod.getStr("") == "generateContent":
            supportsGenerate = true
      if not supportsGenerate:
        continue
      var modelId = item.getOrDefault("name").getStr("")
      if modelId.startsWith("models/"):
        modelId = modelId["models/".len .. ^1]
      if modelId.len == 0:
        continue
      entries.add(ModelCatalogEntry(
        providerName: "gemini",
        modelName: modelId,
        label: item.getOrDefault("displayName").getStr(modelId),
        isFree: false,
        available: true,
      ))
    ok(entries.sortCatalog())
  except CatchableError as e:
    err(e.msg)

proc loadOpenRouterCatalog(apiKey: string; http: HttpRuntimePort): Result[ModelCatalogResult, string] =
  let headers =
    if apiKey.len > 0:
      @[("Authorization", "Bearer " & apiKey),
        ("HTTP-Referer", OpenRouterReferer),
        ("X-Title", OpenRouterTitle)]
    else:
      @[("HTTP-Referer", OpenRouterReferer), ("X-Title", OpenRouterTitle)]
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseOpenRouterCatalog($json)
  
  fetchHttpCatalog(http, OpenRouterModelsEndpoint, headers, parser)

proc loadGroqCatalog(apiKey: string; http: HttpRuntimePort): Result[ModelCatalogResult, string] =
  if apiKey.len == 0:
    return ok(fallbackCatalog("groq"))
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseSimpleListCatalog("groq", $json)
  
  fetchWithApiKey(http, GroqModelsEndpoint, apiKey, parser)

proc loadAnthropicCatalog(apiKey: string; http: HttpRuntimePort): Result[ModelCatalogResult, string] =
  if apiKey.len == 0:
    return ok(fallbackCatalog("anthropic"))
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseAnthropicCatalog($json)
  
  fetchWithApiKey(http, AnthropicModelsEndpoint, apiKey, parser, @[
    ("x-api-key", apiKey),
    ("anthropic-version", AnthropicVersion),
  ])

proc loadGeminiCatalog(apiKey: string; http: HttpRuntimePort): Result[ModelCatalogResult, string] =
  if apiKey.len == 0:
    return ok(fallbackCatalog("gemini"))
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseGeminiCatalog($json)
  
  fetchWithQueryParam(http, GeminiModelsEndpoint, "key", apiKey, parser)

proc loadZaiCatalog(apiKey: string;
                    providerName: string;
                    codingEndpoint: bool;
                    http: HttpRuntimePort): Result[ModelCatalogResult, string] =
  if apiKey.len == 0:
    return ok(fallbackCatalog(providerName))
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseSimpleListCatalog(providerName, $json)
  
  let base =
    if codingEndpoint: "https://api.z.ai/api/coding/paas/v4/models"
    else: "https://api.z.ai/api/paas/v4/models"
  
  fetchWithApiKey(http, base, apiKey, parser)

proc loadOpencodeGoCatalog(apiKey: string; http: HttpRuntimePort): Result[ModelCatalogResult, string] =
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseSimpleListCatalog("opencode-go", $json)
  if apiKey.len == 0:
    return ok(fallbackCatalog("opencode-go"))
  fetchWithApiKey(http, "https://opencode.ai/zen/go/v1/models", apiKey, parser)

proc loadZenCatalog(http: HttpRuntimePort; apiKey = ""): Result[ModelCatalogResult, string] =
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseSimpleListCatalog("zen", $json)
  if apiKey.len == 0:
    fetchHttpCatalog(http, "https://opencode.ai/zen/v1/models", @[], parser)
  else:
    fetchWithApiKey(http, "https://opencode.ai/zen/v1/models", apiKey, parser)

proc parseOllamaTagsCatalog*(body: string): Result[seq[ModelCatalogEntry], string] =
  try:
    let parsed = parseJson(body)
    let models = parsed.getOrDefault("models")
    if models == nil or models.kind != JArray:
      return err("ollama /api/tags missing models array")
    var entries: seq[ModelCatalogEntry] = @[]
    for item in models:
      var modelName = item.getOrDefault("name").getStr("")
      if modelName.len == 0:
        modelName = item.getOrDefault("model").getStr("")
      if modelName.len == 0:
        continue
      entries.add(ModelCatalogEntry(
        providerName: "ollama",
        modelName: modelName,
        label: modelName,
        isFree: true,
        available: true,
        hasPricing: true,
        inputCostMicrosPer1k: 0,
        outputCostMicrosPer1k: 0,
      ))
    ok(entries.sortCatalog())
  except CatchableError as e:
    err(e.msg)

proc loadOllamaCatalog(baseUrl: string; http: HttpRuntimePort): Result[ModelCatalogResult, string] =
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseOllamaTagsCatalog($json)
  
  let url = (if baseUrl.len > 0: baseUrl
             else: descriptorOr("ollama").baseUrl) & "/api/tags"
  fetchHttpCatalog(http, url, @[], parser)

proc loadMinimaxCatalog(apiKey: string): Result[ModelCatalogResult, string] =
  ## MiniMax não tem endpoint de listagem de modelos.
  ## Retorna catálogo estático.
  if apiKey.len == 0:
    return ok(fallbackCatalog("minimax"))
  ok(catalogResult(staticCatalog("minimax"), mcsFallback, getTime().toUnix()))

proc buildModelCatalogLoader*(env: Environment;
                              http: HttpRuntimePort = defaultCatalogHttp()): ModelCatalogLoader {.gcsafe.} =
  ## Returns a closure that loads model catalogs with caching. The provider
  ## keys come from `env`, the environment snapshot.
  ## models.dev result is cached for 5 minutes to avoid re-fetching on every click.
  var cachedModelsDev: Option[ModelCatalogResult] = none(ModelCatalogResult)
  var cachedOpenRouter: Option[ModelCatalogResult] = none(ModelCatalogResult)
  var openRouterError = ""
  const CacheTtlSec = 300  # 5 minutes

  result = proc(providerName: string): Result[ModelCatalogResult, string] {.gcsafe.} =
    let now = getTime().toUnix()

    ## OpenRouter's own API is the source of truth for the ':free' variants.
    ## models.dev can omit those variants or report them without zero pricing.
    if providerName == "openrouter":
      if cachedOpenRouter.isSome and
         (now - cachedOpenRouter.get().fetchedAtUnix) <= CacheTtlSec:
        return ok(cachedOpenRouter.get())
      let direct = loadOpenRouterCatalog(env.catalogEnvValue("openrouter"), http)
      if direct.isOk:
        cachedOpenRouter = some(direct.get())
        return direct
      openRouterError = direct.error

    # Check models.dev cache freshness for the remaining providers.
    if cachedModelsDev.isNone or (now - cachedModelsDev.get().fetchedAtUnix) > CacheTtlSec:
      let modelsDevResult = loadModelsDevCatalog(http)
      if modelsDevResult.isOk:
        cachedModelsDev = some(modelsDevResult.get())

    # Try cached models.dev first
    if cachedModelsDev.isSome:
      let allEntries = cachedModelsDev.get().entries
      var filtered: seq[ModelCatalogEntry] = @[]
      for entry in allEntries:
        if entry.providerName == providerName:
          filtered.add(entry)
      if filtered.len > 0:
        return ok(catalogResult(filtered, mcsLive, cachedModelsDev.get().fetchedAtUnix))

    ## Fallback para APIs específicas ou catálogo estático. Nomes de env e a
    ## base do Ollama vêm do descritor; ver o comentário do bloco `const`.
    case providerName
    of "openrouter":
      if openRouterError.len > 0:
        err(openRouterError)
      else:
        loadOpenRouterCatalog(env.catalogEnvValue("openrouter"), http)
    of "groq":
      loadGroqCatalog(env.catalogEnvValue("groq"), http)
    of "anthropic":
      loadAnthropicCatalog(env.catalogEnvValue("anthropic"), http)
    of "gemini":
      loadGeminiCatalog(env.catalogEnvValue("gemini"), http)
    of "minimax":
      loadMinimaxCatalog(env.catalogEnvValue("minimax"))
    of "zai":
      ## The general Z.ai platform endpoint: `codingEndpoint = false` is the
      ## reachable branch for this provider (the coding plan has its own id).
      loadZaiCatalog(env.catalogEnvValue("zai"), providerName, false, http)
    of "zai-coding":
      loadZaiCatalog(env.catalogEnvValue("zai-coding"), providerName, true, http)
    of "zai-anthropic":
      loadZaiCatalog(env.catalogEnvValue("zai-anthropic"), providerName, true, http)
    of "opencode-go", "opencode":
      loadOpencodeGoCatalog(env.catalogEnvValue("opencode-go"), http)
    of "zen", "opencode-zen":
      loadZenCatalog(http, env.catalogEnvValue("zen"))
    of "ollama":
      loadOllamaCatalog(env.catalogEnvValue("ollama"), http)
    else:
      ok(fallbackCatalog(providerName))
