import std/[algorithm, httpclient, json, os, strutils, times]
import ../../ports/provider
import ../../core/pipeops
import ../../core/providers/smart_routing
import openrouter
import anthropic

const
  OpenRouterModelsEndpoint = "https://openrouter.ai/api/v1/models"
  GroqModelsEndpoint = "https://api.groq.com/openai/v1/models"
  AnthropicModelsEndpoint = "https://api.anthropic.com/v1/models"
  GeminiModelsEndpoint = "https://generativelanguage.googleapis.com/v1beta/models"
  ModelsDevEndpoint = "https://models.dev/api/v1/models"
  DefaultCatalogTtlSec = 12 * 60 * 60

type
  CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.}

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

proc httpGetCatalog(url: string; headers: seq[(string, string)]): Result[string, string] =
  ## Makes HTTP GET request to fetch catalog JSON.
  try:
    var client = newHttpClient(userAgent = "donkey/1.0")
    if headers.len > 0:
      client.headers = newHttpHeaders(headers)
    
    let response = client.get(url)
    if response.status[0] != '2':
      return err("HTTP " & $response.status)
    
    ok(response.body)
  except Exception as e:
    err(e.msg)

proc parseCatalogJson(body: string; parser: CatalogParser): Result[ModelCatalogResult, string] =
  ## Parses JSON body and wraps entries in ModelCatalogResult.
  let parsed = parser(parseJson(body))
  if parsed.isErr:
    return err(parsed.error)
  
  if parsed.value.len > 0:
    ok(catalogResult(parsed.value.sortCatalog(), mcsLive, getTime().toUnix()))
  else:
    err("no models found")

proc fetchHttpCatalog(url: string; headers: seq[(string, string)];
                      parser: CatalogParser): Result[ModelCatalogResult, string] =
  ## Fetches model catalog from HTTP REST API.
  ## Composes: httpGetCatalog |> parseCatalogJson
  let body = httpGetCatalog(url, headers)
  if body.isErr:
    return err(body.error)
  
  parseCatalogJson(body.get(), parser)

proc fetchWithApiKey(url: string; apiKey: string;
                     parser: CatalogParser;
                     headers: seq[(string, string)] = @[]): Result[ModelCatalogResult, string] =
  ## Helper para APIs que usam API Key no header Authorization.
  if apiKey.len == 0:
    return err("API key required")
  
  var allHeaders = @[("Authorization", "Bearer " & apiKey)]
  for h in headers:
    allHeaders.add(h)
  
  fetchHttpCatalog(url, allHeaders, parser)

proc fetchWithQueryParam(url: string; queryParam: string; queryValue: string;
                         parser: CatalogParser): Result[ModelCatalogResult, string] =
  ## Helper para APIs que usam chave como query param.
  let fullUrl = url & (if "?" in url: "&" else: "?") & queryParam & "=" & queryValue
  fetchHttpCatalog(fullUrl, @[], parser)

proc loadModelsDevCatalog(): Result[ModelCatalogResult, string] =
  ## Carrega catálogo do models.dev (catálogo aberto mantido pela comunidade).
  try:
    var client = newHttpClient(userAgent = "donkey/1.0")
    client.headers = newHttpHeaders([("Accept", "application/json")])
    let response = client.get(ModelsDevEndpoint)
    if response.status[0] != '2':
      return err("models.dev returned status " & $response.status)

    let models = parseJson(response.body)
    if models.kind != JArray:
      return err("models.dev response is not an array")
    
    var entries: seq[ModelCatalogEntry] = @[]
    for model in models:
      let provider = model.getOrDefault("provider").getStr("")
      let providerId = model.getOrDefault("providerId").getStr("")
      let modelId = model.getOrDefault("modelId").getStr("")
      let inputCost = model.getOrDefault("inputCost").getFloat(0.0)
      
      if providerId.len > 0:
        # Determina se é free (custo zero)
        let isFree = inputCost == 0.0
        
        # Mapeia provider names do models.dev para nossos nomes internos
        let internalProvider = case provider.toLowerAscii()
          of "minimax": "minimax"
          of "zhipu", "zhipu ai": "zai"
          of "groq": "groq"
          of "anthropic": "anthropic"
          of "google", "gemini": "gemini"
          of "openai": "openrouter"  # OpenAI via OpenRouter
          of "deepseek": "deepseek"
          of "alibaba", "qwen": "alibaba"
          else: ""
        
        if internalProvider.len > 0:
          entries.add(ModelCatalogEntry(
            providerName: internalProvider,
            modelName: providerId,
            label: modelId,
            isFree: isFree,
            available: true,
            hasPricing: inputCost > 0.0
          ))
    
    if entries.len > 0:
      return ok(catalogResult(entries.sortCatalog(), mcsLive, getTime().toUnix()))
    else:
      return err("models.dev returned no entries for supported providers")
  except Exception as e:
    return err("models.dev fetch failed: " & e.msg)

func staticCatalog(providerName: string): seq[ModelCatalogEntry] =
  case providerName
  of "openrouter":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "openai/gpt-4o-mini", label: "openai/gpt-4o-mini", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "openai/gpt-4o", label: "openai/gpt-4o", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "anthropic/claude-opus-4-6", label: "anthropic/claude-opus-4-6", isFree: false, available: true),
    ]
  of "groq":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "llama-3.3-70b-versatile", label: "llama-3.3-70b-versatile", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "llama-3.1-8b-instant", label: "llama-3.1-8b-instant", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "openai/gpt-oss-20b", label: "openai/gpt-oss-20b", isFree: true, available: true, hasPricing: true),
    ]
  of "zen":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "gpt-5.4", label: "gpt-5.4", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "claude-sonnet-4-6", label: "claude-sonnet-4-6", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-5", label: "glm-5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "minimax-m2.5-free", label: "minimax-m2.5-free", isFree: true, available: true),
    ]
  of "anthropic":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "claude-opus-4-6", label: "claude-opus-4-6", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "claude-sonnet-4-6", label: "claude-sonnet-4-6", isFree: false, available: true),
    ]
  of "gemini":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "gemini-2.5-flash", label: "gemini-2.5-flash", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "gemini-2.5-pro", label: "gemini-2.5-pro", isFree: false, available: true),
    ]
  of "minimax":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "MiniMax-M2", label: "MiniMax-M2", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "MiniMax-M2.5", label: "MiniMax-M2.5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "MiniMax-M2.7", label: "MiniMax-M2.7", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "MiniMax-Text-01", label: "MiniMax-Text-01", isFree: false, available: true),
    ]
  of "zai", "zai-coding":
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "glm-5", label: "glm-5", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-4.7", label: "glm-4.7", isFree: false, available: true),
      ModelCatalogEntry(providerName: providerName, modelName: "glm-4.6", label: "glm-4.6", isFree: false, available: true),
    ]
  of "ollama":
    ## Static fallback — Ollama catalog is loaded live from /api/tags.
    @[
      ModelCatalogEntry(providerName: providerName, modelName: "llama3", label: "llama3", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "mistral", label: "mistral", isFree: true, available: true, hasPricing: true),
      ModelCatalogEntry(providerName: providerName, modelName: "codellama", label: "codellama", isFree: true, available: true, hasPricing: true),
    ]
  else:
    @[]

func fallbackCatalog(providerName: string): ModelCatalogResult =
  catalogResult(staticCatalog(providerName), mcsFallback, 0)

func parseCostMicrosPer1k(raw: string): int =
  if raw.len == 0:
    return 0
  try:
    int(parseFloat(raw) * 1_000_000.0 * 1000.0 + 0.5)
  except ValueError:
    0

func modelCatalogTtlSec(): int64 =
  let raw = getEnv("DONKEY_MODEL_CATALOG_TTL_SEC")
  if raw.len == 0:
    return DefaultCatalogTtlSec
  try:
    let ttl = parseInt(raw)
    if ttl > 0: ttl else: DefaultCatalogTtlSec
  except ValueError:
    DefaultCatalogTtlSec

func modelCatalogBaseDir(): string =
  let home = getEnv("DONKEY_HOME")
  if home.len > 0:
    home / "state"
  else:
    getHomeDir() / ".donkey" / "state"

func sanitizeProviderName(providerName: string): string =
  providerName.multiReplace(("/", "_"), (":", "_"), (" ", "_"))

func modelCatalogCachePath(providerName: string): string =
  modelCatalogBaseDir() / ("model_catalog_" & sanitizeProviderName(providerName) & ".json")

proc saveCatalogCache(providerName: string; entries: seq[ModelCatalogEntry]) =
  try:
    createDir(modelCatalogBaseDir())
    let cachePath = modelCatalogCachePath(providerName)
    var data = newJArray()
    for entry in entries:
      data.add(%* {
        "provider": providerName,
        "id": entry.modelName,
        "label": entry.label,
        "is_free": entry.isFree,
        "available": entry.available,
        "has_pricing": entry.hasPricing,
        "input_cost_micros_per_1k": entry.inputCostMicrosPer1k,
        "output_cost_micros_per_1k": entry.outputCostMicrosPer1k,
      })
    let payload = %* {
      "provider": providerName,
      "fetched_at": getTime().toUnix(),
      "data": data,
    }
    writeFile(cachePath, $payload)
  except CatchableError:
    discard

proc loadCatalogCache(providerName: string): Result[ModelCatalogResult, string] =
  try:
    let cachePath = modelCatalogCachePath(providerName)
    if not fileExists(cachePath):
      return err("cache missing")
    let parsed = parseJson(readFile(cachePath))
    let fetchedAt = parsed.getOrDefault("fetched_at").getInt(0).int64
    let nowSec = getTime().toUnix()
    if fetchedAt <= 0 or nowSec - fetchedAt > modelCatalogTtlSec():
      return err("cache expired")
    let data = parsed.getOrDefault("data")
    if data == nil or data.kind != JArray:
      return err("cache missing data")
    var entries: seq[ModelCatalogEntry] = @[]
    for item in data:
      let modelId = item.getOrDefault("id").getStr("")
      if modelId.len == 0:
        continue
      entries.add(ModelCatalogEntry(
        providerName: providerName,
        modelName: modelId,
        label: item.getOrDefault("label").getStr(modelId),
        isFree: item.getOrDefault("is_free").getBool(false),
        available: item.getOrDefault("available").getBool(true),
        hasPricing: item.getOrDefault("has_pricing").getBool(false),
        inputCostMicrosPer1k: item.getOrDefault("input_cost_micros_per_1k").getInt(0),
        outputCostMicrosPer1k: item.getOrDefault("output_cost_micros_per_1k").getInt(0),
      ))
    ok(catalogResult(entries.sortCatalog(), mcsCache, fetchedAt))
  except CatchableError as e:
    err(e.msg)

proc withCacheFallback(providerName: string;
                       live: Result[seq[ModelCatalogEntry], string]): Result[ModelCatalogResult, string] =
  if live.isOk and live.value.len > 0:
    saveCatalogCache(providerName, live.value)
    return ok(catalogResult(live.value.sortCatalog(), mcsLive, getTime().toUnix()))
  let cached = loadCatalogCache(providerName)
  if cached.isOk and cached.value.entries.len > 0:
    return ok(cached.value)
  ok(fallbackCatalog(providerName))

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
        let cached = loadCatalogCache(providerName)
        if cached.isOk and cached.value.entries.len > 0:
          cached.value
        else:
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

proc fetchCatalog(url: string;
                  headers: seq[(string, string)] = @[]): Result[string, string] =
  try:
    let client = newHttpClient()
    defer: client.close()
    if headers.len > 0:
      client.headers = newHttpHeaders(headers)
    let resp = client.get(url)
    if resp.status[0] != '2':
      return err(resp.status & ": " & resp.body)
    ok(resp.body)
  except CatchableError as e:
    err(e.msg)

proc loadOpenRouterCatalog(apiKey: string): Result[ModelCatalogResult, string] =
  let headers =
    if apiKey.len > 0:
      @[("Authorization", "Bearer " & apiKey),
        ("HTTP-Referer", OpenRouterReferer),
        ("X-Title", OpenRouterTitle)]
    else:
      @[("HTTP-Referer", OpenRouterReferer), ("X-Title", OpenRouterTitle)]
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseOpenRouterCatalog($json)
  
  fetchHttpCatalog(OpenRouterModelsEndpoint, headers, parser)

proc loadGroqCatalog(apiKey: string): Result[ModelCatalogResult, string] =
  if apiKey.len == 0:
    return ok(fallbackCatalog("groq"))
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseSimpleListCatalog("groq", $json)
  
  fetchWithApiKey(GroqModelsEndpoint, apiKey, parser)

proc loadAnthropicCatalog(apiKey: string): Result[ModelCatalogResult, string] =
  if apiKey.len == 0:
    return ok(fallbackCatalog("anthropic"))
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseAnthropicCatalog($json)
  
  fetchWithApiKey(AnthropicModelsEndpoint, apiKey, parser, @[
    ("x-api-key", apiKey),
    ("anthropic-version", AnthropicVersion),
  ])

proc loadGeminiCatalog(apiKey: string): Result[ModelCatalogResult, string] =
  if apiKey.len == 0:
    return ok(fallbackCatalog("gemini"))
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseGeminiCatalog($json)
  
  fetchWithQueryParam(GeminiModelsEndpoint, "key", apiKey, parser)

proc loadZaiCatalog(apiKey: string; coding: bool): Result[ModelCatalogResult, string] =
  let providerName = if coding: "zai-coding" else: "zai"
  if apiKey.len == 0:
    return ok(fallbackCatalog(providerName))
  
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseSimpleListCatalog(providerName, $json)
  
  let base =
    if coding: "https://api.z.ai/api/coding/paas/v4/models"
    else: "https://api.z.ai/api/paas/v4/models"
  
  fetchWithApiKey(base, apiKey, parser)

proc loadZenCatalog(): Result[ModelCatalogResult, string] =
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseSimpleListCatalog("zen", $json)
  
  fetchHttpCatalog("https://opencode.ai/zen/v1/models", @[], parser)

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

proc loadOllamaCatalog(baseUrl: string): Result[ModelCatalogResult, string] =
  let parser: CatalogParser = proc(json: JsonNode): Result[seq[ModelCatalogEntry], string] {.gcsafe.} =
    parseOllamaTagsCatalog($json)
  
  let url = (if baseUrl.len > 0: baseUrl else: "http://localhost:11434") & "/api/tags"
  fetchHttpCatalog(url, @[], parser)

proc loadMinimaxCatalog(apiKey: string): Result[ModelCatalogResult, string] =
  ## MiniMax não tem endpoint de listagem de modelos.
  ## Retorna catálogo estático.
  if apiKey.len == 0:
    return ok(fallbackCatalog("minimax"))
  
  ## Lista fixa de modelos MiniMax conhecidos
  let entries = @[
    ModelCatalogEntry(providerName: "minimax", modelName: "MiniMax-M2", label: "MiniMax-M2", isFree: false, available: true),
    ModelCatalogEntry(providerName: "minimax", modelName: "MiniMax-M2.5", label: "MiniMax-M2.5", isFree: false, available: true),
    ModelCatalogEntry(providerName: "minimax", modelName: "MiniMax-M2.7", label: "MiniMax-M2.7", isFree: false, available: true),
    ModelCatalogEntry(providerName: "minimax", modelName: "MiniMax-Text-01", label: "MiniMax-Text-01", isFree: false, available: true),
  ]
  ok(catalogResult(entries, mcsFallback, getTime().toUnix()))

proc buildModelCatalogLoader*(): ModelCatalogLoader {.gcsafe.} =
  result = proc(providerName: string): Result[ModelCatalogResult, string] {.gcsafe.} =
    ## Tenta buscar do models.dev primeiro, depois fallback para API específica ou catálogo estático
    let modelsDevResult = loadModelsDevCatalog()
    if modelsDevResult.isOk:
      let allEntries = modelsDevResult.get().entries
      var filtered: seq[ModelCatalogEntry] = @[]
      for entry in allEntries:
        if entry.providerName == providerName:
          filtered.add(entry)
      if filtered.len > 0:
        return ok(catalogResult(filtered, mcsLive, modelsDevResult.get().fetchedAtUnix))
    
    ## Fallback para APIs específicas ou catálogo estático
    case providerName
    of "openrouter":
      loadOpenRouterCatalog(getEnv("OPENROUTER_API_KEY"))
    of "groq":
      loadGroqCatalog(getEnv("GROQ_API_KEY"))
    of "anthropic":
      loadAnthropicCatalog(getEnv("ANTHROPIC_API_KEY"))
    of "gemini":
      loadGeminiCatalog(getEnv("GEMINI_API_KEY"))
    of "minimax":
      loadMinimaxCatalog(getEnv("MINIMAX_API_KEY"))
    of "zai":
      loadZaiCatalog(getEnv("ZAI_API_KEY"), false)
    of "zai-coding":
      loadZaiCatalog(getEnv("ZAI_CODING_API_KEY", getEnv("ZHIPU_API_KEY")), true)
    of "zen":
      loadZenCatalog()
    of "ollama":
      loadOllamaCatalog(getEnv("OLLAMA_BASE_URL"))
    else:
      ok(fallbackCatalog(providerName))
