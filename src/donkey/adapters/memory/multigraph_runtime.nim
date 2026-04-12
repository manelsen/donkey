## multigraph_runtime — MAGMA wiring for the app entrypoint.

when defined(withPostgres) or defined(withSqlite):
  import std/[os, strutils]
  import ../../core/types
  import ../../core/providers/smart_routing
  import ../../core/memory_rerank_prefs
  import ../../ports/memory
  import ../../ports/embedding
  import ../../ports/reranking
  import ../../ports/ipc
  import ../embedding/openrouter_embed
  import ../reranking/zai_rerank
  import ../reranking/minimax_rerank
  import ../reranking/openrouter_rerank
  import ./md_file
  import ./magma_memory_adapter

  type
    MemoryExportEntry = object
      fileName: string
      content: string

    ResolvedMagmaRerank = object
      provider: string
      model: string

  proc buildMagmaEmbedFn(): EmbedFn {.gcsafe.} =
    let embedKey = getEnv("OPENROUTER_API_KEY")
    let embedAdapter = newOpenRouterEmbeddingAdapter(embedKey)
    result = proc(text: string): seq[float32] {.gcsafe.} =
      embedAdapter.embed(text)

  proc envIntOr(name: string; defaultValue: int): int =
    let raw = getEnv(name)
    if raw.len == 0:
      return defaultValue
    try:
      result = parseInt(raw)
    except ValueError:
      result = defaultValue

  proc envFloatOrUnit(name: string; defaultValue: float32): float32 =
    let raw = getEnv(name)
    if raw.len == 0:
      return defaultValue
    try:
      result = parseFloat(raw).float32
    except ValueError:
      result = defaultValue
    if result < 0.0'f32:
      result = 0.0'f32
    elif result > 1.0'f32:
      result = 1.0'f32

  proc buildMagmaSearchConfig(): SearchConfig =
    result = defaultSearchConfig()
    result.semanticTopKMultiplier = max(1, envIntOr(
      "DONKEY_MEMORY_SEARCH_SEMANTIC_MULTIPLIER",
      result.semanticTopKMultiplier,
    ))
    result.recentTopKMultiplier = max(1, envIntOr(
      "DONKEY_MEMORY_SEARCH_RECENT_MULTIPLIER",
      result.recentTopKMultiplier,
    ))
    result.rerankPoolSize = max(1, envIntOr(
      "DONKEY_MEMORY_RERANK_POOL",
      result.rerankPoolSize,
    ))
    result.rerankWeight = envFloatOrUnit(
      "DONKEY_MEMORY_RERANK_WEIGHT",
      result.rerankWeight,
    )

  func normalizeRerankProvider(raw: string): string =
    case raw.strip.toLowerAscii()
    of "zhipu":
      "zai-coding"
    else:
      raw.strip.toLowerAscii()

  proc inferRerankProvider(model: string): string =
    let normalized = model.strip
    if normalized.len == 0:
      return ""
    if normalized.startsWith("MiniMax-"):
      return "minimax"
    if normalized.toLowerAscii().startsWith("glm-"):
      if getEnv("ZAI_CODING_API_KEY", getEnv("ZHIPU_API_KEY")).len > 0:
        return "zai-coding"
      if getEnv("ZAI_API_KEY").len > 0:
        return "zai"
      return "zai-coding"
    if normalized.contains("/"):
      return "openrouter"
    ""

  proc resolveMagmaRerank(preferencesMd: string): ResolvedMagmaRerank =
    let rerankPrefs = parseMemoryRerankPrefs(preferencesMd)
    let envMode = normalizeMemoryRerankMode(getEnv("DONKEY_MEMORY_RERANK_MODE"))
    let explicitModel =
      if rerankPrefs.model.len > 0: rerankPrefs.model
      else: getEnv("DONKEY_MEMORY_RERANK_MODEL")

    var mode =
      if rerankPrefs.mode.len > 0: rerankPrefs.mode
      else: envMode

    if mode.len == 0:
      let normalizedModel = explicitModel.strip.toLowerAscii()
      if normalizedModel.len == 0 or normalizedModel in ["off", "none"]:
        return ResolvedMagmaRerank()
      mode = MemoryRerankExplicit

    case mode
    of MemoryRerankOff:
      discard
    of MemoryRerankDialogue:
      let routingPrefs = parseSmartRoutingPrefs(preferencesMd)
      if not routingPrefs.usesSmartRouting:
        result.provider = normalizeRerankProvider(routingPrefs.providerName)
        if routingPrefs.modelName.len > 0:
          result.model = routingPrefs.modelName
        elif result.provider.len > 0:
          result.model = defaultModelForProvider(result.provider)
    of MemoryRerankExplicit:
      let normalizedModel = explicitModel.strip
      if normalizedModel.len == 0 or normalizedModel.toLowerAscii in ["off", "none"]:
        return ResolvedMagmaRerank()
      let explicitProvider =
        if rerankPrefs.provider.len > 0: rerankPrefs.provider
        else: getEnv("DONKEY_MEMORY_RERANK_PROVIDER")
      result.provider = normalizeRerankProvider(
        if explicitProvider.len > 0: explicitProvider
        else: inferRerankProvider(normalizedModel)
      )
      result.model = normalizedModel
    else:
      discard

  proc buildMagmaRerankFn(preferencesMd = ""): RerankFn {.gcsafe.} =
    let rerank = resolveMagmaRerank(preferencesMd)
    if rerank.model.len == 0:
      return nil
    let maxChars = max(128, envIntOr("DONKEY_MEMORY_RERANK_MAX_CHARS", DefaultRerankMaxChars))
    let maxTokens = max(128, envIntOr("DONKEY_MEMORY_RERANK_MAX_TOKENS", DefaultRerankMaxTokens))
    case rerank.provider
    of "openrouter":
      let rerankKey = getEnv("OPENROUTER_API_KEY")
      if rerankKey.len == 0:
        return nil
      let rerankAdapter = newOpenRouterRerankAdapter(
        rerankKey,
        model = rerank.model,
        maxChars = maxChars,
        maxTokens = maxTokens,
      )
      result = proc(query: string; candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
        rerankAdapter.rerank(query, candidates)
    of "zai":
      let rerankKey = getEnv("ZAI_API_KEY")
      if rerankKey.len == 0:
        return nil
      let rerankAdapter = newZaiRerankAdapter(
        rerankKey,
        model = rerank.model,
        maxChars = maxChars,
        maxTokens = maxTokens,
      )
      result = proc(query: string; candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
        rerankAdapter.rerank(query, candidates)
    of "zai-coding":
      let rerankKey = getEnv("ZAI_CODING_API_KEY", getEnv("ZHIPU_API_KEY"))
      if rerankKey.len == 0:
        return nil
      let rerankAdapter = newZaiCodingRerankAdapter(
        rerankKey,
        model = rerank.model,
        maxChars = maxChars,
        maxTokens = maxTokens,
      )
      result = proc(query: string; candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
        rerankAdapter.rerank(query, candidates)
    of "minimax":
      let rerankKey = getEnv("MINIMAX_API_KEY")
      if rerankKey.len == 0:
        return nil
      let rerankAdapter = newMiniMaxRerankAdapter(
        rerankKey,
        model = rerank.model,
        maxChars = maxChars,
        maxTokens = maxTokens,
      )
      result = proc(query: string; candidates: seq[RerankCandidate]): seq[float32] {.gcsafe.} =
        rerankAdapter.rerank(query, candidates)
    else:
      discard

  proc newCtlMagmaAdapter(memory: MdFileAdapter): MagmaMemoryAdapter =
    when defined(withSqlite):
      if memory.magmaSqlitePath.len > 0:
        return newSqliteMagmaMemoryAdapter(
          memory.magmaSqlitePath,
          buildMagmaEmbedFn(),
          nil,
          buildMagmaSearchConfig(),
          vectorExtensionPath = memory.magmaSqliteVectorPath,
        )
    when defined(withPostgres):
      if memory.magmaDsn.len > 0:
        return newMagmaMemoryAdapter(
          memory.magmaDsn,
          buildMagmaEmbedFn(),
          nil,
          buildMagmaSearchConfig(),
        )
    nil

  proc buildMemoryExportEntries(ctx: UserContext): seq[MemoryExportEntry] =
    @[
      MemoryExportEntry(fileName: "USER.md", content: ctx.userMd),
      MemoryExportEntry(fileName: "MEMORY.md", content: ctx.memoryMd),
      MemoryExportEntry(fileName: "PREFERENCES.md", content: ctx.preferencesMd),
    ]

  proc exportContextToDir(ctx: UserContext; outDir: string) =
    createDir(outDir)
    for entry in buildMemoryExportEntries(ctx):
      writeFile(outDir / entry.fileName, entry.content)

  proc importContextToMagma(magma: MagmaMemoryAdapter;
                            userId: UserId;
                            ctx: UserContext) =
    if ctx.userMd.strip.len > 0:
      magma.saveUserMd(userId, ctx.userMd)
    if ctx.preferencesMd.strip.len > 0:
      magma.savePreferences(userId, ctx.preferencesMd)
    for chunk in ctx.memoryMd.split("\n\n"):
      let trimmed = chunk.strip()
      if trimmed.len > 0:
        magma.appendMemory(userId, trimmed)

  proc echoMemoryExport(entries: seq[MemoryExportEntry]) =
    for i, entry in entries:
      if i > 0:
        echo ""
      echo "# " & entry.fileName
      echo ""
      echo entry.content

  proc ctlMemorySearch*(memory: MdFileAdapter; uuid, query: string; limit = 10) =
    let magma = newCtlMagmaAdapter(memory)
    if magma == nil:
      echo "MAGMA backend not configured"
      return
    let uid = UserId(uuid)
    let prefsMd = memory.loadContext(uid).preferencesMd
    let hits = magma.searchWithRerank(uid, query, limit, buildMagmaRerankFn(prefsMd))
    if hits.len == 0:
      echo "(no results)"
      return
    for h in hits:
      echo "score=" & $h.score & " kind=" & h.kind
      echo h.content
      echo "---"

  proc ctlMemoryImport*(memory: MdFileAdapter; uuid: string) =
    let uid = UserId(uuid)
    let ctx = memory.loadContext(uid)
    let magma = newCtlMagmaAdapter(memory)
    if magma == nil:
      echo "MAGMA backend not configured"
      return
    magma.deleteUser(uid)
    magma.importContextToMagma(uid, ctx)
    echo "Imported " & uuid & " from .md files"

  proc ctlMemoryExport*(memory: MdFileAdapter; uuid: string; outDir = "") =
    let magma = newCtlMagmaAdapter(memory)
    if magma == nil:
      echo "MAGMA backend not configured"
      return
    let ctx = magma.loadContext(UserId(uuid))
    let entries = buildMemoryExportEntries(ctx)
    if outDir.len == 0:
      echoMemoryExport(entries)
      return
    exportContextToDir(ctx, outDir)
    echo "Exported " & uuid & " to " & outDir

  proc buildGlobalMagmaSearchFn*(memory: MdFileAdapter): SearchFn {.gcsafe, raises: [].} =
    if not memory.hasMagmaBackend:
      return nil
    let magmaSearch = memory.newMagmaAdapter()
    result = proc(userId: UserId; query: string; limit: int): seq[MemoryHit]
                  {.gcsafe, raises: [].} =
      try:
        let ctx = memory.loadContext(userId)
        let rerankFn = buildMagmaRerankFn(ctx.preferencesMd)
        magmaSearch.searchWithRerank(userId, query, limit, rerankFn)
      except Exception:
        @[]

  proc loadMagmaMemoryStats*(memory: MdFileAdapter): MemoryStats {.gcsafe, raises: [].} =
    if not memory.hasMagmaBackend:
      return MemoryStats()
    try:
      let magma = memory.newMagmaAdapter()
      let stats = magma.stats()
      MemoryStats(
        totalNodes: stats.totalNodes,
        memoryNodes: stats.memoryNodes,
        profileNodes: stats.profileNodes,
        preferenceNodes: stats.preferenceNodes,
        entityNodes: stats.entityNodes,
        embeddingNodes: stats.embeddingNodes,
        totalEdges: stats.totalEdges,
      )
    except Exception:
      MemoryStats()
